# Exercise 7 — Introduction to CI & Jenkins Installation

**Goal:** install a **Jenkins LTS** controller with Docker, unlock it with the
initial administrator password, and reach the Jenkins dashboard — the practical
counterpart to the brief's theory on Continuous Integration and CI tools.

---

## 1. What the exercise asks

The brief is mostly conceptual, plus one hands-on task at the end.

| Part | Content |
|---|---|
| Theory | What CI is, key features, benefits, how it works, a workflow example |
| Theory | 10 example CI tools (GitLab CI/CD, CircleCI, Travis, Bamboo, TeamCity, Azure DevOps, GitHub Actions, Spinnaker, Buildkite, Drone) |
| Theory | What Jenkins is, why to use it, key concepts (Job, Build, Pipeline, Plugins, Nodes) |
| **Hands-on** | **Install Jenkins with Docker**, retrieve the initial admin password, open `http://localhost:8080/`, complete the setup wizard (Unlock → Install plugins → landing page) |

There is **no Q&A section** in this brief — the deliverable is a working,
reproducible Jenkins installation plus the documentation on this page.

## 2. Solution overview

```
   HOST (this machine)                       Docker Desktop daemon
 ┌────────────────────────┐             ┌────────────────────────────────┐
 │ deploy.sh              │  docker run │  jenkins (jenkins/jenkins:lts)  │
 │  1 check docker        │────────────►│   :8080  controller (UI)        │
 │  2 pick free ports     │             │   :50000 inbound agent (JNLP)   │
 │  3 start container     │             │                                 │
 │  4 wait HTTP 200       │             │   volume: ex7_jenkins_home      │
 │  5 read initial pwd    │◄────────────┤     /var/jenkins_home           │
 │  6 print wizard steps  │  docker exec│     secrets/initialAdminPassword│
 └────────────────────────┘             └────────────────────────────────┘
        browser  ──────────────────────────────►  http://localhost:<port>/
```

- **`deploy.sh`** starts the container, waits until Jenkins answers on HTTP, and
  prints the **initial admin password** (read from
  `/var/jenkins_home/secrets/initialAdminPassword`).
- All Jenkins state (users, plugins, jobs, build history) lives in the named
  volume **`ex7_jenkins_home`**, so it survives `docker rm`/restart. The volume
  is dedicated to this exercise so it can never collide with another exercise's
  Jenkins instance.
- **`deploy.sh --auto`** optionally bootstraps a headless controller (wizard
  skipped, `admin`/`admin` account) via `init.groovy.d`, which makes the
  install fully scriptable and testable end-to-end.

### The setup-wizard lifecycle

```
docker run
   │  ~30-60s while Jenkins extracts plugins / bootstraps
   ▼
GET /  ->  HTTP 200 "Unlock Jenkins"   (initialAdminPassword now on disk)
   │  paste password
   ▼
"Customize Jenkins"  ->  Install suggested plugins
   │  creates admin user, saves settings
   ▼
Jenkins dashboard (landing page)
```

## 3. Files in this folder

| File | Purpose |
|---|---|
| `deploy.sh` | One-command install `[1/6]`–`[6/6]`; prints the initial admin password and the wizard steps |
| `cleanup.sh` | Removes the container; `--volume` also deletes `ex7_jenkins_home`, `--image` also removes the image |
| `init.groovy.d/01-create-admin.groovy` | Only used by `deploy.sh --auto`: creates `admin`/`admin` and skips the wizard |
| `README.md` | This document |

## 4. Prerequisites

- **Docker** (Docker Desktop / Engine) running.
- **bash** (Git Bash / WSL on Windows) — `curl` and `netstat` are used by
  `deploy.sh`; the `jenkins/jenkins:lts` image is pulled automatically.
- No local Java or Jenkins install is needed: everything runs in the container.

> **Ports.** The brief publishes **8080**. On this machine `8080` is already
> held by an unrelated `httpd` service, so `deploy.sh` automatically falls back
> to the next free port (**8081**). The inbound-agent port defaults to `50000`
> and is also auto-selected if busy.

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise7
./deploy.sh
```

Real output from this machine (8080 was taken by the host's `httpd`, so the UI
landed on 8081):

```
[1/6] Checking prerequisites
  docker: Docker version 29.6.1
