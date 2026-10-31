# Hospital Patient-Record Service — Docker, Minikube & AppArmor

A Flask REST API that adds and retrieves **synthetic** patient records stored in
PostgreSQL. It runs in Docker on a custom bridge network, is deployed to Minikube
with Deployments and Services, and the Python container is restricted with an
AppArmor profile (Linux) or equivalent hardening where AppArmor isn't available (macOS).

> All patient data is synthetic ("Test Patient A"…). Never use real patient data.

---

## 1. Architecture

```
 DOCKER (Part A)                                  KUBERNETES / MINIKUBE (Part B)
 ─────────────────────────────────────            ──────────────────────────────────────────────
 Mac  ──curl──► localhost:5050                     Mac ──curl──► minikube service tunnel
                    │  (-p 5050:5000)                                 │
 ┌──────── network: patient-net (bridge) ─┐        ┌──────── cluster ─▼────────────────────────┐
 │ patient-api  ──"patient-db:5432"──►    │        │ Service patient-api (NodePort 80→5000)     │
 │ (Flask,      Docker DNS               │        │      ├─► Pod patient-api  (replica 1)      │
 │  read-only,                patient-db │        │      └─► Pod patient-api  (replica 2)      │
 │  cap-drop ALL)       (Postgres, NO -p)│        │              │ DNS "patient-db"            │
 └────────────────────────────────────────┘        │ Service patient-db (ClusterIP 5432) ◄──────┘
                                                   │      └─► Pod patient-db + PVC 1Gi           │
                                                   └────────────────────────────────────────────┘
 Only the API is published. The database port is reachable ONLY inside the network/cluster.
```

## 2. Files

| File | Purpose |
|---|---|
| `app/app.py` | Flask REST API: `GET /health`, `GET /patients`, `GET /patients/<id>`, `POST /patients`; validation; JSON errors (400, 404, 405, 415, 503) |
| `app/security_test.py` | Runs inside the container; tries permitted and restricted operations and prints ALLOWED or BLOCKED |
| `app/requirements.txt` | flask, psycopg2-binary, gunicorn |
| `Dockerfile` | `python:3.12-slim`, non-root user (uid 10001), gunicorn on port 5000 |
| `k8s/db-secret.yaml` | Secret with DB name, user and password |
| `k8s/db.yaml` | PVC + PostgreSQL Deployment + **ClusterIP** Service `patient-db` (internal only) |
| `k8s/api.yaml` | API Deployment (2 replicas, probes, securityContext) + **NodePort** Service `patient-api` (30080) |
| `apparmor/k8s-patient-api` | AppArmor profile for the Python container |
| `apparmor/apparmor-patch.yaml` | Adds the AppArmor profile to the Deployment (Linux nodes only) |
| `scripts/*.sh` | One script per part (`docker-demo`, `test-api`, `k8s-deploy`, `apparmor-setup`, `failure-demo`, `cleanup`) |
| `COMMANDS.md` | Command reference with explanations (for the written paper) |

## 3. API reference

| Method | URL | Success | Errors |
|---|---|---|---|
| GET | `/health` | 200 `{"status":"ok","database":"connected"}` | 503 if DB unreachable |
| GET | `/patients` | 200 `{"count":n,"patients":[...]}` | — |
| GET | `/patients/<id>` | 200 record | 404 record not found |
| POST | `/patients` | 201 created record | 400 invalid JSON or fields, 415 not JSON |
| any other | — | — | 404 unknown URL, 405 wrong method |

**Validation rules:** `name` is required (non-empty, at most 100 characters). `age` is a required integer from 0 to 130. `gender` is required and must be `male`, `female` or `other`. `blood_group` is optional (A+, A-, B+, B-, AB+, AB-, O+, O-). `condition` is optional (at most 200 characters). Unknown fields are rejected.

## 4. Prerequisites (macOS)

```bash
docker --version            # Docker Desktop must be running
brew install minikube       # already installed on this Mac (v1.39.0)
kubectl version --client
```

