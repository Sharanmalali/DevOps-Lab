# Exercise 10 — Multi-Node Minikube Cluster with Multiple Apps (Product Catalog + Shopping Cart)

**Goal:** stand up a **3-node** Minikube profile (`devops-multinode`), run two
Flask services on it — **Product Catalog (2 replicas)** and **Shopping Cart
(3 replicas)** — and prove that `podAntiAffinity` puts every replica of an app
on a **different node**, reachable through NodePort Services and verified end
to end with `curl`.

---

## 1. What the exercise asks

| Step | Requirement |
|---|---|
| 0 | Clean up any existing Minikube (`minikube stop && minikube delete`) |
| 1a | `minikube start --nodes 3 -p devops-multinode --force` (docker driver) |
| 1b | `minikube -p devops-multinode addons enable registry` (share images across nodes) |
| 2 | `product_catalog.py` — Flask, `GET /products` → 3 products, `0.0.0.0:80` |
| 3 | `shopping_cart.py` — Flask, `GET`/`POST /cart`, `0.0.0.0:80` |
| 4 | Two Dockerfiles (`python:3.9-slim`), build `product-catalog:latest` + `shopping-cart:latest` |
| 5 | `minikube image load` both images |
| 6 | Deployment YAMLs: `product-catalog` **replicas: 2**, `shopping-cart` **replicas: 3**, each with `podAntiAffinity` on `kubernetes.io/hostname` |
| 7 | Two **NodePort** Services (`80 → 80`) |
| 8 | `kubectl get pods -o wide` — pods of each app on **different nodes** |
| 9 | Access via `minikube service <name>` (browser / URL) |
| 10 | `curl` smoke tests: `/products` (3 items), `/cart` (`[]` → POST → read back) |

The brief is a numbered walkthrough; this solution reproduces the whole flow as
a re-runnable script plus four reviewable manifests.

## 2. Solution overview

```
              minikube profile: devops-multinode   (docker driver, 3 nodes)
              images built on the host, then 'minikube image load' -> EVERY node
┌────────────────────────────┬────────────────────────────┬────────────────────────────┐
│ node: devops-multinode     │ node: devops-multinode-m02 │ node: devops-multinode-m03 │
│  (control-plane)           │                            │                            │
│  product-catalog pod       │  product-catalog pod       │                            │
│  shopping-cart pod         │  shopping-cart pod         │  shopping-cart pod         │
│  (2 product-catalog pods = one per node; 3 shopping-cart pods = one per node)      │
└────────────────────────────┴────────────────────────────┴────────────────────────────┘
        podAntiAffinity: required, topologyKey: kubernetes.io/hostname
        │                                          │
        │  NodePort                                │  NodePort
        ▼                                          ▼
 product-catalog-service                  shopping-cart-service
 http://<node-ip>:<nodePortA>/products    http://<node-ip>:<nodePortB>/cart
```

- **`deploy.sh`** runs the brief end to end as `[1/8]`…`[8/8]`: prereqs →
  create/start the 3-node profile → enable the registry addon → build both
  images → `minikube image load` → `kubectl apply` the four manifests → wait
  for rollouts **and assert the spread** (2 product-catalog pods on 2 distinct
  nodes, 3 shopping-cart pods on 3 distinct nodes — failing loudly otherwise)
  → print the access URLs and `curl`-smoke-test both services. Every step is
  idempotent, so the script is safe to run twice.
- **`cleanup.sh`** deletes the whole profile by default, or only the
  Deployments/Services with `--resources` (cluster kept).
- The manifests stay separate files (deployments + services) exactly as the
  brief presents them, so each concept remains visible on its own.

### Deployment lifecycle

