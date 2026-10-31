# Command Reference — Patient Record Service (for the written paper)

Each command has a one-line explanation. Commands are grouped in the order they are used in the demo.

---

## 1. Docker — images

| Command | Explanation |
|---|---|
| `docker build -t patient-api:1.0 .` | Build an image from the `Dockerfile` in the current directory (`.` is the build context) and tag it `name:version` |
| `docker images` | List local images |
| `docker rmi patient-api:1.0` | Remove an image |
| `docker pull postgres:16-alpine` | Download an image from Docker Hub |
| `docker history patient-api:1.0` | Show the layers of an image (one per Dockerfile instruction) |

**Dockerfile instructions used**

| Instruction | Meaning |
|---|---|
| `FROM python:3.12-slim` | Base image |
| `WORKDIR /app` | Working directory for later instructions and for the container |
| `COPY src dest` | Copy files from the build context into the image |
| `RUN pip install -r requirements.txt` | Run a command at **build** time (creates a layer) |
| `ENV KEY=value` | Set an environment variable |
| `USER 10001` | Run the container as a non-root user |
| `EXPOSE 5000` | Document the port the app listens on (it does **not** publish it) |
| `CMD ["gunicorn", ...]` | Default command run at **container start** |

## 2. Docker — containers

| Command | Explanation |
|---|---|
| `docker run -d --name patient-api ... patient-api:1.0` | Create and start a container. `-d` runs it in the background, `--name` gives it a name |
| `-p 5050:5000` | **Publish** port: host 5050 → container 5000 (makes it reachable from the host) |
| `-e DB_HOST=patient-db` | Pass an environment variable to the container |
| `-v patient-db-data:/var/lib/postgresql/data` | Mount a named **volume** so data survives the container being deleted |
| `--network patient-net` | Attach the container to a network |
| `docker ps` / `docker ps -a` | List running containers / all containers including stopped ones |
| `docker logs patient-api` | Show the container's stdout/stderr (application logs) |
| `docker logs -f --tail 20 patient-api` | Follow the logs live, starting from the last 20 lines |
| `docker exec -it patient-api bash` | Open an interactive shell in a running container |
| `docker exec patient-api python security_test.py` | Run one command inside a running container |
| `docker inspect patient-api` | Full JSON details (config, IP, mounts, state, exit code) |
| `docker inspect -f '{{.State.ExitCode}}' patient-api` | Extract one field using a Go template |
| `docker port patient-api` | Show published port mappings (empty output = nothing published) |
| `docker stop` / `docker start` / `docker restart <name>` | Stop / start / restart a container |
| `docker rm -f <name>` | Force-remove a container, even if it is running |
| `docker stats` | Live CPU and memory usage per container |

## 3. Docker — networking

| Command | Explanation |
|---|---|
| `docker network create --driver bridge patient-net` | Create a **user-defined bridge** network. Containers on it can reach each other **by container name** through Docker's built-in DNS |
| `docker network ls` | List networks (`bridge`, `host`, `none` + custom ones) |
| `docker network inspect patient-net` | Show the subnet, gateway and attached containers with their IPs |
| `docker network connect patient-net <c>` | Attach a running container to a network |
| `docker network disconnect patient-net <c>` | Detach it |
| `docker network rm patient-net` | Delete the network |

> **Default bridge vs custom bridge:** on the default `bridge` network containers can
> only reach each other by IP. A **custom** bridge adds automatic DNS (name → IP) and isolation.

## 4. Docker — security options

| Option | Explanation |
|---|---|
| `--read-only` | Make the container's root filesystem read-only |
| `--tmpfs /tmp` | In-memory writable `/tmp` (needed together with `--read-only`) |
| `--cap-drop ALL` | Remove all Linux capabilities (e.g. NET_RAW, CHOWN) |
| `--security-opt no-new-privileges:true` | Block privilege escalation through setuid binaries |
| `--security-opt apparmor=k8s-patient-api` | Confine the container with an AppArmor profile (Linux only) |
| `--user 10001` | Run as a specific non-root UID |
| `docker info --format '{{.SecurityOptions}}'` | Show which security modules the host supports (apparmor, seccomp) |

## 5. Docker — volumes and cleanup

| Command | Explanation |
|---|---|
| `docker volume ls` / `docker volume rm patient-db-data` | List / delete volumes |
| `docker system prune` | Remove stopped containers, unused networks and dangling images |

## 6. Minikube

