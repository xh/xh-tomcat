# Hoist Dockerfile: xh-tomcat

[Hoist React](https://github.com/exhi/hoist-react/) apps can be deployed via Docker containers running Tomcat (for
Hoist's Grails based back-end) and nginx (to serve compiled client JS/CSS and other assets).

This repo contains a minimal Dockerfile to build the base Tomcat container, which can be used by app-specific Docker
deployments with additional configurations.

## Tomcat versions, JDK versions and Docker tags

 Images are published to Docker Hub as [`xhio/xh-tomcat`](https://hub.docker.com/r/xhio/xh-tomcat), producing the
variants below.

| Variant            | Tomcat  | JDK | Source base image      | Docker tag(s)                           |
|--------------------|:-------:|:---:|------------------------|-----------------------------------------|
| next-tc10-jdk17    |  10.1   | 17  | `tomcat:10.1-jdk17`    | `next-tc10-jdk17`                       |
| next-tc10-jdk21    |  10.1   | 21  | `tomcat:10.1-jdk21`    | `next-tc10-jdk21`                       |
| next-tc10-jdk25    |  10.1   | 25  | `tomcat:10.1-jdk25`    | `next-tc10-jdk25`                       |
| next-tc11-jdk21    |  11.0   | 21  | `tomcat:11.0-jdk21`    | `next-tc11-jdk21`                       |
| next-tc11-jdk25    |  11.0   | 25  | `tomcat:11.0-jdk25`    | `next-tc11-jdk25`                       |
| release-tc10-jdk17 | 10.1.62 | 17  | `tomcat:10.1.62-jdk17` | `latest-tc10-jdk17`, `4.2.1-tc10-jdk17` |
| release-tc10-jdk21 | 10.1.62 | 21  | `tomcat:10.1.62-jdk21` | `latest-tc10-jdk21`, `4.2.1-tc10-jdk21` |
| release-tc10-jdk25 | 10.1.62 | 25  | `tomcat:10.1.62-jdk25` | `latest-tc10-jdk25`, `4.2.1-tc10-jdk25` |
| release-tc11-jdk21 | 11.0.29 | 21  | `tomcat:11.0.29-jdk21` | `latest-tc11-jdk21`, `4.2.1-tc11-jdk21` |
| release-tc11-jdk25 | 11.0.29 | 25  | `tomcat:11.0.29-jdk25` | `latest-tc11-jdk25`, `4.2.1-tc11-jdk25` |

Tomcat 11 is required by Hoist apps on Grails 8+ (Spring Boot 4 / Servlet 6.1), which also require JDK 21+, so it is
not built for JDK 17. Each Tomcat line has its own customized `server.xml` under [`conf/`](./conf), selected by the
`TOMCAT_LINE` build arg.

`next-*` tags are fully mutable. Every variant is rebuilt on every commit to `develop` and on a weekly schedule 
(Wednesday ~20:00 ET) so they pick up upstream patches to the floating Tomcat base images. They are intended for 
testing and snapshot-style deployments.

`release-*` builds publish two tags per (Tomcat line, JDK) pair: an immutable tag pinned to a specific xh-tomcat 
semver release (recorded in `CHANGELOG.md`) and a mutable tag that floats to the most recent release of that pair.

## Support policy

- Only the most recent release gets updates. Older release tags stay on Docker Hub but are not patched.
- We cut a new release promptly when Tomcat ships a security fix on a line we track, or when the upstream base images
  fix critical or high CVEs. Each release records its Tomcat versions in [`CHANGELOG.md`](./CHANGELOG.md).
- For production, use `latest-tcXX-jdkYY`, or pin an exact release tag and move to each new release as it ships. A
  pinned tag never changes, so it never picks up security fixes on its own.
- `next-*` tags are for testing only.

### Legacy tags - scheduled for removal on 2027-02-18

These tags come from older releases. They are frozen, unpatched, and will be deleted from Docker Hub on or after
**2027-02-18**. Move to a `latest-tcXX-jdkYY` tag or pin a current release tag before then.

- `latest` and `next` - bare tags from 2023 and 2022 (Tomcat 8.5, JDK 8). A pull with no tag gets this old image.
- `latest-jdk8`, `latest-jdk11`, `latest-jdk17` - last updated by the `3.x` releases (Tomcat 9.0).
- `next-jdk8`, `next-jdk11`, `next-jdk17` - old snapshot builds (Tomcat 9.0), no longer rebuilt.

Numbered release tags (e.g. `3.2.0-jdk17`) are not on this list and stay available.

## Branches and CI

This repo uses a single `develop` branch (and a `master` branch tracking the most recent release).

GitHub Actions workflows live in [`.github/workflows/`](./.github/workflows):

- **`buildNext.yml`** - runs on every push to `develop`, on a weekly schedule, and on manual dispatch. Builds and
  pushes all `next-*` variants in parallel, each on its floating `major.minor` Tomcat base image.
- **`buildRelease.yml`** - manual dispatch from `master` only. Takes a semver release version as input. Builds and
  pushes the `release-*` variants with both tags, then creates the corresponding git tag and GitHub release.
- **`checkTomcat.yml`** - runs daily. Opens a PR to `develop` when upstream publishes a newer Tomcat patch on a line
  we track, with the CVEs it fixes. Also opens a PR when upstream rebuilds the images we release on, for JDK or Ubuntu
  updates, and our `latest-*` images don't have the rebuild yet. Each PR is a prompt to cut a release. Opens an issue for a newer Tomcat line or LTS JDK, and when `develop` has gone 45
  days without a commit, before GitHub disables scheduled workflows at 60. PRs and issues come from the XH Build Bot.
  Manual dispatch has a dry-run option.

The Tomcat lines, their pinned patch versions and their JDKs live in [`tomcat-versions.json`](./tomcat-versions.json).
Both build workflows read their matrix from it. To release a newer Tomcat patch, merge the Check Tomcat PR (or make
the same edits by hand), merge `develop` to `master`, then dispatch the release.

Both workflows build each image with [`.github/scripts/build-image.sh`](./.github/scripts/build-image.sh). It runs
[`smoke-test.sh`](./.github/scripts/smoke-test.sh) on the image before pushing it, which checks the Tomcat and JDK
versions and the XH config, then boots Tomcat and checks it serves a test app. Pushed images carry SBOM and provenance
attestations.

To build locally, pass the same args CI does:

```sh
docker build --build-arg TOMCAT_VERSION=11.0 --build-arg JDK_VERSION=jdk25 --build-arg TOMCAT_LINE=tc11 -t xh-tomcat-local .
.github/scripts/smoke-test.sh xh-tomcat-local 11.0 jdk25 tc11
```

----
📫☎️🌎 info@xh.io | https://xh.io/contact

Copyright © 2026 Extremely Heavy Industries Inc.