```
kubectl apply -f *.yaml
        ▼
Deployment "shopping-cart" (replicas: 3, namespace: default) -> ReplicaSet -> 3 pod specs
        ▼  scheduler + podAntiAffinity (required, topologyKey: kubernetes.io/hostname):
        │    pod 1 -> any Ready node;  pod 2 -> a node with no "app" pod yet;
        │    pod 3 -> the remaining node   (a 4th replica would stay Pending)
        ▼  rollout status: 3/3 available
Service "shopping-cart-service" (NodePort 80 -> each pod's :80); kube-proxy spreads
new connections across the 3 pod IPs
        ▼
curl http://<node-ip>:<nodePort>/cart
```

## 3. Files in this folder

| File | Purpose |
|---|---|
| `product_catalog.py` | Product Catalog (AppA) — `GET /products` returns the 3-product JSON list |
| `shopping_cart.py` | Shopping Cart (AppB) — `GET /cart`, `POST /cart` appends the JSON body |
| `Dockerfile.product` | `python:3.12-slim` + Flask, runs `product_catalog.py`, `EXPOSE 80` |
| `Dockerfile.shopping` | Same shape for `shopping_cart.py` |
| `product-catalog-deployment.yaml` | Deployment `product-catalog`, **replicas: 2**, required `podAntiAffinity` |
| `shopping-cart-deployment.yaml` | Deployment `shopping-cart`, **replicas: 3**, required `podAntiAffinity` |
| `product-catalog-service.yaml` | NodePort Service `product-catalog-service` (80 → 80) |
| `shopping-cart-service.yaml` | NodePort Service `shopping-cart-service` (80 → 80) |
| `deploy.sh` | One-command flow `[1/8]`–`[8/8]` (cluster → images → manifests → spread + curl proof) |
| `cleanup.sh` | Deletes the profile; `--resources` keeps the cluster and removes only the apps |
| `README.md` | This document |

## 4. Prerequisites

- **Docker** (Docker Desktop / Engine) running — builds the two images and
  drives the Minikube nodes.
- **Minikube ≥ 1.30**, **kubectl** and **bash** (Git Bash / WSL) installed.
- About **4 GB of free RAM** — 3 nodes is more than a single-node Minikube.
- `deploy.sh` starts the cluster itself; nothing needs to be running first.

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise10
./deploy.sh              # add --force (or FORCE=1) if you run as root
```

Expected output (shape of a clean run — pod names, IPs and NodePorts differ):

```
[1/8] Checking prerequisites
  docker: Docker version 29.6.1   minikube: v1.34.0   kubectl: Client Version: v1.34.0
[2/8] Ensuring profile 'devops-multinode' is up (3 nodes, docker driver)
  running: minikube start -p devops-multinode --nodes 3 --driver docker
NAME                   STATUS   ROLES           AGE   VERSION
devops-multinode       Ready    control-plane   2m    v1.34.0
devops-multinode-m02   Ready    <none>          100s  v1.34.0
devops-multinode-m03   Ready    <none>          96s   v1.34.0
[3/8] Enabling the registry addon (idempotent): already enabled
[4/8] Building images: product-catalog:latest, shopping-cart:latest -> built
[5/8] Loading both images onto every node (minikube image load): loaded
[6/8] Applying the four manifests
deployment.apps/product-catalog created   ...   service/shopping-cart-service created
[7/8] Waiting for rollouts, then verifying the pods spread across nodes
  SUCCESS: product-catalog - 2 pods on 2 distinct nodes
  SUCCESS: shopping-cart - 3 pods on 3 distinct nodes
[8/8] Service URLs and smoke tests
  product-catalog-service -> http://192.168.49.2:32316
  shopping-cart-service   -> http://192.168.49.2:32382
    OK: 3 products (Laptop, Phone, Headphones); OK: item appended and read back

============================================================
 Exercise 10 complete   devops-multinode (3 nodes)
 product-catalog (2 replicas) + shopping-cart (3 replicas)
