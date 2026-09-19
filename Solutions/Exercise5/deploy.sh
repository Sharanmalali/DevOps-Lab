#!/usr/bin/env bash
# Exercise 5 - Docker security with AppArmor: validate/apply the profile
# (Task 3), build the image (Task 2), run the Docker SDK scripts
# (Task 4 apply_apparmor.py, Task 5 test_restricted_actions.py).
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash on Windows can hand native tools a truncated PATH that drops
# /c/Program Files/Docker/... — always put docker's directory at the front.
if command -v docker >/dev/null 2>&1; then
    _docker_dir="$(dirname "$(command -v docker)")"
    export PATH="${_docker_dir}:${PATH}"
fi

PYTHON="${PYTHON:-python}"

echo "==> [1/6] Checking prerequisites..."
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH."; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not running."; exit 1; }
command -v "$PYTHON" >/dev/null 2>&1 || {
    echo "ERROR: '$PYTHON' not found (set PYTHON=/path/to/python if needed)."; exit 1; }
if ! "$PYTHON" -c "import docker" >/dev/null 2>&1; then
    echo "    Docker SDK for Python missing - installing it now (pip install docker)..."
    "$PYTHON" -m pip install --quiet docker
    "$PYTHON" -c "import docker" || { echo "ERROR: could not install the docker SDK."; exit 1; }
fi
echo "    Docker SDK for Python: $("$PYTHON" -c "import docker; print(docker.__version__)")"
test -f my-apparmor-profile || { echo "ERROR: my-apparmor-profile not found."; exit 1; }

# AppArmor capability probe (README "Platform notes"): Docker Desktop on
# Windows/WSL2 does not expose AppArmor in `docker info`.
SEC_OPTS="$(docker info --format '{{json .SecurityOptions}}' 2>/dev/null || echo '[]')"
if printf '%s' "${SEC_OPTS}" | grep -q 'name=apparmor'; then
    APPARMOR="enforced"
    echo "    Daemon AppArmor support: YES (${SEC_OPTS})"
else
    APPARMOR="none"
    echo "    [NOTICE] Daemon AppArmor support: NO (${SEC_OPTS})."
    echo "    [NOTICE] The profile will be validated, attached and verified,"
    echo "             but this host cannot enforce it (see README)."
fi

echo "==> [2/6] Task 2: Building image flask-apparmor..."
docker build -t flask-apparmor .
docker images flask-apparmor --format '    {{.Repository}}:{{.Tag}}  {{.Size}}'

echo "==> [3/6] Task 3: Validating AppArmor profile syntax..."
# Locate an apparmor_parser: native Linux first, else the WSL Ubuntu distro
# (which can parse with -Q, skipping the kernel load).
PARSER_CMD=()
PROFILE_SRC="$(pwd)"
if command -v apparmor_parser >/dev/null 2>&1; then
    PARSER_CMD=(apparmor_parser)
    PROFILE_PATH="${PROFILE_SRC}/my-apparmor-profile"
    PARSER_KIND="native"
elif command -v wsl >/dev/null 2>&1; then
    win_dir="$(pwd -W 2>/dev/null || true)"
    if [ -n "${win_dir}" ]; then
        # "C:\Users\..." -> "/mnt/c/Users/..."
        drive="$(printf '%s' "${win_dir}" | cut -c1 | tr '[:upper:]' '[:lower:]')"
        rest="$(printf '%s' "${win_dir}" | cut -c3- | tr '\\' '/')"
        PROFILE_PATH="/mnt/${drive}${rest}/my-apparmor-profile"
    else
        PROFILE_PATH="${PROFILE_SRC}/my-apparmor-profile"
    fi
    if wsl -d Ubuntu -u root -- command -v apparmor_parser >/dev/null 2>&1; then
        # MSYS (Git Bash) would rewrite /mnt/... args for wsl.exe into
        # C:/Program Files/Git/mnt/... — disable that conversion.
        PARSER_CMD=(env MSYS2_ARG_CONV_EXCL='*' wsl -d Ubuntu -u root -- apparmor_parser)
        PARSER_KIND="wsl"
    fi
