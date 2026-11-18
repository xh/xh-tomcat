#!/usr/bin/env bash
# Checks the official tomcat images for updates to the versions pinned in tomcat-versions.json,
# and flags repo inactivity. Run daily by .github/workflows/checkTomcat.yml. Outcomes, each
# idempotent:
#
#  1. A newer patch on a pinned line, published for every JDK we build on that line, opens a PR
#     to develop. It bumps tomcat-versions.json and the README table, and adds a CHANGELOG line.
#     All lines with a newer patch go in one PR. Skipped if a branch for that set of versions
#     already exists. A new PR closes older open bump PRs, which it supersedes.
#  2. A newer Tomcat line (next minor of a tracked line, or the next major) opens an issue.
#  3. A newer LTS JDK for a tracked line opens an issue. Moving lines or JDKs is a judgment
#     call, so 2 and 3 are never automated.
#  4. No commit on develop for INACTIVITY_WARN_DAYS opens an issue. GitHub disables scheduled
#     workflows in public repos after 60 days without activity, including this one.
#
# Env: GH_TOKEN (for gh - in CI, an XH Build Bot token so its PRs and issues show as that bot),
# DRY_RUN=1 to print actions instead of taking them. For testing, PINNED_OVERRIDE (e.g.
# "tc10=10.1.60 tc11=11.0.27") overrides pinned versions and INACTIVITY_WARN_DAYS the idle
# threshold.
set -euo pipefail

INACTIVITY_WARN_DAYS=${INACTIVITY_WARN_DAYS:-45}
DRY_RUN=${DRY_RUN:-0}
VERSIONS=tomcat-versions.json
HUB=https://hub.docker.com/v2/repositories/library/tomcat/tags
BRANCH_PREFIX=tomcat-bump-
FOOTER="Opened by the Check Tomcat workflow."

log() { echo "$*" >&2; }
act() { # Run a command, or just print it in a dry run.
    if [ "$DRY_RUN" = "1" ]; then log "DRY_RUN: $*"; else "$@"; fi
}
newer() { # True if version $2 is newer than $1.
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
}

# Tomcat tag names containing "<major.minor>.", most recently updated first. Docker Hub serves
# at most 10 pages (1000 tags) and refuses later pages, so stop there. Busy lines have more tags
# than that, but upstream rebuilds its current tags often, so the newest patches are always in the
# first pages. Fails on any other error, so a Docker Hub outage never reads as "no update".
line_tags() {
    local url="$HUB?page_size=100&ordering=last_updated&name=$1." page n=0
    while [ -n "$url" ] && [ "$url" != "null" ] && [ $n -lt 10 ]; do
        page=$(curl -fsS --retry 3 "$url") || { echo "::error::Docker Hub request failed: $url" >&2; return 1; }
        # Checked explicitly: callers run this where `set -e` is off.
        jq -er '.results | arrays | .[].name' <<<"$page" \
            || { [ "$(jq -r '.results | length' <<<"$page" 2>/dev/null)" = "0" ] \
                 || { echo "::error::Unexpected Docker Hub response: $url" >&2; return 1; }; }
        url=$(jq -r '.next' <<<"$page") || return 1
        n=$((n + 1))
    done
}

# X.Y.Z versions in a tag list for one JDK. Args: tags, major.minor, jdk.
jdk_versions() {
    grep -E "^${2//./\\.}\\.[0-9]+-$3$" <<<"$1" | sed "s/-$3$//" | sort -u || true
}

# Newest X.Y.Z in a tag list published for every given JDK. Args: tags, major.minor, jdk...
newest_common() {
    local tags=$1 minor=$2 common="" first=1
    shift 2
    for jdk in "$@"; do
        local versions
        versions=$(jdk_versions "$tags" "$minor" "$jdk")
        if [ $first = 1 ]; then common=$versions; first=0; else common=$(comm -12 <(echo "$common") <(echo "$versions")); fi
    done
    sort -V <<<"$common" | grep . | tail -1 || true
}

# True if the line has a GA X.Y.Z release for any JDK. Milestone builds (-M1) do not count.
line_released() {
    local tags
    tags=$(line_tags "$1") || exit 1
    grep -qE "^${1//./\\.}\\.[0-9]+-jdk[0-9]+$" <<<"$tags"
}

