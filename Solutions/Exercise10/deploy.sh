#!/usr/bin/env bash
#
# Exercise 10 - Multi-node Minikube cluster with Product Catalog + Shopping Cart
#
# Creates the 3-node profile "devops-multinode" (docker driver), enables the
# registry addon, builds both Flask images, loads them onto every node, applies
# the four manifests (2 Deployments with required pod anti-affinity + 2 NodePort
# Services), verifies that the replicas really spread across distinct nodes and
# smoke tests both services with curl.
#
# Usage:
#   ./deploy.sh                 # normal run (no --force)
#   ./deploy.sh --force         # pass --force to 'minikube start'
#   FORCE=1 ./deploy.sh         # same as --force, environment form
#   ./deploy.sh -h | --help     # show this help
#
# Why --force is opt-in: the brief starts the cluster as root, and minikube's
# docker driver refuses to run as root unless forced (PROVIDER_DOCKER_AS_ROOT).
# On a normal (non-root) host --force is unnecessary, so it defaults to off.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
# Windows-style host path (forward slashes). With MSYS arg conversion disabled
# below, the Docker CLI needs this form for build contexts and bind mounts.
HOST_WORKDIR="$(pwd -W 2>/dev/null || pwd)"

# Git Bash rewrites slash-leading arguments destined for native executables.
export MSYS2_ARG_CONV_EXCL='*'

# Git Bash can hand native children a truncated PATH (drops the Docker CLI dir
# and docker-credential-desktop). Re-add it explicitly.
DOCKER_BIN_DIR="$(dirname "$(command -v docker 2>/dev/null || echo /usr/bin/docker)")"
case ":$PATH:" in
  *":$DOCKER_BIN_DIR:"*) ;;
  *) PATH="$DOCKER_BIN_DIR:$PATH" ;;
esac
export PATH

PROFILE="devops-multinode"
NODES=3
PC_IMAGE="product-catalog:latest"
SC_IMAGE="shopping-cart:latest"
PC_SVC="product-catalog-service"
SC_SVC="shopping-cart-service"

# FORCE=1 in the environment is the environment form of --force.
case "${FORCE:-0}" in
  1|true|TRUE|yes) FORCE=1 ;;
  *) FORCE=0 ;;
esac

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

port_busy() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    return 1   # no lsof: assume free, kubectl port-forward fails loudly if not
  fi
}
pick_port() { local p="$1"; while port_busy "$p"; do echo "  port $p is in use, trying $((p + 1))..." >&2; p=$((p + 1)); done; echo "$p"; }

