# Hoist Dockerfile: xh-tomcat

[Hoist React](https://github.com/exhi/hoist-react/) apps can be deployed via Docker containers running Tomcat (for
Hoist's Grails based back-end) and nginx (to serve compiled client JS/CSS and other assets).

This repo contains a minimal Dockerfile to build the base Tomcat container, which can be used by app-specific Docker
deployments with additional configurations.

## Tomcat version, JDK versions and Docker tags

All images produced by this repo are currently using **Tomcat 8.5**. The specific patch version of Tomcat is baked
into an image when it is built, based on how the source `tomcat:8.5` image resolves. We record the current full Tomcat 
version strings for versioned xh-tomcat releases in our CHANGELOG.

This repo does support multiple versions of the JDK, however, with distinct branches for each that we keep in sync 
with each other and build/publish with dedicated tags.

| Branch        | JDK Version | Docker Tag(s)                          |
|---------------|:-----------:|----------------------------------------|
| master        |      8      | `latest`, `latest-jdk8`, `vX.Y.Z-jdk8` |
| master-jdk11  |     11      | `latest-jdk11`, `vX.Y.Z-jdk11`         |
| master-jdk17  |     17      | `latest-jdk17`, `vX.Y.Z-jdk17`         |
| develop       |      8      | `next`, `next-jdk8`                    |
| develop-jdk11 |     11      | `next-jdk11`                           |
| develop-jdk17 |     17      | `next-jdk17`                           |


----
📫☎️🌎 info@xh.io | https://xh.io/contact

Copyright © 2022 Extremely Heavy Industries Inc.
