#!/usr/bin/env bash
#
# Exercise 8 - "Hello World" Jenkins job
#
# Creates the GitHub sample repo (devops-sample-code/hello-world.sh), starts a
# headless Jenkins controller, creates the Freestyle job "HelloWorld" (Git SCM +
# `sh hello-world.sh`), triggers a build and verifies the console output.
#
# Usage:
#   GITHUB_TOKEN=<pat> ./deploy.sh     # create/update the repo + run the job
#   ./deploy.sh                        # repo must already exist (public)
#
# GITHUB_TOKEN is only needed to CREATE the repo or push the script. It is never
# written to disk by this script.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
# Windows-style host path (forward slashes). With MSYS arg conversion disabled
# below, the Docker CLI needs this form for build contexts and bind mounts.
HOST_WORKDIR="$(pwd -W 2>/dev/null || pwd)"

# Git Bash rewrites slash-leading arguments destined for native executables.
export MSYS2_ARG_CONV_EXCL='*'

# Git Bash can hand native children a truncated PATH (drops the Docker CLI dir
# and docker-credential-desktop). Re-add it explicitly.
DOCKER_BIN_DIR="$(dirname "$(command -v docker 2>/dev/null || echo /usr/bin/docker)")"
case ":$PATH:" in
  *":$DOCKER_BIN_DIR:"*) ;;
  *) PATH="$DOCKER_BIN_DIR:$PATH" ;;
esac
export PATH

JENKINS_IMAGE="ex8-jenkins"
CONTAINER_NAME="jenkins"
VOLUME_NAME="ex8_jenkins_home"
JOB_NAME="HelloWorld"
JOB_XML="$SCRIPT_DIR/job/HelloWorld-config.xml"

REPO_NAME="devops-sample-code"
REPO_DESC="A demo repository for Jenkins scripting."
FALLBACK_OWNER="shreyassridhar44"
GITHUB_OWNER=""
REPO_URL=""

API="https://api.github.com"
GH_HDR=(-H "User-Agent: ex8-deploy" -H "Accept: application/vnd.github+json")
GH_AUTH=()
[ -n "${GITHUB_TOKEN:-}" ] && GH_AUTH=(-H "Authorization: token ${GITHUB_TOKEN}")

for arg in "$@"; do
  case "$arg" in
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

port_in_use() { netstat -ano 2>/dev/null | grep -qiE "[:.]$1[[:space:]].*LISTENING"; }
pick_port() { local p="$1"; while port_in_use "$p"; do echo "  port $p is in use, trying $((p + 1))..." >&2; p=$((p + 1)); done; echo "$p"; }

# ---------------------------------------------------------------- [1/7] prereqs
echo "[1/7] Checking prerequisites"
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH" >&2; exit 1; }
docker info >/dev/null 2>&1          || { echo "ERROR: Docker daemon is not running" >&2; exit 1; }
command -v curl   >/dev/null 2>&1 || { echo "ERROR: curl not found in PATH" >&2; exit 1; }
echo "  docker: $(docker --version | cut -d, -f1)"
[ -n "${GITHUB_TOKEN:-}" ] && echo "  GITHUB_TOKEN: set" || echo "  GITHUB_TOKEN: not set (repo must already exist)"

# -------------------------------------------------------- [2/7] GitHub sample repo
echo "[2/7] Ensuring GitHub sample repo '${REPO_NAME}' + hello-world.sh"
if [ -n "${GITHUB_TOKEN:-}" ]; then
  GITHUB_OWNER="$(curl -fsS "${GH_HDR[@]}" "${GH_AUTH[@]}" "${API}/user" | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$GITHUB_OWNER" ] || { echo "ERROR: could not determine GitHub user from token" >&2; exit 1; }
else
  GITHUB_OWNER="$FALLBACK_OWNER"
fi
REPO_URL="https://github.com/${GITHUB_OWNER}/${REPO_NAME}.git"
echo "  owner: ${GITHUB_OWNER}"

code="$(curl -s -o /dev/null -w '%{http_code}' "${GH_HDR[@]}" "${GH_AUTH[@]}" "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}")"
if [ "$code" = "200" ]; then
  echo "  repo exists"