> **macOS notes**
> * Port **5000** is used by *AirPlay Receiver*, so the API is published on **5050**.
> * With the Docker driver on macOS the Minikube node IP isn't reachable directly.
>   `minikube service patient-api --url` opens a tunnel, and **that terminal must stay open**.
> * Docker Desktop's kernel has **no AppArmor** (`docker info` shows only seccomp).
>   On a Mac the profile can't be loaded, so hardening is used instead (Section 7). On an
>   Ubuntu machine, the same files apply the real AppArmor profile.

---

## 5. Demonstration — step by step

Run everything from this folder:
```bash
cd ~/DevOps-Lab/devops_lab_exaam
```
Each step shows the **manual commands** to type during the demo. The matching script does the same thing in one go.

### Step 1 — Build the image
```bash
docker build -t patient-api:1.0 .
docker images patient-api
```

### Step 2 — Custom bridge network + database (port NOT published)
```bash
docker network create --driver bridge patient-net
docker network ls

docker run -d --name patient-db --network patient-net \
  -e POSTGRES_DB=patients -e POSTGRES_USER=patient_app -e POSTGRES_PASSWORD=DemoPass123 \
  -v patient-db-data:/var/lib/postgresql/data \
  postgres:16-alpine
```

### Step 3 — Run the API container on the same network
```bash
docker run -d --name patient-api --network patient-net -p 5050:5000 \
  -e DB_HOST=patient-db -e DB_PASSWORD=DemoPass123 \
  --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges:true \
  patient-api:1.0

docker ps
docker logs patient-api        # "Connected to database patient-db:5432/patients - table ready"
```
*(Script: `./scripts/docker-demo.sh` runs steps 1–3 and 4.)*

### Step 4 — Prove Flask reaches the DB **by container name**
```bash
docker network inspect patient-net            # both containers + their IPs
docker exec patient-api python -c "import socket; print(socket.gethostbyname('patient-db'))"
curl http://localhost:5050/health             # {"database":"connected","db_host":"patient-db",...}
```

### Step 5 — Functional REST API + validation
```bash
# add records (201)
curl -X POST http://localhost:5050/patients -H "Content-Type: application/json" \
  -d '{"name":"Test Patient A","age":45,"gender":"female","blood_group":"O+","condition":"Hypertension"}'
# list all / get one (200)
curl http://localhost:5050/patients
curl http://localhost:5050/patients/1
# missing record (404)
curl -i http://localhost:5050/patients/9999
# invalid data (400)
curl -i -X POST http://localhost:5050/patients -H "Content-Type: application/json" \
  -d '{"name":"","age":200,"gender":"x"}'
# malformed JSON (400) and wrong content type (415)
curl -i -X POST http://localhost:5050/patients -H "Content-Type: application/json" -d '{bad'
curl -i -X POST http://localhost:5050/patients -d 'name=x'
```
*(Script: `./scripts/test-api.sh http://localhost:5050` runs all of these.)*

### Step 6 — DB port is not published (Docker)
```bash
docker port patient-api      # 5000/tcp -> 0.0.0.0:5050
docker port patient-db       # (empty) -> 5432 is NOT published to the host
docker ps                    # PORTS column: patient-db shows only "5432/tcp" (no 0.0.0.0:)
```
> `docker ps` shows `5432/tcp` with no `0.0.0.0:` mapping. The port is open inside
> `patient-net` only. Use `docker port`, not `nc localhost 5432`, as the proof: any
> local tool (an SSH tunnel, a local Postgres) could be listening on 5432.

### Step 7 — Deploy to Minikube (Deployment + Service)
```bash
minikube start --driver=docker --memory=3072 --cpus=2
kubectl get nodes

minikube image load patient-api:1.0        # copy local image into the cluster node
kubectl apply -f k8s/                      # Secret, PVC, 2 Deployments, 2 Services
kubectl rollout status deployment/patient-db
kubectl rollout status deployment/patient-api

kubectl get deployments,replicasets,pods,svc -o wide
```
Expected: `patient-api 2/2`, `patient-db 1/1`. `patient-api` is a **NodePort** (`80:30080/TCP`) and
`patient-db` is a **ClusterIP** (`5432/TCP`, no node port).

