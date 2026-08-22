# Exercise 1 — Kubernetes Getting Started: "Hello Pod"

**Goal:** Deploy your first application on Kubernetes — the **Zepto storefront /
delivery-status page**, simulated with the `nginx` image — and access it from
your browser.

---

## 1. What the exercise asks

You are the DevOps engineer at Zepto. Deploy a lightweight web app on a local
Kubernetes cluster (Minikube) so that it is always running, portable and can be
scaled later:

1. Start a Minikube cluster.
2. Create a Pod running the `nginx` image on port 80 (`hello-k8s`).
3. Verify the Pod is running.
4. Expose the Pod as a `NodePort` Service.
5. Open the app in a browser (`minikube service hello-k8s`) → Nginx welcome page.

## 2. Solution overview

```
Browser ──► minikube service hello-k8s
                │
                ▼
        Service "hello-k8s"  (type: NodePort, port 80 → 80)
                │  selector: app=hello-k8s
                ▼
        Pod "hello-k8s"      (container: nginx:1.27, containerPort 80)
```

- The **Pod** runs a single `nginx` container and is labelled `app: hello-k8s`.
- The **Service** targets that label (`selector: app: hello-k8s`), maps
  `port 80` → `targetPort 80`, and is exposed with `type: NodePort` so the
  cluster allocates a port on the Minikube node (visible via
  `kubectl get svc hello-k8s`).
- `minikube service hello-k8s` resolves the URL and opens it in your browser.

The two YAML files are the **declarative equivalent** of the brief's imperative
commands:

| Brief (imperative) | This solution (declarative) |
|---|---|
| `kubectl run hello-k8s --image=nginx --port=80` | `kubectl apply -f pod.yaml` |
| `kubectl expose pod hello-k8s --type=NodePort --port=80` | `kubectl apply -f service.yaml` |

## 3. Files in this folder

| File | Purpose |
|---|---|
| `pod.yaml` | Pod manifest: `hello-k8s`, container `nginx:1.27`, port 80, label `app: hello-k8s` |
| `service.yaml` | Service manifest: `hello-k8s`, `type: NodePort`, `port: 80 → targetPort: 80`, selects `app: hello-k8s` |
| `deploy.sh` | One-command setup: starts Minikube if needed, applies both manifests, waits for Ready, smoke-tests the app through a temporary port-forward, and prints the browser command |
| `cleanup.sh` | Deletes the Service and Pod (add `--cluster` to also stop Minikube) |
| `README.md` | This document |

> **Note on the image tag:** the brief uses `--image=nginx` (= `nginx:latest`).
> This solution pins `nginx:1.27` so the deployment is reproducible — behaviour
> is identical for this exercise.

## 4. Prerequisites

- **Minikube** and **kubectl** installed (see the brief's Pre-Requisites section
  for Linux / macOS / Windows / WSL instructions).
- A backing driver for Minikube: **Docker** (recommended) or VirtualBox/Hyper-V.
- `bash` to run the scripts — on Windows use **WSL** or **Git Bash**; the
  `kubectl` commands work in PowerShell exactly as written.

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise1
./deploy.sh
```

The script prints progress for all 5 stages, smoke-tests the app through a
temporary port-forward, and finishes with the browser command:

```
==> [1/5] Checking prerequisites...
==> [2/5] Ensuring Minikube cluster is running...
    Cluster already running.
==> [3/5] Deploying the nginx pod and NodePort service...
pod/hello-k8s created
service/hello-k8s created
==> [4/5] Waiting for pod hello-k8s to be Ready...
pod/hello-k8s condition met
==> [5/5] Current state:
NAME        READY   STATUS    RESTARTS   AGE   IP           NODE
hello-k8s   1/1     Running   0          30s   10.244.0.3   minikube

NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
hello-k8s     NodePort    10.96.100.42   <none>        80:30754/TCP   5s

==> Verifying the app end-to-end via a temporary port-forward...
    SUCCESS: nginx responded with the HTML welcome page.

To open the app in your browser, run:
    minikube service hello-k8s
```

### Option B — manual (exactly the brief's steps)

```bash
# 1. Start the cluster
minikube start

# 2. Create the pod
kubectl apply -f pod.yaml

# 3. Verify the pod is running
kubectl get pods
# NAME        READY   STATUS    RESTARTS   AGE
# hello-k8s   1/1     Running   0          20s

# 4. Expose it as a NodePort service
kubectl apply -f service.yaml

# 5. Open the app
minikube service hello-k8s
```

(Or use the imperative equivalents: `kubectl run hello-k8s --image=nginx --port=80`
and `kubectl expose pod hello-k8s --type=NodePort --port=80`.)

## 6. How to verify the expected output

| Check | Command | Expected result |
|---|---|---|
| Pod running | `kubectl get pods` | `hello-k8s … 1/1 Running` |
| Pod detail | `kubectl describe pod hello-k8s` | Events end with `Successfully assigned` / `Pulled image` / `Created container` / `Started container` |
| Service exists | `kubectl get svc hello-k8s` | `TYPE NodePort`, `PORT(S) 80:<nodePort>/TCP` |
| Endpoint wired | `kubectl get endpoints hello-k8s` | An IP:80 belonging to the pod |
| App responds | `minikube service hello-k8s` | Browser shows the **"Welcome to nginx!"** page |

## 7. Cleanup

```bash
./cleanup.sh            # delete service + pod, keep the cluster
./cleanup.sh --cluster   # also run: minikube stop
```

Manual equivalent:

```bash
kubectl delete service hello-k8s
kubectl delete pod hello-k8s
```

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| Pod `hello-k8s` stays `Pending` | Resources too low — run `minikube status`, then `minikube start --cpus=2 --memory=4096` |
| `ImagePullBackOff` | Node lost internet — check proxy/DNS, then `kubectl describe pod hello-k8s` |
| `minikube: docker: executable file not found in %PATH%` from Git Bash | Git Bash truncates PATH for native tools; run `minikube` from **PowerShell/WSL** instead (`deploy.sh` already works around this automatically) |
| Scripts won't execute on Windows | Run them inside **WSL**/**Git Bash**, or follow Option B manually from PowerShell |