===========================================================
```

Re-running `./deploy.sh` is safe: the profile is reused if it is running,
`kubectl apply` is idempotent, and the only wobble is the cart (see §6).

### Option B — manual (the brief's steps, condensed and corrected)

```bash
# 1a-1b. 3-node cluster + registry addon (skip --force unless you are root)
minikube start --nodes 3 -p devops-multinode --driver docker
minikube -p devops-multinode addons enable registry
kubectl get nodes                      # expect 3 Ready nodes
# 2-4. apps + images (files from this folder)
docker build -t product-catalog:latest -f Dockerfile.product .
docker build -t shopping-cart:latest  -f Dockerfile.shopping .
# 5. put the images on EVERY node (multi-node has no single docker daemon)
minikube -p devops-multinode image load product-catalog:latest
minikube -p devops-multinode image load shopping-cart:latest
# 6-7. manifests (namespace corrected to 'default', see section 7)
kubectl apply -f product-catalog-deployment.yaml -f shopping-cart-deployment.yaml
kubectl apply -f product-catalog-service.yaml -f shopping-cart-service.yaml
# 8. verify the spread
kubectl get pods -o wide                # 2 + 3 pods on 3 distinct nodes
# 9-10. access + smoke tests (tunnel terminal stays open, like the brief)
minikube -p devops-multinode service product-catalog-service --url
minikube -p devops-multinode service shopping-cart-service --url
curl http://127.0.0.1:<port>/products
curl http://127.0.0.1:<port>/cart
```

## 6. How to verify the expected output

| # | Check | Command | Expected output |
|---|---|---|---|
| 1 | 3 nodes Ready | `kubectl get nodes` | `devops-multinode`, `-m02`, `-m03` all `Ready` |
| 2 | Apps deployed | `kubectl get deploy` | `product-catalog 2/2`, `shopping-cart 3/3` |
| 3 | Pods spread | `kubectl get pods -o wide` | 5 pods (2+3) across **3 distinct NODE values** |
| 4 | Anti-affinity | per-app pod listing | product-catalog on **2** nodes, shopping-cart on **3** |
| 5 | Services | `kubectl get svc` | two `NodePort` services, `80:3xxxx/TCP` |
| 6 | Products | `curl …/products` | JSON list of 3 products |
| 7 | Cart | `curl …/cart` → POST → GET | `[]` (fresh) → `201` → item read back |

Expected output of `kubectl get pods -o wide` (shape — suffixes and IPs differ):

```
NAME                               READY   STATUS    RESTARTS   AGE   IP           NODE                   NOMINATED NODE   READINESS GATES
product-catalog-5fdfc7f5fb-2jlnv   1/1     Running   0          29s   10.244.1.3   devops-multinode-m02   <none>           <none>
product-catalog-5fdfc7f5fb-7v556   1/1     Running   0          29s   10.244.2.4   devops-multinode-m03   <none>           <none>
shopping-cart-788c48675b-7l4lx     1/1     Running   0          25s   10.244.0.4   devops-multinode       <none>           <none>
shopping-cart-788c48675b-d48w2     1/1     Running   0          25s   10.244.1.4   devops-multinode-m02   <none>           <none>
shopping-cart-788c48675b-hml9r     1/1     Running   0          25s   10.244.2.5   devops-multinode-m03   <none>           <none>
```

The two product-catalog pods name **two different nodes**; the three
shopping-cart pods name **all three nodes**. Copy-pasteable spread checks:

```bash
kubectl get pods -l app=product-catalog -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l   # -> 2
kubectl get pods -l app=shopping-cart   -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l   # -> 3
```

```bash
curl http://127.0.0.1:<port>/products
curl http://127.0.0.1:<port>/cart                      # fresh deploy -> []
curl -X POST http://127.0.0.1:<port>/cart -H "Content-Type: application/json" \
  -d '{"id": 1, "name": "Laptop", "quantity": 1}'      # -> 201
