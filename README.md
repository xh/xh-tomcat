# Hoist Dockerfile: xh-tomcat

[Hoist React](https://github.com/exhi/hoist-react/) apps can be deployed via Docker containers running Tomcat (for
Hoist's Grails based back-end) and nginx (to serve compiled client JS/CSS and other assets).

This repo contains a minimal Dockerfile to build the base Tomcat container, which can be used by app-specific Docker
deployments with additional configurations.

## Tomcat version, JDK versions and Docker tags

All images produced by this repo are currently using **Tomcat 9.0**. The specific patch version of Tomcat is baked
into an image when it is built, based on how the source `tomcat:9.0` image resolves. We record the current full Tomcat
version strings for versioned xh-tomcat releases in our CHANGELOG.

This repo does support multiple versions of the JDK, however, with distinct branches for each that we keep in sync
with each other and build/publish with dedicated tags.

| Branch        | Tomcat Version | JDK Version | Docker Tag(s)                         |
|---------------|----------------|:-----------:|---------------------------------------|
| master-jdk8   | 9.0.75         |      8      | `X.Y.Z-jdk8`, `latest-jdk8`, `latest` |
| master-jdk11  | 9.0.75         |     11      | `X.Y.Z-jdk11`, `latest-jdk11`         |
| master-jdk17  | 9.0.75         |     17      | `X.Y.Z-jdk17`, `latest-jdk17`         |
| develop-jdk8  | latest 9.0.x   |      8      | `next-jdk8`                           |
| develop-jdk11 | latest 9.0.x   |     11      | `next-jdk11`                          |
| develop-jdk17 | latest 9.0.x   |     17      | `next-jdk17`                          |

The images above are all [available on Docker Hub](https://hub.docker.com/r/xhio/xh-tomcat/).

----
📫☎️🌎 info@xh.io | https://xh.io/contact

Copyright © 2023 Extremely Heavy Industries Inc.