Access the API through its Service (this is the intended interface):
```bash
minikube service patient-api --url         # e.g. http://127.0.0.1:56363 - keep this terminal OPEN
# in a 2nd terminal:
curl http://127.0.0.1:<port>/health
./scripts/test-api.sh http://127.0.0.1:<port>
```
DB connectivity by Service name inside Kubernetes:
```bash
kubectl exec deploy/patient-api -- python -c "import socket; print(socket.gethostbyname('patient-db'))"
kubectl get svc patient-db          # TYPE = ClusterIP -> not reachable from outside the cluster
kubectl get endpoints               # which pod IPs sit behind each Service
```
*(Script: `./scripts/k8s-deploy.sh`.)*

### Step 8 — Security restrictions (AppArmor / hardening)
```bash
kubectl exec deploy/patient-api -- python security_test.py
```
Actual output on this Mac (no AppArmor, hardening only):
```
Running as uid=10001  AppArmor profile: unconfined
Expected PERMITTED operations (needed by the app):
  [ALLOWED] Read application code /app/app.py
  [ALLOWED] Write temporary file in /tmp
  [ALLOWED] Resolve database by container name  -> patient-db -> 10.102.83.60
  [ALLOWED] Open TCP connection to database
Expected RESTRICTED operations (dangerous):
  [BLOCKED] Modify application code /app/app.py  -> Read-only file system
  [BLOCKED] Write to /etc                        -> Read-only file system
  [BLOCKED] Read /etc/shadow                     -> Permission denied
  [ALLOWED] Spawn a shell (/bin/sh)              <- only AppArmor blocks this (see Section 7)
  [BLOCKED] Open a raw network socket            -> Operation not permitted
  [BLOCKED] Write kernel setting /proc/sys       -> Read-only file system
```
*(Script: `./scripts/apparmor-setup.sh` detects AppArmor and applies it where supported.)*

### Step 9 — Intentional failure → diagnose from logs → fix
```bash
# 1. INTRODUCE the failure: typo in the DB hostname
kubectl set env deployment/patient-api DB_HOST=patient-dbb DB_CONNECT_RETRIES=3

# 2. OBSERVE
kubectl get pods -w               # new pod: Error -> CrashLoopBackOff, RESTARTS increasing (Ctrl+C)

# 3. DIAGNOSE
kubectl logs <new-pod-name> --previous
#   WARNING Database not reachable at patient-dbb:5432 ... could not translate host name "patient-dbb"
#   ERROR FATAL: could not connect to database host 'patient-dbb' - giving up
kubectl describe pod <new-pod-name>   # Last State: Terminated, Reason: Error, Exit Code: 1, DB_HOST: patient-dbb
kubectl get events --sort-by=.lastTimestamp   # BackOff restarting failed container / Readiness probe failed
kubectl get svc                   # the Service is called "patient-db", not "patient-dbb"

# 4. FIX
kubectl apply -f k8s/api.yaml     # restore correct config   (or: kubectl rollout undo deployment/patient-api)
kubectl rollout status deployment/patient-api
```
> **Point to make:** during the failure the two old pods **kept serving traffic**. The
> rolling update only replaces old pods once a new one becomes *Ready*, and the readiness
> probe (`/health`) never passed. So the bad config caused no outage.

The same failure in plain Docker:
```bash
docker run -d --name patient-api-broken --network patient-net \
  -e DB_HOST=patient-dbb -e DB_CONNECT_RETRIES=3 patient-api:1.0
docker ps -a                       # STATUS: Exited (1)
docker logs patient-api-broken     # same "could not translate host name" error
docker inspect patient-api-broken --format '{{.State.ExitCode}}'   # 1
docker rm -f patient-api-broken
```
*(Script: `./scripts/failure-demo.sh break | diagnose | fix`.)*

### Step 10 — Cleanup
```bash
./scripts/cleanup.sh            # containers, network, volume, k8s resources
./scripts/cleanup.sh --all      # also delete the Minikube cluster
```

