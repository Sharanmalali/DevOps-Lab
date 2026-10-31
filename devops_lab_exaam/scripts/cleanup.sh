#!/usr/bin/env bash
# Remove everything created by the demo.
#   ./scripts/cleanup.sh           # Docker containers/network/volume + K8s resources
#   ./scripts/cleanup.sh --all     # also delete the Minikube cluster
cd "$(dirname "$0")/.."

docker rm -f patient-api patient-db patient-api-broken 2>/dev/null
docker network rm patient-net 2>/dev/null
docker volume rm patient-db-data 2>/dev/null
kubectl delete -f k8s/ --ignore-not-found 2>/dev/null
[ "${1:-}" = "--all" ] && minikube delete
echo "Cleanup done."
