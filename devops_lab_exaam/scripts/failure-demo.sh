#!/usr/bin/env bash
# Part D - Introduce ONE failure (wrong DB hostname), diagnose it from logs, fix it.
#   ./scripts/failure-demo.sh break     # introduce the failure
#   ./scripts/failure-demo.sh diagnose  # logs / describe / events
#   ./scripts/failure-demo.sh fix       # restore correct config
set -euo pipefail
cd "$(dirname "$0")/.."

newest_pod() {
  kubectl get pods -l app=patient-api --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{.items[-1].metadata.name}'
}

case "${1:-}" in
  break)
    echo "Setting DB_HOST=patient-dbb (typo) on the API Deployment..."
    kubectl set env deployment/patient-api DB_HOST=patient-dbb DB_CONNECT_RETRIES=3
    echo "Wait ~40 s, then run: $0 diagnose"
    ;;
  diagnose)
    pod="$(newest_pod)"
    echo "== 1. Pod status (look for Error / CrashLoopBackOff, RESTARTS growing)"
    kubectl get pods -l app=patient-api
    echo; echo "== 2. Application logs of the crashed container ($pod)"
    kubectl logs "$pod" --previous 2>/dev/null || kubectl logs "$pod"
    echo; echo "== 3. Container state from describe"
    kubectl describe pod "$pod" | grep -E 'State:|Reason:|Exit Code:|Restart Count:|DB_HOST' || true
    echo; echo "== 4. Events"
    kubectl get events --field-selector involvedObject.name="$pod" --sort-by=.lastTimestamp | tail -5
    echo; echo "== 5. Which DB hosts actually exist?"
    kubectl get svc
    echo; echo "Diagnosis: the app cannot resolve 'patient-dbb' - the Service is named 'patient-db'."
    ;;
  fix)
    echo "Re-applying the correct manifest..."
    kubectl apply -f k8s/api.yaml
    kubectl rollout status deployment/patient-api --timeout=180s
    kubectl get pods -l app=patient-api
    ;;
  *)
    echo "usage: $0 break|diagnose|fix" >&2; exit 1 ;;
esac
