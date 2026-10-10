# Exercise 8 — Creating a "Hello World" Jenkins Job

**Goal:** publish `hello-world.sh` (which prints `Hello, Jenkins!`) to a public
GitHub repo, then create a **Freestyle** Jenkins job that checks the repo out
with **Git SCM** and runs `sh hello-world.sh` as a build step — and watch a
build print `Hello, Jenkins!` followed by `Finished: SUCCESS`.

---

## 1. What the exercise asks

| Step | Requirement |
|---|---|
| 1 | Create a public GitHub repo **`devops-sample-code`** and add **`hello-world.sh`**: `#!/bin/bash` + `echo "Hello, Jenkins!"` |
| 1b | Create a **personal access token** to push code |
| 2–6 | (git) `chmod +x`, init, commit, `git remote add origin`, `git push -u origin main` |
| Pre-req | Jenkins running (Exercise 7) |
| J1 | Jenkins → **New Item** → name `HelloWorld`, **Freestyle project** |
| J2 | **Source Code Management** → Git, repository URL = the sample repo |
| J3 | **Build** → Add build step → **Execute shell** → `sh hello-world.sh` |
| J4 | Save → **Build Now** |
| J5 | **Console Output** shows `Hello, Jenkins!` then `Finished: SUCCESS` |

The brief is a UI walkthrough; this solution reproduces the whole flow
(repo + job + build + verification) so it is reproducible and testable.

## 2. Solution overview

```
  GitHub (public)                     Docker Desktop daemon
 ┌──────────────────────────┐     ┌──────────────────────────────────────┐
 │ devops-sample-code       │     │  jenkins (ex8-jenkins image)          │
 │   hello-world.sh         │◄────┤   Freestyle job "HelloWorld"          │
 │     echo "Hello, Jenkins!"│ git │    SCM: Git -> clone repo             │
 └──────────────────────────┘ clone│    Build: sh hello-world.sh           │
        ▲                          │   volume: ex8_jenkins_home            │
        │ PUT contents (API)       │   UI: :8081 -> :8080                  │
 ┌──────┴───────────┐              └──────────────────────────────────────┘
 │ deploy.sh        │  createItem (config.xml) + /build + console, all via REST
 └──────────────────┘
```

- **`deploy.sh`** ensures the GitHub repo + script exist (via the GitHub
  Contents API), builds/starts a headless Jenkins, creates the Freestyle job
  from `job/HelloWorld-config.xml` (`/createItem`), triggers a build
  (`/build`), then reads `lastBuild` + `consoleText` and asserts the expected
  output.
- The repo is **public**, exactly as the brief requires, so Jenkins clones it
  over HTTPS with **no credentials**.
- Everything runs in a throwaway container; the job and its build history live
  in the `ex8_jenkins_home` volume.

### Build lifecycle

```
POST /job/HelloWorld/build
        │  queue
        ▼
executor picks it up
   → Git SCM: git fetch + checkout origin/main into
     /var/jenkins_home/workspace/HelloWorld
   → Build step:  sh hello-world.sh
        │
        ▼
console:  + sh hello-world.sh
          Hello, Jenkins!
          Finished: SUCCESS
```

## 3. Files in this folder

| File | Purpose |
|---|---|
| `hello-world.sh` | The script from the brief (`echo "Hello, Jenkins!"`); pushed to the repo |
| `Dockerfile.jenkins` | `jenkins/jenkins:lts` + the **git** plugin (stock image ships no plugins) |
| `init.groovy.d/01-create-admin.groovy` | Headless bootstrap: `admin`/`admin`, no setup wizard |
| `job/HelloWorld-config.xml` | The exact Freestyle job configuration (description, Git SCM, shell step) |
| `deploy.sh` | One-command flow `[1/7]`–`[7/7]` (repo → Jenkins → job → build → verify) |
| `cleanup.sh` | Removes the container; `--volume`, `--image`, and `--github` options |
| `README.md` | This document |

## 4. Prerequisites

- **Docker** (Docker Desktop / Engine) running.
- **bash** (Git Bash / WSL on Windows) — `curl` and `netstat` are used by
  `deploy.sh`.
- **Jenkins basics** (Exercise 7) — in particular the "Freestyle project" and
  "Execute shell" concepts.
- **A GitHub token** in `GITHUB_TOKEN` **only when** the repo must be created or
  the script pushed. A classic PAT with `repo` scope works out of the box. If
  the repo already exists publicly, no token is needed (Jenkins clones public
  repos anonymously).

> **Ports.** The brief uses `8080`; it is already held by an unrelated `httpd`
> on this machine, so `deploy.sh` automatically uses the next free port
> (**8081**).

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise8
GITHUB_TOKEN=<your-pat> ./deploy.sh
```

Real output from this machine (UI on 8081 because 8080 was taken):

```
[1/7] Checking prerequisites
  docker: Docker version 29.6.1
  GITHUB_TOKEN: set