| Command | Explanation |
|---|---|
| `minikube start --driver=docker --memory=3072 --cpus=2` | Create and start a local single-node Kubernetes cluster inside Docker |
| `minikube status` | Status of the host, kubelet and apiserver |
| `minikube image load patient-api:1.0` | Copy a locally built image into the cluster node, so pods can use it without a registry |
| `minikube image ls` | List images available inside the cluster |
| `minikube service patient-api --url` | Print a URL to reach a NodePort Service (on macOS it opens a tunnel, so keep the terminal open) |
| `minikube ip` | IP address of the cluster node |
| `minikube ssh` | Shell into the Minikube node |
| `minikube dashboard` | Open the Kubernetes web dashboard |
| `minikube addons list` | List add-ons (ingress, metrics-server, ...) |
| `minikube stop` / `minikube delete` | Stop the cluster / delete it completely |

## 7. kubectl — deploy and inspect

| Command | Explanation |
|---|---|
| `kubectl apply -f k8s/` | Create or update every resource described in the YAML files of the folder (declarative) |
| `kubectl delete -f k8s/` | Delete those resources |
| `kubectl get nodes` | List cluster nodes |
| `kubectl get pods -o wide` | List pods with their IP and node |
| `kubectl get pods -w` | Watch pod status changes live |
| `kubectl get deploy,rs,pods,svc` | List Deployments, ReplicaSets, Pods and Services together |
| `kubectl get endpoints` | Pod IPs currently behind each Service (only Ready pods) |
| `kubectl get secret patient-db-secret -o yaml` | Show a Secret (values are base64-encoded) |
| `kubectl describe pod <pod>` | Detailed state: container state, exit code, restart count, env, probe results, **events** |
| `kubectl describe svc patient-api` | Service type, ports, selector and endpoints |
| `kubectl rollout status deployment/patient-api` | Wait until a rollout finishes |
| `kubectl rollout history deployment/patient-api` | List previous revisions |
| `kubectl rollout undo deployment/patient-api` | Roll back to the previous revision |
| `kubectl rollout restart deployment/patient-api` | Recreate all pods (e.g. after loading a new image) |
| `kubectl scale deployment patient-api --replicas=3` | Change the number of replicas |
| `kubectl set env deployment/patient-api DB_HOST=x` | Change an environment variable (triggers a rolling update) |
| `kubectl set image deployment/patient-api patient-api=patient-api:2.0` | Update the container image |
| `kubectl patch deployment patient-api --patch-file apparmor/apparmor-patch.yaml` | Merge a partial change into a live object |
| `kubectl port-forward svc/patient-api 8081:80` | Forward a local port to a Service (alternative way to access it) |
| `kubectl exec deploy/patient-api -- python security_test.py` | Run a command inside a pod of the Deployment |
| `kubectl exec -it <pod> -- sh` | Interactive shell in a pod |

## 8. kubectl — logs and troubleshooting

| Command | Explanation |
|---|---|
| `kubectl logs <pod>` | Application logs (stdout/stderr) of the current container |
| `kubectl logs <pod> --previous` | Logs of the **previous (crashed)** container. This is the key command for CrashLoopBackOff |
| `kubectl logs -f deploy/patient-api` | Follow the logs of a pod in the Deployment |
| `kubectl logs -l app=patient-api --tail=20` | Logs of every pod with that label |
| `kubectl get events --sort-by=.lastTimestamp` | Cluster events: scheduling, image pull, probe failures, BackOff |
| `kubectl describe pod <pod>` | Shows `Last State: Terminated`, `Reason`, `Exit Code` and events at the bottom |
| `kubectl top pods` | CPU and memory use (needs the metrics-server add-on) |

**Common pod statuses**

| Status | Meaning |
|---|---|
| `Pending` | Not scheduled yet (no resources, or PVC not bound) |
| `ContainerCreating` | Pulling the image or mounting volumes |
| `Running` | Container started (check `READY 1/1` for readiness) |
| `Error` | Container exited with a non-zero code |
| `CrashLoopBackOff` | Container keeps crashing, and Kubernetes waits longer before each restart |
| `ErrImagePull` / `ImagePullBackOff` | Image not found (forgot `minikube image load`, or a wrong tag) |
| `Blocked` | Pod can't satisfy a security requirement (e.g. AppArmor not enabled on the node) |

## 9. Kubernetes objects used

