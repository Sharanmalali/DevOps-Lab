# Exercise 9 — Jenkins Multi-Stage Pipeline (Python/Flask)

**Goal:** push a tiny Flask app to GitHub, create a **Pipeline** job in Jenkins
that runs the brief's stages — **Build → Test → Deploy → Run Application →
Test Application** — and watch the console print `Ran 1 test … OK`,
`Hello, Jenkins Multi-Stage Pipeline!` and `Finished: SUCCESS`.

---

## 1. What the exercise asks

| Step | Requirement |
|---|---|
| 1 | Jenkins installed and running (Exercise 7), with the **Pipeline** plugin |
| 2 | Create the sample app: `app.py`, `requirements.txt` (`flask==2.1.2`), `test_app.py` (unittest) |
| 3 | Push the app to a GitHub repo (`devops-sample-code`) |
| 4 | Create a Jenkins **Pipeline** item, e.g. `Python-MultiStage-Pipeline` |
| 5 | Define a `Jenkinsfile` with stages **Build**, **Test**, **Deploy**, **Run Application**, **Test Application** and a `post` block |
| 6 | Configure the job as **Pipeline script from SCM** → Git → repo URL → `Jenkinsfile` |
| 7 | **Build Now** and observe the stages / console output |
| 8 | Fix the build errors (`python3`, `pip`, `flask` missing) by installing them **inside** the Jenkins container |

The brief is a UI walkthrough; this solution reproduces the entire flow
(repo → Job → build → verification) so it is reproducible and testable from one
command, while keeping the exact Jenkinsfile from the brief.

## 2. Solution overview

```
  GitHub (public)                      Docker Desktop daemon
 ┌──────────────────────────┐      ┌────────────────────────────────────────┐
 │ devops-sample-code       │      │  jenkins (jenkins/jenkins:lts)         │
 │  app.py                  │      │   :8080  controller (UI)               │
 │  test_app.py             │clone │   python3 + flask  (used by the stages)│
 │  requirements.txt        │─────►│   plugins: workflow-aggregator + git   │
 │  Jenkinsfile  ───────────────────┐                                      │
 └──────────────────────────┘      │  Job: Python-MultiStage-Pipeline        │
        ▲                          │   Pipeline script from SCM → Jenkinsfile│
        │  Contents API            │                                         │
 ┌──────┴───────────────┐          │  volume: ex9_jenkins_home               │
 │ deploy.sh            │  REST    └────────────────────────────────────────┘
 │  1 check prereqs     │──────────────►  createItem, /build, consoleText
 │  2 ensure repo+files │                  (crumb + cookie jar for CSRF)
 │  3–5 start Jenkins   │
 │  6 create job        │
 │  7–8 build + assert  │
 └──────────────────────┘
```

- **`deploy.sh`** publishes `app.py`, `test_app.py`, `requirements.txt` and
  `Jenkinsfile` to the public repo, builds the `ex9-jenkins` image, starts the
  controller, creates the job via `/createItem`, triggers a build and **asserts**
  the console output stage by stage.
- **`Jenkinsfile`** is the brief's pipeline, unchanged: it is the deliverable
  and the config the job runs.
- Everything runs in a throwaway container; the job and build history live in
  the `ex9_jenkins_home` volume.

### Pipeline lifecycle

```
POST /job/Python-MultiStage-Pipeline/build
        │
        ▼
 [Declarative: Checkout SCM]  git fetch + checkout origin/main  (Jenkinsfile,
        │                     app.py, test_app.py, requirements.txt)
        ▼
 (Build)            echo 'Creating virtual environment and installing dependencies...'
        ▼
 (Test)             python3 -m unittest discover -s .
        │              .  -->  Ran 1 test in 0.00s / OK
        ▼
 (Deploy)           mkdir -p $WORKSPACE/python-app-deploy ; cp app.py  ...
        ▼
 (Run Application)  nohup python3 app.py > app.log 2>&1 &  ; echo $! > app.pid
        ▼
 (Test Application) python3 test_app.py   -->  Ran 1 test / OK
        ▼
 (Declarative: Post Actions)  echo 'Pipeline completed successfully!'
Finished: SUCCESS
```

## 3. Files in this folder