elif [ "$code" = "404" ]; then
  [ -n "${GITHUB_TOKEN:-}" ] || { echo "ERROR: repo ${GITHUB_OWNER}/${REPO_NAME} missing and GITHUB_TOKEN not set" >&2; exit 1; }
  echo "  creating public repo ${GITHUB_OWNER}/${REPO_NAME}"
  curl -fsS -o /dev/null "${GH_HDR[@]}" "${GH_AUTH[@]}" -X POST "${API}/user/repos" \
    -d "{\"name\":\"${REPO_NAME}\",\"description\":\"${REPO_DESC}\",\"private\":false}"
else
  echo "ERROR: unexpected HTTP ${code} checking repo" >&2; exit 1
fi

if [ -n "${GITHUB_TOKEN:-}" ]; then
  # Idempotent: only push when the remote content differs, so repeated runs do
  # not pile up meaningless "Add hello-world.sh" commits.
  local_script="$(cat "$SCRIPT_DIR/hello-world.sh")"
  remote_script="$(curl -fsS "https://raw.githubusercontent.com/${GITHUB_OWNER}/${REPO_NAME}/main/hello-world.sh" 2>/dev/null || true)"
  if [ -n "$remote_script" ] && [ "$remote_script" = "$local_script" ]; then
    echo "  hello-world.sh already up to date"
  else
    b64="$(base64 < "$SCRIPT_DIR/hello-world.sh" | tr -d '\n')"
    code="$(curl -s -o /dev/null -w '%{http_code}' "${GH_HDR[@]}" "${GH_AUTH[@]}" "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/hello-world.sh?ref=main")"
    if [ "$code" = "200" ]; then
      sha="$(curl -fsS "${GH_HDR[@]}" "${GH_AUTH[@]}" "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/hello-world.sh?ref=main" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
      echo "  updating hello-world.sh"
      curl -fsS -o /dev/null "${GH_HDR[@]}" "${GH_AUTH[@]}" -X PUT "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/hello-world.sh" \
        -d "{\"message\":\"Add hello-world.sh\",\"content\":\"${b64}\",\"branch\":\"main\",\"sha\":\"${sha}\"}"
    else
      echo "  creating hello-world.sh on branch main"
      curl -fsS -o /dev/null "${GH_HDR[@]}" "${GH_AUTH[@]}" -X PUT "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/hello-world.sh" \
        -d "{\"message\":\"Add hello-world.sh\",\"content\":\"${b64}\",\"branch\":\"main\"}"
    fi
  fi
  echo "  script: ${REPO_URL%.git}/blob/main/hello-world.sh"
else
  curl -fsS -o /dev/null "${GH_HDR[@]}" "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/hello-world.sh" \
    || { echo "ERROR: hello-world.sh missing and no GITHUB_TOKEN to add it" >&2; exit 1; }
  echo "  hello-world.sh present (public)"
fi

# ------------------------------------------------- [3/7] port + image + container
echo "[3/7] Preparing Jenkins (image ${JENKINS_IMAGE})"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
sleep 2   # let Docker Desktop release the previous container's published port
JENKINS_PORT="$(pick_port 8080)"
[ "$JENKINS_PORT" = "8080" ] || echo "  NOTE: brief uses 8080, but it is taken on this host -> Jenkins UI on ${JENKINS_PORT}"
docker build -q -t "$JENKINS_IMAGE" -f "$HOST_WORKDIR/Dockerfile.jenkins" "$HOST_WORKDIR" >/dev/null
echo "  image built; UI -> ${JENKINS_PORT}"

echo "[4/7] Starting Jenkins (headless admin/admin)"
docker run -d --name "$CONTAINER_NAME" \
  -p "${JENKINS_PORT}:8080" \
  -v "${VOLUME_NAME}:/var/jenkins_home" \
  -v "${HOST_WORKDIR}/init.groovy.d:/var/jenkins_home/init.groovy.d:ro" \
  -e "JAVA_OPTS=-Djenkins.install.runSetupWizard=false" \
  "$JENKINS_IMAGE" >/dev/null
echo "  container: $(docker inspect -f '{{.Id}}' "$CONTAINER_NAME" | cut -c1-12)"

BASE_URL="http://localhost:${JENKINS_PORT}"

echo "[5/7] Waiting for Jenkins on ${BASE_URL}"
ready=0
for _ in $(seq 1 60); do
  curl -fsS -o /dev/null "${BASE_URL}/login" 2>/dev/null && { ready=1; break; }
  sleep 2
done
[ "$ready" -eq 1 ] || { echo "ERROR: Jenkins did not become ready" >&2; docker logs --tail 30 "$CONTAINER_NAME" >&2 || true; exit 1; }

