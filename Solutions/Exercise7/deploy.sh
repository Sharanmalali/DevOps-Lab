#!/usr/bin/env bash
#
# Exercise 7 - Introduction to CI and Jenkins Installation
#
# Starts a Jenkins LTS controller with Docker and retrieves the initial
# administrator password required by the "Unlock Jenkins" setup wizard.
#
# Usage:
#   ./deploy.sh          # faithful install: prints the initial admin password
#                        # and leaves the setup wizard for you to complete
#   ./deploy.sh --auto   # headless install: skip the wizard, boot with an
#                        # admin/admin account created by init.groovy.d
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Git Bash rewrites slash-leading arguments destined for native (Windows)
# executables. Disable that so docker receives the flags verbatim.
export MSYS2_ARG_CONV_EXCL='*'

# Git Bash hands native children a reduced PATH that can drop the Docker CLI
# directory (and, in turn, docker-credential-desktop). Re-add it explicitly.
DOCKER_BIN_DIR="$(dirname "$(command -v docker 2>/dev/null || echo /usr/bin/docker)")"
case ":$PATH:" in
  *":$DOCKER_BIN_DIR:"*) ;;
  *) PATH="$DOCKER_BIN_DIR:$PATH" ;;
esac
export PATH

JENKINS_IMAGE="jenkins/jenkins:lts"
CONTAINER_NAME="jenkins"
# Dedicated volume so this exercise never collides with another exercise's
# Jenkins state (the brief's plain `docker run` has no volume at all).
VOLUME_NAME="ex7_jenkins_home"
HOST_WORKDIR="$(pwd -W 2>/dev/null || pwd)"

AUTO=0
for arg in "$@"; do
  case "$arg" in
    --auto)      AUTO=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1 ;;
  esac
done

port_in_use() {
  netstat -ano 2>/dev/null | grep -qiE "[:.]$1[[:space:]].*LISTENING"
}

pick_port() {
  local port="$1"
  while port_in_use "$port"; do
    echo "  port $port is in use, trying $((port + 1))..." >&2
    port=$((port + 1))
  done
  echo "$port"
}

echo "[1/6] Checking prerequisites"
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH" >&2; exit 1; }
docker info >/dev/null 2>&1          || { echo "ERROR: Docker daemon is not running" >&2; exit 1; }
command -v curl   >/dev/null 2>&1 || { echo "ERROR: curl not found in PATH" >&2; exit 1; }
echo "  docker: $(docker --version)"

echo "[2/6] Removing any previous container named '${CONTAINER_NAME}'"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "[3/6] Selecting host ports"
JENKINS_PORT="$(pick_port 8080)"
AGENT_PORT="$(pick_port 50000)"
[ "$JENKINS_PORT" = "8080" ] || echo "  NOTE: brief uses 8080, but it is taken on this host -> Jenkins UI on ${JENKINS_PORT}"
echo "  Jenkins UI  -> ${JENKINS_PORT}"
echo "  Agent (JNLP)-> ${AGENT_PORT}"

echo "[4/6] Starting Jenkins (${JENKINS_IMAGE})"
RUN_ARGS=(
  -d
  --name "$CONTAINER_NAME"
  -p "${JENKINS_PORT}:8080"
  -p "${AGENT_PORT}:50000"
  -v "${VOLUME_NAME}:/var/jenkins_home"
)
if [ "$AUTO" -eq 1 ]; then
  echo "  --auto: disabling setup wizard, bootstrapping admin account"
  RUN_ARGS+=( -e "JAVA_OPTS=-Djenkins.install.runSetupWizard=false" )
  RUN_ARGS+=( -v "${HOST_WORKDIR}/init.groovy.d:/var/jenkins_home/init.groovy.d:ro" )
fi
docker run "${RUN_ARGS[@]}" "$JENKINS_IMAGE" >/dev/null
echo "  container id: $(docker inspect -f '{{.Id}}' "$CONTAINER_NAME" | cut -c1-12)"

BASE_URL="http://localhost:${JENKINS_PORT}"

echo "[5/6] Waiting for Jenkins to answer on ${BASE_URL}"
ready=0
for _ in $(seq 1 60); do
  # Before setup, "/" answers 403 while "/login" answers 200 with the
  # "Unlock Jenkins" page - poll the latter.
  if curl -fsS -o /dev/null "${BASE_URL}/login" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 2
done
[ "$ready" -eq 1 ] || { echo "ERROR: Jenkins did not become ready in time" >&2; docker logs --tail 40 "$CONTAINER_NAME" >&2 || true; exit 1; }
echo "  Jenkins is answering HTTP 200"

echo "[6/6] Verifying installation"
if [ "$AUTO" -eq 1 ]; then
  authed=0
  for _ in $(seq 1 30); do
    if curl -fsS -u admin:admin "${BASE_URL}/api/json" 2>/dev/null | grep -q '"mode"'; then
      authed=1
      break
    fi
    sleep 2
  done
  [ "$authed" -eq 1 ] || { echo "ERROR: headless admin login failed" >&2; exit 1; }

  cat <<EOF

============================================================
 Jenkins is installed and ready (headless / --auto mode)
============================================================
 URL       : ${BASE_URL}/
 Username  : admin
 Password  : admin
 Dashboard : ${BASE_URL}/api/json  (authenticated OK)

 The setup wizard was skipped on purpose. Open the URL and log
 in to reach the Jenkins dashboard.
============================================================
EOF
else
  # Wait for the initial admin password file to be written by the container.
  for _ in $(seq 1 30); do
    docker exec "$CONTAINER_NAME" test -f /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null && break
    sleep 2
  done
  INITIAL_PW="$(docker exec "$CONTAINER_NAME" cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || true)"
  if [ -z "$INITIAL_PW" ]; then
    cat >&2 <<EOF
ERROR: initial admin password not found.

This usually means the volume '${VOLUME_NAME}' already contains a Jenkins
instance that finished setup (the wizard is complete), so no fresh secret is
generated. Start from a clean slate and retry:
    ./cleanup.sh --volume && ./deploy.sh
EOF
    exit 1
  fi

  cat <<EOF

============================================================
 Jenkins is installed - complete the setup wizard
============================================================
 URL               : ${BASE_URL}/
 Initial password  : ${INITIAL_PW}

 Next steps (in the browser):
   1. Paste the initial password above to UNLOCK Jenkins.
   2. "Install suggested plugins" (or choose select plugins).
   3. Create the first admin user.
   4. Save and finish -> Jenkins is ready.
============================================================
EOF
fi

echo
echo "Container status:"
docker ps --filter "name=^/${CONTAINER_NAME}\$" --format '  {{.Names}}  {{.Status}}  {{.Ports}}'
echo
echo "Useful commands:"
echo "  logs    : docker logs -f ${CONTAINER_NAME}"
echo "  shell   : docker exec -it ${CONTAINER_NAME} bash"
echo "  password: docker exec ${CONTAINER_NAME} cat /var/jenkins_home/secrets/initialAdminPassword"
echo "  cleanup : ./cleanup.sh [--volume] [--image]"