| File | Purpose |
|---|---|
| `app.py` | The Flask app from the brief (`GET /` → `Hello, Jenkins Multi-Stage Pipeline!`) |
| `test_app.py` | The brief's unittest; the *Test* and *Test Application* stages run it |
| `requirements.txt` | The brief's pins (`flask==2.1.2`) — see the deviations table |
| `Jenkinsfile` | The brief's multi-stage declarative pipeline; pushed and run from SCM |
| `Dockerfile.jenkins` | `jenkins/jenkins:lts` + Pipeline & Git plugins + `python3`, `python3-pip`, `python3-flask` |
| `init.groovy.d/01-create-admin.groovy` | Headless bootstrap: `admin`/`admin`, no setup wizard |
| `job/Python-MultiStage-Pipeline-config.xml` | The exact job config (Pipeline script from SCM → `Jenkinsfile`) |
| `deploy.sh` | One-command flow `[1/8]`–`[8/8]` (repo → Jenkins → job → build → verify) |
| `cleanup.sh` | Removes the container; `--volume`, `--image`, `--github` options |
| `README.md` | This document |

## 4. Prerequisites

- **Docker** (Docker Desktop / Engine) running.
- **bash** (Git Bash / WSL on Windows) — `curl` and `netstat` are used by `deploy.sh`.
- **Jenkins basics** (Exercise 7) — the controller from Ex 7 is enough conceptually.
- **A GitHub token** in `GITHUB_TOKEN` **only when** the repo must be created or
  the app files pushed. A classic PAT with `repo` scope works. If the repo
  already exists publicly, no token is needed (Jenkins clones public repos
  anonymously).

> **Ports.** The brief uses `8080`; if it is taken, `deploy.sh` uses the next
> free port and prints it. Jenkins is on `8080` by default here.

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise9
GITHUB_TOKEN=<your-pat> ./deploy.sh
```

Real output from this machine:

```
[1/8] Checking prerequisites
  docker: Docker version 29.6.1
  GITHUB_TOKEN: set
[2/8] Ensuring GitHub sample repo 'devops-sample-code' + app files
  owner: Sharanmalali
  repo exists
  app.py already up to date
  test_app.py already up to date
  requirements.txt already up to date
  Jenkinsfile already up to date
  repo: https://github.com/Sharanmalali/devops-sample-code
[3/8] Preparing Jenkins (image ex9-jenkins)
  image built; UI -> 8080
[4/8] Starting Jenkins (headless admin/admin)
  container: 4a1c9d0e8f21
[5/8] Waiting for Jenkins on http://localhost:8080
[6/8] Creating Pipeline job 'Python-MultiStage-Pipeline' (script from SCM)
  job created: http://localhost:8080/job/Python-MultiStage-Pipeline
[7/8] Triggering build and waiting for the result
  trigger HTTP 201
[8/8] Verifying the multi-stage console output
  build #1 finished: SUCCESS
  --- console output (tail) ---
  | [Pipeline] End of Pipeline
  | Finished: SUCCESS
  stage ok: (Build)
  stage ok: (Test)
  stage ok: (Deploy)
  stage ok: (Run Application)
  stage ok: (Test Application)
  unit test: 1 test passed
  app output: Hello, Jenkins Multi-Stage Pipeline!

============================================================
 Exercise 9 complete
============================================================
 Repo     : https://github.com/Sharanmalali/devops-sample-code
 Job      : http://localhost:8080/job/Python-MultiStage-Pipeline   (Pipeline, script from SCM)
 Build    : #1 -> SUCCESS
 Stages   : Build -> Test -> Deploy -> Run Application -> Test Application
 Console  : "Ran 1 test ... OK" then "Finished: SUCCESS"

 Open the job, click a build number -> Console Output (or "Pipeline Steps")
 to watch each stage live.
============================================================
```

The parts the brief's *Expected Output* lists, from
`http://localhost:8080/job/Python-MultiStage-Pipeline/1/consoleText`:

```
[Pipeline] { (Build)
Creating virtual environment and installing dependencies...
[Pipeline] // stage
[Pipeline] { (Test)
Running tests...
+ python3 -m unittest discover -s .
.
----------------------------------------------------------------------
Ran 1 test in 0.002s

OK
Hello, Jenkins Multi-Stage Pipeline!
```

Then open `http://localhost:8080/job/Python-MultiStage-Pipeline`, click a build
number → **Console Output** to see every stage live.

