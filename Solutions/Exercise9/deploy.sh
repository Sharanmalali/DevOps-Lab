#!/usr/bin/env bash
#
# Exercise 9 - Jenkins multi-stage pipeline
#
# Publishes the sample Flask app (app.py, test_app.py, requirements.txt) plus the
# declarative Jenkinsfile to a public GitHub repo, starts a headless Jenkins,
# creates the Pipeline job "Python-MultiStage-Pipeline" (Pipeline script from
# SCM), triggers a build and verifies the stage-by-stage console output.
#
# Usage:
#   GITHUB_TOKEN=<pat> ./deploy.sh     # create/update the repo + run the pipeline
#   ./deploy.sh                        # repo + files must already exist (public)
#
# GITHUB_TOKEN is only needed to CREATE the repo or push the app files. It is
# never written to disk by this script.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
# Windows-style host path (forward slashes). With MSYS arg conversion disabled
# below, the Docker CLI needs this form for build contexts and bind mounts.
HOST_WORKDIR="$(pwd -W 2>/dev/null || pwd)"

# Git Bash rewrites slash-leading arguments destined for native executables.
export MSYS2_ARG_CONV_EXCL='*'

# Git Bash can hand native children a truncated PATH (drops the Docker CLI dir
# and docker-credential-desktop). Re-add it explicitly.
DOCKER_BIN_DIR="$(dirname "$(command -v docker 2>/dev/null || echo /usr/bin/docker)")"
case ":$PATH:" in
  *":$DOCKER_BIN_DIR:"*) ;;
  *) PATH="$DOCKER_BIN_DIR:$PATH" ;;
esac
export PATH

JENKINS_IMAGE="ex9-jenkins"
CONTAINER_NAME="jenkins"
VOLUME_NAME="ex9_jenkins_home"
JOB_NAME="Python-MultiStage-Pipeline"
JOB_XML="$SCRIPT_DIR/job/Python-MultiStage-Pipeline-config.xml"

REPO_NAME="devops-sample-code"
REPO_DESC="A demo repository for Jenkins scripting."
GITHUB_OWNER=""
REPO_URL=""

# Files published to the repo and cloned by the pipeline.
APP_FILES=(app.py test_app.py requirements.txt Jenkinsfile)

API="https://api.github.com"
GH_HDR=(-H "User-Agent: ex9-deploy" -H "Accept: application/vnd.github+json")
GH_AUTH=()
[ -n "${GITHUB_TOKEN:-}" ] && GH_AUTH=(-H "Authorization: token ${GITHUB_TOKEN}")

for arg in "$@"; do
  case "$arg" in
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

port_in_use() { netstat -ano 2>/dev/null | grep -qiE "[:.]$1[[:space:]].*LISTENING"; }
pick_port() { local p="$1"; while port_in_use "$p"; do echo "  port $p is in use, trying $((p + 1))..." >&2; p=$((p + 1)); done; echo "$p"; }

# ---------------------------------------------------------------- [1/8] prereqs
echo "[1/8] Checking prerequisites"
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker not found in PATH" >&2; exit 1; }
docker info >/dev/null 2>&1          || { echo "ERROR: Docker daemon is not running" >&2; exit 1; }
command -v curl   >/dev/null 2>&1 || { echo "ERROR: curl not found in PATH" >&2; exit 1; }
echo "  docker: $(docker --version | cut -d, -f1)"
[ -n "${GITHUB_TOKEN:-}" ] && echo "  GITHUB_TOKEN: set" || echo "  GITHUB_TOKEN: not set (repo must already exist)"

# -------------------------------------------------------- [2/8] GitHub sample repo
echo "[2/8] Ensuring GitHub sample repo '${REPO_NAME}' + app files"
if [ -n "${GITHUB_TOKEN:-}" ]; then
  GITHUB_OWNER="$(curl -fsS "${GH_HDR[@]}" "${GH_AUTH[@]}" "${API}/user" | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$GITHUB_OWNER" ] || { echo "ERROR: could not determine GitHub user from token" >&2; exit 1; }
else
  GITHUB_OWNER="${GITHUB_OWNER_FALLBACK:-Sharanmalali}"
fi
REPO_URL="https://github.com/${GITHUB_OWNER}/${REPO_NAME}.git"
echo "  owner: ${GITHUB_OWNER}"

code="$(curl -s -o /dev/null -w '%{http_code}' "${GH_HDR[@]}" "${GH_AUTH[@]}" "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}")"
if [ "$code" = "200" ]; then
  echo "  repo exists"
elif [ "$code" = "404" ]; then
  [ -n "${GITHUB_TOKEN:-}" ] || { echo "ERROR: repo ${GITHUB_OWNER}/${REPO_NAME} missing and GITHUB_TOKEN not set" >&2; exit 1; }
  echo "  creating public repo ${GITHUB_OWNER}/${REPO_NAME}"
  curl -fsS -o /dev/null "${GH_HDR[@]}" "${GH_AUTH[@]}" -X POST "${API}/user/repos" \
    -d "{\"name\":\"${REPO_NAME}\",\"description\":\"${REPO_DESC}\",\"private\":false}"
