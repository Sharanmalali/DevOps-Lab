#!/usr/bin/env bash
# Exercise 4 - Docker networking: Task 6 cleanup - stop/remove the three lab
# containers and the bridge network.
# Usage:
#   ./cleanup.sh          remove containers + network (flask-api image kept)
#   ./cleanup.sh --image  also remove the flask-api image
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools a truncated PATH that drops
# /c/Program Files/Docker/... — always put docker's directory at the front.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    export PATH="${_docker_dir}:${PATH}"
fi

echo "==> Task 6: Stopping and removing containers (mysql, redis, flask)..."
existing="$(docker ps -a --format '{{.Names}}' | grep -Ex 'mysql|redis|flask' || true)"
if [ -n "${existing}" ]; then
    echo "    Stopping: $(printf '%s' "${existing}" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    docker stop ${existing} >/dev/null
    # shellcheck disable=SC2086
    docker rm ${existing} >/dev/null
    echo "    Removed."
else
    echo "    None of the lab containers exist - nothing to remove."
fi

echo "==> Removing network my-bridge-net..."
if docker network inspect my-bridge-net >/dev/null 2>&1; then
    docker network rm my-bridge-net
else
    echo "    Network does not exist - nothing to remove."
fi

if [[ "${1:-}" == "--image" ]]; then
    echo "==> Removing image flask-api..."
    docker rmi flask-api >/dev/null || true
fi

echo "Cleanup complete."