| Object | Purpose in this project |
|---|---|
| **Deployment** | Declares the desired pods (image, replicas, env, probes). It manages a ReplicaSet and does rolling updates and rollbacks |
| **ReplicaSet** | Keeps exactly N identical pods running (created automatically by the Deployment) |
| **Pod** | Smallest unit; one or more containers sharing a network and storage |
| **Service – NodePort** | `patient-api`: stable entry point exposed on every node at port 30080 (external access) |
| **Service – ClusterIP** | `patient-db`: internal virtual IP + DNS name, **not reachable from outside** the cluster |
| **Secret** | Holds the DB password, injected through `secretKeyRef` / `envFrom` |
| **PersistentVolumeClaim** | Requests 1Gi of storage so PostgreSQL data survives pod restarts |
| **readinessProbe** | Pod gets traffic only when `/health` returns 200 |
| **livenessProbe** | Kubernetes restarts the container if `/health` keeps failing |
| **securityContext** | `runAsNonRoot`, `readOnlyRootFilesystem`, `capabilities.drop`, `allowPrivilegeEscalation`, `seccompProfile`, `appArmorProfile` |

## 10. AppArmor (Linux hosts)

| Command | Explanation |
|---|---|
| `cat /sys/module/apparmor/parameters/enabled` | `Y` means the kernel has AppArmor enabled |
| `sudo aa-status` | List loaded profiles and their mode (enforce/complain) |
| `sudo apparmor_parser -r -W apparmor/k8s-patient-api` | Load (`-r` replace) a profile into the kernel and cache it (`-W`) |
| `sudo apparmor_parser -R apparmor/k8s-patient-api` | Unload the profile |
| `sudo aa-complain <profile>` / `sudo aa-enforce <profile>` | Switch to log-only mode / blocking mode |
| `cat /proc/1/attr/current` (inside container) | Which profile confines the process, e.g. `k8s-patient-api (enforce)` |
| `sudo dmesg \| grep DENIED` or `journalctl -k \| grep apparmor` | Kernel log of operations AppArmor blocked |

**Profile rule syntax**

| Rule | Meaning |
|---|---|
| `profile NAME flags=(attach_disconnected) { ... }` | Profile definition |
| `#include <abstractions/base>` | Common rules every program needs (libc, locale...) |
| `file,` | Allow file access (narrowed by the deny rules) |
| `network inet stream,` | Allow TCP over IPv4 |
| `deny network raw,` | Block raw sockets |
| `deny /usr/bin/** x,` | Block executing anything under /usr/bin (shells, curl...) |
| `deny /app/** w,` | Block writing to the app directory |
| `deny mount,` / `deny ptrace,` | Block mounting filesystems / debugging other processes |
| `deny capability sys_admin,` | Block a Linux capability |
| permissions | `r` read, `w` write, `x` execute, `l` link, `k` lock, `m` memory-map exec |

## 11. curl — testing the REST API

| Command | Explanation |
|---|---|
| `curl http://localhost:5050/patients` | GET request |
| `curl -i URL` | Also show the response status line and headers |
| `curl -X POST URL -H "Content-Type: application/json" -d '{...}'` | POST JSON. `-X` sets the method, `-H` adds a header, `-d` sets the body |
| `curl -s -w '%{http_code}' URL` | Silent mode, printing only the HTTP status code |

**HTTP status codes returned**

| Code | When |
|---|---|
| 200 OK | Successful GET |
| 201 Created | Patient added |
| 400 Bad Request | Invalid JSON or failed validation |
| 404 Not Found | Patient id doesn't exist / unknown URL |
| 405 Method Not Allowed | e.g. DELETE on /patients/1 |
| 415 Unsupported Media Type | Body isn't `application/json` |
| 503 Service Unavailable | Database unreachable (`/health`) |

## 12. One-line answers (viva)

* **Why a custom bridge network?** It gives automatic DNS, so Flask uses `DB_HOST=patient-db` instead of a changing IP. It also isolates the app from other containers.
* **How is the DB port kept private?** Docker: the DB container is started without `-p`. Kubernetes: the DB Service is `ClusterIP`. Only the API is published (`-p 5050:5000` / NodePort 30080).
* **Deployment vs ReplicaSet?** A ReplicaSet only keeps N pods running. A Deployment manages ReplicaSets and adds rolling updates, history and rollback.
* **How was the failure diagnosed?** `kubectl get pods` showed CrashLoopBackOff, `kubectl logs --previous` showed "could not translate host name patient-dbb", and `kubectl describe` showed `Exit Code 1` and `DB_HOST=patient-dbb`. Fixed with `kubectl apply -f k8s/api.yaml` / `kubectl rollout undo`.
* **Why no outage during the failure?** The new pod never passed its readiness probe, so the rolling update kept the old pods serving.
* **What is AppArmor?** A Linux kernel Mandatory Access Control module that confines a program to a per-profile list of allowed files, capabilities and network operations, even if it runs as root.
* **Why isn't AppArmor active on the Mac?** Docker Desktop runs containers in a LinuxKit VM whose kernel has no AppArmor (only seccomp). The profile is applied on Linux hosts. On the Mac, read-only rootfs, dropped capabilities, non-root and seccomp provide the restrictions.