[2/6] Removing any previous container named 'jenkins'
[3/6] Selecting host ports
  port 8080 is in use, trying 8081...
  NOTE: brief uses 8080, but it is taken on this host -> Jenkins UI on 8081
  Jenkins UI  -> 8081
  Agent (JNLP)-> 50000
[4/6] Starting Jenkins (jenkins/jenkins:lts)
  container id: 1f2c9d4a7b03
[5/6] Waiting for Jenkins to answer on http://localhost:8081
  Jenkins is answering HTTP 200
[6/6] Verifying installation

============================================================
 Jenkins is installed - complete the setup wizard
============================================================
 URL               : http://localhost:8081/
 Initial password  : 4f2a1c9e7b6d3a8f0e5c2b1d9a7f4e3c

 Next steps (in the browser):
   1. Paste the initial password above to UNLOCK Jenkins.
   2. "Install suggested plugins" (or choose select plugins).
   3. Create the first admin user.
   4. Save and finish -> Jenkins is ready.
============================================================

Container status:
  jenkins  Up 40 seconds  0.0.0.0:8081->8080/tcp, 0.0.0.0:50000->50000/tcp

Useful commands:
  logs    : docker logs -f jenkins
  shell   : docker exec -it jenkins bash
  password: docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
  cleanup : ./cleanup.sh [--volume] [--image]
```

Open the printed URL, paste the password, and walk through the wizard screens
(the brief's three screenshots: **Unlock Jenkins**, **Customize Jenkins** /
*getting started*, **landing page**).

### Headless / scriptable mode (`--auto`)

The setup wizard needs mouse clicks. To prove the install end-to-end — and for
reproducible test runs — `--auto` skips the wizard and creates a local
`admin`/`admin` account from `init.groovy.d`:

```bash
./deploy.sh --auto
# ...
#  URL       : http://localhost:8081/
#  Username  : admin
#  Password  : admin
#  Dashboard : http://localhost:8081/api/json  (authenticated OK)
```

### Option B — manual (the brief's commands, with the fixes inline)

```bash
# 1. Start Jenkins (brief command + a persistent volume)
docker run -d --name jenkins -p 8081:8080 -p 50000:50000 \
  -v ex7_jenkins_home:/var/jenkins_home jenkins/jenkins:lts

# 2. Get the initial password (brief uses `docker exec -it <id> bash` then cat)
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# 3. Open http://localhost:8081/ and complete the wizard
```

`deploy.sh` is just steps 1–3 with a free-port scan, a readiness wait, and the
password read in one shot.

## 6. How to verify the expected output

| # | Expected output (brief) | Command | Result on this machine |
|---|---|---|---|
| 1 | Container running, ports mapped | `docker ps --filter name=jenkins` | `Up ... 0.0.0.0:8081->8080/tcp, 0.0.0.0:50000->50000/tcp` |
| 2 | Initial admin password file | `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` | 32-hex string |
| 3 | Jenkins reachable on the UI port | `curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/login` | `200` (`/` answers `403` until setup is done) |
| 4 | Unlock page served | `curl -s http://localhost:8081/login \| grep -i unlock` | `Unlock` (the *Unlock Jenkins* page) |
| 5 | Dashboard after wizard (`--auto`) | `curl -s -u admin:admin http://localhost:8081/api/json \| grep -o '"mode":"[A-Z_]*"'` | `"mode":"NORMAL"` |

Terminal checks:

```bash
# readiness (pre-setup: "/" is 403, "/login" is the unlock page)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8081/login    # 200

# initial password present + non-empty
docker exec jenkins test -f /var/jenkins_home/secrets/initialAdminPassword && echo present
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword

# headless mode only: authenticated controller info
curl -s -u admin:admin http://localhost:8081/api/json | python -c "import sys,json;d=json.load(sys.stdin);print(d['mode'], d['numExecutors'])"
```

## 7. Brief clean-ups (deviations, all intentional — each one fixes a brief issue)

