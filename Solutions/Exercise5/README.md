# Exercise 5 — Docker Security with AppArmor and Python

**Goal:** Secure a containerized Flask app with an **AppArmor profile** — deny
reads of `/etc/**`, deny writes to `/var/**`, deny binary execution under
`/bin` and `/usr/bin` — then apply it with the **Docker SDK for Python** and
**prove the denials** from inside the container.

---

## 1. What the exercise asks

**Scenario:** a Python Flask web app runs in a Docker container; restrict
access to sensitive directories and prevent unauthorized actions (executing
binaries, reading restricted files).

| Task | Requirement |
|---|---|
| 1 | Write a basic Flask app (`app.py`) |
| 2 | Containerize it (`Dockerfile`), build image `flask-apparmor` |
| 3 | Create `my-apparmor-profile`, install it to `/etc/apparmor.d/`, load it with `apparmor_parser -r`, run the container with `--security-opt="apparmor=my-apparmor-profile"` |
| 4 | Write `apply_apparmor.py` — Docker SDK: build the image, run the container with the profile, verify via `HostConfig.SecurityOpt`, stop it |
| 5 | Write `test_restricted_actions.py` — Docker SDK: run the container with the profile, try `cat /etc/passwd` (expect exit **1**) and `/bin/bash` (expect exit **126**), stop it |

Plus 5 questions (answered in section 8).

## 2. Solution overview

```
 HOST (your machine)                                  kernel-side (Linux only)
 ┌──────────────────────────────┐                 ┌────────────────────────────┐
 │ apply_apparmor.py            │   docker run    │ AppArmor profile           │
 │   images.build(flask-apparmor│ ──────────────► │  my-apparmor-profile       │
 │   containers.run(            │  security_opt=  │   deny /etc/** r           │
 │     security_opt=[           │  apparmor=...   │   deny /var/** rw          │
 │       "apparmor=my-apparmor- │                 │   deny /bin/** rmx         │
 │        profile"])            │   exec_run(...) │   deny /usr/bin/** rmx     │
 │ test_restricted_actions.py   │ ──────────────► │   network inet stream,     │
 │   cat /etc/passwd  → exit 1  │                 │   capability net_bind_…,   │
 │   /bin/bash        → exit 126│                 │   deny capability sys_admin│
 └──────────────────────────────┘                 │   /** rwklmix,  (catch-all)│
                                                  └────────────────────────────┘
```

- The profile is a **default-deny allow list**: anything without a matching
  rule is refused by the kernel. That is why the catch-all `/** rwklmix,`
  comes first and the exercise's restrictions are carved out with `deny`
  rules (deny beats allow).
- The Docker SDK only **requests** the profile
  (`HostConfig.SecurityOpt = ["apparmor=my-apparmor-profile"]`); **enforcement
  is kernel work** and only happens where AppArmor is active.

### Platform notes (read this — where enforcement can and cannot happen)

This lab was developed and tested on **Docker Desktop for Windows over
WSL2**, a host where the profile **cannot be enforced** — and the solution
reports that honestly instead of pretending. Probe evidence from this machine:

| Probe | Result |
|---|---|
| `docker info --format '{{json .SecurityOptions}}'` | `["name=seccomp,profile=builtin","name=cgroupns"]` — **no `name=apparmor`** |
| WSL2 kernel `/sys/module/apparmor/parameters/enabled` | `N` |
| `/proc/cmdline` / `/sys/kernel/security/lsm` | no `apparmor` in either (`capability,landlock,yama,safesetid,selinux`) |
| Docker Desktop VM securityfs | no `apparmor` directory |
| Ubuntu WSL distro's `apparmor_parser` | present — profile **syntax is validated** with it (`-Q` skips the kernel load) |

What works on every platform (and is exercised by `deploy.sh`):

1. **Profile syntax validation** — `apparmor_parser -Q my-apparmor-profile`
   (exit 0; the "Cache read/write disabled" line is an informational warning
   on kernels without AppArmor, not an error).
2. **Profile attachment** — `--security-opt apparmor=…` is accepted by any
   daemon; `docker inspect` shows it in `HostConfig.SecurityOpt`.
