#!/usr/bin/env bash
# Exercise 2 - Flask on Minikube: remove the deployment and service.
# Usage:
#   ./cleanup.sh            delete deployment + service (cluster keeps running)
#   ./cleanup.sh --cluster   also stop the Minikube cluster
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools (minikube, docker) a truncated
# PATH that drops /c/Program Files/Docker/... — always put docker's directory
# at the very front so every native child resolves docker helpers correctly.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    export PATH="${_docker_dir}:${PATH}"
fi

echo "==> Deleting service flask-app-service (if it exists)..."
kubectl delete service flask-app-service --ignore-not-found

echo "==> Deleting deployment flask-app (if it exists)..."
kubectl delete deployment flask-app --ignore-not-found

if [[ "${1:-}" == "--cluster" ]]; then
    echo "==> Stopping Minikube..."
    minikube stop
fi

echo "Cleanup complete."
