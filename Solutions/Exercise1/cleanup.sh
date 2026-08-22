#!/usr/bin/env bash
# Exercise 1 - Hello Pod: remove the service and pod created by deploy.sh.
# Usage:
#   ./cleanup.sh            delete the service and pod (cluster keeps running)
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

echo "==> Deleting service hello-k8s (if it exists)..."
kubectl delete service hello-k8s --ignore-not-found

echo "==> Deleting pod hello-k8s (if it exists)..."
kubectl delete pod hello-k8s --ignore-not-found

if [[ "${1:-}" == "--cluster" ]]; then
    echo "==> Stopping Minikube..."
    minikube stop
fi

echo "Cleanup complete."