fi

if [ "${#PARSER_CMD[@]}" -eq 0 ]; then
    echo "    [NOTICE] No apparmor_parser available - syntax check SKIPPED."
    echo "             Install one with: sudo apt-get install apparmor-utils"
else
    echo "    ${PARSER_CMD[*]} -Q ${PROFILE_PATH}"
    parser_out="$("${PARSER_CMD[@]}" -Q "${PROFILE_PATH}" 2>&1)" && parser_rc=0 || parser_rc=$?
    # -Q skips the kernel load; the 'Cache read/write disabled' line is an
    # informational warning on kernels without AppArmor, not an error.
    printf '%s\n' "${parser_out}" | grep -v 'Cache read/write disabled' | sed 's/^/    /' || true
    if [ "${parser_rc}" -ne 0 ]; then
        echo "    ERROR: profile syntax invalid (parser exit ${parser_rc})."
        exit 1
    fi
    echo "    Profile syntax OK."
fi

if [ "${APPARMOR}" = "enforced" ]; then
    echo "    Loading the profile into the kernel (root required)..."
    if [ "${PARSER_KIND:-}" = "native" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            cp my-apparmor-profile /etc/apparmor.d/my-apparmor-profile
            apparmor_parser -r /etc/apparmor.d/my-apparmor-profile
        elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            sudo -n cp my-apparmor-profile /etc/apparmor.d/my-apparmor-profile
            sudo -n apparmor_parser -r /etc/apparmor.d/my-apparmor-profile
        else
            echo "    ERROR: root needed to load the profile. Run manually:"
            echo "      sudo cp my-apparmor-profile /etc/apparmor.d/"
            echo "      sudo apparmor_parser -r /etc/apparmor.d/my-apparmor-profile"
            exit 1
        fi
    elif [ "${PARSER_KIND:-}" = "wsl" ]; then
        env MSYS2_ARG_CONV_EXCL='*' wsl -d Ubuntu -u root -- sh -c "cp '${PROFILE_PATH}' /etc/apparmor.d/my-apparmor-profile && apparmor_parser -r /etc/apparmor.d/my-apparmor-profile"
    else
        echo "    ERROR: no apparmor_parser to load the profile with."; exit 1
    fi
    if [ "${PARSER_KIND:-}" = "native" ] && grep -q 'my-apparmor-profile' /sys/kernel/security/apparmor/profiles 2>/dev/null; then
        echo "    Profile loaded (visible in /sys/kernel/security/apparmor/profiles)."
    fi
else
    echo "    [NOTICE] Kernel load skipped - this daemon does not enforce"
    echo "             AppArmor, so there is nothing to load into."
fi

echo "==> [4/6] Task 4: Running apply_apparmor.py (Docker SDK)..."
"$PYTHON" apply_apparmor.py

echo "==> [5/6] Task 5: Running test_restricted_actions.py..."
"$PYTHON" test_restricted_actions.py

echo "==> [6/6] Final state..."
docker ps -a --filter ancestor=flask-apparmor \
    --format 'table {{.ID}}\t{{.Status}}\t{{.Image}}'
echo ""
if [ "${APPARMOR}" = "enforced" ]; then
    echo "Summary: profile syntax validated, loaded and enforced - the test"
    echo "         script must have shown Exit Code 1 / 126."
else
    echo "Summary: profile syntax validated and attached to the container"
    echo "         config (inspect shows it), but this daemon does NOT"
    echo "         enforce AppArmor - test commands succeeded, as reported"
    echo "         honestly by test_restricted_actions.py. For enforced"
    echo "         results, re-run on a Linux host (README has the steps)."
fi
echo ""
echo "Done. Run './cleanup.sh' when you are finished."
