#!/usr/bin/env bash
# Exercise 1 - Hello Pod: remove the service and pod created by deploy.sh.
# Usage:
#   ./cleanup.sh            delete the service and pod (cluster keeps running)
#   ./cleanup.sh --cluster   also stop the Minikube cluster
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools (minikube) a truncated PATH, so
# minikube may not find docker. Keep docker's directory at the front of PATH.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    case ":${PATH}:" in
        *":${_docker_dir}:"*) ;;
        *) export PATH="${_docker_dir}:${PATH}" ;;
    esac
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
