"""
Patient Record Service - Flask REST API backed by PostgreSQL.

SYNTHETIC DATA ONLY - for an internal demonstration, never real patients.

Endpoints
  GET  /health               -> service + database status
  GET  /patients             -> list all patient records
  GET  /patients/<id>        -> one record (404 if missing)
  POST /patients             -> add a record (JSON body, validated)

The database host is read from DB_HOST; in Docker and Kubernetes it is the
*name* of the database container / Service ("patient-db"), resolved by DNS.
"""
import logging
import os
import sys
import time

import psycopg2
import psycopg2.extras
from flask import Flask, jsonify, request
from werkzeug.exceptions import HTTPException

DB_HOST = os.getenv("DB_HOST", "patient-db")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "patients")
DB_USER = os.getenv("DB_USER", "patient_app")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_CONNECT_RETRIES = int(os.getenv("DB_CONNECT_RETRIES", "10"))

ALLOWED_GENDERS = {"male", "female", "other"}
ALLOWED_BLOOD_GROUPS = {"A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"}

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [patient-api] %(message)s",
)
log = logging.getLogger("patient-api")

app = Flask(__name__)


def get_conn():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=3,
    )


def init_db():
    """Create the table, retrying while the database container starts up.

    If the database never becomes reachable the process exits with code 1, so
    Docker shows the container as Exited and Kubernetes as CrashLoopBackOff -
    the error message below is what you look for in the logs.
    """
    for attempt in range(1, DB_CONNECT_RETRIES + 1):
        try:
            with get_conn() as conn, conn.cursor() as cur:
                # Replicas start together; the lock stops two concurrent
                # CREATE TABLE IF NOT EXISTS from colliding in PostgreSQL.
                cur.execute("SELECT pg_advisory_xact_lock(4242)")
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS patients (
                        id          SERIAL PRIMARY KEY,
                        name        VARCHAR(100) NOT NULL,
                        age         INTEGER      NOT NULL CHECK (age BETWEEN 0 AND 130),
                        gender      VARCHAR(10)  NOT NULL,
                        blood_group VARCHAR(3),
                        condition   VARCHAR(200),
                        created_at  TIMESTAMP    DEFAULT NOW()
                    )
                    """
                )
            log.info("Connected to database %s:%s/%s - table ready", DB_HOST, DB_PORT, DB_NAME)
            return
        except psycopg2.OperationalError as exc:
            reason = str(exc).strip().splitlines()[0]
            log.warning(
                "Database not reachable at %s:%s (attempt %d/%d): %s",
                DB_HOST, DB_PORT, attempt, DB_CONNECT_RETRIES, reason,
            )
            time.sleep(3)
    log.error("FATAL: could not connect to database host '%s' - giving up", DB_HOST)
    sys.exit(1)


def validate_patient(data):
    """Return a list of validation error messages (empty list = valid)."""
    errors = []
    if not isinstance(data, dict):
        return ["request body must be a JSON object"]

    allowed = {"name", "age", "gender", "blood_group", "condition"}
    unknown = set(data) - allowed
    if unknown:
        errors.append(f"unknown field(s): {', '.join(sorted(unknown))}")

    name = data.get("name")
    if not isinstance(name, str) or not name.strip():
        errors.append("'name' is required and must be a non-empty string")
    elif len(name) > 100:
        errors.append("'name' must be at most 100 characters")

    age = data.get("age")
    # bool is a subclass of int in Python, so reject it explicitly
    if not isinstance(age, int) or isinstance(age, bool):
        errors.append("'age' is required and must be an integer")
    elif not 0 <= age <= 130:
        errors.append("'age' must be between 0 and 130")

    gender = data.get("gender")
    if not isinstance(gender, str) or gender.lower() not in ALLOWED_GENDERS:
        errors.append(f"'gender' is required and must be one of {sorted(ALLOWED_GENDERS)}")

    blood = data.get("blood_group")
    if blood is not None and blood not in ALLOWED_BLOOD_GROUPS:
        errors.append(f"'blood_group' must be one of {sorted(ALLOWED_BLOOD_GROUPS)}")

    condition = data.get("condition")
    if condition is not None and (not isinstance(condition, str) or len(condition) > 200):
        errors.append("'condition' must be a string of at most 200 characters")
    return errors


def row_to_dict(row):
    row = dict(row)
    row["created_at"] = row["created_at"].isoformat() if row.get("created_at") else None
    return row


@app.get("/health")
def health():
    try:
        with get_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT 1")
        return jsonify(status="ok", database="connected", db_host=DB_HOST), 200
    except psycopg2.OperationalError as exc:
        log.error("Health check failed - database %s unreachable: %s", DB_HOST, str(exc).strip())
        return jsonify(status="error", database="unreachable", db_host=DB_HOST), 503


@app.get("/patients")
def list_patients():
    with get_conn() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT * FROM patients ORDER BY id")
        rows = [row_to_dict(r) for r in cur.fetchall()]
    return jsonify(count=len(rows), patients=rows), 200


@app.get("/patients/<int:patient_id>")
def get_patient(patient_id):
    with get_conn() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT * FROM patients WHERE id = %s", (patient_id,))
        row = cur.fetchone()
    if row is None:
        log.info("GET /patients/%d -> 404 not found", patient_id)
        return jsonify(error="Not Found", message=f"patient {patient_id} does not exist"), 404
    return jsonify(row_to_dict(row)), 200


@app.post("/patients")
def add_patient():
    if not request.is_json:
        return jsonify(error="Unsupported Media Type",
                       message="Content-Type must be application/json"), 415
    data = request.get_json(silent=True)
    if data is None:
        return jsonify(error="Bad Request", message="request body is not valid JSON"), 400

    errors = validate_patient(data)
    if errors:
        log.info("POST /patients -> 400 validation failed: %s", errors)
        return jsonify(error="Validation Failed", details=errors), 400

    with get_conn() as conn, conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            INSERT INTO patients (name, age, gender, blood_group, condition)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING *
            """,
            (data["name"].strip(), data["age"], data["gender"].lower(),
             data.get("blood_group"), data.get("condition")),
        )
        row = cur.fetchone()
    log.info("POST /patients -> 201 created patient id=%d", row["id"])
    return jsonify(row_to_dict(row)), 201


@app.errorhandler(HTTPException)
def handle_http_error(exc):
    # Return JSON (not HTML) for 404 on unknown URLs, 405 wrong method, etc.
    return jsonify(error=exc.name, message=exc.description), exc.code


@app.errorhandler(psycopg2.Error)
def handle_db_error(exc):
    log.error("Database error: %s", str(exc).strip())
    return jsonify(error="Service Unavailable", message="database error"), 503


init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
