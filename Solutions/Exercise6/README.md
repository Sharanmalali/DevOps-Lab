# Exercise 6 — Real-Time Operations Monitoring with Prometheus, Grafana & Jenkins

**Goal:** Build the ZAPPTTO delivery-monitoring stack — a Python app that
simulates delivery metrics, **Prometheus** scraping it with alert rules,
**Grafana** showing the four KPI panels, and a **Jenkins pipeline** that builds/
runs the whole thing — then **prove the alerts fire**.

---

## 1. What the exercise asks

**Scenario:** manage a fast-paced delivery service; get real-time insight into
operational efficiency and be alerted before problems grow.

| Task | Requirement |
|---|---|
| 1 | Write `delivery_metrics.py` — `prometheus_client` HTTP server on **:8000** exporting `total_deliveries`, `pending_deliveries`, `on_the_way_deliveries`, `average_delivery_time` |
| 2 | `prometheus.ym` = scrape config; `alert_rules.yml` = `HighPendingDeliveries` (`pending_deliveries > 10`, `for: 15s`) + `HighAverageDeliveryTime` (`avg > 30`) |
| 3 | Grafana with Prometheus data source + 4-panel dashboard |
| 5 | Jenkins pipeline (`Jenkinsfile`): Pre-check Docker → Setup Workspace → Build Docker Image → Run Application → Run Prometheus & Grafana |
| 6 | Simulate alerts, verify in Prometheus/Grafana |

**Expected outputs:** `/metrics` endpoint, Prometheus query graphs, Grafana
dashboard, successful Jenkins build, and firing Prometheus alerts (section 6
maps each one to a command).

## 2. Solution overview

```
   HOST (this machine)                        Docker Desktop daemon
 ┌────────────────────────┐              ┌──────────────────────────────────┐
 │ delivery_metrics.py    │  :8000       │  jenkins  (ex6-jenkins image)    │
 │  total/pending/onway   │◄─────────────┤   pipeline 'delivery-monitoring' │
 │  average_time (Summary)│  host.docker │   sh → docker build / run        │
 └────────────────────────┘  .internal   └───────────────┬──────────────────┘
            ▲                                             │ docker.sock (DooD)
            │ scrape /metrics                             ▼
 ┌──────────┴───────────┐   :9090      ┌──────────────────────────────────┐
 │ prometheus            │◄────────────┤  grafana  :3000                  │
 │  scrape:5s eval:5s    │  datasource │   provisioned datasource+dash    │
 │  alert_rules.yml      │────────────►│   4 panels (delivery-operations) │
 └───────────────────────┘             └──────────────────────────────────┘
              network: ex6-net
```

- **deploy.sh** (host side) starts the simulator, then Prometheus and Grafana
  with the config files in this folder bind-mounted in.
- **Jenkins** gets the host's `docker.sock` (Docker-out-of-Docker) so the
  pipeline's `docker build/run` commands act on the same daemon. The pipeline
  *recreates* Prometheus and Grafana from the workspace (brief Step 5), which
  is why it also needs a network (`ex6-net`) and the host source path.
- Alerts are evaluated by Prometheus itself; Grafana only visualises.

### Data flow of one alert

```
delivery_metrics.py  set()/observe() every 1s
        │ /metrics
        ▼
Prometheus scrape (5s) → evaluates alert expr every 5s
        │ expr true for `for:` duration
        ▼
state: inactive → pending → firing   (visible in Prometheus → Alerts, and via
                                      Grafana's alert panel / API)
```

## 3. Files in this folder

