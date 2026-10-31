"""
Security test - run INSIDE the patient-api container to show which operations
are PERMITTED and which are RESTRICTED by the AppArmor profile (Linux) or by
the hardened container settings (macOS / no AppArmor).

    docker exec patient-api python security_test.py
    kubectl exec deploy/patient-api -- python security_test.py
"""
import os
import socket
import subprocess


def attempt(label, func):
    try:
        detail = func()
        print(f"  [ALLOWED] {label}" + (f"  -> {detail}" if detail else ""))
    except Exception as exc:  # noqa: BLE001 - we want to report any failure
        print(f"  [BLOCKED] {label}  -> {type(exc).__name__}: {exc}")


def read_app_code():
    with open("/app/app.py") as f:
        return f"read {len(f.read())} bytes"


def write_tmp():
    with open("/tmp/scratch.txt", "w") as f:
        f.write("temporary data")
    return "wrote /tmp/scratch.txt"


def resolve_db():
    return f"patient-db -> {socket.gethostbyname(os.getenv('DB_HOST', 'patient-db'))}"


def connect_db():
    with socket.create_connection((os.getenv("DB_HOST", "patient-db"), 5432), timeout=3):
        return "TCP 5432 open"


def modify_app_code():
    with open("/app/app.py", "a") as f:
        f.write("# tampered\n")
    return "app code was modified!"


def write_etc():
    with open("/etc/malicious.conf", "w") as f:
        f.write("x")
    return "wrote /etc/malicious.conf"


def read_shadow():
    with open("/etc/shadow") as f:
        return f"read {len(f.read())} bytes"


def spawn_shell():
    out = subprocess.run(["/bin/sh", "-c", "echo shell-works"], capture_output=True, text=True, check=True)
    return out.stdout.strip()


def raw_socket():
    socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP).close()
    return "raw ICMP socket opened"


def write_proc_sys():
    with open("/proc/sys/kernel/hostname", "w") as f:
        f.write("hacked")
    return "changed kernel hostname"


if __name__ == "__main__":
    profile = "unconfined"
    try:
        with open("/proc/self/attr/current") as f:
            profile = f.read().strip() or profile
    except OSError:
        pass
    print(f"Running as uid={os.getuid()}  AppArmor profile: {profile}")

    print("\nExpected PERMITTED operations (needed by the app):")
    attempt("Read application code /app/app.py", read_app_code)
    attempt("Write temporary file in /tmp", write_tmp)
    attempt("Resolve database by container name", resolve_db)
    attempt("Open TCP connection to database", connect_db)

    print("\nExpected RESTRICTED operations (dangerous):")
    attempt("Modify application code /app/app.py", modify_app_code)
    attempt("Write to /etc", write_etc)
    attempt("Read /etc/shadow", read_shadow)
    attempt("Spawn a shell (/bin/sh)", spawn_shell)
    attempt("Open a raw network socket", raw_socket)
    attempt("Write kernel setting /proc/sys", write_proc_sys)
