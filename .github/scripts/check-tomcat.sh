#!/usr/bin/env bash
# Checks the official tomcat images for updates to the versions pinned in tomcat-versions.json,
# and flags repo inactivity. Run daily by .github/workflows/checkTomcat.yml. Outcomes, each
# idempotent:
#
#  1. A newer patch on a pinned line, published for every JDK we build on that line, opens a PR
#     to develop. It bumps tomcat-versions.json and the README table, and adds a CHANGELOG line.
#     All lines with a newer patch go in one PR. Skipped if a PR in any state already exists for
#     that set of versions. A new PR closes older open bump PRs, which it supersedes.
#  2. Upstream rebuilds its tomcat images for JDK and Ubuntu updates without a Tomcat version
#     change. If the upstream image for a pinned version is no longer the base of our latest-*
#     image, a PR to develop adds a CHANGELOG note, to prompt a release. The branch is keyed on
#     all our latest-* images and the note, so before a release only a new upstream JDK opens a
#     new PR, which closes the old one. Open refresh PRs close once our images are current.
#     While a release is already due (develop pins a version or variant no release has yet),
#     only a JDK not yet in the CHANGELOG opens a refresh PR, as that release picks up the newest
#     images anyway. A bump PR from 1 notes JDK changes itself and closes open refresh PRs. While
#     it is open, a later JDK update is added to its CHANGELOG note.
#  3. A newer Tomcat line (next minor of a tracked line, or the next major) opens an issue.
#  4. A newer LTS JDK for a tracked line opens an issue. Moving lines or JDKs is a judgment
#     call, so 3 and 4 are never automated.
#  5. No commit on develop for INACTIVITY_WARN_DAYS opens an issue. GitHub disables scheduled
#     workflows in public repos after 60 days without activity, including this one.
#
# Env: GH_TOKEN (for gh - in CI, an XH Build Bot token so its PRs and issues show as that bot),
# DRY_RUN=1 to print actions instead of taking them. For testing, with DRY_RUN=1:
# PINNED_OVERRIDE (e.g. "tc10=10.1.60 tc11=11.0.27") overrides pinned versions, COMPARE_RELEASE
# (e.g. 4.2.0) compares upstream against that release's tags instead of latest-*, and
# INACTIVITY_WARN_DAYS sets the idle threshold. Needs docker with buildx.
set -euo pipefail

INACTIVITY_WARN_DAYS=${INACTIVITY_WARN_DAYS:-45}
DRY_RUN=${DRY_RUN:-0}
COMPARE_RELEASE=${COMPARE_RELEASE:-latest}
VERSIONS=tomcat-versions.json
REPO=xhio/xh-tomcat
HUB=https://hub.docker.com/v2/repositories/library/tomcat/tags
BRANCH_PREFIX=tomcat-bump-
REFRESH_PREFIX=base-refresh-
REFRESH_NOTE_PREFIX="* Rebuilt on the latest upstream \`tomcat\` images"
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

# Numbers of open issues with this exact title. Call it as `x=$(open_issues t) || exit 1`.
open_issues() {
    gh issue list --state open --search "in:title \"$1\"" --json number,title \
        --jq ".[] | select(.title == \"$1\") | .number" \
        || { echo "::error::Could not list issues titled $1" >&2; return 1; }
}

open_issue_once() { # Args: title, body. Skips if an open issue already has this title.
    local found
    found=$(open_issues "$1") || exit 1
    if [ -n "$found" ]; then
        log "Issue already open: $1"
    else
        act gh issue create --title "$1" --body "$2"
    fi
}