tag_exists() { # 200 is true, 404 is false, anything else fails the run.
    local code
    code=$(curl -s --retry 3 -o /dev/null -w '%{http_code}' "$HUB/$1")
    case $code in
        200) return 0 ;;
        404) return 1 ;;
        *) echo "::error::Docker Hub returned $code for tag $1" >&2; exit 1 ;;
    esac
}

# CVEs listed on Tomcat's security page for versions after $1, up to and including $2. Returns 1
# if the page can't be fetched or has no entries for the line, so an outage or a page redesign is
# never reported as "no CVEs".
tomcat_cves() {
    local from=$1 to=$2 page
    page=$(curl -fsS --retry 3 "https://tomcat.apache.org/security-${to%%.*}.html") || return 1
    grep -qF "Fixed in Apache Tomcat ${to%.*}." <<<"$page" || return 1
    awk '{ gsub(/Fixed in Apache Tomcat /, "\n@@FIXED ") } 1' <<<"$page" \
        | awk '/^@@FIXED /{ split($2, a, "<"); v = a[1] }
               v { while (match($0, /CVE-[0-9]+-[0-9]+/)) { print v, substr($0, RSTART, RLENGTH); $0 = substr($0, RSTART + RLENGTH) } }' \
        | sort -u \
        | while read -r v cve; do
            [ "${v%.*}" = "${to%.*}" ] && newer "$from" "$v" && ! newer "$to" "$v" && echo "$cve"
          done | sort -u || true
}

open_issue_once() { # Args: title, body. Skips if an open issue already has this title.
    if [ -n "$(gh issue list --state open --search "in:title \"$1\"" --json title \
            --jq ".[] | select(.title == \"$1\") | .title")" ]; then
        log "Issue already open: $1"
    else
        act gh issue create --title "$1" --body "$2"
    fi
}

#-----------------------------------------------------------------------------------------------
if [ -n "${PINNED_OVERRIDE:-}" ] && [ "$DRY_RUN" != "1" ]; then
    echo "::error::PINNED_OVERRIDE is for testing and requires a dry run"
    exit 1
fi

LINES=$(jq -r '.[].line' "$VERSIONS")
[ -n "$LINES" ] || { echo "::error::No lines in $VERSIONS"; exit 1; }
pinned() {
    local override
    override=$(tr ' ' '\n' <<<"${PINNED_OVERRIDE:-}" | sed -n "s/^$1=//p")
    if [ -n "$override" ]; then echo "$override"; else jq -r --arg l "$1" '.[] | select(.line == $l) | .version' "$VERSIONS"; fi
}
jdks() { jq -r --arg l "$1" '.[] | select(.line == $l) | .jdks[]' "$VERSIONS"; }

# 1. Newer patches on pinned lines.
BUMPS=()
for line in $LINES; do
    PINNED=$(pinned "$line")
    MINOR=${PINNED%.*}
    TAGS=$(line_tags "$MINOR")
    # shellcheck disable=SC2046
    LATEST=$(newest_common "$TAGS" "$MINOR" $(jdks "$line"))
    log "$line: pinned $PINNED, newest for all its JDKs ${LATEST:-none}"
    if [ -z "$LATEST" ]; then
        echo "::error::No $MINOR.x release found for all $line JDKs. Check Docker Hub and tomcat-versions.json."
        exit 1
    fi
    if newer "$PINNED" "$LATEST"; then BUMPS+=("$line $PINNED $LATEST"); fi

    # A newer patch missing one of our JDKs blocks bumps for the whole line, so flag it.
    OTHER=$(for j in $(jdks "$line"); do jdk_versions "$TAGS" "$MINOR" "$j"; done | sort -V | tail -1)
    for jdk in $(jdks "$line"); do
        if newer "$LATEST" "$OTHER" && ! jdk_versions "$TAGS" "$MINOR" "$jdk" | grep -qx "$OTHER"; then
            open_issue_once "Tomcat $OTHER is not published for $jdk" \
                "The official \`tomcat\` image publishes \`$OTHER\` for some of the JDKs we build on \`$line\`, but not \`$jdk\`. Check Tomcat only bumps when every JDK has the new version, so \`$line\` stays on \`$LATEST\` until this resolves. If upstream has dropped \`$jdk\` for this line, remove it from \`tomcat-versions.json\`.

$FOOTER"
        fi
    done
done

