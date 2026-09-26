#!/usr/bin/env bash
# Exercise 6 - Real-time operations monitoring & alerting:
#   Step 1: Python metrics simulator on the host
#   Step 2: Prometheus scraping it + alert rules
#   Step 3: Grafana with provisioned datasource + dashboard
#   Step 5: Jenkins running the exercise's pipeline (Docker-out-of-Docker)
#   Step 6: verify the alerts actually fire (Expected Output 5)
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools a truncated PATH that drops
# /c/Program Files/Docker/... — always put docker's directory at the front.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    export PATH="${_docker_dir}:${PATH}"
fi

PYTHON="${PYTHON:-python}"
# Stop MSYS (Git Bash) from rewriting docker's mount arguments, e.g.
# /var/run/docker.sock -> C:/Program Files/Git/var/run/...
export MSYS2_ARG_CONV_EXCL='*'
SCRIPT_DIR="$(pwd -W 2>/dev/null || pwd)"   # C:\... path for docker -v on Docker Desktop
# Forward-slash form: the daemon (and a Linux docker CLI inside containers)
# can resolve "C:/..." bind sources; backslashes cannot.
HOST_SRC="${SCRIPT_DIR//\\//}"
METRICS_URL="http://127.0.0.1:8000/metrics"
METRICS_LOG="${TMPDIR:-/tmp}/ex6-delivery_metrics.log"
METRICS_PID_FILE="${TMPDIR:-/tmp}/ex6-delivery_metrics.pid"
JOB_NAME="delivery-monitoring"
NET="ex6-net"

port_busy() { netstat -ano 2>/dev/null | grep -E ":$1[[:space:]]" | grep -q LISTENING; }

# Remove our own (possibly stale) lab containers first so their published
# ports don't trip the port checks below. Only the exact lab names are
# touched - other containers on the machine are left alone.
docker rm -f prometheus grafana jenkins delivery_metrics >/dev/null 2>&1 || true

echo "==> [1/8] Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH."; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not running."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found (use Git Bash / WSL)."; exit 1; }
command -v "$PYTHON" >/dev/null 2>&1 || {
    echo "ERROR: '$PYTHON' not found (set PYTHON=/path/to/python if needed)."; exit 1; }
if ! "$PYTHON" -c "import prometheus_client" >/dev/null 2>&1; then
    echo "    Installing prometheus-client (brief step 2a: pip install prometheus-client)..."
    "$PYTHON" -m pip install --quiet prometheus-client
    "$PYTHON" -c "import prometheus_client" || { echo "ERROR: could not install prometheus-client."; exit 1; }
fi
echo "    prometheus-client: $("$PYTHON" -c "from importlib.metadata import version; print(version('prometheus-client'))")"

# Port allocation. 8080 is taken by an unrelated httpd on this machine, so
# Jenkins falls back to 8081 (see README "Brief clean-ups").
if [ -z "${JENKINS_PORT:-}" ]; then
    if port_busy 8080; then
        JENKINS_PORT=8081
        echo "    [NOTICE] Port 8080 busy (not ours) - Jenkins UI on http://localhost:8081"
    else
        JENKINS_PORT=8080
    fi
fi
if [ -z "${JENKINS_AGENT_PORT:-}" ]; then
    if port_busy 50000; then JENKINS_AGENT_PORT=50001; else JENKINS_AGENT_PORT=50000; fi
fi
for p in 9090 3000 "${JENKINS_PORT}" "${JENKINS_AGENT_PORT}"; do
    if port_busy "${p}"; then
        echo "ERROR: port ${p} is already in use by another process."; exit 1
    fi
done
if docker network inspect "${NET}" >/dev/null 2>&1; then
    echo "    Network ${NET} already exists - reusing it."
else
    docker network create "${NET}" >/dev/null
    echo "    Network ${NET} created."
fi

echo "==> [2/8] Pulling images and building the lab images..."
docker pull prom/prometheus >/dev/null
docker pull grafana/grafana >/dev/null
docker pull jenkins/jenkins:lts >/dev/null
docker build -q -t delivery_metrics . >/dev/null
docker build -q -t ex6-jenkins -f Dockerfile.jenkins . >/dev/null
echo "    Images ready: prom/prometheus, grafana/grafana, jenkins/jenkins:lts, delivery_metrics, ex6-jenkins"

echo "==> [3/8] Step 1: Starting the delivery metrics simulator (host python)..."
if curl -fsS --max-time 3 "${METRICS_URL}" 2>/dev/null | grep -q pending_deliveries; then
    echo "    Simulator already serving on :8000 - reusing it."
    # Record the port owner so cleanup.sh (and the final summary) can stop it
    if [ ! -f "${METRICS_PID_FILE}" ]; then
        _owner="$(netstat -ano 2>/dev/null | grep ':8000[[:space:]].*LISTENING' | awk '{print $NF}' | head -1)"
        [ -n "${_owner}" ] && echo "${_owner}" >"${METRICS_PID_FILE}"
    fi
elif port_busy 8000; then
    echo "ERROR: port 8000 is in use by something that is not our simulator."; exit 1
