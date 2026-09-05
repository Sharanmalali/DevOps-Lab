#!/usr/bin/env bash
# Exercise 3 - Flash sale on a single node with ReplicaSets: build the image
# inside Minikube's Docker daemon, deploy the ReplicaSet + Service, scale
# 3 -> 5 replicas, prove load distribution, and prove the self-healing loop.
# Note: load is generated FROM INSIDE the cluster because 'kubectl
# port-forward' pins all traffic to a single pod and would hide distribution.
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools (minikube, docker) a truncated
# PATH that drops /c/Program Files/Docker/... — always put docker's directory
# at the very front so every native child resolves docker helpers correctly.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    export PATH="${_docker_dir}:${PATH}"
fi

# Wait until N flashsale pods are Running with READY 1/1 (polls $2*2 sec).
# The STATUS column filter excludes Terminating/Completed pods mid-deletion,
# which still show 1/1 for a few seconds and would otherwise fake success.
wait_ready_pods() {
    local expected="$1" tries="$2" i n
    for i in $(seq 1 "${tries}"); do
        n="$(kubectl get pods -l app=flashsale --no-headers 2>/dev/null | awk '$2 == "1/1" && $3 == "Running" { c++ } END { print c + 0 }')"
        if [ "${n}" -ge "${expected}" ]; then
            return 0
        fi
        sleep 2
    done
    echo "    ERROR: only ${n:-0}/${expected} pods ready after $((tries * 2))s."
    return 1
}

echo "==> [1/6] Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH."; exit 1; }
command -v minikube >/dev/null 2>&1 || { echo "ERROR: minikube not found in PATH."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH."; exit 1; }

echo "==> [2/6] Ensuring Minikube single-node cluster is running..."
if kubectl get nodes >/dev/null 2>&1; then
    echo "    Cluster already running."
else
    minikube start --nodes=1
fi
kubectl get nodes

echo "==> [3/6] Building the flashsale:1.0 image inside Minikube's Docker daemon..."
if ( eval "$(minikube docker-env --shell bash)" && docker build -t flashsale:1.0 . >/dev/null 2>&1 ); then
    echo "    Image flashsale:1.0 built via 'minikube docker-env' (brief Step 5)."
else
    echo "    docker-env path unavailable - falling back to build + 'minikube image load'..."
    docker build -t flashsale:1.0 . >/dev/null
    minikube image load flashsale:1.0
    echo "    Image flashsale:1.0 loaded into the cluster."
fi

echo "==> [4/6] Deploying the ReplicaSet (3 replicas) and Service (brief Steps 3-4)..."
kubectl apply -f flashsale-replicaset.yaml
wait_ready_pods 3 60
kubectl get rs flashsale-rs

echo "==> [5/6] Scaling the ReplicaSet from 3 to 5 replicas (brief Steps 7-9)..."
kubectl scale rs flashsale-rs --replicas=5
wait_ready_pods 5 60
kubectl get rs flashsale-rs
kubectl get pods -l app=flashsale -o wide

echo "==> [6/6] Verifying load distribution and self-healing (brief Steps 10-11)..."
echo "    Running an in-cluster load generator: 15 x GET /buy via flashsale-svc..."
kubectl delete pod flashsale-loadgen --ignore-not-found --wait=true >/dev/null 2>&1 || true
kubectl run flashsale-loadgen --restart=Never --image=flashsale:1.0 \
    --image-pull-policy=IfNotPresent --command -- python -c \
    'import urllib.request,json,collections;c=collections.Counter(json.load(urllib.request.urlopen("http://flashsale-svc/buy",timeout=5))["served_by_pod"] for _ in range(15));print("\n".join("%d %s"%(n,p) for p,n in c.most_common()))' \
    >/dev/null 2>&1

phase=""
for _ in $(seq 1 60); do
    phase="$(kubectl get pod flashsale-loadgen -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "${phase}" in Succeeded|Failed) break ;; esac
    sleep 2
done
if [ "${phase}" != "Succeeded" ]; then
    kubectl logs flashsale-loadgen --tail=20 2>/dev/null || true
    kubectl delete pod flashsale-loadgen --ignore-not-found --wait=false >/dev/null 2>&1 || true
    echo "    FAILED: load generator did not succeed (phase: ${phase:-not found})."
    exit 1
fi
load_out="$(kubectl logs flashsale-loadgen)"
kubectl delete pod flashsale-loadgen --ignore-not-found --wait=false >/dev/null 2>&1 || true

echo "    Requests per pod:"
printf '%s\n' "${load_out}" | awk 'NF == 2 && $2 ~ /^flashsale-rs-/ { printf "      %2d  %s\n", $1, $2 }'
distinct="$(printf '%s\n' "${load_out}" | awk 'NF == 2 && $2 ~ /^flashsale-rs-/ { a[$2] = 1 } END { print length(a) + 0 }')"
if [ "${distinct}" -ge 2 ]; then
    echo "    SUCCESS: 15 requests spread across ${distinct} different pods."
else
    echo "    FAILED: only ${distinct} pod served the traffic."
    exit 1
fi

pods_out="$(kubectl get pods -l app=flashsale --no-headers)"
victim="$(printf '%s\n' "${pods_out}" | awk '$2 == "1/1" && $3 == "Running" { print $1; exit }')"
echo "    Deleting pod ${victim} to prove the self-healing loop..."
kubectl delete pod "${victim}" --wait=false
wait_ready_pods 5 60
kubectl get pods -l app=flashsale
echo "    SUCCESS: ReplicaSet replaced the deleted pod - back to 5/5 ready."

echo ""
echo "==> Final state:"
kubectl get rs
echo ""
kubectl get pods -o wide
echo ""
echo "Done. Run './cleanup.sh' when you are finished."