if [ ${#BUMPS[@]} -gt 0 ]; then
    BRANCH=$BRANCH_PREFIX$(for b in "${BUMPS[@]}"; do echo "${b##* }"; done | paste -sd- -)
    BRANCH_EXISTS=0
    git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null && BRANCH_EXISTS=1
    PR_STATES=$(gh pr list --state all --head "$BRANCH" --json state --jq '.[].state' | sort -u | paste -sd, -)
    if [ -n "$PR_STATES" ]; then
        # Open: nothing to do. Closed or merged: someone decided, so don't reopen it daily.
        log "PR for $BRANCH already exists ($PR_STATES)."
    else
        TITLE="Bump Tomcat to $(for b in "${BUMPS[@]}"; do echo "${b##* }"; done | paste -sd/ - | sed 's#/# / #g')"
        NOTES=""
        BODY_LINES=""
        for b in "${BUMPS[@]}"; do
            read -r line from to <<<"$b"
            major=${to%%.*}
            SEC_URL="https://tomcat.apache.org/security-$major.html"
            if CVES=$(tomcat_cves "$from" "$to"); then
                CVE_COUNT=$(grep -c . <<<"$CVES" || true)
            else
                CVES=""
                CVE_COUNT=-1
            fi
            if [ "$CVE_COUNT" -lt 0 ]; then
                NOTE="CVE list unavailable, see the [Tomcat $major security page]($SEC_URL)"
            elif [ "$CVE_COUNT" -gt 0 ]; then
                NOTE="with fixes for $CVE_COUNT CVEs listed on the [Tomcat $major security page]($SEC_URL)"
            else
                NOTE="with no CVEs listed yet on the [Tomcat $major security page]($SEC_URL)"
            fi
            log "Bumping $line $from -> $to, $CVE_COUNT CVEs"
            NOTES+="* Tomcat \`$to\` (from \`$from\`), $NOTE."$'\n'
            BODY_LINES+="- \`$line\`: \`$from\` -> \`$to\`, $NOTE."$'\n'
            if [ "$CVE_COUNT" -gt 0 ]; then BODY_LINES+="  - ${CVES//$'\n'/, }"$'\n'; fi

            # Bump tomcat-versions.json and this line's rows in the README table.
            sed -i.bak -E "s/(\"line\": *\"$line\", *\"version\": *\")[0-9.]+\"/\1$to\"/" "$VERSIONS" && rm "$VERSIONS.bak"
            if [ "$(jq -r --arg l "$line" '.[] | select(.line == $l) | .version' "$VERSIONS")" != "$to" ]; then
                echo "::error::Could not bump $line in $VERSIONS"
                exit 1
            fi
            sed -i.bak -E "/^\| release-$line-/s/${from//./\\.}/$to/g" README.md && rm README.md.bak
            if grep -E "^\| release-$line-" README.md | grep -qF "$from" \
                || ! grep -E "^\| release-$line-" README.md | grep -qF "$to"; then
                echo "::error::Could not bump $line in the README table"
                exit 1
            fi
        done

        # Add the notes at the top of the `## next` section of the CHANGELOG, creating it if needed.
        if ! grep -q '^## next' CHANGELOG.md; then
            awk 'done != 1 && /^## / { print "## next - under development"; print ""; print ""; done = 1 } { print }' \
                CHANGELOG.md >CHANGELOG.md.new
            mv CHANGELOG.md.new CHANGELOG.md
        fi
        # Notes go in via the environment, as `awk -v` rejects multi-line values on some awks.
        NOTES=$NOTES awk '
            done != 1 && /^## next/ { print; getline; print; printf "%s", ENVIRON["NOTES"]; done = 1; next }
            { print }' CHANGELOG.md >CHANGELOG.md.new
        mv CHANGELOG.md.new CHANGELOG.md

        BODY="Bumps the pinned Tomcat versions in \`tomcat-versions.json\`:

$BODY_LINES
Each new version is published for every JDK we build on its line. The base images also carry the latest upstream
JDK and Ubuntu updates.

Merging rebuilds the \`next-*\` tags. To publish it, release from \`master\` as usual.

$FOOTER"
        act git checkout -b "$BRANCH"
        # Commit as the XH Build Bot app's bot user. The email is GitHub's noreply form,
        # <user id>+<login>, which links the commit to that account (id from
        # `gh api 'users/xh-build-bot[bot]'`).
        act git -c user.name="xh-build-bot[bot]" \
            -c user.email="324593885+xh-build-bot[bot]@users.noreply.github.com" \
            commit -am "$TITLE"
        if [ $BRANCH_EXISTS = 1 ]; then
            # A past run pushed the branch but failed to open the PR. It's the bot's own branch,
            # rebuilt from develop, so replace it.
            log "Branch $BRANCH exists with no PR - replacing it."
            act git push --force origin "$BRANCH"
        else
            act git push origin "$BRANCH"
        fi
        act gh pr create --base develop --head "$BRANCH" --title "$TITLE" --body "$BODY"

        # Close older bump PRs. The new PR is built from develop, so it includes their changes.
        for old in $(gh pr list --state open --base develop --json headRefName \
                --jq ".[] | select(.headRefName | startswith(\"$BRANCH_PREFIX\")) | .headRefName"); do
            [ "$old" = "$BRANCH" ] && continue
            act gh pr close "$old" --delete-branch --comment "Superseded by the PR from \`$BRANCH\`."
        done

        if [ "$DRY_RUN" = "1" ]; then
            log "DRY_RUN: PR title: $TITLE"
            log "DRY_RUN: PR body:"$'\n'"$BODY"
            git --no-pager diff
            git checkout -- "$VERSIONS" README.md CHANGELOG.md
            # Confirm the token can push, without creating anything.
            git push --dry-run --force origin "HEAD:refs/heads/$BRANCH"
        fi
    fi
fi

# 2. Newer Tomcat lines: the next minor of each tracked line, and the next major.
TRACKED=$(for line in $LINES; do v=$(pinned "$line"); echo "${v%.*}"; done | sort -uV)
TOP_MAJOR=$(tail -1 <<<"$TRACKED" | cut -d. -f1)
CANDIDATES=$( (while read -r m; do echo "${m%.*}.$(( ${m#*.} + 1 ))"; done <<<"$TRACKED"; echo "$((TOP_MAJOR + 1)).0") | sort -uV)
for cand in $CANDIDATES; do
    grep -qx "$cand" <<<"$TRACKED" && continue
    if line_released "$cand"; then
        log "Newer Tomcat line available: $cand"
        open_issue_once "Tomcat $cand is available" \
            "The official \`tomcat\` image now publishes Tomcat \`$cand\` releases. We track $(paste -sd, - <<<"$TRACKED" | sed 's/,/, /g'). Adding a line is a manual change: add it to \`tomcat-versions.json\`, add a \`conf/\` \`server.xml\` for it, and test.

$FOOTER"
    fi
done

# 3. Newer LTS JDK for a tracked line. Java LTS releases come every two years: 17, 21, 25, 29...
for line in $LINES; do
    v=$(pinned "$line")
    top=$(jdks "$line" | sed 's/^jdk//' | sort -n | tail -1)
    next_lts="jdk$((top + 4))"
    if tag_exists "${v%.*}-$next_lts"; then
        log "$line: $next_lts available"
        open_issue_once "Tomcat ${v%.*} is available on JDK ${next_lts#jdk}" \
            "The official \`tomcat\` image now publishes \`${v%.*}-$next_lts\`. We build \`$line\` for $(jdks "$line" | paste -sd, - | sed 's/,/, /g'). Adding a JDK is a manual change: add it to \`tomcat-versions.json\` and the README table, and test.

$FOOTER"
    fi
done

# 4. Inactivity warning.
LAST_COMMIT=$(git log -1 --format=%ct origin/develop 2>/dev/null || git log -1 --format=%ct)
AGE_DAYS=$(( ($(date +%s) - LAST_COMMIT) / 86400 ))
log "Last commit on develop: $AGE_DAYS days ago"
IDLE_TITLE="Scheduled workflows go idle soon"
if [ "$AGE_DAYS" -lt "$INACTIVITY_WARN_DAYS" ]; then
    # Close a past warning once develop is active again, so the next idle spell alerts afresh.
    for n in $(gh issue list --state open --search "in:title \"$IDLE_TITLE\"" --json number,title \
            --jq ".[] | select(.title == \"$IDLE_TITLE\") | .number"); do
        act gh issue close "$n" --comment "\`develop\` has a commit from $AGE_DAYS days ago. Closing."
    done
else
    open_issue_once "$IDLE_TITLE" \
        "There has been no commit on \`develop\` for $AGE_DAYS days. GitHub disables scheduled workflows in public repos after 60 days without activity. That would stop the weekly \`next-*\` rebuild and this check.

To reset the clock, merge or push any commit to \`develop\`. If they were already disabled, re-enable them with \`gh workflow enable buildNext.yml\` and \`gh workflow enable checkTomcat.yml\`.

$FOOTER"
fi
