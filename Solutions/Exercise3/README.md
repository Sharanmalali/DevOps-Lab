# Exercise 3 — Scaling a Flask App on a Single Node using ReplicaSets

**Goal:** Run a "flash sale" Flask service as **3 identical pods** behind a
ReplicaSet, **scale to 5**, watch the Service spread checkout traffic across
all of them, and prove the ReplicaSet **replaces a deleted pod on its own** —
exactly how e-commerce sites survive Big Billion Days / Prime Day traffic spikes.

---

## 1. What the exercise asks

1. Create `app.py` — a flash-sale service with `GET /` (welcome), `GET /buy`
   (simulated checkout that reports **which pod served it**) and `GET /health`
   (probe endpoint), listening on port **5000**.
2. Create a `Dockerfile` (python:3.11-slim + Flask + Gunicorn).
3. Build the image **inside Minikube's Docker daemon** (`minikube docker-env`).
4. Start a single-node Minikube (`minikube start --nodes=1`).
5. Create `flashsale-replicaset.yaml` — a **ReplicaSet (replicas: 3)** with
   readiness/liveness probes and CPU/memory requests+limits, plus a
   **ClusterIP Service** (`80 → 5000`).
6. `kubectl apply` it and verify: 3 pods Running, `kubectl get rs` 3/3/3.
7. Scale the ReplicaSet to **5** (`kubectl scale rs … --replicas=5`).
8. Verify the ReplicaSet shows `5 5 5`.
9. Verify 5 pods, distributed (`kubectl get pods -o wide`).
10. **Delete one pod** and watch Kubernetes recreate it.
11. Verify 5 pods again — a new pod name replaced the deleted one.
12. Answer the 7 Q&A questions (reproduced in section 8).

Additional challenges from the brief: use a different image, create a
Deployment instead of a ReplicaSet, inspect with `kubectl describe`.

## 2. Solution overview

```
 curl / load generator
        │  http://flashsale-svc/buy  (ClusterIP :80)
        ▼
 Service "flashsale-svc"  ── selector: app=flashsale ──┐
                                                        │  iptables spreads
                                                        │  each new connection
        ┌──────────────────┬──────────────────┬─────────┴──┬─────────────────┐
        ▼                  ▼                  ▼            ▼                 ▼
  flashsale-rs pod    flashsale-rs pod   flashsale-rs pod  ... (5 total)  flashsale-rs pod
  gunicorn :5000      gunicorn :5000     gunicorn :5000                  gunicorn :5000
        ▲
        │  ReplicaSet "flashsale-rs" (desired: 3 → scaled to 5)
        └─ control loop: actual pods ≠ desired? → create/delete pods
           (deleting a pod → count drops → RS creates a replacement)
```

- The **ReplicaSet** owns the pods (`app: flashsale`) and keeps *desired*
  replicas alive — that is the whole self-healing/scale mechanism.
- The **ClusterIP Service** load-balances each new TCP connection across the
  ready pods (kube-proxy iptables rules).
- **Readiness probe** (`/health`, period 5s) keeps traffic away from pods that
  are not up yet; **liveness probe** (`/health`, period 10s) restarts a hung
  container; **requests/limits** (`100m/128Mi` → `500m/256Mi`) document how
  much of the single node each pod may use.

### Brief clean-ups (deviations, all intentional)

| Brief says | This solution uses | Why |
|---|---|---|
| File `ex3-flash-sale.py` but `CMD … app:app` | `app.py` + `COPY app.py .` | gunicorn's `app:app` needs a module actually named `app` — the brief's Dockerfile would crash with `ModuleNotFoundError` |
| Builds `flask-app` tag in Step 5 | builds `flashsale:1.0` | Step 5 contradicts the YAML (`image: flashsale:1.0`) and the Dockerfile section (`<user>/flashsale:1.0`); one consistent tag |
| RS named `flashsale-rs` *and* `flask-app-rs` in different steps | always `flashsale-rs` | copy-paste drift in the brief's sample outputs |
| Step 1: `minikube delete` first | reuse a running cluster (`deploy.sh` starts one only if missing) | deleting the cluster is optional; not needed for this exercise |
| (no `imagePullPolicy`) | (kept as-is) | tag `1.0` ⇒ default `IfNotPresent` ⇒ the locally built image is used, no registry needed |