# 'minikube service --url' blocks on some hosts (it starts a tunnel), so read
# it in the background and stop it once a URL is printed or 30 s elapsed.
service_url() {
  local svc="$1" tmp url pid i
  tmp="$(mktemp)"
  minikube -p "$PROFILE" service "$svc" --url >"$tmp" 2>/dev/null &
  pid=$!
  url=""
  for i in $(seq 1 30); do
    url="$(grep -m1 -E '^https?://' "$tmp" 2>/dev/null || true)"
    [ -n "$url" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$tmp"
  printf '%s\n' "$url"
}

# ---------------------------------------------------------------- [1/8] prereqs
echo "[1/8] Checking prerequisites"
command -v docker   >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH" >&2; exit 1; }
command -v minikube >/dev/null 2>&1 || { echo "ERROR: minikube not found in PATH" >&2; exit 1; }
command -v kubectl  >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH" >&2; exit 1; }
command -v curl     >/dev/null 2>&1 || { echo "ERROR: curl not found in PATH" >&2; exit 1; }
docker info >/dev/null 2>&1         || { echo "ERROR: Docker daemon is not running" >&2; exit 1; }
echo "  docker   : $(docker --version | cut -d, -f1)"
echo "  minikube : $(minikube version --short 2>/dev/null || minikube version 2>/dev/null | head -1)"
echo "  kubectl  : $(kubectl version --client 2>/dev/null | head -1)"

# ------------------------------------------------- [2/8] multi-node profile
echo "[2/8] Ensuring profile '${PROFILE}' is up (${NODES} nodes, docker driver)"
status_out="$(minikube status -p "$PROFILE" 2>/dev/null || true)"
if printf '%s' "$status_out" | grep -q 'host: Running'; then
  echo "  profile already running"
else
  start_cmd=(minikube start -p "$PROFILE" --nodes "$NODES" --driver docker)
  [ "$FORCE" -eq 1 ] && start_cmd+=(--force)
  echo "  running: ${start_cmd[*]}"
  "${start_cmd[@]}"
fi
# minikube names the kube context after the profile; pin kubectl to it so every
# later step talks to this exercise's cluster and not some other current one.
if ! kubectl config use-context "$PROFILE" >/dev/null 2>&1; then
  echo "ERROR: kube context '${PROFILE}' not found - is the profile healthy?" >&2
  echo "       try: minikube -p ${PROFILE} update-context" >&2
  exit 1
fi
node_count="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ' || true)"
node_count="${node_count:-0}"
[ "$node_count" -eq "$NODES" ] || { echo "ERROR: expected ${NODES} nodes, found ${node_count}" >&2; exit 1; }
kubectl get nodes

# ------------------------------------------------------ [3/8] registry addon
echo "[3/8] Enabling the registry addon (idempotent)"
addon_out="$(minikube -p "$PROFILE" addons list 2>/dev/null || true)"
if printf '%s\n' "$addon_out" | grep -qiE 'registry.*enabled'; then
  echo "  registry addon already enabled"
else
  echo "  enabling it so images can be shared across the nodes"
  minikube -p "$PROFILE" addons enable registry
fi

# -------------------------------------------------------- [4/8] docker builds
echo "[4/8] Building images ${PC_IMAGE} and ${SC_IMAGE}"
docker build -q -t "$PC_IMAGE" -f "$HOST_WORKDIR/Dockerfile.product" "$HOST_WORKDIR" >/dev/null
docker build -q -t "$SC_IMAGE" -f "$HOST_WORKDIR/Dockerfile.shopping" "$HOST_WORKDIR" >/dev/null
echo "  built: ${PC_IMAGE}, ${SC_IMAGE}"

# --------------------------------------------------- [5/8] load onto the nodes
echo "[5/8] Loading both images onto every node (minikube image load)"
minikube -p "$PROFILE" image load "$PC_IMAGE"
minikube -p "$PROFILE" image load "$SC_IMAGE"
echo "  loaded: ${PC_IMAGE}, ${SC_IMAGE}"

# ------------------------------------------------------- [6/8] apply manifests
echo "[6/8] Applying the four manifests"
for manifest in "$SCRIPT_DIR"/*.yaml; do
  echo "  -> $(basename "$manifest")"
  kubectl apply -f "$manifest"
done

# -------------------------------------------- [7/8] rollout + scheduling spread
check_spread() {
  local app="$1" want="$2" nodes count distinct
  nodes="$(kubectl get pods -l "app=${app}" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' || true)"
  count="$(printf '%s\n' "$nodes" | sed '/^$/d' | wc -l | tr -d ' ')"
  distinct="$(printf '%s\n' "$nodes" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
  if [ "$count" -ne "$want" ]; then
    echo "ERROR: expected ${want} '${app}' pods, found ${count}" >&2
    kubectl get pods -l "app=${app}" -o wide >&2 || true
    exit 1
  fi
  if [ "$distinct" -ne "$want" ]; then
    echo "ERROR: podAntiAffinity violated - the ${count} '${app}' pods sit on only ${distinct} distinct node(s); expected ${want}" >&2
    kubectl get pods -l "app=${app}" -o wide >&2 || true
    echo "Hint: requiredDuringScheduling... leaves extra pods Pending unless ${want} nodes are Ready - check 'kubectl get nodes'" >&2
    exit 1
  fi
  echo "  SUCCESS: ${app} - ${count} pods on ${distinct} distinct nodes"
}

echo "[7/8] Waiting for rollouts, then verifying the pods spread across nodes"
kubectl rollout status deployment/product-catalog --timeout=180s
kubectl rollout status deployment/shopping-cart --timeout=180s

echo "  product-catalog pods:"
kubectl get pods -l app=product-catalog -o wide
echo "  shopping-cart pods:"
kubectl get pods -l app=shopping-cart -o wide
check_spread product-catalog 2
check_spread shopping-cart 3

# ------------------------------------------------ [8/8] access URLs + curl tests
echo "[8/8] Service URLs and smoke tests"
NODE_IP="$(minikube -p "$PROFILE" ip 2>/dev/null || true)"
PC_NODEPORT="$(kubectl get svc "$PC_SVC" -o jsonpath='{.spec.ports[0].nodePort}')"
SC_NODEPORT="$(kubectl get svc "$SC_SVC" -o jsonpath='{.spec.ports[0].nodePort}')"
PC_URL="$(service_url "$PC_SVC")"
SC_URL="$(service_url "$SC_SVC")"
PC_FALLBACK="http://${NODE_IP}:${PC_NODEPORT}"
SC_FALLBACK="http://${NODE_IP}:${SC_NODEPORT}"

echo "  ${PC_SVC}"
echo "    minikube service --url : ${PC_URL:-<no URL within 30s>}"
echo "    node-ip fallback       : ${PC_FALLBACK}"
echo "  ${SC_SVC}"
echo "    minikube service --url : ${SC_URL:-<no URL within 30s>}"
echo "    node-ip fallback       : ${SC_FALLBACK}"

# The cart keeps its items in pod memory, and a NodePort round-robins across
# the 3 replicas - so the POST/GET pair must pin to ONE pod. The brief's curl
# goes through the minikube service tunnel for the same reason; a background
# 'kubectl port-forward svc/...' reproduces that pinning exactly.
PF_PIDS=""
cleanup_pf() { for p in $PF_PIDS; do kill "$p" 2>/dev/null || true; done; }
trap cleanup_pf EXIT

wait_ready() {   # $1 = port-forward pid, $2 = local port, $3 = path
  local pid="$1" port="$2" path="$3" i
  for i in $(seq 1 20); do
    curl -fsS -o /dev/null --max-time 3 "http://127.0.0.1:${port}${path}" 2>/dev/null && return 0
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  return 1
}

PC_PORT="$(pick_port 18080)"
SC_PORT="$(pick_port 18090)"
kubectl port-forward "svc/${PC_SVC}" "${PC_PORT}:80" >/dev/null 2>&1 &
pc_pf=$!; PF_PIDS="$PF_PIDS $pc_pf"
kubectl port-forward "svc/${SC_SVC}" "${SC_PORT}:80" >/dev/null 2>&1 &
sc_pf=$!; PF_PIDS="$PF_PIDS $sc_pf"
wait_ready "$pc_pf" "$PC_PORT" "/products" || { echo "ERROR: port-forward to ${PC_SVC} did not come up" >&2; exit 1; }
wait_ready "$sc_pf" "$SC_PORT" "/cart"     || { echo "ERROR: port-forward to ${SC_SVC} did not come up" >&2; exit 1; }

echo "  GET /products"
products="$(curl -fsS --max-time 10 "http://127.0.0.1:${PC_PORT}/products")"
pcount="$(printf '%s' "$products" | grep -o '"id"' | wc -l | tr -d ' ' || true)"
[ "$pcount" -eq 3 ] || { echo "ERROR: expected 3 products, got: ${products}" >&2; exit 1; }
printf '%s' "$products" | grep -q '"name":"Laptop"'       || { echo "ERROR: Laptop missing from /products: ${products}" >&2; exit 1; }
printf '%s' "$products" | grep -q '"name":"Phone"'        || { echo "ERROR: Phone missing from /products: ${products}" >&2; exit 1; }
printf '%s' "$products" | grep -q '"name":"Headphones"'   || { echo "ERROR: Headphones missing from /products: ${products}" >&2; exit 1; }
echo "    -> ${products}"
echo "    OK: 3 products (Laptop, Phone, Headphones)"

echo "  GET /cart"
cart_before="$(curl -fsS --max-time 10 "http://127.0.0.1:${SC_PORT}/cart")"
if [ "$cart_before" = "[]" ]; then
  echo "    -> []   (empty, as the brief expects on a fresh deploy)"
else
  echo "    -> ${cart_before}"
  echo "    NOTE: not empty - the cart lives in pod memory and survives re-runs;"
  echo "          the POST below is asserted by its item count instead."
fi

echo "  POST /cart (laptop) then GET /cart"
curl -fsS --max-time 10 -o /dev/null -X POST "http://127.0.0.1:${SC_PORT}/cart" \
  -H "Content-Type: application/json" \
  -d '{"id": 1, "name": "Laptop", "quantity": 1}'
cart_after="$(curl -fsS --max-time 10 "http://127.0.0.1:${SC_PORT}/cart")"
before_n="$(printf '%s' "$cart_before" | grep -o '"name"' | wc -l | tr -d ' ' || true)"
after_n="$(printf '%s' "$cart_after" | grep -o '"name"' | wc -l | tr -d ' ' || true)"
[ "$after_n" -eq $((before_n + 1)) ] || { echo "ERROR: POST /cart did not append - before=${cart_before} after=${cart_after}" >&2; exit 1; }
echo "    -> ${cart_after}"
echo "    OK: item appended and read back"

# Optional reachability note (not fatal): on Docker Desktop for macOS/Windows
# the raw node IP is often unreachable from the host - use the tunnel instead.
if curl -fsS --max-time 5 "${PC_FALLBACK}/products" >/dev/null 2>&1; then
  echo "  node-ip URL reachable directly: ${PC_FALLBACK}"
else
  echo "  note: ${PC_FALLBACK} not reachable from this host (normal on Docker Desktop);"
  echo "        use 'minikube -p ${PROFILE} service ${PC_SVC}' (tunnel) instead"
fi

cleanup_pf
trap - EXIT

cat <<EOF

============================================================
 Exercise 10 complete
============================================================
 Cluster  : ${PROFILE} (${NODES} nodes, docker driver)
 Apps     : product-catalog (2 replicas) + shopping-cart (3 replicas)
 Spread   : 2 product-catalog pods on 2 distinct nodes,
            3 shopping-cart pods on 3 distinct nodes (podAntiAffinity)
 Services : ${PC_SVC}
              ${PC_URL:-$PC_FALLBACK}
            ${SC_SVC}
              ${SC_URL:-$SC_FALLBACK}
 Smoke    : GET /products -> 3 products (Laptop, Phone, Headphones)
            GET /cart -> [] on a fresh deploy; POST /cart -> item appended

 Verify spread any time: kubectl get pods -o wide
 Cleanup : ./cleanup.sh              (delete the whole profile)
           ./cleanup.sh --resources  (keep the cluster, delete the apps)
===========================================================
EOF

echo
echo "Useful commands:"
echo "  nodes    : kubectl get nodes -o wide"
echo "  pods     : kubectl get pods -o wide"
echo "  logs     : kubectl logs -l app=product-catalog --tail=20"
echo "  open svc : minikube -p ${PROFILE} service ${PC_SVC}"
echo "  cleanup  : ./cleanup.sh [--resources]"
