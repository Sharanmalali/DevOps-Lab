#!/usr/bin/env bash
#
# Exercise 10 - remove what deploy.sh created
#
# Usage:
#   ./cleanup.sh                # delete the whole 'devops-multinode' profile
#                               # (control-plane + 2 worker nodes; recommended)
#   ./cleanup.sh --resources    # only delete the Deployments and Services
#                               # (kubectl delete) and keep the cluster running
#   ./cleanup.sh -h | --help    # show this help
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Git Bash rewrites slash-leading arguments destined for native executables.
export MSYS2_ARG_CONV_EXCL='*'

# Git Bash can hand native children a truncated PATH (drops the Docker CLI dir).
DOCKER_BIN_DIR="$(dirname "$(command -v docker 2>/dev/null || echo /usr/bin/docker)")"
case ":$PATH:" in
  *":$DOCKER_BIN_DIR:"*) ;;
  *) PATH="$DOCKER_BIN_DIR:$PATH" ;;
esac
export PATH

PROFILE="devops-multinode"

DELETE_RESOURCES=0
for arg in "$@"; do
  case "$arg" in
    --resources|--resource) DELETE_RESOURCES=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ "$DELETE_RESOURCES" -eq 1 ]; then
  # ------------------------------------------------- [1/2] delete the manifests
  echo "[1/2] Deleting Deployments + Services (cluster kept)"
  command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH" >&2; exit 1; }

  # Pin kubectl to this exercise's context when it exists, so we never delete
  # from whatever cluster happens to be current.
  CTX=""
  if kubectl config get-contexts "$PROFILE" -o name >/dev/null 2>&1; then
    CTX="--context=${PROFILE}"
  else
    echo "  note: context '${PROFILE}' not found - using the current context"
  fi
  if ! kubectl ${CTX:+"$CTX"} get nodes >/dev/null 2>&1; then
    echo "ERROR: cluster '${PROFILE}' is not reachable - nothing to delete" >&2
    echo "       (start it with ./deploy.sh, or run './cleanup.sh' with no flags to remove the profile itself)" >&2
    exit 1
  fi

  for manifest in "$SCRIPT_DIR"/*.yaml; do
    echo "  -> $(basename "$manifest")"
    kubectl ${CTX:+"$CTX"} delete -f "$manifest" --ignore-not-found
  done

  echo "[2/2] Cluster left running"
  kubectl ${CTX:+"$CTX"} get nodes 2>/dev/null || true
else
  # ------------------------------------------------ [1/2] delete the profile
  echo "[1/2] Deleting profile '${PROFILE}' (cluster + all 3 nodes)"
  command -v minikube >/dev/null 2>&1 || { echo "ERROR: minikube not found in PATH" >&2; exit 1; }

  profiles="$(minikube profile list 2>/dev/null || true)"
  if printf '%s\n' "$profiles" | grep -q "${PROFILE}"; then
    minikube -p "$PROFILE" delete
    echo "  profile deleted"
  else
    echo "  profile '${PROFILE}' not present (already gone)"
  fi

  echo "[2/2] Local images kept (docker rmi product-catalog:latest shopping-cart:latest to drop them)"
fi

echo
echo "Cleanup complete."
