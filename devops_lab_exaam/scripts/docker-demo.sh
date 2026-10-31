#!/usr/bin/env bash
# Part A - Docker: custom bridge network, DB + API containers, connectivity checks.
set -euo pipefail
cd "$(dirname "$0")/.."

NET=patient-net
HOST_PORT=5050        # macOS uses 5000 for AirPlay Receiver, so publish on 5050

echo "[1/6] Build the API image"
docker build -t patient-api:1.0 .

echo "[2/6] Create custom bridge network '${NET}'"
docker network inspect "$NET" >/dev/null 2>&1 || docker network create --driver bridge "$NET"

echo "[3/6] Start PostgreSQL (NO -p flag -> port 5432 is NOT published)"
docker rm -f patient-db >/dev/null 2>&1 || true
docker run -d --name patient-db --network "$NET" \
  -e POSTGRES_DB=patients -e POSTGRES_USER=patient_app -e POSTGRES_PASSWORD=DemoPass123 \
  -v patient-db-data:/var/lib/postgresql/data \
  postgres:16-alpine

echo "[4/6] Start the API (only port published) with hardened runtime options"
APPARMOR_OPT=()
if docker info --format '{{.SecurityOptions}}' | grep -q apparmor \
   && sudo -n true 2>/dev/null && sudo apparmor_parser -r -W apparmor/k8s-patient-api 2>/dev/null; then
  APPARMOR_OPT=(--security-opt apparmor=k8s-patient-api)
  echo "  AppArmor supported - using profile k8s-patient-api"
else
  echo "  AppArmor not supported on this Docker host (e.g. Docker Desktop on macOS) - using hardening only"
fi
docker rm -f patient-api >/dev/null 2>&1 || true
docker run -d --name patient-api --network "$NET" -p "${HOST_PORT}:5000" \
  -e DB_HOST=patient-db -e DB_PASSWORD=DemoPass123 \
  --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges:true \
  ${APPARMOR_OPT[@]+"${APPARMOR_OPT[@]}"} \
  patient-api:1.0

echo "[5/6] Wait for the API"
for _ in $(seq 1 30); do
  curl -fs "http://localhost:${HOST_PORT}/health" >/dev/null 2>&1 && break
  sleep 1
done
docker ps --filter network="$NET" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo "[6/6] Connectivity checks"
echo "  Containers on ${NET}:"
docker network inspect "$NET" --format '{{range .Containers}}    {{.Name}}  {{.IPv4Address}}{{"\n"}}{{end}}'
echo "  DNS lookup of the DB container name from inside the API container:"
docker exec patient-api python -c "import socket; print('    patient-db ->', socket.gethostbyname('patient-db'))"
echo "  /health (Flask -> PostgreSQL via name 'patient-db'):"
echo "    $(curl -s "http://localhost:${HOST_PORT}/health")"
echo "  Published ports - patient-api: $(docker port patient-api | head -1)"
echo "  Published ports - patient-db : $(docker port patient-db || true) (empty = not published)"

echo
echo "Next: ./scripts/test-api.sh http://localhost:${HOST_PORT}"
echo "      docker exec patient-api python security_test.py"