COOKIE_JAR=".ex8-cookies.txt"
RENDERED=".ex8-job-config.xml"
cleanup_tmp() { rm -f "$COOKIE_JAR" "$RENDERED" 2>/dev/null || true; }
trap cleanup_tmp EXIT

CRUMB="$(curl -fsS -u admin:admin -c "$COOKIE_JAR" "$BASE_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")"
[ -n "$CRUMB" ] || { echo "ERROR: could not obtain CSRF crumb" >&2; exit 1; }

# ------------------------------------------------------------- [6/7] create job
echo "[6/7] Creating Freestyle job '${JOB_NAME}' (Git SCM + shell)"
sed "s#https://github.com/[^/]*/devops-sample-code.git#${REPO_URL}#" "$JOB_XML" > "$RENDERED"
if curl -fsS -o /dev/null -u admin:admin "${BASE_URL}/job/${JOB_NAME}/api/json" 2>/dev/null; then
  curl -fsS -o /dev/null -u admin:admin -b "$COOKIE_JAR" -H "$CRUMB" -X POST "${BASE_URL}/job/${JOB_NAME}/doDelete"
  echo "  removed previous job"
fi
curl -fsS -o /dev/null -u admin:admin -b "$COOKIE_JAR" -H "$CRUMB" \
  -H "Content-Type: application/xml" --data-binary @"$RENDERED" \
  "${BASE_URL}/createItem?name=${JOB_NAME}"
echo "  job created: ${BASE_URL}/job/${JOB_NAME}"

# --------------------------------------------------------- [7/7] build + verify
echo "[7/7] Triggering build and waiting for the result"
trigger_code="$(curl -s -o /dev/null -w '%{http_code}' -u admin:admin -b "$COOKIE_JAR" -H "$CRUMB" -X POST "${BASE_URL}/job/${JOB_NAME}/build")"
echo "  trigger HTTP ${trigger_code}"
case "$trigger_code" in
  200|201|302) ;;
  *) echo "ERROR: build trigger failed (HTTP ${trigger_code})" >&2; exit 1 ;;
esac

build_num=""; result=""
for _ in $(seq 1 120); do
  j="$(curl -s -u admin:admin "${BASE_URL}/job/${JOB_NAME}/lastBuild/api/json?tree=number,building,result" 2>/dev/null || true)"
  if [ -n "$j" ]; then
    building="$(printf '%s' "$j" | grep -o '"building":[a-z]*' | head -1 | cut -d: -f2 || true)"
    if [ "$building" = "false" ]; then
      build_num="$(printf '%s' "$j" | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2 || true)"
      result="$(printf '%s' "$j" | grep -o '"result":"[A-Z]*"' | head -1 | cut -d'"' -f4 || true)"
      break
    fi
  fi
  sleep 3
done
[ -n "$build_num" ] || { echo "ERROR: build did not finish in time" >&2; exit 1; }

echo "  build #${build_num} finished: ${result}"
echo "  --- console output (tail) ---"
CONSOLE="$(curl -s -u admin:admin "${BASE_URL}/job/${JOB_NAME}/${build_num}/consoleText")"
printf '%s\n' "$CONSOLE" | tail -n 6 | sed 's/^/  | /'

printf '%s\n' "$CONSOLE" | grep -q "Hello, Jenkins!" || { echo "ERROR: console output missing 'Hello, Jenkins!'" >&2; exit 1; }
[ "$result" = "SUCCESS" ]                      || { echo "ERROR: build result was ${result}" >&2; exit 1; }

cat <<EOF

============================================================
 Exercise 8 complete
============================================================
 Repo    : ${REPO_URL%.git}
 Script  : echo "Hello, Jenkins!"
 Job     : ${BASE_URL}/job/${JOB_NAME}   (Freestyle, Git SCM)
 Build   : #${build_num} -> ${result}
 Console : "Hello, Jenkins!" then "Finished: SUCCESS"

 Open the job, click a build number -> Console Output to see it live.
============================================================
EOF

echo
echo "Container status:"
docker ps --filter "name=^/${CONTAINER_NAME}\$" --format '  {{.Names}}  {{.Status}}  {{.Ports}}'
echo
echo "Useful commands:"
echo "  logs    : docker logs -f ${CONTAINER_NAME}"
echo "  cleanup : ./cleanup.sh [--volume] [--image] [--github]"
