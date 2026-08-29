# Exercise 2 — Deploy a Flask App on Minikube using kubectl and YAML

**Goal:** Run a Python Flask application on the Minikube cluster — build the
image **inside Minikube's Docker daemon**, deploy it with a Deployment + Service
YAML, and access it from your machine.

---

## 1. What the exercise asks

1. Start Minikube.
2. Create `app.py` — a Flask app that answers *"Hello from Flask on Kubernetes!"*
   on port **15000**.
3. Create a `Dockerfile` for the app.
4. Build the image using **Minikube's Docker daemon** (`minikube docker-env`).
5. Create `flask-deployment.yaml` — a Deployment with `imagePullPolicy: Never`.
6. Deploy with `kubectl apply` and verify (deployment, pods, describe, logs).
7. Observe that `curl http://127.0.0.1:15000` fails — the app is not exposed yet.
8. Add a **NodePort Service** (`port: 15000 → targetPort: 15000`) to the YAML,
   re-apply, then open the app with `minikube service flask-app-service --url`.

## 2. Solution overview

```
curl / browser ──► minikube service flask-app-service --url (NodePort)
                            │
                            ▼
        Service "flask-app-service"  (NodePort, port 15000 → targetPort 15000)
                            │  selector: app=flask-app
                            ▼
        Deployment "flask-app"  ──►  Pod (image: flask-app:latest, port 15000)
                                          │
                                          ▼
                                   Flask (app.py, 0.0.0.0:15000)
```

- The **image** (`flask-app:latest`) is built directly into the cluster's Docker
  daemon, so `imagePullPolicy: Never` makes Kubernetes use the local image and
  never contact a registry.
- The **Deployment** keeps 1 replica of the pod and manages rollout/replicaSets.
- The **Service** exposes the pod on port 15000:
  `External request :15000 → Service :15000 → container :15000 → Flask :15000`.

## 3. Files in this folder

| File | Purpose |
|---|---|
| `app.py` | Flask application — `GET /` returns "Hello from Flask on Kubernetes!", listens on `0.0.0.0:15000` |
| `Dockerfile` | Builds `python:3.8-slim` + Flask, runs `app.py` |
| `.dockerignore` | Keeps README/scripts out of the build context |
| `flask-deployment.yaml` | Deployment (`imagePullPolicy: Never`) **+** NodePort Service, exactly as the brief's final version |
| `deploy.sh` | One-command flow: cluster → image build in Minikube → apply → rollout → HTTP smoke-test |
| `cleanup.sh` | Deletes the Service and Deployment (add `--cluster` to also stop Minikube) |
| `README.md` | This document |

## 4. Prerequisites

