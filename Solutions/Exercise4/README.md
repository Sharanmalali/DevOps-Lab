# Exercise 4 — Docker Networking with Multiple Containers

**Goal:** Run a **three-container application** — Flask REST API + MySQL +
Redis — on a user-defined **bridge network**, and prove that containers find
each other **by name** while the host reaches the API through a **published
port**.

---

## 1. What the exercise asks

**Scenario:** a web application made of three containers:
a Python Flask web server (1), a MySQL database (2), a Redis cache (3).

| Task | Requirement |
|---|---|
| 1 | Create a bridge network: `docker network create --driver bridge my-bridge-net` |
| 2 | Verify it: `docker network ls` |
| 3 | Inspect it: `docker network inspect my-bridge-net` |
| 4 | Build the Flask image (`flask-api`) from the given `app.py`, `requirements.txt`, `Dockerfile`; launch `mysql`, `redis`, `flask` — all with `--net=my-bridge-net`, flask with `-p 5001:5001` |
| 5 | Test connectivity: `docker exec -it flask bash`, then `ping mysql` and `ping redis` |
| 6 | Clean up: stop/rm the 3 containers, `docker network rm my-bridge-net` |

Plus 4 questions (answered in section 8).

## 2. Solution overview

```
 HOST (your machine)
   │  curl http://127.0.0.1:5001/about        ← published port (-p 5001:5001)
   ▼
 ┌──────────────────── docker network: my-bridge-net (bridge, 172.19.0.0/16) ────────────────────┐
 │                                                                                              │
 │   flask (flask-api)              mysql (mysql:latest)          redis (redis:latest)          │
 │   172.19.0.4 :5001               172.19.0.2 :3306              172.19.0.3 :6379             │
 │        │                               ▲                          ▲                          │
 │        └── ping mysql / ping redis ────┴──────────────────────────┘                          │
 │           (Docker's embedded DNS: name "mysql" → 172.19.0.2)                                │
 └──────────────────────────────────────────────────────────────────────────────────────────────┘
```

- Containers on the same user-defined network get **automatic DNS**: every
  container's name resolves to its IP (that's what makes `ping mysql` work).
- `-p 5001:5001` is the **only** host↔container link; container↔container
  traffic never leaves the bridge.

### Brief clean-ups (deviations, all intentional — each one fixes a brief bug)

| Brief says | This solution uses | Why |
|---|---|---|
| `Flask==2.0.1` alone in `requirements.txt` | adds era-matching pins (`Werkzeug==2.0.3`, `Jinja2==3.0.3`, `itsdangerous==2.0.1`, `click==8.0.4`) | Installing `Flask==2.0.1` **today** pulls Werkzeug 3.x and crashes: `ImportError: cannot import name 'url_quote' from 'werkzeug.urls'` (reproduced during this lab). |
| `app.run(debug=True, port=5001)` | `app.run(debug=True, host='0.0.0.0', port=5001)` | Flask defaults to `127.0.0.1` **inside the container** — with the brief's code, the `-p 5001:5001` mapping and Q4 (`-p` exposes a port) would connect-refuse from the host. |
| Dockerfile has no `ping` | adds `iputils-ping` | `python:3.9-slim` ships without ping — Task 5's `docker exec flask ping mysql` would be `command not found`. |
| `docker run … mysql:latest` (no env) | adds `-e MYSQL_ROOT_PASSWORD=root` | Modern `mysql` images refuse to start without a root-password variable; the brief's container would exit instantly. |
| Q4 answer truncated: `` `-p 500" `` | completed: `-p 5001:5001` | Typo in the brief. |
| Inspect shows `172.18.0.0/16` | actual subnet varies (this run: `172.19.0.0/16`) | Docker picks the first free private range — the brief's sample is just an example. |

## 3. Files in this folder

| File | Purpose |
|---|---|
| `app.py` | Flask REST API — `GET /about` returns name/version/description JSON on port **5001** (brief's code + `host='0.0.0.0'`) |
| `requirements.txt` | `Flask==2.0.1` + its era-matching transitive pins (see clean-ups) |
| `Dockerfile` | Brief's Dockerfile + `iputils-ping` so Task 5's pings work |
| `deploy.sh` | One-command flow: Tasks 1–5 (network → inspect → build → 3 containers → pings → HTTP check) |
| `cleanup.sh` | Task 6 (stop/rm containers + network; `--image` also removes `flask-api`) |
| `README.md` | This document |

## 4. Prerequisites

- **Docker only** (Docker Desktop / Docker Engine running) — this exercise does
  **not** use Minikube or Kubernetes.
- `bash` for the scripts (Git Bash / WSL on Windows); the manual commands in
  Option B work from any shell.

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise4
./deploy.sh
```

