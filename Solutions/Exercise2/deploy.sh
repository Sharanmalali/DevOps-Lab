#!/usr/bin/env bash
# Exercise 2 - Flask on Minikube: build the image inside Minikube's Docker
# daemon, deploy the Flask app with its Service, and verify it end-to-end.
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools (minikube, docker) a truncated
# PATH that drops /c/Program Files/Docker/... — always put docker's directory
# at the very front so every native child resolves docker helpers correctly.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    export PATH="${_docker_dir}:${PATH}"
fi

echo "==> [1/5] Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH."; exit 1; }
command -v minikube >/dev/null 2>&1 || { echo "ERROR: minikube not found in PATH."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH."; exit 1; }

echo "==> [2/5] Ensuring Minikube cluster is running..."
if kubectl get nodes >/dev/null 2>&1; then
    echo "    Cluster already running."
else
    minikube start
fi

echo "==> [3/5] Building the flask-app image inside Minikube's Docker daemon..."
if ( eval "$(minikube docker-env --shell bash)" && docker build -t flask-app . >/dev/null 2>&1 ); then
    echo "    Image flask-app:latest built via 'minikube docker-env' (brief Step 4)."
else
    echo "    docker-env path unavailable - falling back to build + 'minikube image load'..."
    docker build -t flask-app . >/dev/null
    minikube image load flask-app
    echo "    Image flask-app:latest loaded into the cluster."
fi

echo "==> [4/5] Deploying the Flask application and Service..."
kubectl apply -f flask-deployment.yaml
kubectl rollout status deployment/flask-app --timeout=120s

echo "==> [5/5] Current state:"
kubectl get deployments
echo ""
kubectl get pods -l app=flask-app
echo ""
kubectl get svc flask-app-service

echo ""
echo "==> Verifying the app end-to-end via a temporary port-forward..."
PF_PORT=18081
kubectl port-forward svc/flask-app-service "${PF_PORT}:15000" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT

ok=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
    body="$(curl -fsS --max-time 5 "http://127.0.0.1:${PF_PORT}" 2>/dev/null || true)"
    if printf '%s' "${body}" | grep -q "Hello from Flask on Kubernetes!"; then
        ok=1
        break
    fi
    sleep 2
done

if [ -n "${ok}" ]; then
    echo "    SUCCESS: $(curl -fsS --max-time 5 "http://127.0.0.1:${PF_PORT}")"
else
    echo "    FAILED: Flask did not respond as expected on port ${PF_PORT}."
    exit 1
fi

echo ""
echo "To open the app in your browser, run:"
echo "    minikube service flask-app-service --url"
echo ""
echo "Done. Run './cleanup.sh' when you are finished."
