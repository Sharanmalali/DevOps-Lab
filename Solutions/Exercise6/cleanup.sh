#!/usr/bin/env bash
# Exercise 6 - cleanup: stop the delivery metrics simulator and remove the
# Prometheus / Grafana / Jenkins / delivery_metrics containers + lab network.
# Usage:
#   ./cleanup.sh            containers + network (+ host simulator)
#   ./cleanup.sh --image    also remove the delivery_metrics and ex6-jenkins images
#   ./cleanup.sh --volumes  also remove the jenkins_home volume
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools a truncated PATH that drops
# /c/Program Files/Docker/... — always put docker's directory at the front.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    export PATH="${_docker_dir}:${PATH}"
fi

PID_FILE="${TMPDIR:-/tmp}/ex6-delivery_metrics.pid"

echo "==> Stopping the delivery metrics simulator (Step 1 process)..."
stopped=""
if [ -f "${PID_FILE}" ]; then
    pid="$(cat "${PID_FILE}")"
    if MSYS2_ARG_CONV_EXCL='*' taskkill /F /PID "${pid}" >/dev/null 2>&1; then
        stopped="pid ${pid}"
    fi
    rm -f "${PID_FILE}"
fi
# Fall back to whoever owns the metrics port - but only kill it if the
# response proves it is OUR simulator (some other app may use port 8000).
if curl -fsS --max-time 3 http://127.0.0.1:8000/metrics 2>/dev/null | grep -q pending_deliveries; then
    owner="$(netstat -ano 2>/dev/null | grep ':8000[[:space:]].*LISTENING' | awk '{print $NF}' | head -1)"
    if [ -n "${owner}" ] && MSYS2_ARG_CONV_EXCL='*' taskkill /F /PID "${owner}" >/dev/null 2>&1; then
        stopped="${stopped:+${stopped}, }port-8000 owner pid ${owner}"
    fi
fi
if [ -n "${stopped}" ]; then
    echo "    Stopped simulator (${stopped})."
else
    echo "    Simulator not running - nothing to stop."
fi

echo "==> Removing containers (prometheus, grafana, jenkins, delivery_metrics)..."
existing="$(docker ps -a --format '{{.Names}}' | grep -Ex 'prometheus|grafana|jenkins|delivery_metrics' || true)"
if [ -n "${existing}" ]; then
    # shellcheck disable=SC2086
    docker rm -f ${existing} >/dev/null
    echo "    Removed: $(printf '%s' "${existing}" | tr '\n' ' ')"
else
    echo "    None of the lab containers exist - nothing to remove."
fi

echo "==> Removing network ex6-net..."
if docker network inspect ex6-net >/dev/null 2>&1; then
    docker network rm ex6-net >/dev/null
    echo "    Removed."
else
    echo "    Network does not exist - nothing to remove."
fi

if [[ "${1:-}" == "--image" ]]; then
    echo "==> Removing images delivery_metrics, ex6-jenkins..."
    docker rmi delivery_metrics ex6-jenkins >/dev/null 2>&1 || echo "    Some images were not present - skipped."
fi

if [[ "${1:-}" == "--volumes" ]]; then
    echo "==> Removing volume jenkins_home..."
    docker volume rm jenkins_home >/dev/null 2>&1 || echo "    Volume does not exist - skipped."
fi

echo "Cleanup complete."