Real output from a clean run (first-run image pulls trimmed):

```
==> [1/6] Checking prerequisites...
==> [2/6] Task 1+2: Creating the bridge network and listing it...
2813af2f3791b19bc835325822de139eee8a6b4dbb0903cc66dbf73b73bf00e3
NETWORK ID     NAME                      DRIVER    SCOPE
0d7a5bfe0310   bridge                    bridge    local
27f2c6290b5e   furnishing-mes_fmes-net   bridge    local
bf81f5ab8ed0   minikube                  bridge    local
2813af2f3791   my-bridge-net             bridge    local
==> [3/6] Task 3: Inspecting my-bridge-net...
    Name:    my-bridge-net
    Driver:  bridge
    Scope:   local
    Subnet:  172.19.0.0/16
    Gateway: 172.19.0.1
    Attached containers: 0
==> [4/6] Task 4: Building flask-api and launching the 3 containers...
    Image flask-api built.
    Started: mysql, redis, flask on my-bridge-net (flask published on host :5001).
==> [5/6] Task 5: Verifying container-to-container connectivity...
    Waiting for mysqld to finish first-time initialisation (up to 90s)...
    mysql is ready (mysqladmin ping OK).
    From inside the flask container: ping mysql
PING mysql (172.19.0.2) 56(84) bytes of data.
64 bytes from mysql.my-bridge-net (172.19.0.2): icmp_seq=1 ttl=64 time=2.05 ms
64 bytes from mysql.my-bridge-net (172.19.0.2): icmp_seq=2 ttl=64 time=0.083 ms
64 bytes from mysql.my-bridge-net (172.19.0.2): icmp_seq=3 ttl=64 time=0.080 ms

--- mysql ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2029ms
rtt min/avg/max/mdev = 0.080/0.739/2.054/0.929 ms
    From inside the flask container: ping redis
PING redis (172.19.0.3) 56(84) bytes of data.
64 bytes from redis.my-bridge-net (172.19.0.3): icmp_seq=1 ttl=64 time=1.03 ms
64 bytes from redis.my-bridge-net (172.19.0.3): icmp_seq=2 ttl=64 time=0.101 ms
64 bytes from redis.my-bridge-net (172.19.0.3): icmp_seq=3 ttl=64 time=0.744 ms

--- redis ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2020ms
rtt min/avg/max/mdev = 0.101/0.623/1.025/0.386 ms
==> [6/6] Verifying host -> flask via the published port, final state...
    SUCCESS: GET http://127.0.0.1:5001/about ->
      {
        "description": "This is a simple REST API built with Flask.",
        "name": "Simple REST API",
        "version": "1.0"
      }

NAMES     STATUS          IMAGE
flask     Up 19 seconds   flask-api
redis     Up 20 seconds   redis:latest
mysql     Up 22 seconds   mysql:latest

Done. Run './cleanup.sh' when you are finished.
```

### Option B — manual (the brief's commands, with the fixes inline)

```bash
# Task 1: create the bridge network
docker network create --driver bridge my-bridge-net

# Task 2: verify
docker network ls                     # my-bridge-net  bridge  local

# Task 3: inspect (subnet/gateway are chosen by Docker)
docker network inspect my-bridge-net

# Task 4a: build the Flask image (files are in this folder)
docker build -t flask-api .

# Task 4b: launch the containers on the network
docker run -d --name mysql --net=my-bridge-net -e MYSQL_ROOT_PASSWORD=root mysql:latest
docker run -d --name redis --net=my-bridge-net redis:latest
docker run -d --name flask  --net=my-bridge-net -p 5001:5001 flask-api

# Task 5: connectivity tests
docker exec -it flask bash            # interactive shell inside flask…
ping mysql                            # …or directly, non-interactive:
docker exec flask ping -c 3 mysql
docker exec flask ping -c 3 redis
docker exec flask getent hosts mysql  # DNS name -> IP, another way to see it

# Host -> container through the published port
curl http://127.0.0.1:5001/about

# Task 6: clean up
docker stop mysql redis flask && docker rm mysql redis flask
docker network rm my-bridge-net
```

## 6. How to verify the expected output