| File | Purpose |
|---|---|
| `delivery_metrics.py` | Step 1 simulator (brief code, with deterministic ranges — see clean-ups) |
| `prometheus.yml` | Step 2a scrape config — self + `host.docker.internal:8000`, `rule_files`, `scrape/eval: 5s` |
| `alert_rules.yml` | Step 2a alert rules (brief verbatim) |
| `Dockerfile` | Builds the `delivery_metrics` image (`python:3.12-slim`) |
| `Dockerfile.jenkins` | `jenkins/jenkins:lts` + Pipeline plugins + Docker CLI (brief's stock image can't run the Jenkinsfile) |
| `Jenkinsfile` | Step 5 pipeline (brief stages + a Verify stage) |
| `provisioning/datasources/prometheus.yml` | Grafana data source (provisioned, uid `prometheus-uid`) |
| `provisioning/dashboards/dashboards.yml` | Grafana dashboard provider |
| `provisioning/dashboards/delivery-dashboard.json` | 4-panel dashboard, uid `delivery-operations` |
| `deploy.sh` | One-command flow `[1/8]`–`[8/8]` (see section 5) |
| `cleanup.sh` | Stops the simulator, removes containers/network; `--image`, `--volumes` |
| `README.md` | This document |

## 4. Prerequisites

- **Docker** (Docker Desktop / Engine) running, with the Compose socket at the
  default location.
