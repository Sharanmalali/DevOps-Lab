"""Exercise 5 - Task 5: test restricted actions inside the container.

Brief fixes (documented in README "Brief clean-ups"):
  * prints "Container started: <id>" and "Container stopped" as the brief's
    expected output shows (the brief's script omits both),
  * prints an interpretation for every command: on a host that enforces
    AppArmor you get the brief's expected Exit Code 1 / 126; on a daemon
    without AppArmor support (e.g. Docker Desktop on Windows/WSL2) the
    commands succeed and we say so instead of pretending they were denied,
  * removes stale running copies of our container first so port 5000 is free,
  * actionable error if the daemon rejects the run because the profile is
    not loaded on the host.
"""
import sys

import docker
from docker.errors import APIError, DockerException

IMAGE = "flask-apparmor"
PROFILE = "my-apparmor-profile"

# Container output could contain characters the Windows console's default
# cp1252 codec cannot encode - never crash over output text.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass

TESTS = [
    # (command, label for the brief-style message, exit code the brief's
    # reference host shows, reason)
    ("cat /etc/passwd", "read /etc/passwd", 1,
     "reading /etc/passwd must be denied (deny /etc/** r)"),
    ("/bin/bash", "execute /bin/bash", 126,
     "executing /bin/bash must be denied (deny /bin/** rmx)"),
]


def main():
    try:
        client = docker.from_env()
        client.ping()
    except DockerException as exc:
        print(f"ERROR: cannot reach the Docker daemon: {exc}", file=sys.stderr)
        return 1

    info = client.info()
    security_opts = [str(o) for o in (info.get("SecurityOptions") or [])]
    enforced = any(o.startswith("name=apparmor") for o in security_opts)
    if not enforced:
        print("[NOTICE] This Docker daemon has NO AppArmor support - the "
              "profile is attached but cannot block anything here.")
        print("[NOTICE] Expected results below therefore differ from the "
              "brief (which assumes an enforcing Linux host).")

    stale = client.containers.list(all=True, filters={"ancestor": IMAGE})
    for c in [c for c in stale if c.status == "running"]:
        print(f"[INFO] Removing stale running container {c.short_id}...")
        c.remove(force=True)

    try:
        container = client.containers.run(
            IMAGE,
            ports={"5000/tcp": 5000},
            security_opt=[f"apparmor={PROFILE}"],
            detach=True,
        )
    except APIError as exc:
        print(f"ERROR: daemon refused to start the container with "
              f"security_opt=apparmor={PROFILE}:\n{exc}", file=sys.stderr)
        print("Hint: load the profile on the host first "
              "(sudo apparmor_parser -r /etc/apparmor.d/my-apparmor-profile) "
              "or re-run ./deploy.sh on a Linux host.", file=sys.stderr)
        return 1

    print(f"Container started: {container.short_id}")

    failed = False
    for command, label, brief_exit, reason in TESTS:
        exit_code, output = container.exec_run(command)
        text = output.decode(errors="replace").strip()
        shown = text if text else "<empty>"
        print(f"Attempt to {label}: Exit Code {exit_code}, "
              f"Output: {shown}")

        if enforced:
            if exit_code == brief_exit:
                print(f"    [OK] Denied as the {PROFILE} profile expects, "
                      f"with the brief's exit code {brief_exit} ({reason}).")
            elif exit_code != 0:
                print(f"    [OK] Denied ({reason}); exit code {exit_code} "
                      f"here vs {brief_exit} on the brief's reference host.")
            else:
                print(f"    [FAIL] Exit code 0 - the profile did NOT block "
                      f"{command} on this enforcing host.")
                failed = True
        else:
            if exit_code == 0:
                print(f"    [NOTICE] Command SUCCEEDED - without AppArmor "
                      "support the daemon cannot enforce the profile "
                      f"(on an enforcing Linux host this must exit "
                      f"{brief_exit}).")
            else:
                print(f"    [UNEXPECTED] Exit code {exit_code} on a "
                      "non-enforcing daemon - see output above.")
                failed = True

    print("Container stopped")
    container.stop()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
