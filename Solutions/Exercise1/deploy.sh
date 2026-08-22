#!/usr/bin/env bash
# Exercise 1 - Hello Pod: start Minikube, deploy nginx, expose it, verify.
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

echo "==> [1/5] Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH."; exit 1; }
command -v minikube >/dev/null 2>&1 || { echo "ERROR: minikube not found in PATH."; exit 1; }

echo "==> [2/5] Ensuring Minikube cluster is running..."
if kubectl get nodes >/dev/null 2>&1; then
    echo "    Cluster already running."
else
    minikube start
fi

echo "==> [3/5] Deploying the nginx pod and NodePort service..."
kubectl apply -f pod.yaml -f service.yaml

echo "==> [4/5] Waiting for pod hello-k8s to be Ready..."
kubectl wait --for=condition=Ready pod/hello-k8s --timeout=120s

echo "==> [5/5] Current state:"
kubectl get pods -o wide
echo ""
kubectl get svc hello-k8s

echo ""
echo "==> Verifying the app end-to-end via a temporary port-forward..."
PF_PORT=18080
kubectl port-forward svc/hello-k8s "${PF_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT

ok=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS --max-time 5 "http://127.0.0.1:${PF_PORT}" 2>/dev/null | head -n 1 | grep -qi html; then
        ok=1
        break
    fi
    sleep 2
done

if [ -n "${ok}" ]; then
    echo "    SUCCESS: nginx responded with the HTML welcome page."
else
    echo "    FAILED: no HTTP response on port ${PF_PORT}."
    exit 1
fi

echo ""
echo "To open the app in your browser, run:"
echo "    minikube service hello-k8s"
echo ""
echo "Done. Run './cleanup.sh' when you are finished."