curl http://127.0.0.1:<port>/cart
```

Expected output — the 3 products, then the cart before and after the POST:

```json
[
    {"id": 1, "name": "Laptop", "price": 1200},
    {"id": 2, "name": "Phone", "price": 800},
    {"id": 3, "name": "Headphones", "price": 150}
]
[]
[
    {"id": 1, "name": "Laptop", "quantity": 1}
]
```

> **Cart state caveat.** The cart lives in **pod memory**, and a NodePort
> round-robins across the 3 replicas — a POST can land on a different pod than
> the following GET. The brief pins one pod by curling through the `minikube
> service` tunnel; `deploy.sh` does the same with a background
> `kubectl port-forward`. On a re-run the cart is not `[]` (the pods were not
> recreated), so `deploy.sh` asserts the item **count grew by one** instead.

## 7. Brief clean-ups (deviations, all intentional)

| Brief says | This solution uses | Why |
|---|---|---|
| `shopping_cart_deployment.yaml` uses `namespace: devops-exercise` while its Service uses `default` | both Deployments in **`default`** | The namespace is never created, so `kubectl apply` fails with `namespaces "devops-exercise" not found`. Even if created, a Service in `default` only selects pods in `default` — the pods would get **no endpoints**. |
| `imagePullPolicy: Never` | `imagePullPolicy: IfNotPresent` | `Never` hard-fails (`ErrImageNeverPull`) the moment a node lacks the image (e.g. after a node container is recreated) and never self-heals. `IfNotPresent` still prefers the locally loaded image, but tolerates a rebuilt node. |
| `minikube start … --force` always | `--force` is **opt-in**: `./deploy.sh --force` or `FORCE=1` | The brief deliberately continues **as root**, and the docker driver refuses root with `PROVIDER_DOCKER_AS_ROOT` unless forced. On a normal host `--force` masks real problems, so it must be requested explicitly. |
| `FROM python:3.9-slim` | `FROM python:3.12-slim` | 3.9 is past end-of-life; the app is three lines of Flask and runs identically on 3.12, which still receives security fixes. |
| Registry addon presented as *the* way to share images across nodes (step 1b), yet step 5 uses `minikube image load` | **both** kept: addon enabled in `[3/8]`, images loaded in `[5/8]`, roles spelled out | They do different jobs. `minikube image load` actually copies the local images **into every node's runtime** — that alone satisfies `imagePullPolicy: IfNotPresent` and is enough to schedule. The registry **addon** is an in-cluster registry (docker driver: port `32775`, not `5000`) you would *push* to for rebuilds without re-loading. |
| Step 0: `minikube stop && minikube delete` first | reuse a running profile; create/start only if absent or stopped | Deleting the cluster is optional; a re-runnable script should not destroy your cluster on every run. |
| Step 9: open a browser per service (blocks a terminal) | print `minikube service --url` **with a 30 s timeout** plus the `<node-ip>:<nodePort>` fallback | Browsers and blocking tunnels do not belong in a script; the fallback URL is what you use when the tunnel is not running. |

## 8. Key concepts from this exercise

### Multi-node Minikube
`minikube start --nodes 3` creates a control-plane node plus workers
(`devops-multinode`, `-m02`, `-m03`) as separate containers on the Docker
driver — each a full Kubernetes node with its own kubelet, pod CIDR and
**its own image storage**.

### podAntiAffinity + topologyKey
`requiredDuringSchedulingIgnoredDuringExecution` says: *no two pods matching
this label may share a node*, where "share" is defined by
`topologyKey: kubernetes.io/hostname`. Two replicas over three nodes always
fit; three replicas need all three nodes free. `IgnoredDuringExecution` means
existing pods are **not** evicted if the rule later becomes unsatisfiable —
the *extra* pod simply stays **Pending**. The softer
`preferredDuringScheduling…` variant would only *nudge* pods apart and can
legitimately place two on one node.

### imagePullPolicy: IfNotPresent vs Never

| Policy | Behaviour | Here |
|---|---|---|
| `Never` | use only the node-local image; fail if absent | brief's choice — brittle after node recreation |
| `IfNotPresent` | use the local image if present, else pull | this solution — same happy path, self-healing edge case |
| `Always` | always pull from a registry | wrong for locally built images with a `latest` tag |

Both images are loaded locally first, so the local copy always wins.

### NodePort vs ClusterIP
`ClusterIP` (Exercise 3) is reachable only **inside** the cluster. `NodePort`
exposes the Service on **every node** at a high port (`30000–32767`), so
`http://<any-node-ip>:<nodePort>` reaches the pods from outside — the
`192.168.49.2:32316`-style URL in the brief's output. `minikube service` is
the convenience wrapper that prints or tunnels that URL.