[2/7] Ensuring GitHub sample repo 'devops-sample-code' + hello-world.sh
  owner: shreyassridhar44
  repo exists
  updating hello-world.sh
  script: https://github.com/shreyassridhar44/devops-sample-code/blob/main/hello-world.sh
[3/7] Preparing Jenkins (image ex8-jenkins)
  port 8080 is in use, trying 8081...
  NOTE: brief uses 8080, but it is taken on this host -> Jenkins UI on 8081
  image built; UI -> 8081
[4/7] Starting Jenkins (headless admin/admin)
  container: bc6f936b6816
[5/7] Waiting for Jenkins on http://localhost:8081
[6/7] Creating Freestyle job 'HelloWorld' (Git SCM + shell)
  job created: http://localhost:8081/job/HelloWorld
[7/7] Triggering build and waiting for the result
  trigger HTTP 201
  build #1 finished: SUCCESS
  --- console output (tail) ---
  | Commit message: "Add hello-world.sh"
  | First time build. Skipping changelog.
  | [HelloWorld] $ /bin/sh -xe /tmp/jenkins18326201100859575947.sh
  | + sh hello-world.sh
  | Hello, Jenkins!
  | Finished: SUCCESS

============================================================
 Exercise 8 complete
============================================================
 Repo    : https://github.com/shreyassridhar44/devops-sample-code
 Script  : echo "Hello, Jenkins!"
 Job     : http://localhost:8081/job/HelloWorld   (Freestyle, Git SCM)
 Build   : #1 -> SUCCESS
 Console : "Hello, Jenkins!" then "Finished: SUCCESS"

 Open the job, click a build number -> Console Output to see it live.
============================================================

Container status:
jenkins  Up 33 seconds  0.0.0.0:8081->8080/tcp, [::]:8081->8080/tcp

Useful commands:
  logs    : docker logs -f jenkins
  cleanup : ./cleanup.sh [--volume] [--image] [--github]
```

Then open `http://localhost:8081/job/HelloWorld`, click a build number →
**Console Output** to see the live log.

### Option B — manual (the brief's steps, with the fixes inline)

```bash
# 1. Create the repo + script (brief uses the GitHub UI + git/PAT)
#    create repo "devops-sample-code" (public), then:
printf '#!/bin/bash\necho "Hello, Jenkins!"\n' > hello-world.sh
chmod +x hello-world.sh
git init && git add hello-world.sh && git commit -m "Add hello-world.sh"
git remote add origin https://github.com/<you>/devops-sample-code.git
git push -u origin main                       # username + PAT when prompted

# 2. Start Jenkins (Exercise 7) - here with the git plugin baked in
docker build -t ex8-jenkins -f Dockerfile.jenkins .
docker run -d --name jenkins -p 8081:8080 \
  -v ex8_jenkins_home:/var/jenkins_home \
  -v "$PWD/init.groovy.d:/var/jenkins_home/init.groovy.d:ro" \
  -e JAVA_OPTS=-Djenkins.install.runSetupWizard=false ex8-jenkins

# 3. Then in the UI: New Item -> "HelloWorld" -> Freestyle project
#    SCM: Git -> https://github.com/<you>/devops-sample-code.git
#    Build: Execute shell -> sh hello-world.sh
#    Save -> Build Now -> build #1 -> Console Output
```

`deploy.sh` performs step 3 through Jenkins' REST API (`/createItem`), which is
the same `config.xml` the UI saves — see `job/HelloWorld-config.xml`.

## 6. How to verify the expected output

| # | Expected output (brief) | Command | Result on this machine |
|---|---|---|---|
| 1 | Script on GitHub | open the repo URL | `hello-world.sh` (2 lines) on branch `main` |
| 2 | Jenkins job configured | `docker exec jenkins cat /var/jenkins_home/jobs/HelloWorld/config.xml` | Git SCM + `sh hello-world.sh` |
| 3 | Build succeeds | `curl -s -u admin:admin localhost:8081/job/HelloWorld/lastBuild/api/json?tree=number,result,building` | `{"...","building":false,"number":1,"result":"SUCCESS"}` |
| 4 | Console output | `curl -s -u admin:admin localhost:8081/job/HelloWorld/lastBuild/consoleText` | ends with `Hello, Jenkins!` / `Finished: SUCCESS` |

Terminal checks:

```bash
# build result
curl -s -u admin:admin "http://localhost:8081/job/HelloWorld/lastBuild/api/json?tree=number,result" 
# {"_class":"...FreeStyleBuild","number":1,"result":"SUCCESS"}

# console: the two lines that matter
curl -s -u admin:admin "http://localhost:8081/job/HelloWorld/lastBuild/consoleText" | tail -3
# + sh hello-world.sh
# Hello, Jenkins!
# Finished: SUCCESS

# the script GitHub serves (via the API)
curl -s https://raw.githubusercontent.com/shreyassridhar44/devops-sample-code/main/hello-world.sh
# #!/bin/bash
# echo "Hello, Jenkins!"
```

