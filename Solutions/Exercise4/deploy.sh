#!/usr/bin/env bash
# Exercise 4 - Docker networking: create a bridge network, run Flask + MySQL +
# Redis on it, and prove name-based connectivity (Tasks 1-5 of the brief).
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools a truncated PATH that drops
# /c/Program Files/Docker/... — always put docker's directory at the front.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    export PATH="${_docker_dir}:${PATH}"
fi

echo "==> [1/6] Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH."; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not running."; exit 1; }

echo "==> [2/6] Task 1+2: Creating the bridge network and listing it..."
if docker network inspect my-bridge-net >/dev/null 2>&1; then
    echo "    Network my-bridge-net already exists - reusing it."
else
    docker network create --driver bridge my-bridge-net
fi
docker network ls --filter driver=bridge

echo "==> [3/6] Task 3: Inspecting my-bridge-net..."
docker network inspect my-bridge-net --format \
'    Name:    {{.Name}}
    Driver:  {{.Driver}}
    Scope:   {{.Scope}}
    Subnet:  {{range .IPAM.Config}}{{.Subnet}}{{end}}
    Gateway: {{range .IPAM.Config}}{{.Gateway}}{{end}}
    Attached containers: {{len .Containers}}'

echo "==> [4/6] Task 4: Building flask-api and launching the 3 containers..."
docker build -q -t flask-api . >/dev/null
echo "    Image flask-api built."
# Stale copies from a previous run — only our three lab container names.
docker rm -f mysql redis flask >/dev/null 2>&1 || true
# The brief runs plain `mysql:latest`, but modern mysql images refuse to start
# without a root password env var (container would exit instantly).
docker run -d --name mysql --net=my-bridge-net -e MYSQL_ROOT_PASSWORD=root mysql:latest >/dev/null
docker run -d --name redis --net=my-bridge-net redis:latest >/dev/null
docker run -d --name flask --net=my-bridge-net -p 5001:5001 flask-api >/dev/null
echo "    Started: mysql, redis, flask on my-bridge-net (flask published on host :5001)."

echo "==> [5/6] Task 5: Verifying container-to-container connectivity..."
echo "    Waiting for mysqld to finish first-time initialisation (up to 90s)..."
mysql_ready=""
for _ in $(seq 1 45); do
    if docker exec mysql mysqladmin ping -uroot -proot --silent >/dev/null 2>&1; then
        mysql_ready=1
        break
    fi
    sleep 2
done
if [ -n "${mysql_ready}" ]; then
    echo "    mysql is ready (mysqladmin ping OK)."
else
    echo "    WARNING: mysqld not answering yet - ICMP ping below still proves the network."
fi

echo "    From inside the flask container: ping mysql"
docker exec flask ping -c 3 mysql
echo "    From inside the flask container: ping redis"
docker exec flask ping -c 3 redis

echo "==> [6/6] Verifying host -> flask via the published port, final state..."
body="$(curl -fsS --max-time 5 http://127.0.0.1:5001/about 2>/dev/null || true)"
if printf '%s' "${body}" | grep -q "Simple REST API"; then
    echo "    SUCCESS: GET http://127.0.0.1:5001/about ->"
    printf '%s\n' "${body}" | sed 's/^/      /'
else
    echo "    FAILED: flask did not answer on port 5001. Recent logs:"
    docker logs flask 2>&1 | tail -n 10
    exit 1
fi
echo ""
docker ps --filter name=mysql --filter name=redis --filter name=flask \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo ""
echo "Done. Run './cleanup.sh' when you are finished."
