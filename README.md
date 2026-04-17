# Hoist Dockerfile: xh-tomcat

[Hoist React](https://github.com/exhi/hoist-react/) apps can be deployed via Docker containers running Tomcat (for
Hoist's Grails based back-end) and nginx (to serve compiled client JS/CSS and other assets).

This repo contains a minimal Dockerfile to build the base Tomcat container, which can be used by app-specific Docker
deployments with additional configurations.

## Tomcat versions, JDK versions and Docker tags

Images are published to Docker Hub as [`xhio/xh-tomcat`](https://hub.docker.com/r/xhio/xh-tomcat). We support two
Tomcat lines (`9.0` and `10.1`) and four JDK versions (11, 17, 21, 25), producing the variants below:

| Variant             | Tomcat | JDK | Source base image    | Docker tag(s)                 |
|---------------------|:------:|:---:|----------------------|-------------------------------|
| next-jdk11          |  9.0   | 11  | `tomcat:9.0-jdk11`   | `next-jdk11`                  |
| next-jdk17          |  9.0   | 17  | `tomcat:9.0-jdk17`   | `next-jdk17`                  |
| next-jdk21          |  9.0   | 21  | `tomcat:9.0-jdk21`   | `next-jdk21`                  |
| next-jdk25          |  9.0   | 25  | `tomcat:9.0-jdk25`   | `next-jdk25`                  |
| next-tc10-jdk11     |  10.1  | 11  | `tomcat:10.1-jdk11`  | `next-tc10-jdk11`             |
| next-tc10-jdk17     |  10.1  | 17  | `tomcat:10.1-jdk17`  | `next-tc10-jdk17`             |
| next-tc10-jdk21     |  10.1  | 21  | `tomcat:10.1-jdk21`  | `next-tc10-jdk21`             |
| next-tc10-jdk25     |  10.1  | 25  | `tomcat:10.1-jdk25`  | `next-tc10-jdk25`             |
| release-jdk11       |  9.0   | 11  | `tomcat:A.B.C-jdk11` | `latest-jdk11`, `X.Y.Z-jdk11` |
| release-jdk17       |  9.0   | 17  | `tomcat:A.B.C-jdk17` | `latest-jdk17`, `X.Y.Z-jdk17` |

`next-*` tags are fully mutable and rebuilt on every commit to `develop` and on a weekly schedule (Wednesday 20:00
ET) so they pick up upstream patches to the floating `tomcat:9.0` / `tomcat:10.1` base images. They are intended for
testing and snapshot-style deployments.

`release-*` builds publish two tags per JDK: an immutable `X.Y.Z-jdkXX` tag pinned to a specific xh-tomcat semver
release (recorded in `CHANGELOG.md`) and a mutable `latest-jdkXX` tag that floats to the most recent release of that
JDK line.

## Branches and CI

This repo uses a single `develop` branch (and a `main` branch tracking the most recent release).

GitHub Actions workflows live in [`.github/workflows/`](./.github/workflows):

- **`buildNext.yml`** — runs on every push to `develop`, on a weekly schedule, and on manual dispatch. Builds and
  pushes all `next-*` variants in parallel via a matrix.
- **`buildRelease.yml`** — manual dispatch from `main` only. Takes a semver release version as input. The locked
  Tomcat patch version is the `TOMCAT_VERSION` ARG default in the [`Dockerfile`](./Dockerfile). Builds and pushes
  the `release-*` variants with both `latest-jdkXX` and `X.Y.Z-jdkXX` tags, then creates the corresponding git
  tag and GitHub release. To release with a newer Tomcat patch, bump the `TOMCAT_VERSION` default in the Dockerfile
  and update `CHANGELOG.md` in a normal PR before dispatching the workflow.

----
📫☎️🌎 info@xh.io | https://xh.io/contact

Copyright © 2026 Extremely Heavy Industries Inc.