else
    nohup "$PYTHON" delivery_metrics.py >"${METRICS_LOG}" 2>&1 &
    echo $! >"${METRICS_PID_FILE}"
    for _ in $(seq 1 15); do
        curl -fsS --max-time 2 "${METRICS_URL}" >/dev/null 2>&1 && break
        sleep 1
    done
    echo "    Started (pid $(cat "${METRICS_PID_FILE}"), log ${METRICS_LOG})."
fi
for m in total_deliveries pending_deliveries on_the_way_deliveries average_delivery_time_sum; do
    curl -fsS --max-time 3 "${METRICS_URL}" | grep -q "^${m} " \
        || { echo "ERROR: metric ${m} missing from ${METRICS_URL}"; exit 1; }
done
echo "    GET ${METRICS_URL} -> all 4 delivery metrics present."

echo "==> [4/8] Step 2: Starting Prometheus..."
docker rm -f prometheus >/dev/null 2>&1 || true
docker run -d --name prometheus --network "${NET}" -p 9090:9090 \
    --add-host=host.docker.internal:host-gateway \
    -v "${SCRIPT_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml" \
    -v "${SCRIPT_DIR}/alert_rules.yml:/etc/prometheus/alert_rules.yml" \
    prom/prometheus >/dev/null
ups=0
for _ in $(seq 1 25); do
    ups="$(curl -fsS --max-time 3 http://127.0.0.1:9090/api/v1/targets 2>/dev/null | grep -o '"health":"up"' | wc -l | tr -d ' ' || true)"
    [ "${ups:-0}" -ge 2 ] && break
    sleep 3
done
if [ "${ups:-0}" -lt 2 ]; then
    echo "ERROR: not all Prometheus targets came up (${ups} up). Recent logs:"
    docker logs prometheus 2>&1 | tail -n 15; exit 1
fi
echo "    Targets up: ${ups}/2 (prometheus self + delivery_service)."
curl -fsS http://127.0.0.1:9090/api/v1/rules | grep -q HighPendingDeliveries \
    || { echo "ERROR: alert rules not loaded."; exit 1; }
curl -fsS http://127.0.0.1:9090/api/v1/rules | grep -q HighAverageDeliveryTime \
    || { echo "ERROR: alert rules not loaded."; exit 1; }
echo "    Alert rules loaded: HighPendingDeliveries, HighAverageDeliveryTime."

echo "==> [5/8] Step 3: Starting Grafana with provisioned datasource + dashboard..."
docker rm -f grafana >/dev/null 2>&1 || true
docker run -d --name grafana --network "${NET}" -p 3000:3000 \
    -v "${SCRIPT_DIR}/provisioning/datasources:/etc/grafana/provisioning/datasources" \
    -v "${SCRIPT_DIR}/provisioning/dashboards:/etc/grafana/provisioning/dashboards" \
    grafana/grafana >/dev/null
healthy=""
for _ in $(seq 1 30); do
    if curl -fsS --max-time 3 -u admin:admin http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
        healthy=1; break
    fi
    sleep 3
done
[ -n "${healthy}" ] || { echo "ERROR: Grafana did not become healthy. Logs:"; docker logs grafana 2>&1 | tail -n 15; exit 1; }
curl -fsS -u admin:admin http://127.0.0.1:3000/api/datasources | grep -q '"name":"Prometheus"' \
    || { echo "ERROR: Prometheus datasource not provisioned."; exit 1; }
panels="$(curl -fsS -u admin:admin http://127.0.0.1:3000/api/dashboards/uid/delivery-operations \
    | "$PYTHON" -c "import sys,json;print(len(json.load(sys.stdin)['dashboard']['panels']))")"
[ "${panels}" = "4" ] || { echo "ERROR: dashboard has ${panels} panels, expected 4."; exit 1; }
echo "    Grafana healthy; datasource 'Prometheus' provisioned; dashboard has ${panels}/4 panels."

echo "==> [6/8] Step 5: Starting Jenkins and running the pipeline..."
docker rm -f jenkins >/dev/null 2>&1 || true
# The named volume keeps old plugin jars from a previous image; drop it so
# every deploy boots Jenkins with exactly the plugins baked into ex6-jenkins.
docker volume rm jenkins_home >/dev/null 2>&1 || true
docker run -d --name jenkins \
    -p "${JENKINS_PORT}:8080" -p "${JENKINS_AGENT_PORT}:50000" \
    -e JAVA_OPTS="-Djenkins.install.runSetupWizard=false" \
    -e EX6_HOST_SRC="${HOST_SRC}" \
    -e EX6_SOURCE_DIR="/workspace-src" \
    -v jenkins_home:/var/jenkins_home \
    -v "${SCRIPT_DIR}:/workspace-src:ro" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --group-add 0 \
    --network "${NET}" \
    --add-host=host.docker.internal:host-gateway \
    ex6-jenkins >/dev/null
J="http://127.0.0.1:${JENKINS_PORT}"
for _ in $(seq 1 60); do
    curl -fsS --max-time 3 "${J}/login" >/dev/null 2>&1 && break
    sleep 4