## 7. Brief clean-ups (deviations, all intentional — each one fixes a brief gap)

| Brief says | This solution uses | Why |
|---|---|---|
| Create the repo/script by hand, add a PAT, `git push` interactively | GitHub Contents API (`GITHUB_TOKEN`) | Makes the flow scriptable/repeatable; the token is read from the environment and never written to disk. Jenkins clones the **public** repo anonymously, so no credentials are stored in Jenkins. |
| `-p 8080:8080` | auto-scan `8080` → next free port (this host: **8081**) | `8080` is held by an unrelated `httpd` on this machine, so a fixed mapping fails with *port already allocated*. |
| Stock `jenkins/jenkins:lts` | `Dockerfile.jenkins` adds the **git** plugin | The stock image ships **zero** plugins; selecting *Git* under Source Code Management needs the `git` plugin, else the job can't clone. |
| Complete the setup wizard + log in by hand | `-Djenkins.install.runSetupWizard=false` + `init.groovy.d` creates `admin`/`admin` | Jenkins' API-driven job creation needs an authenticated session; the wizard is interactive-only. |
| Configure the job through the UI | post `job/HelloWorld-config.xml` to `/createItem` | Same config Jenkins saves; keeps the job definition as a reviewable file. |
| No container volume | `-v ex8_jenkins_home:/var/jenkins_home` (namespaced `ex8_*`) | Keeps the job/build state across container restarts and isolated from other exercises' Jenkins. |
| Trigger the build from the dashboard | `POST /job/HelloWorld/build` (+ CSRF crumb from `/crumbIssuer`) | Reproducible trigger; the crumb + cookie jar satisfy Jenkins' CSRF protection (no global disabling). |
| (brief links an external `Jenkins-CI-Automation.md` for the pre-req) | assumes **Exercise 7** in this repo | Self-contained; the Jenkins install/port details live in `Solutions/Exercise7`. |

## 8. Key concepts from this exercise

### Freestyle job vs Pipeline
A **Freestyle** project is Jenkins' classic UI-configured job: a set of build
steps, no script. (Exercise 9 uses a **Pipeline** instead.) Both ultimately run
commands in a workspace on an executor node.

### Source Code Management (Git SCM)
The `git` plugin adds a *Source Code Management → Git* section. On each build
Jenkins does `git fetch` + `git checkout` of the configured branch into
`/var/jenkins_home/workspace/<job>`, so the build step sees the repo's files
(`hello-world.sh` is at the repo root, hence `sh hello-world.sh` works directly).

### Build steps & the shell
"Execute shell" runs the command under `/bin/sh -xe`. The `-x` echoes each
command (`+ sh hello-world.sh`) — which is why the console shows both the
command and its output.

### Console output = the build's story
`Started by user …` → SCM checkout → build steps → `Finished: SUCCESS`. This is
the brief's Expected Output, and it is exactly what `deploy.sh` asserts.

### CSRF crumbs
Jenkins rejects state-changing REST calls without a **CSRF crumb**. `deploy.sh`
fetches one from `/crumbIssuer` with a cookie jar and sends it back on every
POST — the standard way to script Jenkins without disabling CSRF protection.

## 9. Cleanup

```bash
./cleanup.sh             # remove the Jenkins container
./cleanup.sh --volume    # also delete ex8_jenkins_home (job + build history)
./cleanup.sh --image     # also remove the ex8-jenkins image
./cleanup.sh --github    # also DELETE the devops-sample-code repo (DESTRUCTIVE; needs GITHUB_TOKEN)
```

By default the **GitHub repo is kept** — the brief asks for it to exist as a
deliverable. Container/volume/image removal was tested on this machine.

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `ERROR: repo ... missing and GITHUB_TOKEN not set` | export a token (`GITHUB_TOKEN=<pat> ./deploy.sh`) or create the repo first |
| Job fails at SCM: `Couldn't find any revision to build` | the repo has no `main` branch yet — re-run `deploy.sh` (it creates `hello-world.sh` on `main`) |
| `404 /job/HelloWorld` after createItem | the build was queued; `deploy.sh` polls `lastBuild`, give it a few seconds |
| Jenkins UI not on 8080 | `8080` is taken on this host; `deploy.sh` prints the port it chose (8081) |
| `curl: option --data-binary: error reading a file` | a Git Bash `/tmp` path was passed to the Windows `curl.exe`; `deploy.sh` uses relative temp files for exactly this reason |
| Script aborts right after "Triggering build" | `set -o pipefail` + a no-match `grep`; `deploy.sh` guards those pipelines — update to the shipped version |
| `name "/jenkins" is already in use` | stale container — `deploy.sh` runs `docker rm -f jenkins` first; `./cleanup.sh` clears leftovers |
| `docker: command not found` in Git Bash | Git Bash truncated `PATH`; both scripts prepend Docker's bin dir |
