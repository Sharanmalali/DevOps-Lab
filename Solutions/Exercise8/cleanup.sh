#!/usr/bin/env bash
#
# Exercise 8 - remove the resources created by deploy.sh
#
# Usage:
#   ./cleanup.sh                 # remove the Jenkins container only
#   ./cleanup.sh --volume        # also delete the ex8_jenkins_home data volume
#   ./cleanup.sh --image         # also remove the ex8-jenkins image
#   ./cleanup.sh --github        # also delete the devops-sample-code repo
#                                # (needs GITHUB_TOKEN; DESTRUCTIVE)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export MSYS2_ARG_CONV_EXCL='*'

DOCKER_BIN_DIR="$(dirname "$(command -v docker 2>/dev/null || echo /usr/bin/docker)")"
case ":$PATH:" in
  *":$DOCKER_BIN_DIR:"*) ;;
  *) PATH="$DOCKER_BIN_DIR:$PATH" ;;
esac
export PATH

JENKINS_IMAGE="ex8-jenkins"
CONTAINER_NAME="jenkins"
VOLUME_NAME="ex8_jenkins_home"
REPO_NAME="devops-sample-code"
FALLBACK_OWNER="shreyassridhar44"

REMOVE_VOLUME=0
REMOVE_IMAGE=0
REMOVE_GITHUB=0
for arg in "$@"; do
  case "$arg" in
    --volume|--volumes) REMOVE_VOLUME=1 ;;
    --image)            REMOVE_IMAGE=1 ;;
    --github)           REMOVE_GITHUB=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH" >&2; exit 1; }

echo "[1/4] Removing container '${CONTAINER_NAME}'"
if docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1; then echo "  removed"; else echo "  not present (already gone)"; fi

echo "[2/4] Data volume '${VOLUME_NAME}'"
if [ "$REMOVE_VOLUME" -eq 1 ]; then
  if docker volume rm "$VOLUME_NAME" >/dev/null 2>&1; then echo "  removed"; else echo "  not present (already gone)"; fi
else
  echo "  kept (pass --volume to delete Jenkins configuration/history)"
fi

echo "[3/4] Image '${JENKINS_IMAGE}'"
if [ "$REMOVE_IMAGE" -eq 1 ]; then
  if docker image rm "$JENKINS_IMAGE" >/dev/null 2>&1; then echo "  removed"; else echo "  not removed (in use or already gone)"; fi
else
  echo "  kept (pass --image to remove)"
fi

echo "[4/4] GitHub repo '${REPO_NAME}'"
if [ "$REMOVE_GITHUB" -eq 1 ]; then
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "  skipped: GITHUB_TOKEN not set (needed to delete the repo)"
  else
    owner="$(curl -fsS -H "User-Agent: ex8-cleanup" -H "Authorization: token ${GITHUB_TOKEN}" "https://api.github.com/user" | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$owner" ] || owner="$FALLBACK_OWNER"
    if curl -fsS -o /dev/null -H "User-Agent: ex8-cleanup" -H "Authorization: token ${GITHUB_TOKEN}" \
        -X DELETE "https://api.github.com/repos/${owner}/${REPO_NAME}"; then
      echo "  deleted ${owner}/${REPO_NAME}"
    else
      echo "  could not delete ${owner}/${REPO_NAME} (missing or no permission)"
    fi
  fi
else
  echo "  kept (pass --github to delete; DESTRUCTIVE)"
fi

echo
echo "Cleanup complete."