### Option B — manual (the brief's steps, with the fixes inline)

```bash
# 1. Create the app (files are already in this folder)
mkdir python-flask-app && cd python-flask-app
cp ../Solutions/Exercise9/{app.py,test_app.py,requirements.txt} .
# ...or type them out exactly as in the brief (Steps 2)

# 2. Push it (brief uses the GitHub UI + a PAT)
git init && git add . && git commit -m "Initial commit"
git remote add origin https://github.com/<you>/devops-sample-code.git
git push -u origin main

# 3. Start Jenkins (Exercise 7) WITH the Pipeline + Git plugins and python3,
#    i.e. the image this folder builds:
docker build -t ex9-jenkins .
docker run -d --name jenkins -p 8080:8080 \
  -v ex9_jenkins_home:/var/jenkins_home .

# 4. Jenkins UI → New Item -> "Python-MultiStage-Pipeline" -> Pipeline
#    Pipeline → "Pipeline script from SCM" → Git -> your repo URL,
#    Script Path = Jenkinsfile  (this is what job/*.xml stores)
# 5. Save -> Build Now -> each stage turns green
```

## 5.b Step 8 — the build errors, and why they happen

On a stock `jenkins/jenkins:lts`, *Test* fails almost immediately with:

```
+ python3 -m unittest discover -s .
/var/jenkins_home/workspace/.../script.sh: python3: not found
```

The stages run **on the controller itself** (`agent any`), and the controller
image contains only a JRE — no Python. The brief's Step 8 remedy is:

```bash
docker ps -a                       # find the Jenkins container id
docker exec -it -u root <id> bash  # a root shell inside the controller
apt-get update
apt install python3
apt install pip
apt install python3-flask
python3 -m unittest discover -s .
```

That fixes the *current* container but is lost on every recreate/upgrade. This
solution applies the same packages in `Dockerfile.jenkins`, so the fix is
durable — the interactive detour is not needed:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-flask python3-venv
```

## 6. How to verify the expected output

| Brief's expected outcome | Check | Expected |
|---|---|---|
| App on GitHub | open the repo URL | `app.py`, `test_app.py`, `requirements.txt`, `Jenkinsfile` on `main` |
| Job is a pipeline from SCM | `docker exec jenkins cat /var/jenkins_home/jobs/Python-MultiStage-Pipeline/config.xml` | `<flow-definition>` with `<scriptPath>Jenkinsfile</scriptPath>` |
| Build succeeded | `curl -s -u admin:admin "localhost:8080/job/Python-MultiStage-Pipeline/lastBuild/api/json?tree=number,result"` | `"result":"SUCCESS"` |
| All 5 stages ran | open the build's **Pipeline Steps** / console | `(Build) (Test) (Deploy) (Run Application) (Test Application)` |
| Test stage passed | console | `Ran 1 test in …` + `OK` |
| App runs | console of *Test Application* | `Hello, Jenkins Multi-Stage Pipeline!` |
| Post-success block | console tail | `Pipeline completed successfully!` / `Finished: SUCCESS` |

Terminal checks:

```bash
# build result
curl -s -u admin:admin "http://localhost:8080/job/Python-MultiStage-Pipeline/lastBuild/api/json?tree=number,result"

# the stage lines that matter
curl -s -u admin:admin "http://localhost:8080/job/Python-MultiStage-Pipeline/lastBuild/consoleText" \
  | grep -E '\((Build|Test|Deploy|Run Application|Test Application)\)|Ran 1 test|^OK|Hello, Jenkins Multi-Stage Pipeline!|Finished: SUCCESS'