## 3. Files in this folder

| File | Purpose |
|---|---|
| `app.py` | Flash-sale service — `/`, `/buy` (reports `served_by_pod`), `/health` |
| `Dockerfile` | `python:3.11-slim` + Flask + Gunicorn, serves on `0.0.0.0:5000` |
| `.dockerignore` | Keeps README/scripts out of the build context |
| `flashsale-replicaset.yaml` | ReplicaSet (3 replicas, probes, resources) **+** ClusterIP Service, per the brief |
| `deploy.sh` | One-command flow: cluster → image build → apply → **scale 3→5** → **load-distribution proof** → **self-heal proof** |
| `cleanup.sh` | Deletes the Service and ReplicaSet (add `--cluster` to also stop Minikube) |
| `README.md` | This document |

## 4. Prerequisites

- Minikube + kubectl + Docker installed (see the brief's installation links).
- `bash` for the scripts (WSL / Git Bash on Windows); manual `kubectl`
  commands work from any shell.
- The cluster does **not** need to be running — `deploy.sh` starts it if needed.

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise3
./deploy.sh
```

Real output from a clean run:

```
==> [1/6] Checking prerequisites...
==> [2/6] Ensuring Minikube single-node cluster is running...
    Cluster already running.
NAME       STATUS   ROLES           AGE    VERSION
minikube   Ready    control-plane   5h5m   v1.34.0
==> [3/6] Building the flashsale:1.0 image inside Minikube's Docker daemon...
    Image flashsale:1.0 built via 'minikube docker-env' (brief Step 5).
==> [4/6] Deploying the ReplicaSet (3 replicas) and Service (brief Steps 3-4)...
replicaset.apps/flashsale-rs created
service/flashsale-svc created
NAME           DESIRED   CURRENT   READY   AGE
flashsale-rs   3         3         3       2s
==> [5/6] Scaling the ReplicaSet from 3 to 5 replicas (brief Steps 7-9)...
replicaset.apps/flashsale-rs scaled
NAME           DESIRED   CURRENT   READY   AGE
flashsale-rs   5         5         5       8s
NAME                 READY   STATUS    RESTARTS   AGE   IP            NODE
flashsale-rs-5t4sc   1/1     Running   0          8s    10.244.0.18   minikube
flashsale-rs-p4h4z   1/1     Running   0          8s    10.244.0.17   minikube
flashsale-rs-spts2   1/1     Running   0          5s    10.244.0.20   minikube
flashsale-rs-wlmf7   1/1     Running   0          8s    10.244.0.16   minikube
flashsale-rs-xgjmh   1/1     Running   0          5s    10.244.0.19   minikube
==> [6/6] Verifying load distribution and self-healing (brief Steps 10-11)...
    Running an in-cluster load generator: 15 x GET /buy via flashsale-svc...
    Requests per pod:
       4  flashsale-rs-p4h4z
       3  flashsale-rs-xgjmh
       3  flashsale-rs-spts2
       3  flashsale-rs-5t4sc
       2  flashsale-rs-wlmf7
    SUCCESS: 15 requests spread across 5 different pods.
    Deleting pod flashsale-rs-5t4sc to prove the self-healing loop...
pod "flashsale-rs-5t4sc" deleted from default namespace
NAME                 READY   STATUS    RESTARTS   AGE
flashsale-rs-fp8br   1/1     Running   0          6s
flashsale-rs-p4h4z   1/1     Running   0          18s
flashsale-rs-spts2   1/1     Running   0          15s
flashsale-rs-wlmf7   1/1     Running   0          18s
flashsale-rs-xgjmh   1/1     Running   0          15s
    SUCCESS: ReplicaSet replaced the deleted pod - back to 5/5 ready.

==> Final state:
NAME                   DESIRED   CURRENT   READY   AGE
flashsale-rs           5         5         5       19s
…
Done. Run './cleanup.sh' when you are finished.
```

> **Why a load-generator pod instead of `curl`?** The Service is
> `ClusterIP` — it is only reachable from *inside* the cluster (unlike
> Exercise 2's NodePort). And `kubectl port-forward svc/…` is useless for this
> proof: it pins every request to **one** backend pod, so all 15 requests look
> like they came from a single pod. The script therefore runs a throw-away pod
> that fires 15 requests through the Service's real load balancing.

### Option B — manual (the brief's steps, with the naming fixed)

```bash
# 1-2. Single-node cluster
minikube start --nodes=1          # skip if already running
kubectl get nodes

# 3. Build the image in Minikube's Docker daemon (brief Step 5, corrected tag)
eval $(minikube docker-env)       # PowerShell: minikube docker-env | Invoke-Expression
docker build -t flashsale:1.0 .

# 4-6. Deploy the ReplicaSet + Service and verify 3/3/3
kubectl apply -f flashsale-replicaset.yaml
kubectl get pods                  # 3 pods, 1/1 Running
kubectl get rs                    # flashsale-rs  3  3  3

# 7-9. Scale to 5 and verify
kubectl scale rs flashsale-rs --replicas=5
kubectl get rs                    # flashsale-rs  5  5  5
kubectl get pods -o wide          # 5 pods, all on the single node

# Prove load distribution (in-cluster, 15 x /buy)
kubectl run flashsale-loadgen --rm -i --restart=Never --image=flashsale:1.0 \
  --image-pull-policy=IfNotPresent --command -- python -c \
  'import urllib.request,json; [print(json.load(urllib.request.urlopen("http://flashsale-svc/buy"))["served_by_pod"]) for _ in range(15)]'

# 10-11. Delete one pod and watch the replacement appear
kubectl delete pod <any-flashsale-pod-name>
kubectl get pods                  # a NEW pod name appears; count returns to 5

# Extra: inspect like the brief's Additional Challenges suggest
kubectl describe rs flashsale-rs   # Events: SuccessfulCreate / SuccessfulDelete
kubectl logs -l app=flashsale
```

## 6. How to verify the expected output

| Check | Command | Expected result |
|---|---|---|
| Initial replicas | `kubectl get rs` | `flashsale-rs 3 3 3` |
| After scaling | `kubectl get rs` | `flashsale-rs 5 5 5` |
| Pods running | `kubectl get pods -l app=flashsale` | 5 × `1/1 Running` |
| Pod distribution | `kubectl get pods -o wide` | all 5 pods on node `minikube` (single-node cluster) |
| Load spread | load-generator above / `./deploy.sh` | `served_by_pod` differs across **all 5** pods |
| Self-healing | delete a pod, `kubectl get pods` | count returns to 5 with a **new** pod name |
| Probes healthy | `kubectl describe pod <pod>` | `Readiness` + `Liveness` no failures |
| Controller history | `kubectl describe rs flashsale-rs` | `SuccessfulCreate`, `SuccessfulDelete` events |

## 7. Key concepts from this exercise

### ReplicaSet vs Deployment

| | ReplicaSet (this exercise) | Deployment (Exercise 2) |
|---|---|---|
| Keeps N pods alive | ✅ | ✅ (via an underlying ReplicaSet) |
| Rolling updates / rollback | ❌ | ✅ |
| Intended use | learning the scaling/reconciliation core | what you run in production |

A Deployment *is* the brief's "Additional Challenge #2" — it simply wraps a
ReplicaSet and adds rollout strategy.

### The reconciliation loop (why deletion self-heals)

```
desired = 5   actual = 5   →  do nothing
desired = 5   actual = 4   →  create 1 pod   (this is what we proved)
desired = 5   actual = 6   →  delete 1 pod   (this is what scaling down does)
```

kube-controller-manager runs this comparison continuously (no polling of your
part) — same mechanism that makes `kubectl scale` take effect instantly.

### Pod distribution on a *single* node

All 5 pods land on the one `minikube` node (see `-o wide`), but they still get
**5 different pod IPs**, and the Service spreads connections across those IPs.
Distribution across *nodes* (anti-affinity / real autoscaling) is Exercise 10's
multi-node exercise.

### Readiness vs liveness vs startup

| Probe | Question it answers | On failure |
|---|---|---|
| `readinessProbe` | "Is this pod ready to receive **traffic**?" | removed from the Service's endpoints |
| `livenessProbe` | "Is this pod **stuck**?" | container is restarted |

Here both hit `/health` with different periods (5s vs 10s) — the brief's way of
keeping the demo simple.

### requests vs limits

`requests: 100m/128Mi` = what the scheduler *reserves*;
`limits: 500m/256Mi` = the ceiling (exceeding the CPU limit throttles the
container; exceeding memory would OOM-kill it). 5 pods × 100m = 500m of the
node's CPU stays schedulable-friendly.

### Scaling back down (the other half of the flash sale)

```bash
kubectl scale rs flashsale-rs --replicas=3   # RS deletes the 2 newest pods
```

That's the "traffic returns to normal → scale back down to save resources"
half of the real-life use case.

## 8. Q&A (from the exercise)

| # | Q | A |
|---|---|---|
| 1 | What is the initial number of replicas in the ReplicaSet? | **3** |
| 2 | How many pods are running after applying the ReplicaSet configuration? | **3** |
| 3 | What happens when you scale the ReplicaSet to 5 replicas? | Kubernetes creates 2 additional pods to meet the desired number of replicas (5). The ReplicaSet now has 5 running pods. |
| 4 | What happens when you delete one pod? | Kubernetes automatically creates a new pod to replace the deleted one, maintaining the desired number of replicas (5). |
| 5 | How does Kubernetes maintain the desired number of replicas? | Kubernetes continuously monitors the number of running pods and compares it to the desired number of replicas. If there's a discrepancy, Kubernetes creates or deletes pods to maintain the desired state. |
| 6 | How many nodes are running? | **1** (single-node Minikube) |
| 7 | Where are the pods running with respect to nodes? | Node 1 (`minikube`): pod 1–pod 5. **All 5 pods run on the single node.** |

## 9. Additional challenges (from the brief)

- **Use a different image** — edit the YAML's `image:` line and
  `kubectl apply -f flashsale-replicaset.yaml`. For a rolling-style in-place
  image swap on an existing RS:
  `kubectl set image rs/flashsale-rs flashsale-container=flashsale:1.1`.
  (A Deployment turns this into a zero-downtime rollout — see Exercise 2.)
- **Create a Deployment instead of a ReplicaSet** — replace
  `kind: ReplicaSet` with `kind: Deployment`, nest the pod template under
  `spec.template` as-is, drop nothing else; the Service and scaling commands
  (`kubectl scale deployment …`) work the same way.
- **Inspect with `kubectl describe`** —
  `kubectl describe rs flashsale-rs` shows the controller's
  `SuccessfulCreate`/`SuccessfulDelete` events; `kubectl describe pod <pod>`
  shows probe history and resource requests/limits.

## 10. Cleanup

```bash
./cleanup.sh            # delete ReplicaSet + service, keep the cluster
./cleanup.sh --cluster   # also run: minikube stop
```

Manual equivalent:

```bash
kubectl delete service flashsale-svc
kubectl delete replicaset flashsale-rs
```

Scale down instead of deleting, to see the reverse operation:
`kubectl scale rs flashsale-rs --replicas=1`.

## 11. Troubleshooting

| Symptom | Fix |
|---|---|
| Pods `ImagePullBackOff` | `flashsale:1.0` missing in the cluster — re-run `./deploy.sh`, or `docker build -t flashsale:1.0 .` + `minikube image load flashsale:1.0` |
| Gunicorn exits with `ModuleNotFoundError: app` | the file must be named `app.py` (the brief's `ex3-flash-sale.py` name breaks `CMD … app:app`) |
| Distribution test shows only 1 pod | you are curling through `kubectl port-forward` — it pins one backend by design; use the in-cluster load generator |
| Pending pods / `Insufficient cpu` | requests (`100m` × 5) exceed spare node capacity — free resources or lower `resources.requests` |
| Replacement pod slow after delete | image must exist locally; a re-pull from a registry is what takes long (`minikube image ls flashsale:1.0` to confirm) |
| `minikube: docker not found in %PATH%` (Git Bash) | Git Bash truncates PATH for native tools — `deploy.sh` works around this automatically |