- **Python 3.10+** with `prometheus-client` (installed automatically by
  `deploy.sh`; the brief's step 2a is `pip3 install prometheus-client`).
- **bash** (Git Bash / WSL on Windows) — `curl`, `netstat` are used by deploy.sh.
- No local Jenkins install is needed: it runs from the `ex6-jenkins` image.

> **Ports.** 8080 must be free for Jenkins; if it is busy (on this machine an
> unrelated `httpd` holds it) `deploy.sh` automatically uses **8081**.
> 9090 (Prometheus), 3000 (Grafana) and 8000/8010 (metrics) must be free.

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise6
./deploy.sh
```

Real output from this machine (trimmed); Jenkins UI is on 8081 because 8080 was
taken by the host's `httpd`:

```
==> [1/8] Checking prerequisites...
    prometheus-client: 0.26.0
    [NOTICE] Port 8080 busy (not ours) - Jenkins UI on http://localhost:8081
    Network ex6-net created.
==> [2/8] Pulling images and building the lab images...
    Images ready: prom/prometheus, grafana/grafana, jenkins/jenkins:lts, delivery_metrics, ex6-jenkins
==> [3/8] Step 1: Starting the delivery metrics simulator (host python)...
    Started (pid 293, log /tmp/ex6-delivery_metrics.log).
    GET http://127.0.0.1:8000/metrics -> all 4 delivery metrics present.
==> [4/8] Step 2: Starting Prometheus...
    Targets up: 2/2 (prometheus self + delivery_service).
    Alert rules loaded: HighPendingDeliveries, HighAverageDeliveryTime.
==> [5/8] Step 3: Starting Grafana with provisioned datasource + dashboard...
    Grafana healthy; datasource 'Prometheus' provisioned; dashboard has 4/4 panels.
==> [6/8] Step 5: Starting Jenkins and running the pipeline...
    Jenkins up on http://127.0.0.1:8081 (wizard disabled so the job can be scripted).
    Job 'delivery-monitoring' created from the Jenkinsfile.
    Build queued - waiting for the result (up to 10 min)...
    Pipeline result: SUCCESS.
    | --- delivery metrics (Step 1 process on the host) ---
    | pending_deliveries 13.0
    | --- Prometheus targets ---
    |       2 "health":"up"
    | --- Grafana health ---
    | { "database": "ok", ... }
==> [7/8] Step 6: Waiting for alerts to fire (Expected Output 5)...
    firing  HighAverageDeliveryTime    severity=critical
==> [8/8] Final state...
NAMES              STATUS              PORTS
grafana            Up 30 seconds       0.0.0.0:3000->3000/tcp
prometheus         Up 31 seconds       0.0.0.0:9090->9090/tcp
delivery_metrics   Up 33 seconds       0.0.0.0:8010->8000/tcp
jenkins            Up About a minute   0.0.0.0:8081->8080/tcp, 0.0.0.0:50000->50000/tcp

    Metrics : http://127.0.0.1:8000/metrics          (host python, pid 293)
    Prometheus: http://localhost:9090   (Status -> Targets, Alerts)
    Grafana   : http://localhost:3000   (admin/admin, dashboard 'Delivery Operations Monitoring')
    Jenkins   : http://127.0.0.1:8081  (pipeline 'delivery-monitoring' = SUCCESS)

Done. Run './cleanup.sh' when you are finished.
```

`[7/8]` waits until **at least one alert is `firing`**; both rules become
`firing` within the wait window (see section 6). If the window elapses the
script prints the alert JSON and exits non-zero — it never claims success
without a firing alert.

### Option B — manual (the brief's commands, with the fixes inline)

```bash
# Step 1 — simulator
pip install prometheus-client
python delivery_metrics.py            # serves http://localhost:8000/metrics

# Step 2 — Prometheus (config + rules bind-mounted in)
docker run -d --name prometheus --network ex6-net -p 9090:9090 \
  --add-host=host.docker.internal:host-gateway \
  -v "$PWD/prometheus.yml:/etc/prometheus/prometheus.yml" \
  -v "$PWD/alert_rules.yml:/etc/prometheus/alert_rules.yml" \
  prom/prometheus

# Step 3 — Grafana
docker run -d --name grafana --network ex6-net -p 3000:3000 \
  -v "$PWD/provisioning/datasources:/etc/grafana/provisioning/datasources" \
  -v "$PWD/provisioning/dashboards:/etc/grafana/provisioning/dashboards" \
  grafana/grafana

# Step 5 — Jenkins (image built from Dockerfile.jenkins)
docker build -t ex6-jenkins -f Dockerfile.jenkins .
docker run -d --name jenkins -p 8081:8080 -p 50000:50000 \
  -e JAVA_OPTS=-Djenkins.install.runSetupWizard=false \
  -e EX6_HOST_SRC="$PWD" -e EX6_SOURCE_DIR=/workspace-src \
  -v jenkins_home:/var/jenkins_home -v "$PWD:/workspace-src:ro" \
  -v /var/run/docker.sock:/var/run/docker.sock --group-add 0 \
  --network ex6-net --add-host=host.docker.internal:host-gateway ex6-jenkins
# then create the pipeline job from Jenkinsfile (deploy.sh does this by API)
```

`EX6_HOST_SRC` must be the **host** path (forward slashes), because the
pipeline recreates Prometheus/Grafana and the *daemon* resolves those bind
sources on the host — see the DooD clean-up.

## 6. How to verify the expected output

| # | Expected output (brief) | Command | Result on this machine |
|---|---|---|---|
| 1 | Metrics endpoint | `curl http://localhost:8000/metrics \| grep -E "^pending_deliveries "` | `pending_deliveries 13.0` (value changes each second) |
| 2 | Prometheus query graphs | open http://localhost:9090 → Graph, query `total_deliveries` | trend line, updates every 5s |
| 3 | Grafana dashboard | open http://localhost:3000 (admin/admin) → *Delivery Operations Monitoring* | 4 panels: Total, Pending, On-the-Way, Average Delivery Time |
| 4 | Jenkins logs | http://localhost:8081 → `delivery-monitoring` → Console | `Finished: SUCCESS`, Docker build/run logs |
| 5 | Prometheus alerts | http://localhost:9090 → Alerts, or `curl -s localhost:9090/api/v1/alerts` | `HighAverageDeliveryTime` **firing** (critical), `HighPendingDeliveries` pending→firing |

Terminal checks:

```bash
curl -s http://localhost:9090/api/v1/targets | python -c "import sys,json;print([t['health'] for t in json.load(sys.stdin)['data']['activeTargets']])"
# ['up', 'up']

curl -s http://localhost:9090/api/v1/rules | python -c "import sys,json;print([r['name'] for g in json.load(sys.stdin)['data']['groups'] for r in g['rules']])"
# ['HighPendingDeliveries', 'HighAverageDeliveryTime']

curl -s http://localhost:9090/api/v1/alerts | python -c "import sys,json;print([(a['labels']['alertname'],a['state']) for a in json.load(sys.stdin)['data']['alerts']])"
# [('HighAverageDeliveryTime', 'firing'), ('HighPendingDeliveries', 'firing')]
```

## 7. Brief clean-ups (deviations, all intentional — each one fixes a brief bug)

| Brief says | This solution uses | Why |
|---|---|---|
| File named **`prometheus.ym`** (missing `l`) | `prometheus.yml` | Prometheus only auto-loads `/etc/prometheus/prometheus.yml`; the typo'd name is also referenced by `--mount`/`-v`, so the brief's own run command mounts a file that doesn't exist. |
| `prometheus.yml` lists the rules file as `alert_rules.yml` but the Step 2a heading calls the file **`alerts_rules.yml`** (plural) | single `alert_rules.yml` (matches `rule_files:` and the mount) | Consistent with the file the brief's `-v` command actually mounts. |
| Prometheus run uses `--network=host`, target `172.17.0.1:8000` | bridge network `ex6-net` + target `host.docker.internal:8000` (`--add-host=host.docker.internal:host-gateway`) | `--network=host` is **ignored on Docker Desktop** (Windows/macOS VM) so `localhost:9090` wouldn't be published, and `172.17.0.1` is the Linux `docker0` address that doesn't exist here. `host.docker.internal` works on Desktop and, with the `host-gateway` flag, on plain Linux too. |
| Jenkins via stock `jenkins/jenkins:lts` | `Dockerfile.jenkins` = `jenkins/jenkins:lts` + `workflow-aggregator` + `pipeline-model-definition` + Docker CLI | Stock LTS has neither Pipeline plugins (the brief's calling of `sh`/declarative `pipeline {}` fails with *No such DSL method 'pipeline'*) nor a Docker CLI inside the container, so its own pipeline can't run. |
| Manual "retrieve initial admin password / skip update password" + New Item → paste script | `-Djenkins.install.runSetupWizard=false`, job created from `Jenkinsfile` via the Jenkins API | Makes the pipeline reproducible and scriptable; the wizard/PSA steps are interactive-only and can't be automated. |
| `Setup Workspace` copies from `/path/to/your/local/files` (a placeholder) | bind-mounts this folder at `/workspace-src` (`EX6_SOURCE_DIR`) | `/path/to/...` is a literal placeholder — the copy can never succeed. |
| `Run Application`: `-p 8000:8000` | `-p 8010:8000` | Port 8000 is already the Step 1 simulator on the host; publishing 8000 would fail. 8010 keeps the brief's container while letting Prometheus scrape the *host* process. |
| `docker run`/`docker build` with no re-run guard | `docker rm -f <name> 2>/dev/null \|\| true` before each `docker run` | The brief's plain `docker run` fails on the second attempt with *name already in use*. |
| `Run Prometheus & Grafana` mounts `$WORKSPACE/...` from inside the Jenkins container | mounts the **host** path (`EX6_HOST_SRC`) via `--mount type=bind` | Docker-out-of-Docker: the daemon resolves bind sources on the **host**, so `/var/jenkins_home/workspace/...` is invisible to it → *not a directory* mount error. |
| Step 6: "modify `delivery_metrics.py` to `randint(50, 100)`, restart, verify alerts" | the shipped ranges already cross the thresholds (`randint(11,20)`, `uniform(20,50)`) and `deploy.sh` verifies a firing alert | `randint(10,20)` in the brief includes `10`, which is **not** `> 10` — a sample of 10 resets the `for: 15s` clock; `uniform(15,45)` averages to exactly **30**, the `> 30` threshold, so firing there is a coin flip. The shipped ranges make Expected Output 5 deterministic. |
| `alert_rules.yml` has no `for` on the average alert; brief note says "last 15 second" | kept the brief's `for:` (15s on pending; none on average) | Matches the brief; the *description* text is the only mismatch (brief copy), left as-is for fidelity. |
| Prometheus defaults (scrape/eval 15s) | `scrape_interval: 5s`, `evaluation_interval: 5s` | With 15s scraping a `for: 15s` rule needs luck to leave `pending` inside the deploy wait; 5s makes alerts fire promptly and the run reproducible. |

## 8. Key concepts from this exercise

### Gauges vs Summary

- `total_deliveries`, `pending_deliveries`, `on_the_way_deliveries` are
  **Gauges** — a single number that can go up or down (current state).
- `average_delivery_time` is a **Summary** — it exposes
  `average_delivery_time_sum` and `average_delivery_time_count`; the average is
  the ratio of the two (that's the `_sum / _count` expression used in the
  alert and the dashboard).

### Why `host.docker.internal` (and not `172.17.0.1`)

Prometheus runs *inside* a container; the simulator runs on the host. On Docker
Desktop the container→host alias is `host.docker.internal`; on Linux it doesn't
exist by default, so `deploy.sh` adds
`--add-host=host.docker.internal:host-gateway`, which makes the same config
work on both.

### Docker-out-of-Docker (DooD)

Mounting `/var/run/docker.sock` lets the Jenkins container drive the host
daemon. Two consequences, both handled here:

1. **Bind-mount sources are host paths** — the pipeline must use
   `EX6_HOST_SRC`, not `$WORKSPACE`.
2. The socket is owned `root:root`; the `jenkins` user needs
   `--group-add 0` (the root group) to use it — no `chmod`, no `-u root`.

### Why alerts need the `for:` window

A single high sample shouldn't page anyone. `for: 15s` means "the expression
must stay true for 15s" — during that time the alert is `pending`, then
`firing`. With a 1s simulator that can momentarily dip, the deterministic
ranges above ensure the expression stays true (section 7).

### How the dashboard is provisioned

Grafana reads `/etc/grafana/provisioning/datasources/*.yml` (data source,
`uid: prometheus-uid`) and `/etc/grafana/provisioning/dashboards/*.json` at
startup, so the dashboard exists with no manual clicking. The panels query the
data source by `uid`, which is why the JSON pins `prometheus-uid`.

## 9. Cleanup

```bash
./cleanup.sh             # stop simulator + remove containers + network
./cleanup.sh --image     # also remove delivery_metrics and ex6-jenkins images
./cleanup.sh --volumes   # also remove the jenkins_home volume
```

`cleanup.sh` stops the Step 1 simulator by its PID file, falling back to the
port-8000 owner **only if** `GET /metrics` proves it is our simulator — so an
unrelated app on port 8000 is never killed. Both modes were tested on this
machine (containers gone, network gone, simulator stopped).

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| Jenkins build fails: `No such DSL method 'pipeline'` | the stock `jenkins/jenkins:lts` image lacks Pipeline plugins — rebuild `ex6-jenkins` from `Dockerfile.jenkins` |
| Pipeline mount error `not a directory` / `mounts denied` | DooD bind source issue — make sure Jenkins sees `EX6_HOST_SRC` (forward-slash host path) and the stage uses `--mount`, not `$WORKSPACE` |
| `part of the container's workspace is not visible to the daemon` | same as above; start Jenkins via `deploy.sh` |
| Jenkins UI not on 8080 | 8080 is taken; this run used **8081** (`deploy.sh` prints the URL it chose) |
| Alerts stay `pending`, Expected Output 5 not met | the simulator range is at the threshold (brief default) — this folder's ranges cross it; confirm `pending_deliveries > 10` and probe the average IP |
| `name "/prometheus" is already in use` | stale container — every `docker run` here is prefixed by `docker rm -f`, and `./cleanup.sh` removes leftovers |
| `docker: command not found` inside a Git Bash pipeline | Git Bash truncated `PATH`; `deploy.sh` prepends Docker's bin dir — re-run via `./deploy.sh` |
| `port is already allocated` on 8000/8010/9090/3000 | a leftover container holds it: `./cleanup.sh`, then redeploy |
| `docker-credential-desktop: executable file not found` | Git Bash `PATH` truncation again — `deploy.sh`'s PATH guard fixes it in-script |
| Jenkins job exists but you want a clean slate | delete the `jenkins_home` volume: `./cleanup.sh --volumes` |
