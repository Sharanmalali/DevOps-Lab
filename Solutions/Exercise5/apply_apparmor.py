"""Exercise 5 - Task 4: apply the AppArmor profile to the Flask container
using the Docker SDK for Python.

Brief fixes (documented in README "Brief clean-ups"):
  * prints every banner line the brief's *expected* output shows (the brief's
    script omits them),
  * removes stale running copies of our container first so port 5000 is free,
  * prints an honest capability notice when the daemon has no AppArmor
    support (e.g. Docker Desktop on Windows/WSL2): the profile is still
    attached to the container config and visible via inspect, but nothing
    is enforced,
  * actionable error if the daemon rejects the run because the profile is
    not loaded on the host.
"""
import json
import sys

import docker
from docker.errors import APIError, BuildError, DockerException

IMAGE = "flask-apparmor"
PROFILE = "my-apparmor-profile"

# Build logs contain box-drawing/progress characters (pip's "━" bars) that
# the Windows console's default cp1252 codec cannot encode - never crash
# over a log line.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass


def fmt_build_chunk(chunk):
    """Turn a docker build log chunk (str or dict, classic or BuildKit
    JSON) into a printable line."""
    text = chunk if isinstance(chunk, str) else None
    if text is None:
        text = chunk.get("stream") or chunk.get("status") or chunk.get("error") or json.dumps(chunk)
    text = text.strip()
    if not text:
        return ""
    try:
        obj = json.loads(text)
    except (ValueError, TypeError):
        obj = None
    if isinstance(obj, dict):
        text = str(obj.get("stream") or obj.get("status") or obj.get("error") or text).strip()
    return text


def main():
    try:
        client = docker.from_env()
        client.ping()
    except DockerException as exc:
        print(f"ERROR: cannot reach the Docker daemon: {exc}", file=sys.stderr)
        return 1

    # Honest platform notice BEFORE doing anything (README "Platform notes").
    info = client.info()
    security_opts = [str(o) for o in (info.get("SecurityOptions") or [])]
    enforced = any(o.startswith("name=apparmor") for o in security_opts)
    if enforced:
        print(f"[INFO] Daemon AppArmor support: {', '.join(security_opts)}")
    else:
        print("[NOTICE] This Docker daemon reports NO AppArmor support "
              f"({', '.join(security_opts) or 'no SecurityOptions'}).")
        print("[NOTICE] The profile will still be attached to the container "
              "config (verifiable via inspect), but it will NOT be enforced.")

    print("Building image from Dockerfile...")
    try:
        _, logs = client.images.build(path=".", tag=IMAGE, rm=True, forcerm=True)
        for chunk in logs:
            line = fmt_build_chunk(chunk)
            if line:
                print(f"[INFO] {line}")
    except BuildError as exc:
        print(f"ERROR: image build failed:\n{exc}", file=sys.stderr)
        return 1

    # A previous (interrupted) run may still hold port 5000.
    stale = client.containers.list(all=True, filters={"ancestor": IMAGE})
    running = [c for c in stale if c.status == "running"]
    for c in running:
        print(f"[INFO] Removing stale running container {c.short_id}...")
        c.remove(force=True)

    print("Running container with AppArmor profile...")
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

    print("Inspecting container to verify the AppArmor profile...")
    container_info = client.api.inspect_container(container.id)
    apparmor_profile = container_info["HostConfig"]["SecurityOpt"]
    print(f"AppArmor profile applied: {apparmor_profile}")

    print("Stopping the container...")
    container.stop()
    if not enforced:
        print("[NOTICE] Remember: 'applied' above means attached to the "
              "container config only - this daemon does not enforce it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
