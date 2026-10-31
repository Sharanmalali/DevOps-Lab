#!/usr/bin/env bash
# Part C - AppArmor. Applies the profile where the node kernel supports it,
# otherwise reports that and runs the same tests against the hardened pod.
set -euo pipefail
cd "$(dirname "$0")/.."

enabled="$(minikube ssh -- cat /sys/module/apparmor/parameters/enabled 2>/dev/null | tr -d '\r' || true)"

if [ "$enabled" = "Y" ]; then
  echo "AppArmor is ENABLED on the Minikube node."
  # docker driver: node container shares the host kernel, so load on the host
  if command -v apparmor_parser >/dev/null 2>&1; then
    sudo apparmor_parser -r -W apparmor/k8s-patient-api
  else
    minikube cp apparmor/k8s-patient-api /tmp/k8s-patient-api
    minikube ssh -- sudo apparmor_parser -r -W /tmp/k8s-patient-api
  fi
  echo "Profile loaded. Patching the Deployment to use it..."
  kubectl patch deployment patient-api --patch-file apparmor/apparmor-patch.yaml
  kubectl rollout status deployment/patient-api --timeout=120s
  echo "Profile seen by the container:"
  kubectl exec deploy/patient-api -- cat /proc/1/attr/current
else
  echo "AppArmor is NOT available on this node (Docker Desktop / LinuxKit kernel on macOS)."
  echo "The profile is NOT applied - pods requesting it would be rejected."
  echo "Restrictions in force instead: runAsNonRoot, readOnlyRootFilesystem,"
  echo "capabilities drop ALL, allowPrivilegeEscalation=false, seccomp RuntimeDefault."
fi

echo
echo "Permitted vs restricted operations inside the patient-api container:"
kubectl exec deploy/patient-api -- python security_test.py
echo
echo "Interactive shell attempt (blocked under AppArmor, allowed without it):"
kubectl exec deploy/patient-api -- sh -c 'echo "shell started"' || echo "  -> shell blocked"