```

## 7. Brief clean-ups (deviations, all intentional)

| Brief says | This solution uses | Why |
|---|---|---|
| `app.py` as given | identical | the pipeline's output must match the brief |
| `requirements.txt` = `flask==2.1.2` | kept in the repo (the brief's deliverable); the image provides distro `python3-flask` | nothing in the brief's `Jenkinsfile` runs `pip install`, so the stages use the interpreter's Flask; the distro package is the hermetic way to give `python3` a Flask |
| Configure the job through the **UI** | post `job/Python-MultiStage-Pipeline-config.xml` to `/createItem` | same config Jenkins saves; keeps the job definition reviewable |
| Stock `jenkins/jenkins:lts` | `Dockerfile.jenkins` adds **workflow-aggregator** (pipeline) + **git** plugins | the stock image ships **no** plugins; a "Pipeline script from SCM" job cannot be created without them |
| (default "lightweight checkout") | `<lightweight>false</lightweight>` in the job config | a lightweight checkout fetches *only* `Jenkinsfile`; the stages then hit `${WORKSPACE}/app.py` with an empty workspace and *Test* fails |
| Step 8: `docker exec … apt install python3 pip flask` | same packages in `Dockerfile.jenkins` | the brief's fix is manual and lost on recreate; baking it in keeps the pipeline reproducible |
| Create repo & push with git/PAT | GitHub Contents API (`GITHUB_TOKEN`), idempotent upsert | fully scripted, no empty re-push commits |
| Port 8080 | picked automatically (8080 → next free) | avoids `port is already allocated` on a busy host |
| Store state in the container | named volume `ex9_jenkins_home` | keeps jobs/builds across restarts, namespaced away from Ex 7/8 |
| Trigger build from UI | `POST /job/…/build` with a `crumb` + cookie jar | reproducible trigger that satisfies Jenkins' CSRF protection |

## 8. Key concepts from this exercise

### Declarative Pipeline vs Freestyle
Exercise 8's job is a Freestyle project — pure UI/build steps. Here the job is a
**Pipeline** described by a versioned `Jenkinsfile` (`pipeline { agent; stages; }`),
so the build definition itself lives in Git and is reviewed like code.

### `agent any` and where stages run
"`agent any`" means the stages execute on the controller (there are no agents in
a lab container). That is exactly why `python3` must exist **inside** the Jenkins
image — the brief's whole Step 8 exists for this reason.

### Stages, steps and `sh`
Each `stage` groups a logical phase (Build/Test/…). Inside `steps`, `sh '…'` runs
the command through `/bin/sh -xe`, which echoes commands (`+ python3 -m unittest`)
into the console — that echo is what the brief's expected console shows.

### `${WORKSPACE}`
The build's checkout and scratch directory
(`/var/jenkins_home/workspace/Python-MultiStage-Pipeline`). The *Deploy* stage
copies the app into `${WORKSPACE}/python-app-deploy`, the brief's "mock
deployment directory".

### Why `Jenkinsfile` from SCM
"Pipeline script from SCM" makes each build read `Jenkinsfile` from the
repository's `main` branch. Change the file, push, build — no Jenkins UI edit.
(`<scriptPath>Jenkinsfile</scriptPath>` in the rendered config is that setting.)

### CSRF crumbs
Jenkins rejects state-changing REST calls without a **CSRF crumb**; `deploy.sh`
fetches one from `/crumbIssuer` with a cookie jar and sends it on every POST.

## 9. Cleanup

```bash
./cleanup.sh             # remove the Jenkins container
./cleanup.sh --volume    # also delete ex9_jenkins_home (job + build history)
./cleanup.sh --image     # also remove the ex9-jenkins image
./cleanup.sh --github    # also DELETE the devops-sample-code repo (needs GITHUB_TOKEN; DESTRUCTIVE)
```

By default the **GitHub repo is kept** — it is a deliverable of the brief.

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| *Test* stage: `python3: command not found` | the image lacks Python — rebuild from `Dockerfile.jenkins` (or apply the brief's Step 8 apt install) |
| Job can't be created: HTTP 400/405 | missing plugin (`workflow-aggregator`/`git`) — rebuild the image; the stock image has none |
| SCM: `Couldn't find any revision to build` | the repo has no `main` branch yet — re-run `deploy.sh` (it pushes the app on `main`) |
| `ERROR: repo … missing and GITHUB_TOKEN not set` | export a token (`GITHUB_TOKEN=<pat> ./deploy.sh`) or create the repo first |
| Jenkins UI not on 8080 | 8080 was busy; `deploy.sh` prints the port it chose |
| `name "/jenkins" is already in use` | stale container — `deploy.sh` removes it first; `./cleanup.sh` clears leftovers |
| `base64: invalid option` on script start | macOS lacks `--wrap`; `deploy.sh` uses plain `base64 < file` |
| The app ends up still running after the build | it's a `nohup … &` background process, exactly per the brief; the container is throw-away |