3. **Both Docker SDK scripts run end-to-end** with explicit `[NOTICE]` lines
   stating the profile is attached but not enforced, and honest per-command
   results (`Exit Code 0` instead of the brief's `1`/`126`).

What needs an **enforcing Linux host** (Ubuntu/Debian with AppArmor): the
kernel load (`apparmor_parser -r`) and real denials. Section 5, Option B
has the exact commands; `deploy.sh` performs them automatically on such a
host (it detects the daemon capability and only loads then).

> Note: this daemon *does* filter syscalls — `name=seccomp,profile=builtin`
> in the probe output — so container sandboxing here is seccomp-based,
> not AppArmor-based.

### Brief clean-ups (deviations, all intentional — each one fixes a brief bug)

| Brief says | This solution uses | Why |
|---|---|---|
| Profile block headed `/usr/bin/python3 { … }` (no `profile` keyword) | named `profile my-apparmor-profile { … }` | `--security-opt apparmor=my-apparmor-profile` resolves a profile **by name**. The brief's path-style header registers under the literal name `/usr/bin/python3` — which doesn't even exist in `python:3.8-slim` (the interpreter is `/usr/local/bin/python`) — so on an enforcing host the container would fail to start with *profile not found*. |
| Deny-only rules (`deny /etc/** r`, …) | catch-all `/** rwklmix,` **plus** the deny carve-outs | AppArmor **default-denies** anything with no matching rule. With the brief's profile, Python can't read its own standard library (`/usr/local/**`), `/proc`, `/sys`, `/dev`… the container dies at startup on an enforcing host. |
| `deny /bin/** rmix` | `deny /bin/** rmx` (allow side: `rwklmix`) | Reproduced against Ubuntu's `apparmor_parser`: `i` is **not a valid file-mode letter** (`syntax error, unexpected TOK_ID`); bare `x` is invalid in *allow* rules (needs an `ix`/`px`/`ux` qualifier) but **must be bare in deny rules** (`in deny rules 'x' must not be preceded by exec qualifier`). The validated letters are `r w k l m` + `ix`. |
| Task 4/5 scripts print only 2 lines each, but the brief's *expected output* shows `Building image from Dockerfile...`, `Running container...`, `Container started: …`, `Inspecting container…`, `Stopping the container...`, `Container stopped` | every banner line from the expected output is printed | The brief's code and its own expected output disagree; the scripts match the expected output. |
| Scripts `stop()` the container but never remove it | stops it (brief-faithful), and each script removes **stale running** copies of `flask-apparmor` before starting | An interrupted run keeps port 5000 bound; leftovers would break the next run. `./cleanup.sh` removes everything afterwards. |
| Expected output assumes `Exit Code 1` / `126` unconditionally | those codes only on an **enforcing** host; here you get `Exit Code 0` + `[NOTICE]` lines explaining why | Enforcement is a kernel feature this host lacks (platform notes above). Printing the brief's codes without enforcement would be a lie; the verdict logic checks the daemon capability first. |
| `/bin/bash` exec shown as exit `126` | same `126` expected on enforcing hosts; on this host bash exits `0` immediately (no tty/stdin → EOF) | Platform difference, called out by the script itself. |
| `capability net_bind_service` commented "to bind port 5000" | kept as-is (it's an *allow* — harmless) | Port 5000 is unprivileged, so the rule is a no-op; kept for brief fidelity. |

## 3. Files in this folder

| File | Purpose |
|---|---|
| `app.py` | Brief's Flask app (Task 1) — `GET /` greeting on port **5000** |
| `Dockerfile` | Brief's Dockerfile (Task 2) — `python:3.8-slim` + Flask, `CMD ["python", "app.py"]` |
| `.dockerignore` | Keeps README/scripts/profile out of the build context (≈656 B, like the brief's `3.072kB` sample) |
| `my-apparmor-profile` | The AppArmor profile (Task 3), syntax-validated; see clean-ups for the fixes over the brief |
| `apply_apparmor.py` | Task 4 — Docker SDK: build → run with `security_opt` → verify via `HostConfig.SecurityOpt` → stop |
| `test_restricted_actions.py` | Task 5 — Docker SDK: run with the profile → `cat /etc/passwd` → `/bin/bash` → verdict per daemon capability → stop |
| `deploy.sh` | One-command flow: prereqs + capability probe (1/6) → build (2/6) → profile syntax check + kernel load when possible (3/6) → Task 4 (4/6) → Task 5 (5/6) → summary (6/6) |
| `cleanup.sh` | Removes `flask-apparmor` containers; `--image` also removes the image |
| `README.md` | This document |

## 4. Prerequisites

- **Docker** (Docker Desktop / Docker Engine running).
- **Python 3** with the Docker SDK — `deploy.sh` installs it automatically
  (`pip install docker`) if missing; the brief's Task 4 instructions are the
  same.
- `bash` for the scripts (Git Bash / WSL on Windows).
- **For profile syntax validation:** any `apparmor_parser`
  (`sudo apt-get install apparmor-utils`, the brief's pre-requisite) — the
  script also falls back to the **Ubuntu WSL distro's** parser on Windows.
- **For actual enforcement** (exit 1/126): a Linux host with AppArmor active
  (`cat /sys/module/apparmor/parameters/enabled` → `Y`).

## 5. How to use the code

### Option A — automated (recommended)

```bash
cd Solutions/Exercise5
./deploy.sh
```

Real output from this machine (Docker Desktop/WSL2 — **non-enforcing**;
`[2/6]` build output and the `/etc/passwd` listing trimmed):

```
==> [1/6] Checking prerequisites...
    Docker SDK for Python: 7.1.0
    [NOTICE] Daemon AppArmor support: NO (["name=seccomp,profile=builtin","name=cgroupns"]).
    [NOTICE] The profile will be validated, attached and verified,
             but this host cannot enforce it (see README).
==> [2/6] Task 2: Building image flask-apparmor...
#4 [1/4] FROM docker.io/library/python:3.8-slim@sha256:1d52838af602...
#7 [3/4] COPY . /app
#7 CACHED
#8 [4/4] RUN pip install flask
#8 CACHED
#9 DONE 2.9s
flask-apparmor:latest  208MB
==> [3/6] Task 3: Validating AppArmor profile syntax...
    env MSYS2_ARG_CONV_EXCL=* wsl -d Ubuntu -u root -- apparmor_parser -Q /mnt/c/Users/.../Exercise5/my-apparmor-profile
    Profile syntax OK.
    [NOTICE] Kernel load skipped - this daemon does not enforce
             AppArmor, so there is nothing to load into.
==> [4/6] Task 4: Running apply_apparmor.py (Docker SDK)...
[NOTICE] This Docker daemon reports NO AppArmor support (name=seccomp,profile=builtin, name=cgroupns).
[NOTICE] The profile will still be attached to the container config (verifiable via inspect), but it will NOT be enforced.
Building image from Dockerfile...
[INFO] Step 1/6 : FROM python:3.8-slim
...
[INFO] Successfully built bfbad6e6c3e5
[INFO] Successfully tagged flask-apparmor:latest
Running container with AppArmor profile...
Container started: 1c3ec90e1a73
Inspecting container to verify the AppArmor profile...
AppArmor profile applied: ['apparmor=my-apparmor-profile']
Stopping the container...
[NOTICE] Remember: 'applied' above means attached to the container config only - this daemon does not enforce it.
==> [5/6] Task 5: Running test_restricted_actions.py...
[NOTICE] This Docker daemon has NO AppArmor support - the profile is attached but cannot block anything here.
[NOTICE] Expected results below therefore differ from the brief (which assumes an enforcing Linux host).
Container started: 7f2b28cea260
Attempt to read /etc/passwd: Exit Code 0, Output: root:x:0:0:root:/root:/bin/bash
...
    [NOTICE] Command SUCCEEDED - without AppArmor support the daemon cannot enforce the profile (on an enforcing Linux host this must exit 1).
Attempt to execute /bin/bash: Exit Code 0, Output: <empty>
    [NOTICE] Command SUCCEEDED - without AppArmor support the daemon cannot enforce the profile (on an enforcing Linux host this must exit 126).
Container stopped
==> [6/6] Final state...
CONTAINER ID   STATUS                        IMAGE
7f2b28cea260   Exited (137) 1 second ago     flask-apparmor
1c3ec90e1a73   Exited (137) 14 seconds ago   flask-apparmor

Summary: profile syntax validated and attached to the container
         config (inspect shows it), but this daemon does NOT
         enforce AppArmor - test commands succeeded, as reported
         honestly by test_restricted_actions.py. For enforced
         results, re-run on a Linux host (README has the steps).

Done. Run './cleanup.sh' when you are finished.
```

On an **enforcing Linux host** the same script loads the profile in `[3/6]`,
and `[5/6]` prints the brief's expected `Exit Code 1` / `Exit Code 126` with
`[OK] Denied as the my-apparmor-profile profile expects…` verdicts.

### Option B — manual (the brief's commands, with the fixes inline)

```bash
# Tasks 1-2: app.py and Dockerfile are in this folder
docker build -t flask-apparmor .

# Task 3a: syntax check (works anywhere an apparmor_parser exists, incl. WSL)
apparmor_parser -Q my-apparmor-profile

# Task 3b: install + load the profile (Linux host with AppArmor, root)
sudo cp my-apparmor-profile /etc/apparmor.d/
sudo apparmor_parser -r /etc/apparmor.d/my-apparmor-profile

# Task 3c: run the container with the profile (CLI equivalent of the SDK scripts)
docker run --security-opt="apparmor=my-apparmor-profile" -p 5000:5000 flask-apparmor

# Task 4 + 5: the Docker SDK scripts
pip install docker            # if you don't have it yet
python apply_apparmor.py      # build → run with profile → verify → stop
python test_restricted_actions.py   # restricted actions → verdicts → stop
```

While the Task 3c container is up, the app answers on the published port:

```bash
curl http://127.0.0.1:5000/
# Hello, this is a secure Flask application running inside a Docker container!
```

## 6. How to verify the expected output

| Check | Command | Expected result |
|---|---|---|
| Profile syntax | `apparmor_parser -Q my-apparmor-profile` | exit `0` (warnings about cache are fine) |
| Image built | `docker images flask-apparmor` | `flask-apparmor:latest` |
| Profile attached | `docker inspect --format '{{.HostConfig.SecurityOpt}}' <container>` | `['apparmor=my-apparmor-profile']` |
| Restricted read (enforcing host) | `python test_restricted_actions.py` | `Attempt to read /etc/passwd: Exit Code 1, Output: <empty>` + `[OK]` |
| Restricted exec (enforcing host) | `python test_restricted_actions.py` | `Attempt to execute /bin/bash: Exit Code 126, Output: <empty>` + `[OK]` |
| Non-enforcing host | same script | `Exit Code 0` for both **plus** explicit `[NOTICE]` lines (see platform notes) |
| Containers left behind | `docker ps -a --filter ancestor=flask-apparmor` | the `Exited` containers from the run (remove with `./cleanup.sh`) |

## 7. Key concepts from this exercise

### What AppArmor is (Q1/Q2, expanded)

**AppArmor** is a Linux **mandatory access control** (MAC) system: instead of
"this process may do whatever its user may do", a **profile** pins the
process to an explicit allow list of paths, network types and kernel
capabilities — enforced by the kernel, even for root inside the container.

| | AppArmor | seccomp |
|---|---|---|
| Filters | **paths** (files, network rules, capabilities) | **syscalls** |
| Granularity | per-binary/profile name | per-container filter |
| On this host | not available (platform notes) | active (`profile=builtin`) |

A profile has two modes — **enforce** (deny + audit) and **complain** (log
only) — and rules come in two flavours: plain `allow` lines and `deny`
lines; **deny wins** on a conflict, and *no matching rule = denial*.

### Why the profile looks the way it does

```apparmor
profile my-apparmor-profile {     # named → resolvable via --security-opt
    /** rwklmix,                  # catch-all: the runtime may read/write/lock/mmap + ix-exec
    network inet stream,          # TCP only (Flask serves on 5000)
    capability net_bind_service,  # allow binding privileged ports (no-op for 5000, kept per brief)
    deny capability sys_admin,    # never: mount/pivot_root/namespace tricks
    deny /etc/** r,               # passwd, shadow, hosts, resolv.conf...
    deny /var/** rw,              # logs, spool, lib state
    deny /bin/** rmx,             # no executing host binaries
    deny /usr/bin/** rmx,         # usrmerge: /bin -> /usr/bin
}
```

### Why restricting `/etc/` and `/var/` matters (Q3)

- `/etc/passwd` / `/etc/shadow` leak accounts and hashes (reconnaissance);
  `/etc/resolv.conf`, `hosts`, `sudoers` influence where traffic goes and
  who can escalate.
- `/var/` holds mutable system state (logs, package caches, spools) —
  writable paths are the usual route to persistence after a breach.
- Inside a container both are attack surface the app never legitimately
  needs.

### Other capabilities you can restrict (Q4)

Besides `sys_admin` / `net_bind_service` used here: `net_raw` (raw sockets,
sniffing/spoofing), `sys_ptrace` (debug/inspect other processes),
`sys_module` (load kernel modules), `mknod`/`setfcap`/`chown` and the rest
of Linux's ~40 capability types — plus, beyond capabilities, AppArmor can
restrict network rules (`network inet stream`), `mount`/`umount`, `pivot_root`,
and ioctl ranges. Docker already drops many of these by default; an
AppArmor profile makes the policy explicit and auditable.

### Verifying a profile is applied (Q5)

```bash
docker inspect --format '{{.HostConfig.SecurityOpt}}' <container>
# ['apparmor=my-apparmor-profile']
```

or from Python (Task 4): `client.api.inspect_container(id)
['HostConfig']['SecurityOpt']`. On an enforcing host you can additionally
confirm the kernel side: `cat /sys/kernel/security/apparmor/profiles | grep
my-apparmor-profile`, and `docker exec <c> cat /proc/1/attr/current` shows
the profile the process actually runs under. `HostConfig.SecurityOpt` proves
the *request*; `/proc/1/attr/current` + a denied command prove *enforcement*.

## 8. Q&A (from the exercise)

| # | Q | A |
|---|---|---|
| 1 | What is the purpose of using AppArmor with Docker containers? | AppArmor is used to enforce security policies and confine applications to a limited set of resources. With Docker containers, it helps to limit access to system resources, files, and networks, thus providing an additional layer of security. |
| 2 | How do AppArmor profiles help secure a Docker container? | AppArmor profiles define what a containerized application can or cannot do. They restrict access to sensitive directories, network capabilities, file execution, and system calls, ensuring the container behaves securely without affecting the host system. |
| 3 | Why is it important to restrict access to sensitive directories such as `/etc/` and `/var/`? | Sensitive directories like `/etc/` contain configuration files and sensitive information such as user data and system settings. Restricting access prevents the container from reading or modifying important system files, reducing the risk of security breaches. |
| 4 | What other capabilities can you restrict using AppArmor profiles? | AppArmor can restrict a container's ability to access the network, bind to specific ports, execute binaries, write to specific directories, and use system administration capabilities (`cap_sys_admin`). |
| 5 | How can you verify if an AppArmor profile is successfully applied to a Docker container? | Inspect the container with the Docker SDK or CLI: the `HostConfig.SecurityOpt` field shows the applied security options, including the AppArmor profile name. |

## 9. Cleanup

```bash
./cleanup.sh          # remove flask-apparmor containers (image kept)
./cleanup.sh --image  # also remove the flask-apparmor image
```

Both modes were tested on this machine: containers removed (`Removed 2
container(s).`), and with `--image` the `flask-apparmor` image is gone too.
The script only touches containers created **from the `flask-apparmor`
image** — other containers on the machine are left alone.

The profile file stays in this folder; on an enforcing Linux host you can
unload it from the kernel with:

```bash
sudo apparmor_parser -R /etc/apparmor.d/my-apparmor-profile   # --remove
```

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `apparmor: profile my-apparmor-profile is not loaded` when running the container | load it first: `sudo cp my-apparmor-profile /etc/apparmor.d/ && sudo apparmor_parser -r /etc/apparmor.d/my-apparmor-profile` (deploy.sh `[3/6]` does this automatically on enforcing hosts) |
| `profile ... is not found` | the brief's unnamed profile registers under its path name — use this folder's named profile (`profile my-apparmor-profile`) and check `sudo aa-status` |
| `syntax error, unexpected TOK_ID` / `'x' must be preceded by exec qualifier` from `apparmor_parser` | you're using the brief's `rmix` letters — use the validated modes in this folder's profile (see clean-ups) |
| `File C:/Program Files/Git/mnt/c/... not found` (Git Bash + WSL parser) | MSYS rewrote the `/mnt/...` argument; `deploy.sh` already sets `MSYS2_ARG_CONV_EXCL='*'` — run the scripts via `./deploy.sh` |
| `UnicodeEncodeError: 'charmap' codec can't encode ...` | Windows console codepage vs pip's progress-bar characters — the scripts force UTF-8 with `errors="replace"` on stdout/stderr |
| Test shows `Exit Code 0` instead of `1`/`126` | the daemon doesn't enforce AppArmor — check `docker info --format '{{json .SecurityOptions}}'` for `name=apparmor`; expected on Docker Desktop/WSL2 (platform notes) |
| `ModuleNotFoundError: docker` | `pip install docker` (deploy.sh installs it automatically) |
| Port 5000 already in use | a stale running `flask-apparmor` container — the scripts remove ours before starting; otherwise `docker rm -f <id>` or change the host side (`ports={'5000/tcp': 5001}`) |
| `Cannot connect to the Docker daemon` | start Docker Desktop / `sudo systemctl start docker` |
| Profile loads but nothing is denied on Linux | check the mode: `cat /proc/1/attr/current` must show `my-apparmor-profile (enforce)` — `complain` only logs |
