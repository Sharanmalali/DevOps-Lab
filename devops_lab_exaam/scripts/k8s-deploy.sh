#!/usr/bin/env bash
# Part B - Minikube: load image, deploy DB + API, verify.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/5] Start Minikube (docker driver)"
minikube status >/dev/null 2>&1 || minikube start --driver=docker --memory=3072 --cpus=2

echo "[2/5] Build image and load it into the Minikube node"
docker build -t patient-api:1.0 .
minikube image load patient-api:1.0

echo "[3/5] Apply manifests (Secret, PVC, DB Deployment+Service, API Deployment+Service)"
kubectl apply -f k8s/

echo "[4/5] Wait for rollouts"
kubectl rollout status deployment/patient-db  --timeout=180s
kubectl rollout status deployment/patient-api --timeout=180s

echo "[5/5] Resources"
kubectl get deploy,rs,pods,svc -o wide
echo
echo "DB name resolution from an API pod:"
kubectl exec deploy/patient-api -- python -c "import socket; print('  patient-db ->', socket.gethostbyname('patient-db'))"
echo
echo "Next:"
echo "  minikube service patient-api --url        # keep this terminal open (macOS tunnel)"
echo "  ./scripts/test-api.sh <URL printed above>"
echo "  ./scripts/apparmor-setup.sh               # AppArmor (Linux) / hardening check (macOS)"
