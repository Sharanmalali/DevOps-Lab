#!/usr/bin/env bash
# Exercise 5 - cleanup: remove the containers created by apply_apparmor.py /
# test_restricted_actions.py (and optionally the flask-apparmor image).
# Usage:
#   ./cleanup.sh          remove flask-apparmor containers (image kept)
#   ./cleanup.sh --image  also remove the flask-apparmor image
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools a truncated PATH that drops
# /c/Program Files/Docker/... — always put docker's directory at the front.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    export PATH="${_docker_dir}:${PATH}"
fi

echo "==> Removing flask-apparmor containers (running and stopped)..."
ids="$(docker ps -a --filter ancestor=flask-apparmor -q || true)"
if [ -n "${ids}" ]; then
    # shellcheck disable=SC2086
    docker rm -f ${ids} >/dev/null
    echo "    Removed $(printf '%s\n' ${ids} | wc -l | tr -d ' ') container(s)."
else
    echo "    No flask-apparmor containers found - nothing to remove."
fi

if [[ "${1:-}" == "--image" ]]; then
    echo "==> Removing image flask-apparmor..."
    docker rmi flask-apparmor >/dev/null 2>&1 || {
        echo "    Image not found or still in use - skipped."
    }
fi

# The AppArmor profile itself is left alone: on this host it is never
# loaded into a kernel (see README "Platform notes"); on Linux hosts
# unload it with:  sudo apparmor_parser -R /etc/apparmor.d/my-apparmor-profile
echo "Cleanup complete."