else
  echo "ERROR: unexpected HTTP ${code} checking repo" >&2; exit 1
fi

# Idempotent content upsert: only commit when the remote bytes differ, so
# repeated runs do not pile up meaningless commits (same fix as Exercise 8).
upsert_file() {
  local file="$1" message="$2"
  local local_content remote_content b64 sha code
  local_content="$(cat "$SCRIPT_DIR/$file")"
  remote_content="$(curl -fsS "https://raw.githubusercontent.com/${GITHUB_OWNER}/${REPO_NAME}/main/${file}" 2>/dev/null || true)"
  if [ -n "$remote_content" ] && [ "$remote_content" = "$local_content" ]; then
    echo "  ${file} already up to date"
    return 0
  fi
  b64="$(base64 < "$SCRIPT_DIR/$file" | tr -d '\n')"
  code="$(curl -s -o /dev/null -w '%{http_code}' "${GH_HDR[@]}" "${GH_AUTH[@]}" "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/${file}?ref=main")"
  if [ "$code" = "200" ]; then
    sha="$(curl -fsS "${GH_HDR[@]}" "${GH_AUTH[@]}" "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/${file}?ref=main" | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    echo "  updating ${file}"
    curl -fsS -o /dev/null "${GH_HDR[@]}" "${GH_AUTH[@]}" -X PUT "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/${file}" \
      -d "{\"message\":\"${message}\",\"content\":\"${b64}\",\"branch\":\"main\",\"sha\":\"${sha}\"}"
  else
    echo "  creating ${file} on branch main"
    curl -fsS -o /dev/null "${GH_HDR[@]}" "${GH_AUTH[@]}" -X PUT "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/${file}" \
      -d "{\"message\":\"${message}\",\"content\":\"${b64}\",\"branch\":\"main\"}"
  fi
}

if [ -n "${GITHUB_TOKEN:-}" ]; then
  for f in "${APP_FILES[@]}"; do upsert_file "$f" "Add ${f}"; done
  echo "  repo: ${REPO_URL%.git}"
else
  for f in "${APP_FILES[@]}"; do
    curl -fsS -o /dev/null "${GH_HDR[@]}" "${API}/repos/${GITHUB_OWNER}/${REPO_NAME}/contents/${f}" \
      || { echo "ERROR: ${f} missing and no GITHUB_TOKEN to add it" >&2; exit 1; }
  done
  echo "  app files present (public)"
fi

# ------------------------------------------------- [3/8] port + image + container
echo "[3/8] Preparing Jenkins (image ${JENKINS_IMAGE})"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
sleep 2   # let Docker Desktop release the previous container's published port
JENKINS_PORT="$(pick_port 8080)"
[ "$JENKINS_PORT" = "8080" ] || echo "  NOTE: brief uses 8080, but it is taken on this host -> Jenkins UI on ${JENKINS_PORT}"
docker build -q -t "$JENKINS_IMAGE" -f "$HOST_WORKDIR/Dockerfile.jenkins" "$HOST_WORKDIR" >/dev/null
echo "  image built; UI -> ${JENKINS_PORT}"

echo "[4/8] Starting Jenkins (headless admin/admin)"
docker run -d --name "$CONTAINER_NAME" \
  -p "${JENKINS_PORT}:8080" \
  -v "${VOLUME_NAME}:/var/jenkins_home" \
  -v "${HOST_WORKDIR}/init.groovy.d:/var/jenkins_home/init.groovy.d:ro" \
  -e "JAVA_OPTS=-Djenkins.install.runSetupWizard=false" \
  "$JENKINS_IMAGE" >/dev/null
echo "  container: $(docker inspect -f '{{.Id}}' "$CONTAINER_NAME" | cut -c1-12)"

BASE_URL="http://localhost:${JENKINS_PORT}"

echo "[5/8] Waiting for Jenkins on ${BASE_URL}"
ready=0
for _ in $(seq 1 90); do
  curl -fsS -o /dev/null "${BASE_URL}/login" 2>/dev/null && { ready=1; break; }
  sleep 2
done
[ "$ready" -eq 1 ] || { echo "ERROR: Jenkins did not become ready" >&2; docker logs --tail 30 "$CONTAINER_NAME" >&2 || true; exit 1; }

COOKIE_JAR=".ex9-cookies.txt"
RENDERED=".ex9-job-config.xml"
cleanup_tmp() { rm -f "$COOKIE_JAR" "$RENDERED" 2>/dev/null || true; }
trap cleanup_tmp EXIT

CRUMB="$(curl -fsS -u admin:admin -c "$COOKIE_JAR" "$BASE_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22:%22,//crumb)")"
[ -n "$CRUMB" ] || { echo "ERROR: could not obtain CSRF crumb" >&2; exit 1; }

