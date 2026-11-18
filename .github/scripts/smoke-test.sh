#!/usr/bin/env bash
# Smoke test a locally built xh-tomcat image before it is pushed.
#
# Usage: smoke-test.sh <image> <tomcat-version> <jdk> <tomcat-line>
#   e.g. smoke-test.sh xhio/xh-tomcat:next-tc10-jdk25 10.1 jdk25 tc10
#
# <tomcat-version> may be a line (10.1) or an exact patch (10.1.62). Checks:
#   - Tomcat and JDK versions match what was asked for.
#   - The XH server.xml for the line is in place and bundled webapps are gone.
#   - Tomcat boots, serves a deployed app, and hides server info on errors.
set -euo pipefail

IMAGE=$1
TOMCAT_VERSION=$2
JDK=$3
LINE=$4
JDK_MAJOR=${JDK#jdk}
REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
NAME="xh-tomcat-smoke-$$"
WORK=$(mktemp -d)

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  docker logs "$NAME" 2>&1 | tail -40 >&2 || true
  exit 1
}

# Versions.
TC_ACTUAL=$(docker run --rm --entrypoint catalina.sh "$IMAGE" version | sed -n 's/^Server number: *//p')
[[ "$TC_ACTUAL" == "$TOMCAT_VERSION" || "$TC_ACTUAL" == "$TOMCAT_VERSION".* ]] || fail "Tomcat $TC_ACTUAL, expected $TOMCAT_VERSION"
echo "ok - Tomcat $TC_ACTUAL"

JDK_ACTUAL=$(docker run --rm --entrypoint java "$IMAGE" -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -1)
[[ "$JDK_ACTUAL" == "$JDK_MAJOR" || "$JDK_ACTUAL" == "$JDK_MAJOR".* ]] || fail "JDK $JDK_ACTUAL, expected $JDK_MAJOR"
echo "ok - JDK $JDK_ACTUAL"

# Image contents.
docker run --rm --entrypoint cat "$IMAGE" /usr/local/tomcat/conf/server.xml > "$WORK/server.xml"
cmp -s "$WORK/server.xml" "$REPO_ROOT/conf/$LINE/server.xml" || fail "server.xml differs from conf/$LINE/server.xml"
echo "ok - server.xml matches conf/$LINE"

WEBAPPS=$(docker run --rm --entrypoint ls "$IMAGE" -A /usr/local/tomcat/webapps)
[[ -z "$WEBAPPS" ]] || fail "webapps not empty: $WEBAPPS"
echo "ok - webapps empty"

# Boot with a trivial app and hit it over HTTP.
mkdir -p "$WORK/ROOT"
echo "xh-smoke-ok" > "$WORK/ROOT/index.html"
docker run -d --name "$NAME" -p 127.0.0.1::8080 "$IMAGE" >/dev/null
docker cp "$WORK/ROOT" "$NAME:/usr/local/tomcat/webapps/ROOT"
PORT=$(docker port "$NAME" 8080/tcp | head -1 | sed 's/.*://') || fail "container not running"
URL="http://127.0.0.1:$PORT"

for _ in $(seq 1 60); do
  BODY=$(curl -fsS --max-time 5 "$URL/" 2>/dev/null || true)
  [[ "$BODY" == "xh-smoke-ok" ]] && break
  sleep 1
done
[[ "$BODY" == "xh-smoke-ok" ]] || fail "app not served at $URL/"
echo "ok - app served over HTTP"

ERR=$(curl -sS --max-time 5 -o "$WORK/404.html" -w '%{http_code}' "$URL/no-such-page")
[[ "$ERR" == "404" ]] || fail "expected 404, got $ERR"
if grep -qi "apache tomcat" "$WORK/404.html"; then fail "error page shows server info"; fi
echo "ok - error page hides server info"

echo "PASS - $IMAGE"