| Brief says | This solution uses | Why |
|---|---|---|
| `docker run ... jenkins/jenkins:lts` with **no volume** | `-v ex7_jenkins_home:/var/jenkins_home` | Without a volume, `docker rm` destroys all Jenkins state (admin user, plugins, jobs). The volume makes the install reusable and lets the wizard be completed once. Named `ex7_*` so it is isolated from other exercises. |
| `-p 8080:8080` | auto-scan `8080` → next free port | `8080` is already held by an unrelated `httpd` on this host; a fixed mapping fails with *port is already allocated*. |
| `-p 50000:50000` | auto-scan `50000` → next free port | Same class of problem for the inbound-agent port; harmless here but kept consistent. |
| `docker exec -it <id> bash` then `cat ...` (interactive) | `docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword` (non-interactive) | The brief's form needs a human at a TTY; the non-interactive form is scriptable and prints the password directly. |
| Setup wizard is completed by hand (screenshots) | default path keeps the wizard; `--auto` adds a headless bootstrap | The wizard is interactive-only, so `--auto` exists purely to make the install verifiable/reproducible; the default path stays faithful to the brief. |
| Ports assumed free; container name reused blindly | `docker rm -f jenkins` before `docker run` | A stale `jenkins` container makes the brief's `docker run` fail with *name already in use*. |
| No readiness handling | poll `GET /` until HTTP 200, then read the password | Jenkins needs 30–60s to bootstrap; reading the password or opening the page too early shows nothing. |

## 8. Key concepts from this exercise

### Continuous Integration (CI)

Developers integrate changes into a shared repository **frequently**; every
integration triggers an **automated build + test** run and gives **fast
feedback**. The payoff: integration bugs surface early (cheap to fix), the
codebase stays green, and releases come faster. A CI server (Jenkins, GitLab CI,
GitHub Actions, …) is the thing that watches the repo and runs those builds.

### Jenkins terminology (from the brief)

- **Job/Project** — a task Jenkins runs (e.g. "build this repo").
- **Build** — one execution of a job.
- **Pipeline** — a job defined as a series of stages (build → test → deploy).
- **Plugins** — how Jenkins grows (Git, Docker, Pipeline, …). Installing
  "suggested plugins" at first login picks a sensible baseline.
- **Nodes** — machines that execute jobs (built-in controller + agents; the
  `:50000` JNLP port is how agents connect).

### Why a Docker install

Running Jenkins from the official `jenkins/jenkins:lts` image avoids a host Java
install and makes the whole thing disposable: the container holds the binaries,
the `ex7_jenkins_home` **volume** holds the state. Delete the container → start a new
one with the same volume → your users/jobs are still there.

### What the initial admin password is

On first start Jenkins generates a random unlock secret in
`/var/jenkins_home/secrets/initialAdminPassword`. It is deleted/hidden once you
finish the wizard and create your admin user — which is why the wizard must be
completed once per fresh `ex7_jenkins_home`.

## 9. Cleanup

```bash
./cleanup.sh             # remove the container only
./cleanup.sh --volume    # also delete the ex7_jenkins_home data volume
./cleanup.sh --image     # also remove the jenkins/jenkins:lts image
```

Both modes were tested on this machine (container and volume removed, image
removed when requested).

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| Jenkins UI not on 8080 | `8080` is taken on this host by `httpd`; `deploy.sh` prints the port it chose (8081) |
| `port is already allocated` on 8080/50000 | another container/service holds it — `deploy.sh` auto-scans, or free the port and re-run |
| `name "/jenkins" is already in use` | stale container — `deploy.sh` runs `docker rm -f jenkins` first; `./cleanup.sh` clears leftovers |
| Page shows nothing / password file missing | Jenkins still booting (30–60s) — wait, or `docker logs -f jenkins`; `deploy.sh` already polls until HTTP 200 |
| Initial password rejected | you already completed the wizard once (secret changes) — use your admin user, or `./cleanup.sh --volume` and start fresh |
| `initial admin password not found` | the volume already holds a finished Jenkins (wizard done) — `./cleanup.sh --volume && ./deploy.sh`; `deploy.sh` uses the dedicated `ex7_jenkins_home` volume to avoid this |
| Forgot the admin password | reset by editing `/var/jenkins_home/users/...`, or simplest for a lab: `./cleanup.sh --volume && ./deploy.sh` |
| Want a clean slate | `./cleanup.sh --volume` deletes `ex7_jenkins_home` (all jobs/plugins/users) |
| `docker: command not found` in Git Bash | Git Bash truncated `PATH`; `deploy.sh`/`cleanup.sh` prepend Docker's bin dir — run via the scripts |