### Why images must be loaded onto every node
On a single node, `eval $(minikube docker-env)` makes the build land where the
kubelet looks. With 3 nodes there is **one docker CLI but three runtimes**: a
pod scheduled on `-m03` only sees images present on `-m03`. `minikube image
load` pushes the image into each node's runtime; skip it and the unlucky node
shows `ImagePullBackOff` for an image that "exists on your machine".

### The registry addon
`minikube addons enable registry` runs an in-cluster Docker registry (plus a
`kube-registry-proxy` on the docker driver — **port 32775**, not the default
5000). You `docker tag` + push to it and every node can pull — complementary to
`image load` for one-off local builds.

## 9. Cleanup

```bash
./cleanup.sh               # delete the whole devops-multinode profile (3 nodes)
./cleanup.sh --resources   # only delete the Deployments + Services, keep the cluster
```

Manual equivalents:

```bash
kubectl delete -f product-catalog-deployment.yaml -f shopping-cart-deployment.yaml
kubectl delete -f product-catalog-service.yaml -f shopping-cart-service.yaml
minikube -p devops-multinode delete
```

Local images are kept by default; `docker rmi product-catalog:latest
shopping-cart:latest` removes them. Deleting the profile also removes the
registry addon's state.

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| Extra pod stuck **Pending**: `FailedScheduling: 3 nodes didn't match Pod's node affinity/anti-affinity` | required anti-affinity cannot be satisfied — fewer Ready nodes than replicas. Check `kubectl get nodes`; fix the `NotReady`/stopped node (or `minikube -p devops-multinode start`) before the pod can land |
| Pod `ImagePullBackOff` / `ErrImageNeverPull` on one node | the image is not on **that** node — run `minikube -p devops-multinode image load product-catalog:latest` (and the shopping-cart one), then `kubectl delete pod <name>` to reschedule |
| `namespaces "devops-exercise" not found` on apply | the brief's namespace bug — use this folder's manifests (everything lives in `default`, see section 7) |
| `PROVIDER_DOCKER_AS_ROOT: The docker driver should not be used with root privileges` | the brief's `--force` case — re-run as your normal user, or `./deploy.sh --force` / `FORCE=1 ./deploy.sh` |
| `kubectl` talks to the wrong cluster or profile (`no such host`, odd pods) | a different profile is current — `kubectl config use-context devops-multinode` (`deploy.sh` pins the context automatically) |
| `minikube service … --url` never returns | on the docker driver it starts a tunnel; `deploy.sh` gives it 30 s then falls back to `<node-ip>:<nodePort>`. Manually, keep the tunnel terminal open, as the brief notes |
| NodePort URL unreachable from the host (macOS/Windows Docker Desktop) | the minikube node IP is inside the VM — normal. Use the tunnel (`minikube -p devops-multinode service shopping-cart-service`) instead of the raw node IP |
| `POST /cart` returns `415` | missing `-H "Content-Type: application/json"` — Flask refuses to parse the body without it |
| `GET /cart` does not show the item you just POSTed | you hit a **different replica** (each pod has its own in-memory cart). Use the tunnel/`kubectl port-forward` (one pod), or accept the eventual-consistency demo for what it is |
| Registry addon port confusion (`:5000` refused) | with the docker driver the registry listens on **32775** — the addon prints this in its own banner (brief step 1b) |
