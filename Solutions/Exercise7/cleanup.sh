#!/usr/bin/env bash
#
# Exercise 7 - remove the Jenkins controller created by deploy.sh
#
# Usage:
#   ./cleanup.sh              # remove the container only
#   ./cleanup.sh --volume     # also delete the jenkins_home data volume
#   ./cleanup.sh --image      # also remove the jenkins/jenkins:lts image
#   ./cleanup.sh --volume --image
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

JENKINS_IMAGE="jenkins/jenkins:lts"
CONTAINER_NAME="jenkins"
VOLUME_NAME="ex7_jenkins_home"

REMOVE_VOLUME=0
REMOVE_IMAGE=0
for arg in "$@"; do
  case "$arg" in
    --volume|--volumes) REMOVE_VOLUME=1 ;;
    --image)            REMOVE_IMAGE=1 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1 ;;
  esac
done

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH" >&2; exit 1; }

echo "[1/3] Removing container '${CONTAINER_NAME}'"
if docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "  removed"
else
  echo "  not present (already gone)"
fi

echo "[2/3] Data volume '${VOLUME_NAME}'"
if [ "$REMOVE_VOLUME" -eq 1 ]; then
  if docker volume rm "$VOLUME_NAME" >/dev/null 2>&1; then
    echo "  removed"
  else
    echo "  not present (already gone)"
  fi
else
  echo "  kept (pass --volume to delete Jenkins configuration/history)"
fi

echo "[3/3] Image '${JENKINS_IMAGE}'"
if [ "$REMOVE_IMAGE" -eq 1 ]; then
  if docker image rm "$JENKINS_IMAGE" >/dev/null 2>&1; then
    echo "  removed"
  else
    echo "  not removed (in use or already gone)"
  fi
else
  echo "  kept (pass --image to remove)"
fi

echo
echo "Cleanup complete."