# ------------------------------------------------------------- [6/8] create job
echo "[6/8] Creating Pipeline job '${JOB_NAME}' (script from SCM)"
sed "s#https://github.com/[^/]*/devops-sample-code.git#${REPO_URL}#" "$JOB_XML" > "$RENDERED"
if curl -fsS -o /dev/null -u admin:admin "${BASE_URL}/job/${JOB_NAME}/api/json" 2>/dev/null; then
  curl -fsS -o /dev/null -u admin:admin -b "$COOKIE_JAR" -H "$CRUMB" -X POST "${BASE_URL}/job/${JOB_NAME}/doDelete"
  echo "  removed previous job"
fi
curl -fsS -o /dev/null -u admin:admin -b "$COOKIE_JAR" -H "$CRUMB" \
  -H "Content-Type: application/xml" --data-binary @"$RENDERED" \
  "${BASE_URL}/createItem?name=${JOB_NAME}"
echo "  job created: ${BASE_URL}/job/${JOB_NAME}"

# --------------------------------------------------------- [7/8] build + verify
echo "[7/8] Triggering build and waiting for the result"
trigger_code="$(curl -s -o /dev/null -w '%{http_code}' -u admin:admin -b "$COOKIE_JAR" -H "$CRUMB" -X POST "${BASE_URL}/job/${JOB_NAME}/build")"
echo "  trigger HTTP ${trigger_code}"
case "$trigger_code" in
  200|201|302) ;;
  *) echo "ERROR: build trigger failed (HTTP ${trigger_code})" >&2; exit 1 ;;
esac

build_num=""; result=""
for _ in $(seq 1 160); do
  j="$(curl -s -u admin:admin "${BASE_URL}/job/${JOB_NAME}/lastBuild/api/json?tree=number,building,result" 2>/dev/null || true)"
  if [ -n "$j" ]; then
    building="$(printf '%s' "$j" | grep -o '"building":[a-z]*' | head -1 | cut -d: -f2 || true)"
    if [ "$building" = "false" ]; then
      build_num="$(printf '%s' "$j" | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2 || true)"
      result="$(printf '%s' "$j" | grep -o '"result":"[A-Z]*"' | head -1 | cut -d'"' -f4 || true)"
      break
    fi
  fi
  sleep 3
done
[ -n "$build_num" ] || { echo "ERROR: build did not finish in time" >&2; exit 1; }

CONSOLE="$(curl -s -u admin:admin "${BASE_URL}/job/${JOB_NAME}/${build_num}/consoleText")"

# --------------------------------------------------- [8/8] assert stage-by-stage
echo "[8/8] Verifying the multi-stage console output"
echo "  build #${build_num} finished: ${result}"
echo "  --- console output (tail) ---"
printf '%s\n' "$CONSOLE" | tail -n 8 | sed 's/^/  | /'

[ "$result" = "SUCCESS" ] || { echo "ERROR: build result was ${result}" >&2; printf '%s\n' "$CONSOLE" | tail -n 30 >&2; exit 1; }
for marker in "(Build)" "(Test)" "(Deploy)" "(Run Application)" "(Test Application)"; do
  printf '%s\n' "$CONSOLE" | grep -qF "$marker" || { echo "ERROR: console is missing stage ${marker}" >&2; exit 1; }
  echo "  stage ok: ${marker}"
done
printf '%s\n' "$CONSOLE" | grep -q "Ran 1 test"                       || { echo "ERROR: test stage did not run the unit test" >&2; exit 1; }
printf '%s\n' "$CONSOLE" | grep -q "Hello, Jenkins Multi-Stage Pipeline!" || { echo "ERROR: console missing the app's greeting" >&2; exit 1; }
printf '%s\n' "$CONSOLE" | grep -q "Pipeline completed successfully!" || { echo "ERROR: post-success block did not run" >&2; exit 1; }
echo "  unit test: 1 test passed"
echo "  app output: Hello, Jenkins Multi-Stage Pipeline!"

cat <<EOF

============================================================
 Exercise 9 complete
============================================================
 Repo     : ${REPO_URL%.git}
 Job      : ${BASE_URL}/job/${JOB_NAME}   (Pipeline, script from SCM)
 Build    : #${build_num} -> ${result}
 Stages   : Build -> Test -> Deploy -> Run Application -> Test Application
 Console  : "Ran 1 test ... OK" then "Finished: SUCCESS"

 Open the job, click a build number -> Console Output (or "Pipeline Steps")
 to watch each stage live.
============================================================
EOF

echo
echo "Container status:"
docker ps --filter "name=^/${CONTAINER_NAME}\$" --format '  {{.Names}}  {{.Status}}  {{.Ports}}'
echo
echo "Useful commands:"
echo "  logs    : docker logs -f ${CONTAINER_NAME}"
echo "  cleanup : ./cleanup.sh [--volume] [--image] [--github]"