- Minikube + kubectl + Docker installed (see the brief's installation links).
- `bash` for the scripts (WSL / Git Bash on Windows); manual `kubectl` commands
  work from any shell.
- The cluster does **not** need to be running — `deploy.sh` starts it if needed.

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise2
./deploy.sh
```

Expected output:

```
==> [1/5] Checking prerequisites...
==> [2/5] Ensuring Minikube cluster is running...
    Cluster already running.
==> [3/5] Building the flask-app image inside Minikube's Docker daemon...
    Image flask-app:latest built via 'minikube docker-env' (brief Step 4).
==> [4/5] Deploying the Flask application and Service...
deployment.apps/flask-app unchanged
service/flask-app-service created
deployment.apps/flask-app condition met
==> [5/5] Current state:
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
flask-app    1/1     1            1           20s

NAME                          READY   STATUS    RESTARTS   AGE
flask-app-3443a-213a          1/1     Running   0          20s

NAME                 TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
flask-app-service    NodePort    10.101.165.1   <none>        15000:30343/TCP  5s

==> Verifying the app end-to-end via a temporary port-forward...
    SUCCESS: Hello from Flask on Kubernetes!

To open the app in your browser, run:
    minikube service flask-app-service --url
```

> The script prefers the brief's **`minikube docker-env`** build path (Step 4).
> If that endpoint is unreachable on your machine, it automatically falls back
> to `docker build` + `minikube image load flask-app` (also listed in the
> brief's cheat sheet, section 4).

### Option B — manual (the brief's steps)

```bash
# 1. Start the cluster
minikube start

# 2-3. Create app.py and Dockerfile (contents are in this folder), then build:
# 4. Build inside Minikube's Docker daemon
eval $(minikube docker-env)          # PowerShell: minikube docker-env | Invoke-Expression
docker build -t flask-app .

# 5-6. Deploy (flask-deployment.yaml is in this folder)
kubectl apply -f flask-deployment.yaml

# 7-9. Verify
kubectl get deployments
kubectl get pods -l app=flask-app
kubectl describe deployment flask-app

# 10. Logs — expect the Flask "Running on http://0.0.0.0:15000" banner
kubectl logs -l app=flask-app

# 11. Services (only kubernetes exists until the Service is applied)
kubectl get services

# 12. This FAILS on purpose — the app is not reachable from the host yet:
curl http://127.0.0.1:15000

# 13. flask-deployment.yaml already includes the Service — re-apply and access:
kubectl apply -f flask-deployment.yaml
minikube service flask-app-service --url     # prints e.g. http://127.0.0.1:36157

# New terminal:
curl http://127.0.0.1:36157
# Hello from Flask on Kubernetes!
```

## 6. How to verify the expected output

| Check | Command | Expected result |
|---|---|---|
| Deployment ready | `kubectl get deployments` | `flask-app … 1/1 … 1` |
| Pod running | `kubectl get pods -l app=flask-app` | `1/1 Running` |
| Deployment detail | `kubectl describe deployment flask-app` | `Available True`, `Progressing True`, revision 1 |
| App logs | `kubectl logs -l app=flask-app` | `* Running on http://0.0.0.0:15000` |
| Service | `kubectl get svc flask-app-service` | `NodePort … 15000:<nodePort>/TCP` |
| End-to-end | `minikube service flask-app-service --url` then `curl <url>` | `Hello from Flask on Kubernetes!` |

## 7. Key concepts from this exercise

### port vs targetPort

```
External request (port 15000) → Service (port 15000) → Container (targetPort 15000) → Flask
```

- **port** — the Service's own port that clients talk to.
- **targetPort** — the container port the traffic is forwarded to.

### imagePullPolicy: Never

| Policy | Behaviour |
|---|---|
| `Always` | Always pull from a registry |
| `IfNotPresent` | Pull only if the image is missing locally |
| `Never` | **Use the local image only** — required here because `flask-app:latest` was built inside Minikube's daemon and does not exist on Docker Hub |

### Why `curl http://127.0.0.1:15000` fails (brief Step 12)

Minikube runs the pod inside its own VM/container network; the app listens on
port 15000 **inside** the cluster only. Without a Service (and a way to reach
it from the host) the connection is refused — that is exactly why Step 13 adds
the NodePort Service.

## 8. Q&A (from the exercise)

| Q | A |
|---|---|
| What is the purpose of `minikube service flask-app-service --url`? | To provide the URL for accessing the flask-app-service running in Minikube. |
| What happens when you run it? | Minikube checks the service is running, generates a URL and displays it. |
| Why is `targetPort` used? | To specify the port on which the container is listening. |
| Difference between `port` and `targetPort`? | `port` is the exposed Service port; `targetPort` is the container port. |
| How do you access a Flask app running in Minikube? | `minikube service <service-name> --url` to get the access URL. |
| Why must the terminal stay open with the Docker driver? | The driver needs the terminal to maintain the Minikube connection/tunnel. |
| Benefit of the `--url` flag? | It gives the access URL without constructing it manually. |
| What command exposes a service? | `kubectl expose` or `kubectl apply -f <service.yaml>`. |
| How does Minikube help local testing? | It runs a single-node cluster locally without a full Kubernetes setup. |
| Role of kubectl? | The CLI to deploy, scale and manage resources on the cluster. |

## 9. Cleanup

```bash
./cleanup.sh            # delete service + deployment, keep the cluster
./cleanup.sh --cluster   # also run: minikube stop
```

Manual equivalent:

```bash
kubectl delete service flask-app-service
kubectl delete deployment flask-app
```

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| Pod `ImagePullBackOff` / `ErrImageNeverPull` | `flask-app:latest` is missing in the cluster — re-run `./deploy.sh`, or build + `minikube image load flask-app` |
| `minikube docker-env` build fails | Endpoint unreachable — the script auto-falls back; manually: `docker build -t flask-app .` then `minikube image load flask-app` |
| `minikube: docker not found in %PATH%` (Git Bash) | Git Bash truncates PATH for native tools — use PowerShell/WSL (`deploy.sh` works around this automatically) |
| `curl 127.0.0.1:15000` refused | Expected before the Service exists; after applying, use `minikube service flask-app-service --url` |
| Port-forward port busy | Change `PF_PORT` in `deploy.sh` |