---

## 6. Security design

| Layer | Setting | What it prevents |
|---|---|---|
| Image | `USER 10001` (non-root) | root-level damage if the app is compromised |
| Docker | `--read-only --tmpfs /tmp` | modifying code or system files (only /tmp writable) |
| Docker | `--cap-drop ALL` | raw sockets, chown, network admin, etc. |
| Docker | `--security-opt no-new-privileges` | setuid privilege escalation |
| K8s | `runAsNonRoot`, `readOnlyRootFilesystem`, `capabilities.drop: [ALL]`, `allowPrivilegeEscalation: false`, `seccompProfile: RuntimeDefault` | same as above, enforced by the kubelet |
| AppArmor | profile `k8s-patient-api` | exec of shells/binaries, writes to /app, /etc, /proc/sys, raw sockets, mount, ptrace |
| Network | DB Service is **ClusterIP**; no `-p` on the DB container | the database can't be reached from outside |
| Secrets | DB credentials in a Kubernetes **Secret** | no passwords in the Deployment YAML |

## 7. AppArmor on a Linux host ("where supported")

AppArmor is a Linux kernel security module. It is **not** available in Docker Desktop's
LinuxKit VM, so on macOS the profile can't be loaded (the scripts detect this). On an
**Ubuntu** machine (or Ubuntu VM):

```bash
# check support
cat /sys/module/apparmor/parameters/enabled            # Y
sudo aa-status | head

# load the profile into the kernel (-r replace, -W write cache)
sudo apparmor_parser -r -W apparmor/k8s-patient-api
sudo aa-status | grep k8s-patient-api                  # listed in enforce mode

# Docker
docker run -d --name patient-api --network patient-net -p 5050:5000 \
  -e DB_HOST=patient-db -e DB_PASSWORD=DemoPass123 \
  --security-opt apparmor=k8s-patient-api patient-api:1.0
docker exec patient-api cat /proc/1/attr/current        # k8s-patient-api (enforce)
docker exec patient-api python security_test.py
docker exec patient-api sh                              # -> permission denied (blocked)

# Kubernetes (minikube --driver=docker shares the host kernel, so loading on the host is enough)
kubectl patch deployment patient-api --patch-file apparmor/apparmor-patch.yaml
kubectl exec deploy/patient-api -- cat /proc/1/attr/current
kubectl exec deploy/patient-api -- python security_test.py   # shell spawn now [BLOCKED]
sudo dmesg | grep -i apparmor | grep DENIED             # kernel audit log of blocked actions
```

The profile (`apparmor/k8s-patient-api`) **permits** normal file reads, TCP/UDP networking
(HTTP + PostgreSQL + DNS) and signals between gunicorn processes. It **denies** executing
`/bin`, `/usr/bin`, `/sbin` and `/usr/sbin` binaries, writing to `/app`, `/etc`, `/proc/sys` and `/sys`, reading
`/etc/shadow`, raw/packet sockets, `mount`, `ptrace`, and `sys_admin`/`sys_module`/`net_raw`
capabilities. The profile was checked with `apparmor_parser` (Ubuntu 24.04), and it compiles cleanly.

## 8. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `bind: address already in use` on 5000 | macOS AirPlay Receiver. Use `-p 5050:5000` |
| Pods `ErrImagePull` / `ImagePullBackOff` | image not in the cluster: `minikube image load patient-api:1.0`, and keep `imagePullPolicy: IfNotPresent` |
| Code changed but pods run old code | rebuild, then `minikube image load patient-api:1.0` and `kubectl rollout restart deployment/patient-api` |
| `minikube service` URL stops working | the tunnel terminal was closed. Rerun the command |
| API pods `CrashLoopBackOff` | `kubectl logs <pod> --previous`. Usually a wrong `DB_HOST` or password, or the DB isn't ready |
| Pod `Blocked`: AppArmor not enabled | the AppArmor patch was applied on a node without AppArmor. Run `kubectl replace -f k8s/api.yaml` to remove it (`apply` keeps patched fields) |
