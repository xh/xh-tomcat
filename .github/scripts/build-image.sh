#!/usr/bin/env bash
# Build, smoke test and push one xh-tomcat image. Used by buildNext and buildRelease.
#
# Usage: build-image.sh <tomcat-version> <jdk> <tomcat-line> <tag> [<tag>...]
#   e.g. build-image.sh 10.1.62 jdk17 tc10 xhio/xh-tomcat:4.2.0-tc10-jdk17 xhio/xh-tomcat:latest-tc10-jdk17
#
# Needs a buildx builder with the docker-container driver (docker/setup-buildx-action), which is
# required to attach attestations. All tags must be in the same repository. Steps:
#   1. Build and load the image locally, then run smoke-test.sh on it.
#   2. Rebuild from cache with SBOM and provenance attestations and push it by digest only, with
#      no tags. A plain `docker push` of the loaded image would drop the attestations.
#   3. Check the pushed image has the same layers as the tested one. The second build looks up
#      the base image again, so an upstream re-publish between builds could change it.
#   4. Only then point the tags at the pushed digest. No tag ever names an untested image.
set -euo pipefail

TOMCAT_VERSION=$1
JDK=$2
LINE=$3
shift 3
TAGS=("$@")
[[ ${#TAGS[@]} -gt 0 ]] || { echo "Usage: $0 <tomcat-version> <jdk> <tomcat-line> <tag>..." >&2; exit 1; }
REPO=${TAGS[0]%:*}
for t in "${TAGS[@]}"; do
  [[ "${t%:*}" == "$REPO" ]] || { echo "All tags must be in $REPO: $t" >&2; exit 1; }
done
SCRIPTS=$(cd "$(dirname "$0")" && pwd)
META=$(mktemp)
trap 'rm -f "$META"' EXIT

ARGS=(
  --build-arg TOMCAT_VERSION="$TOMCAT_VERSION"
  --build-arg JDK_VERSION="$JDK"
  --build-arg TOMCAT_LINE="$LINE"
)

# 1. Build and test.
docker buildx build --pull --load "${ARGS[@]}" -t "${TAGS[0]}" .
"$SCRIPTS/smoke-test.sh" "${TAGS[0]}" "$TOMCAT_VERSION" "$JDK" "$LINE"

# 2. Push by digest, with attestations.
docker buildx build --sbom=true --provenance=mode=max "${ARGS[@]}" \
  --output "type=image,name=$REPO,push-by-digest=true,push=true" --metadata-file "$META" .
DIGEST=$(jq -r '."containerimage.digest"' "$META")
[[ "$DIGEST" == sha256:* ]] || { echo "FAIL: no digest in build metadata" >&2; exit 1; }
PUSHED_REF="$REPO@$DIGEST"

# 3. Compare layers. With attestations the pushed ref is an index, and .Image is keyed by platform.
TESTED=$(docker image inspect --format '{{json .RootFS.Layers}}' "${TAGS[0]}" | jq -c .)
PUSHED=$(docker buildx imagetools inspect "$PUSHED_REF" --format '{{json .Image}}' \
  | jq -c 'if has("rootfs") then .rootfs.diff_ids else (to_entries | map(.value.rootfs.diff_ids) | .[0]) end')
if [[ "$PUSHED" != "$TESTED" ]]; then
  echo "FAIL: $PUSHED_REF layers differ from the tested image. No tags were changed." >&2
  exit 1
fi
echo "ok - pushed $PUSHED_REF, layers match tested image"

# 4. Tag.
TAG_ARGS=()
for t in "${TAGS[@]}"; do TAG_ARGS+=(-t "$t"); done
docker buildx imagetools create "${TAG_ARGS[@]}" "$PUSHED_REF"
for t in "${TAGS[@]}"; do
  [[ "$(docker buildx imagetools inspect "$t" --format '{{json .Manifest}}' | jq -r .digest)" == "$DIGEST" ]] \
    || { echo "FAIL: $t does not point at $DIGEST" >&2; exit 1; }
  echo "ok - tagged $t"
done