done
curl -fsS --max-time 3 "${J}/login" >/dev/null 2>&1 || {
    echo "ERROR: Jenkins did not come up on ${J}. Logs:"; docker logs jenkins 2>&1 | tail -n 20; exit 1; }
echo "    Jenkins up on ${J} (wizard disabled so the job can be scripted)."

JOB_XML="${TMPDIR:-/tmp}/ex6-job.xml"
"$PYTHON" - "${JOB_XML}" <<'PYEOF'
import sys
import xml.sax.saxutils as xu

script = open("Jenkinsfile", encoding="utf-8").read()
body = xu.escape(script)
job_xml = (
    "<?xml version='1.1' encoding='UTF-8'?>"
    '<flow-definition plugin="workflow-job">'
    "<description>Exercise 6 - delivery monitoring pipeline</description>"
    "<keepDependencies>false</keepDependencies>"
    "<properties/>"
    '<definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">'
    "<script>" + body + "</script><sandbox>true</sandbox></definition>"
    "<triggers/><disabled>false</disabled></flow-definition>"
)
open(sys.argv[1], "w", encoding="utf-8").write(job_xml)
PYEOF

jar="$(mktemp)"
crumb="$(curl -fsS -c "${jar}" "${J}/crumbIssuer/api/json" \
    | "$PYTHON" -c "import sys,json;print(json.load(sys.stdin)['crumb'])")"
curl -fsS -b "${jar}" -c "${jar}" -X POST -H "Jenkins-Crumb: ${crumb}" \
    "${J}/job/${JOB_NAME}/doDelete" >/dev/null 2>&1 || true
curl -fsS -b "${jar}" -c "${jar}" -X POST -H "Jenkins-Crumb: ${crumb}" \
    -H "Content-Type: application/xml" --data-binary "@${JOB_XML}" \
    "${J}/createItem?name=${JOB_NAME}" >/dev/null
echo "    Job '${JOB_NAME}' created from the Jenkinsfile."
curl -fsS -b "${jar}" -X POST -H "Jenkins-Crumb: ${crumb}" \
    "${J}/job/${JOB_NAME}/build" >/dev/null
echo "    Build queued - waiting for the result (up to 10 min)..."

build_state=""
for _ in $(seq 1 200); do
        # lastBuild (not the job itself) is where building/result live
        json="$(curl -fsS --max-time 5 "${J}/job/${JOB_NAME}/lastBuild/api/json?tree=building,result,number" 2>/dev/null || true)"
    if [ -n "${json}" ]; then
        building="$(printf '%s' "${json}" | "$PYTHON" -c "import sys,json;print(json.load(sys.stdin).get('building'))" 2>/dev/null || echo None)"
        if [ "${building}" = "False" ]; then
            build_state="$(printf '%s' "${json}" | "$PYTHON" -c "import sys,json;print(json.load(sys.stdin).get('result'))")"
            break
        fi
    fi
    sleep 3
done
console="$(curl -fsS "${J}/job/${JOB_NAME}/lastBuild/consoleText" 2>/dev/null || true)"
if [ "${build_state}" != "SUCCESS" ]; then
    echo "ERROR: pipeline result: ${build_state:-timeout}. Last 60 console lines:"
    printf '%s\n' "${console}" | tail -n 60
    exit 1
fi
echo "    Pipeline result: SUCCESS."
printf '%s\n' "${console}" | tail -n 25 | sed 's/^/    | /'

echo "==> [7/8] Step 6: Waiting for alerts to fire (Expected Output 5)..."
firing=0
for _ in $(seq 1 50); do
    firing="$(curl -fsS --max-time 3 http://127.0.0.1:9090/api/v1/alerts 2>/dev/null \
        | grep -o '"state":"firing"' | wc -l | tr -d ' ' || true)"
    [ "${firing:-0}" -ge 1 ] && break
    sleep 3
done
ALERTS_JSON="$(curl -fsS http://127.0.0.1:9090/api/v1/alerts)"
if [ "${firing:-0}" -ge 1 ]; then
    printf '%s' "${ALERTS_JSON}" | "$PYTHON" -c "
import sys, json
for a in json.load(sys.stdin)['data']['alerts']:
    if a['state'] == 'firing':
        print('    firing  %-26s severity=%s' % (a['labels'].get('alertname'), a['labels'].get('severity')))"
else
    echo "ERROR: no alerts fired within 150s. Rules/expr check:"
    printf '%s' "${ALERTS_JSON}" | head -c 400; echo
    exit 1
fi

echo "==> [8/8] Final state..."
docker ps --filter name=prometheus --filter name=grafana --filter name=jenkins --filter name=delivery_metrics \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo ""
echo "    Metrics : ${METRICS_URL}          (host python, pid $(cat "${METRICS_PID_FILE}" 2>/dev/null || echo '?'))"
echo "    Prometheus: http://localhost:9090   (Status -> Targets, Alerts)"
echo "    Grafana   : http://localhost:3000   (admin/admin, dashboard 'Delivery Operations Monitoring')"
echo "    Jenkins   : ${J}  (pipeline '${JOB_NAME}' = SUCCESS)"
echo ""
echo "Done. Run './cleanup.sh' when you are finished."