# Tomcat and JDK versions and rootfs layers of an image's linux/amd64 variant, as JSON. Returns 1
# on any error, so a registry problem is never read as "no change".
image_info() {
    local out
    out=$(docker buildx imagetools inspect "$1" --format '{{json .Image}}') \
        || { echo "::error::Could not inspect $1" >&2; return 1; }
    jq -ce 'def envvar($k): ([.config.Env[] | select(startswith($k + "="))][0] // "") | ltrimstr($k + "=");
        (if has("rootfs") then . else (.["linux/amd64"] // error("no linux/amd64 image")) end)
        | {tomcat: (envvar("TOMCAT_VERSION") | select(. != "") // error("no TOMCAT_VERSION")),
           jdk: (envvar("JAVA_VERSION") | ltrimstr("jdk-")),
           layers: (.rootfs.diff_ids | arrays // error("no layers"))}' <<<"$out" \
        || { echo "::error::Unexpected image config for $1" >&2; return 1; }
}

# True if our repo has this tag, false if not. Any other answer fails the run.
our_tag_exists() {
    local code
    code=$(curl -s --retry 3 -o /dev/null -w '%{http_code}' "https://hub.docker.com/v2/repositories/$REPO/tags/$1")
    case $code in
        200) return 0 ;;
        404) return 1 ;;
        *) echo "::error::Docker Hub returned $code for $REPO:$1" >&2; exit 1 ;;
    esac
}

# Short JDK version for notes: without the build number, unless only the build number changed.
# Args: our version, upstream version.
jdk_label() {
    if [ "${1%%+*}" = "${2%%+*}" ]; then echo "$2"; else echo "${2%%+*}"; fi
}

# Base refresh notes in the CHANGELOG's `## next` section, one per line, with any wrapped
# continuation lines joined back on. Arg: CHANGELOG file, default CHANGELOG.md.
next_refresh_notes() {
    PREFIX=$REFRESH_NOTE_PREFIX awk '
        /^## / { in_next = ($0 ~ /^## next/) }
        cur != "" && /^  \* / { next }
        cur != "" && /^  [^ *]/ { sub(/^ +/, ""); cur = cur " " $0; next }
        cur != "" { print cur; cur = "" }
        in_next && index($0, ENVIRON["PREFIX"]) == 1 { cur = $0 }
        END { if (cur != "") print cur }' "${1:-CHANGELOG.md}"
}

# Add notes ($1, newline-terminated) at the top of the CHANGELOG's `## next` section, creating it
# if needed. If the notes include a base refresh note, it replaces any earlier one there, so only
# the latest one stays.
changelog_add() {
    if ! grep -q '^## next' CHANGELOG.md; then
        awk 'done != 1 && /^## / { print "## next - under development"; print ""; print ""; done = 1 } { print }' \
            CHANGELOG.md >CHANGELOG.md.new
        mv CHANGELOG.md.new CHANGELOG.md
    fi
    # Values go in via the environment, as `awk -v` rejects multi-line values on some awks.
    NOTES=$1 PREFIX=$REFRESH_NOTE_PREFIX awk '
        BEGIN { p = ENVIRON["PREFIX"]; strip = index(ENVIRON["NOTES"], p) > 0 }
        /^## / { in_next = ($0 ~ /^## next/); skip = 0 }
        skip && /^  / { next }
        { skip = 0 }
        after_head { after_head = 0; if ($0 == "") next }
        strip && in_next && index($0, p) == 1 { skip = 1; next }
        done != 1 && /^## next/ { print; print ""; printf "%s", ENVIRON["NOTES"]; done = 1; after_head = 1; next }
        { print }' CHANGELOG.md >CHANGELOG.md.new
    mv CHANGELOG.md.new CHANGELOG.md
}

# Commit the working tree changes as the XH Build Bot app's bot user. The email is GitHub's
# noreply form, <user id>+<login>, which links the commit to that account (id from
# `gh api 'users/xh-build-bot[bot]'`). Arg: message.
bot_commit() {
    act git -c user.name="xh-build-bot[bot]" \
        -c user.email="324593885+xh-build-bot[bot]@users.noreply.github.com" \
        commit -am "$1"
}

# Commit the working tree changes to a new branch as the bot, push it, open a PR to develop, and
# close open PRs from older branches with any of the given prefixes, which it supersedes.
# Args: branch, title, body, prefix...
open_pr() {
    local branch=$1 title=$2 body=$3 exists=0
    shift 3
    git ls-remote --exit-code --heads origin "$branch" >/dev/null && exists=1
    act git checkout -b "$branch"
    bot_commit "$title"
    if [ $exists = 1 ]; then
        # A past run pushed the branch but failed to open the PR. It's the bot's own branch,
        # rebuilt from develop, so replace it.
        log "Branch $branch exists with no PR - replacing it."
        act git push --force origin "$branch"
    else
        act git push origin "$branch"
    fi
    act gh pr create --base develop --head "$branch" --title "$title" --body "$body"
    close_superseded "$branch" "$@"

    if [ "$DRY_RUN" = "1" ]; then
        log "DRY_RUN: PR title: $title"
        log "DRY_RUN: PR body:"$'\n'"$body"
        git --no-pager diff
        git checkout -- "$VERSIONS" README.md CHANGELOG.md
        # Confirm the token can push, without creating anything.
        git push --dry-run --force origin "HEAD:refs/heads/$branch"
    fi
}

# Head branches of open PRs to develop that start with $1. Call it as
# `x=$(open_pr_branches p) || exit 1`, so a gh failure fails the run.
open_pr_branches() {
    gh pr list --state open --base develop --limit 500 --json headRefName \
        --jq ".[] | select(.headRefName | startswith(\"$1\")) | .headRefName" \
        || { echo "::error::Could not list open PRs" >&2; return 1; }
}

# Close open PRs from other branches with any of the given prefixes. The PR from this branch is
# built from develop, so it includes their changes. Args: branch, prefix...
close_superseded() {
    local branch=$1 prefix old olds
    shift
    for prefix in "$@"; do
        olds=$(open_pr_branches "$prefix") || exit 1
        for old in $olds; do
            [ "$old" = "$branch" ] && continue
            act gh pr close "$old" --delete-branch --comment "Superseded by the PR from \`$branch\`."
        done
    done
}

# True if every closed PR from this branch was closed by this script as superseded, not by a person.
only_superseded() {
    local out
    out=$(gh pr list --state closed --head "$1" --json comments \
        --jq 'all(.[]; any(.comments[]; (.body | startswith("Superseded by"))
            and (.author.login | test("^(app/)?xh-build-bot(\\[bot\\])?$"))))') \
        || { echo "::error::Could not read PR comments for $1" >&2; exit 1; }
    [ "$out" = true ]
}

# States of the PRs with this head branch, comma-separated, or empty if none. Call it as
# `x=$(pr_states b) || exit 1`, so a gh failure fails the run instead of reading as "no PR".
pr_states() {
    local states
    states=$(gh pr list --state all --head "$1" --json state --jq '.[].state') \
        || { echo "::error::Could not list PRs for $1" >&2; return 1; }
    grep . <<<"$states" | sort -u | paste -sd, - || true
}

# JDK versions in a base refresh note in `## next`, from a merged PR waiting for a release, one
# per line. New notes keep them, so a later note doesn't drop them from the release notes.
# Arg: CHANGELOG file, default CHANGELOG.md.
next_note_jdks() {
    next_refresh_notes "$@" | sed -n 's/.*JDK updates (\(.*\))\.$/\1/p' | tr ',' '\n' | tr -d '` ' | grep . || true
}

# Add JDK versions to an open bump PR's CHANGELOG note, if upstream has newer JDKs than it lists.
# Pushes a commit to the PR's branch. Args: branch, JDK versions the release will ship.
update_bump_note() {
    local branch=$1 want=$2 changelog have new start
    git fetch -q origin "$branch" || { echo "::error::Could not fetch $branch" >&2; exit 1; }
    changelog=$(git show FETCH_HEAD:CHANGELOG.md) || exit 1
    have=$(next_note_jdks <(printf '%s\n' "$changelog"))
    new=$(newest_jdks "$want" | grep -vxF -f <(printf '%s\n' "$have") || true)
    [ -n "$new" ] || return 0
    log "Upstream JDK updates since $branch opened: $(paste -sd' ' - <<<"$new")"
    start=$(git symbolic-ref -q --short HEAD || git rev-parse HEAD)
    git checkout -q -B "$branch" FETCH_HEAD
    changelog_add "$(refresh_note "$have"$'\n'"$want")"$'\n'
    if git diff --quiet; then
        log "The note on $branch already covers them."
        git checkout -q "$start"
        return 0
    fi
    bot_commit "Note upstream JDK updates: $(paste -sd' ' - <<<"$new")"
    act git push origin "$branch"
    if [ "$DRY_RUN" = "1" ]; then
        git --no-pager diff
        git checkout -- CHANGELOG.md
        git push --dry-run origin "HEAD:refs/heads/$branch"
    fi
    git checkout -q "$start"
}

# The newest of these JDK versions for each major, one per line. A release ships only that one.
newest_jdks() {
    { grep . <<<"$1" || true; } | sort -V | awk -F. '{ last[$1] = $0 } END { for (m in last) print last[m] }' | sort -V
}

# CHANGELOG note for a base image refresh. Arg: JDK versions, one per line, maybe none.
refresh_note() {
    local list
    list=$(newest_jdks "$1" | sed 's/.*/`&`/' | paste -sd, - | sed 's/,/, /g' || true)
    if [ -n "$list" ]; then
        echo "$REFRESH_NOTE_PREFIX, with JDK updates ($list)."
    else
        echo "$REFRESH_NOTE_PREFIX (OS and package updates, no JDK change)."
    fi
}

#-----------------------------------------------------------------------------------------------
if { [ -n "${PINNED_OVERRIDE:-}" ] || [ "$COMPARE_RELEASE" != "latest" ]; } && [ "$DRY_RUN" != "1" ]; then
    echo "::error::PINNED_OVERRIDE and COMPARE_RELEASE are for testing and require a dry run"
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

# 2. Base images. For each variant, compare our latest-* image with the upstream image of the
# pinned version. Our image is built FROM upstream, so while upstream is unchanged our layers start
# with its layers. For a line with a bump, also note any JDK change in the new version's images.
STALE=""        # One "variant our-jdk upstream-jdk" line per variant whose upstream was rebuilt.
DUE_ROWS=""     # The same, for variants with a release due whose upstream has a newer JDK.
OUR_LAYERS=""   # Top layer of each of our images checked, to key the refresh branch.
REFRESH_JDKS="" # JDK versions in upstream images of pinned versions that are newer than ours.
BUMP_JDKS=""    # JDK versions in bumped versions' images that are newer than ours.
RELEASE_DUE=0   # Set if develop pins a Tomcat version or variant no release has yet.
for line in $LINES; do
    pin=$(pinned "$line")
    bump_to=""
    for b in ${BUMPS[@]+"${BUMPS[@]}"}; do
        read -r bline _ bto <<<"$b"
        if [ "$bline" = "$line" ]; then bump_to=$bto; fi
    done
    for jdk in $(jdks "$line"); do
        variant=$line-$jdk
        if ! our_tag_exists "$COMPARE_RELEASE-$variant"; then
            # A line or JDK added since the last release.
            log "$variant: no $COMPARE_RELEASE tag yet, skipping its base image check. A release is due."
            RELEASE_DUE=1
            continue
        fi
        OURS=$(image_info "$REPO:$COMPARE_RELEASE-$variant") || exit 1
        our_jdk=$(jq -r .jdk <<<"$OURS")
        our_tomcat=$(jq -r .tomcat <<<"$OURS")
        if [ -n "$bump_to" ]; then
            BUMP_UP=$(image_info "tomcat:$bump_to-$jdk") || exit 1
            bump_jdk=$(jq -r .jdk <<<"$BUMP_UP")
            if newer "$our_jdk" "$bump_jdk"; then BUMP_JDKS+="$(jdk_label "$our_jdk" "$bump_jdk")"$'\n'; fi
        fi
        OUR_LAYERS+="$(jq -r '.layers[-1]' <<<"$OURS")"$'\n'
        UP=$(image_info "tomcat:$pin-$jdk") || exit 1
        up_jdk=$(jq -r .jdk <<<"$UP")
        if [ "$our_tomcat" != "$pin" ]; then
            # tomcat-versions.json has moved on since the release, e.g. a merged bump PR. The next
            # release builds on the newest images anyway. Only a JDK change may need a note.
            log "$variant: $COMPARE_RELEASE has Tomcat $our_tomcat, develop pins $pin. A release is due."
            RELEASE_DUE=1
            if newer "$our_jdk" "$up_jdk"; then
                DUE_ROWS+="$variant $our_jdk $up_jdk"$'\n'
                REFRESH_JDKS+="$(jdk_label "$our_jdk" "$up_jdk")"$'\n'
            fi
        elif jq -en --argjson u "$UP" --argjson o "$OURS" '$o.layers[0:($u.layers | length)] == $u.layers' >/dev/null; then
            log "$variant: $COMPARE_RELEASE is built on the current tomcat:$pin-$jdk (JDK $our_jdk)"
        else
            log "$variant: tomcat:$pin-$jdk has been rebuilt since $COMPARE_RELEASE (JDK $our_jdk -> $up_jdk)"
            STALE+="$variant $our_jdk $up_jdk"$'\n'
            if newer "$our_jdk" "$up_jdk"; then REFRESH_JDKS+="$(jdk_label "$our_jdk" "$up_jdk")"$'\n'; fi
        fi
    done
done

PENDING_JDKS=$(next_note_jdks)

# An open bump PR holds back refresh PRs. Its release picks up the newest images too.
BUMP_PENDING=0
if [ ${#BUMPS[@]} -gt 0 ]; then
    BRANCH=$BRANCH_PREFIX$(for b in "${BUMPS[@]}"; do echo "${b##* }"; done | paste -sd- -)
    STATES=$(pr_states "$BRANCH") || exit 1
    if [ -n "$STATES" ]; then
        # Open: keep its JDK note current. Closed or merged: someone decided, so don't reopen it.
        log "PR for $BRANCH already exists ($STATES)."
        case $STATES in *OPEN*)
            BUMP_PENDING=1
            # In case a past run opened it but failed to close the PRs it supersedes.
            close_superseded "$BRANCH" "$BRANCH_PREFIX" "$REFRESH_PREFIX"
            update_bump_note "$BRANCH" "$BUMP_JDKS$REFRESH_JDKS$PENDING_JDKS" ;;
        esac
    else
        BUMP_PENDING=1
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

        # The new images also carry any upstream JDK update, which is worth its own note.
        NOTE_JDKS=$BUMP_JDKS$REFRESH_JDKS
        if [ -n "$(grep . <<<"$NOTE_JDKS" || true)" ]; then
            NOTES+="$(refresh_note "$NOTE_JDKS$PENDING_JDKS")"$'\n'
            BODY_LINES+="- Upstream JDK updates: $(newest_jdks "$NOTE_JDKS" | paste -sd, - | sed 's/,/, /g')."$'\n'
        fi
        changelog_add "$NOTES"

        BODY="Bumps the pinned Tomcat versions in \`tomcat-versions.json\`:

$BODY_LINES
Each new version is published for every JDK we build on its line. The base images also carry the latest upstream
JDK and Ubuntu updates.

Merging rebuilds the \`next-*\` tags. To publish it, release from \`master\` as usual.

$FOOTER"
        # A bump release also picks up any newer base, so it supersedes refresh PRs too.
        open_pr "$BRANCH" "$TITLE" "$BODY" "$BRANCH_PREFIX" "$REFRESH_PREFIX"
    fi
fi

# JDKs a due release would ship that `## next` does not list yet.
UNNOTED_JDKS=$(newest_jdks "$REFRESH_JDKS" | grep -vxF -f <(printf '%s\n' "$PENDING_JDKS") || true)

if [ $BUMP_PENDING = 1 ]; then
    : # The bump PR notes JDK changes and closes refresh PRs.
elif [ $RELEASE_DUE = 1 ] && [ -z "$UNNOTED_JDKS" ]; then
    # A due release rebuilds every variant on the newest images, so OS updates need no PR.
    if [ -n "$STALE" ]; then log "Upstream images were rebuilt, but a release is already due. It will pick them up."; fi
elif [ -n "$STALE$UNNOTED_JDKS" ]; then
    REFRESH_NOTE=$(refresh_note "$REFRESH_JDKS$PENDING_JDKS")
    # Keyed on all our images and the note. A new release or a new JDK gets a new PR, while more
    # upstream rebuilds before a release, on any variant, don't churn the open one.
    BRANCH=$REFRESH_PREFIX$(printf '%s\n%s\n' "$OUR_LAYERS" "$REFRESH_NOTE" | git hash-object --stdin | cut -c1-10)
    STATES=$(pr_states "$BRANCH") || exit 1
    if [ "$STATES" = CLOSED ] && only_superseded "$BRANCH"; then
        # Closed by a bump PR that was then closed without merging. Nobody declined this refresh.
        log "PR for $BRANCH was superseded by a PR that is now closed. Opening it again."
        STATES=""
    fi
    if [ -n "$STATES" ]; then
        log "PR for $BRANCH already exists ($STATES)."
        case $STATES in *OPEN*) close_superseded "$BRANCH" "$REFRESH_PREFIX" ;; esac
    elif next_refresh_notes | grep -qxF "$REFRESH_NOTE"; then
        # A merged refresh PR is waiting for a release, which will build on the newest images.
        log "The CHANGELOG already has \"$REFRESH_NOTE\". A release is due."
    else
        changelog_add "$REFRESH_NOTE"$'\n'
        JDK_VERSIONS=$(newest_jdks "$REFRESH_JDKS")
        if [ -n "$JDK_VERSIONS" ]; then
            TITLE="Refresh base images: JDK $(paste -sd/ - <<<"$JDK_VERSIONS" | sed 's#/# / #g')"
        else
            TITLE="Refresh base images: upstream OS updates"
        fi
        ROWS=$(while read -r variant ours up; do
            if [ -n "$variant" ]; then echo "| \`$variant\` | \`$ours\` | \`$up\` |"; fi
        done <<<"$STALE$DUE_ROWS")
        BODY="Our next release builds on upstream \`tomcat\` images that are newer than our \`$COMPARE_RELEASE-*\` images:

| Variant | JDK in \`$COMPARE_RELEASE-*\` | JDK upstream |
|---------|---------|---------|
$ROWS

Merging adds a CHANGELOG note. To ship the update, merge \`develop\` to \`master\` and release a new patch version as
usual. A release rebuilds every variant on the newest upstream images.

$FOOTER"
        open_pr "$BRANCH" "$TITLE" "$BODY" "$REFRESH_PREFIX"
    fi
elif [ $RELEASE_DUE = 0 ] && [ -z "$STALE" ] && [ -n "$OUR_LAYERS" ]; then
    # Our images are current, e.g. after a release, so an open refresh PR's note is now wrong.
    OLDS=$(open_pr_branches "$REFRESH_PREFIX") || exit 1
    for old in $OLDS; do
        act gh pr close "$old" --delete-branch --comment "Our \`$COMPARE_RELEASE-*\` images are built on the current upstream images. Closing."
    done
fi

# 3. Newer Tomcat lines: the next minor of each tracked line, and the next major.
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

# 4. Newer LTS JDK for a tracked line. Java LTS releases come every two years: 17, 21, 25, 29...
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

# 5. Inactivity warning.
LAST_COMMIT=$(git log -1 --format=%ct origin/develop 2>/dev/null || git log -1 --format=%ct)
AGE_DAYS=$(( ($(date +%s) - LAST_COMMIT) / 86400 ))
log "Last commit on develop: $AGE_DAYS days ago"
IDLE_TITLE="Scheduled workflows go idle soon"
if [ "$AGE_DAYS" -lt "$INACTIVITY_WARN_DAYS" ]; then
    # Close a past warning once develop is active again, so the next idle spell alerts afresh.
    IDLE_ISSUES=$(open_issues "$IDLE_TITLE") || exit 1
    for n in $IDLE_ISSUES; do
        act gh issue close "$n" --comment "\`develop\` has a commit from $AGE_DAYS days ago. Closing."
    done
else
    open_issue_once "$IDLE_TITLE" \
        "There has been no commit on \`develop\` for $AGE_DAYS days. GitHub disables scheduled workflows in public repos after 60 days without activity. That would stop the weekly \`next-*\` rebuild and this check.

To reset the clock, merge or push any commit to \`develop\`. If they were already disabled, re-enable them with \`gh workflow enable buildNext.yml\` and \`gh workflow enable checkTomcat.yml\`.

$FOOTER"
fi