| Check | Command | Expected result |
|---|---|---|
| Network exists | `docker network ls` | `my-bridge-net  bridge  local` |
| Network details | `docker network inspect my-bridge-net` | `Driver: bridge`, a `172.x.0.0/16` subnet, `Attached containers: 3` |
| 3 containers running | `docker ps` | `mysql`, `redis`, `flask` all `Up` |
| flask → mysql | `docker exec flask ping -c 3 mysql` | resolves to `172.19.0.2`-style IP, **0% packet loss** |
| flask → redis | `docker exec flask ping -c 3 redis` | resolves to `172.19.0.3`-style IP, **0% packet loss** |
| host → flask | `curl http://127.0.0.1:5001/about` | JSON with `"name": "Simple REST API"` |
| Inspect shows attachments | `docker network inspect my-bridge-net` | `Containers` map has 3 entries (name → IP) |

## 7. Key concepts from this exercise

### What `--net` (=`--network`) does

Attaches the container to a named network at start. On a **user-defined**
bridge network (like `my-bridge-net`) Docker additionally provides embedded
DNS by container name — the default `bridge` network does **not** do name
resolution. That's the whole reason Task 1 exists.

### How containers communicate on the same network

1. **By name** (preferred): `ping mysql`, `http://redis:6379`,
   `mysql -h mysql` — Docker's embedded DNS turns the name into the container
   IP on the bridge.
2. **By IP**: `172.19.0.2` — works, but IPs change on every restart; names
   don't.

### bridge vs host network (Q3's answer, expanded)

| | bridge (default, used here) | host |
|---|---|---|
| Network stack | private — container gets its own IP | shares the host's stack (no separate IP) |
| Port mapping (`-p`) | required to reach the host side | unnecessary — the process binds host ports directly |
| Isolation | containers are behind a NAT "door" | container sees/uses host networking directly |
| DNS by name | ✅ on user-defined bridges | n/a (no per-container interface) |

### Exposing a port: `EXPOSE` vs `-p`

- `EXPOSE 5001` (Dockerfile) is **documentation only** — it changes nothing.
- `-p 5001:5001` (docker run) actually **publishes** the port:
  `host:5001 → container:5001`. That is the `-p` flag Q4 asks about.

### The three network directions in this lab

| Direction | Mechanism |
|---|---|
| flask → mysql / redis | bridge + DNS by name (Task 5) |
| host → flask | published port `-p 5001:5001` |
| mysql ↔ redis | also allowed — same network, no firewall between containers |

## 8. Q&A (from the exercise)

| # | Q | A |
|---|---|---|
| 1 | What is the purpose of the `--net` flag in `docker run`? | The `--net` flag specifies the network to connect the container to. |
| 2 | How do containers communicate with each other on the same network? | Containers communicate using their container names or IP addresses. |
| 3 | What is the difference between a bridge network and a host network? | A bridge network provides isolation between containers, while a host network shares the host's network stack. Think of it like: **Bridge Network:** Containers are in a private room, talking to each other through a door. **Host Network:** Containers are in the same room as the host, talking directly to everyone. |
| 4 | How can you expose a container's port to the host machine? | Use the `-p` flag to expose a container's port (e.g. `-p 5001:5001`). |

## 9. Cleanup

```bash
./cleanup.sh          # remove containers + network (flask-api image kept)
./cleanup.sh --image  # also remove the flask-api image
```

Manual equivalent (Task 6 verbatim):

```bash
docker stop mysql redis flask && docker rm mysql redis flask
docker network rm my-bridge-net
```

The script only touches the three lab container names (`mysql`, `redis`,
`flask`) and `my-bridge-net` — other containers/networks on the machine are
left alone.

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `ping: command not found` in flask | rebuild — the Dockerfile installs `iputils-ping` (brief's file omits it) |
| mysql container exits immediately | modern mysql images need `-e MYSQL_ROOT_PASSWORD=…` (script sets `root`) |
| `ImportError: … url_quote …` on flask start | `Flask==2.0.1` pulled a too-new Werkzeug — use this folder's pinned `requirements.txt` |
| `curl: Failed to connect … port 5001` | flask not started (`docker logs flask`), or the `host='0.0.0.0'` fix was reverted |
| `Temporary failure in name resolution` | container not on `my-bridge-net` — check `docker inspect <name>` → `NetworkSettings.Networks` |
| Port 5001 already in use | another process owns it — stop it, or change the host side: `-p 15001:5001` |
| `Cannot connect to the Docker daemon` | start Docker Desktop / `sudo systemctl start docker` |
