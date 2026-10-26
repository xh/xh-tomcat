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
| release-tc10-jdk17 | 10.1.61 | 17  | `tomcat:10.1.61-jdk17` | `latest-tc10-jdk17`, `4.2.0-tc10-jdk17` |
| release-tc10-jdk21 | 10.1.61 | 21  | `tomcat:10.1.61-jdk21` | `latest-tc10-jdk21`, `4.2.0-tc10-jdk21` |
| release-tc10-jdk25 | 10.1.61 | 25  | `tomcat:10.1.61-jdk25` | `latest-tc10-jdk25`, `4.2.0-tc10-jdk25` |
| release-tc11-jdk21 | 11.0.27 | 21  | `tomcat:11.0.27-jdk21` | `latest-tc11-jdk21` (from next release) |
| release-tc11-jdk25 | 11.0.27 | 25  | `tomcat:11.0.27-jdk25` | `latest-tc11-jdk25` (from next release) |

Tomcat 11 is required by Hoist apps on Grails 8+ (Spring Boot 4 / Servlet 6.1), which also require JDK 21+, so it is
not built for JDK 17. Each Tomcat line has its own customized `server.xml` under [`conf/`](./conf), selected by the
`TOMCAT_LINE` build arg.

`next-*` tags are fully mutable. Every variant is rebuilt on every commit to `develop` and on a weekly schedule 
(Wednesday ~20:00 ET) so they pick up upstream patches to the floating Tomcat base images. They are intended for 
testing and snapshot-style deployments.

`release-*` builds publish two tags per (Tomcat line, JDK) pair: an immutable tag pinned to a specific xh-tomcat 
semver release (recorded in `CHANGELOG.md`) and a mutable tag that floats to the most recent release of that pair.

## Branches and CI

This repo uses a single `develop` branch (and a `master` branch tracking the most recent release).

GitHub Actions workflows live in [`.github/workflows/`](./.github/workflows):

- **`buildNext.yml`** — runs on every push to `develop`, on a weekly schedule, and on manual dispatch. Builds and
  pushes all `next-*` variants in parallel via a matrix.
- **`buildRelease.yml`** — manual dispatch from `master` only. Takes a semver release version as input. The locked
  Tomcat patch version is pinned in the workflow's build matrix (with the [`Dockerfile`](./Dockerfile)
  `TOMCAT_VERSION` ARG default kept in sync for local builds). Builds and pushes the `release-*` variants with both 
  tags, then creates the corresponding git tag and GitHub release. To release with a newer Tomcat patch, bump the 
  matrix entry (and the Dockerfile default) and update `CHANGELOG.md` in a normal PR before dispatching the workflow.

----
📫☎️🌎 info@xh.io | https://xh.io/contact

Copyright © 2026 Extremely Heavy Industries Inc.
