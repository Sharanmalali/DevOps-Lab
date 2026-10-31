#!/usr/bin/env bash
# Exercise every endpoint, including the error cases, against a base URL.
#   ./scripts/test-api.sh http://localhost:5050          (Docker)
#   ./scripts/test-api.sh http://127.0.0.1:<tunnel-port> (Minikube)
set -u
BASE="${1:-http://localhost:5050}"

call() {   # $1 = title, rest = curl args
  local title="$1"; shift
  echo "== ${title}"
  curl -s -w '\n   -> HTTP %{http_code}\n\n' "$@"
}

call "Health check (Flask -> database)"      "$BASE/health"
call "Add patient (valid, 201)"              -X POST "$BASE/patients" -H 'Content-Type: application/json' \
     -d '{"name":"Test Patient A","age":45,"gender":"female","blood_group":"O+","condition":"Hypertension"}'
call "Add patient (valid, 201)"              -X POST "$BASE/patients" -H 'Content-Type: application/json' \
     -d '{"name":"Test Patient B","age":30,"gender":"male","blood_group":"B+","condition":"Asthma"}'
call "List all patients (200)"               "$BASE/patients"
call "Get patient 1 (200)"                   "$BASE/patients/1"
call "Missing record (404)"                  "$BASE/patients/9999"
call "Invalid fields (400)"                  -X POST "$BASE/patients" -H 'Content-Type: application/json' \
     -d '{"name":"","age":200,"gender":"unknown","blood_group":"Z+"}'
call "Missing required fields (400)"         -X POST "$BASE/patients" -H 'Content-Type: application/json' -d '{}'
call "Malformed JSON (400)"                  -X POST "$BASE/patients" -H 'Content-Type: application/json' -d '{bad json'
call "Wrong content type (415)"              -X POST "$BASE/patients" -d 'name=x'
call "Wrong HTTP method (405)"               -X DELETE "$BASE/patients/1"
