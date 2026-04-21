# Changelog

Note that the `next-tc10-jdkXX` tags are mutable and are rebuilt after any updates to this project and on a weekly
schedule. This ensures the `next` series tags pick up ongoing updates to the official `tomcat:10.1` base image.

Versioned builds are immutable and have locked-in the latest Tomcat version at the time of the build (recorded in the
log entries below). These are recommended for production use in applications, to ensure a known-good version of Tomcat
is used for deployments, without the possibility of unexpected container updates from one app build to the next.

See this project's README for details on how images are tagged for use with different supported JDK versions.

## next - under development

* Tomcat `10.1` (exact version dependent on build time)

## 4.0.0 - 2026-04-20

* **Breaking:** Dropped support for Tomcat `9.0` and JDK 11. Going forward, xh-tomcat only publishes images
  for Tomcat `10.1` on JDK 17 and JDK 25. Apps still on the dropped versions should pin to a `3.x` release tag (e.g.
  `3.2.0-jdk11`) until they are ready to migrate.
* **Breaking:** Release tag scheme now includes a Tomcat-line segment. Tags are published as
  `latest-tc10-jdkXX` and `<xh-release>-tc10-jdkXX` (e.g. `latest-tc10-jdk17`, `4.0.0-tc10-jdk17`) instead of the
  previous `latest-jdkXX` / `<xh-release>-jdkXX`. This makes it possible to publish multiple Tomcat lines in
  parallel in the future. Apps pulling `latest-jdk17` will need to switch to `latest-tc10-jdk17` to move forward;
  `latest-jdk17` and earlier `3.x-jdkXX` tags remain available but will no longer be updated.
* Added `release-tc10-jdk25` tags (`latest-tc10-jdk25`, `<xh-release>-tc10-jdk25`).
* Tomcat `10.1.54`.

## 3.2.0 - 2025-07-08

* Tomcat `9.0.107`
* Increase `maxHttpHeaderSize` limit imposed by Tomcat to 64kb.

## 3.1.0 - 2024-10-14

* Tomcat `9.0.96`

## 3.0.0 - 2023-05-31

* Tomcat `9.0.75`
* Increase `maxPostSize` limit imposed by Tomcat to 100mb.

## 2.2.0 - 2023-05-25

* Tomcat `8.5.89`
* Skipped install of `vim` to minimize exposure to reported vulnerabilities within that package.

## 2.1.0 - 2022-06-23 (tagged as next-jdkXX) + 2023-05-25 (tagged as 2.1.0-jdkXX)

* Tomcat `8.5.81`
* Update `maxPostSize` in `server.xml` overrides from 20mb -> 50mb.

Note: This image was published with the `next-jdkXX` tag with the above version of Tomcat in June 2022, where it
remained in "next" status (without any further updates) for almost a year. We are now (May 2023) completing the intended
work to move to stable `x.y.z` tags + regularly rebuilt `next` tags across this set of images. Going forward, the `next`
tag will have a newer version of Tomcat based on the latest stable build of the official image, as detailed above.
Applications that were using the `next` tag prior to 2023-05-25 and wish to get back to the same underlying version
of Tomcat can spec the `2.1.0-jdkXX` tag, although we recommend moving to the latest versioned tag instead. The `next`
tag should be reserved for testing or apps that for some reason require a "snapshot" style build of this image.


------------------------------------------

📫☎️🌎 info@xh.io | <https://xh.io>

Copyright © 2023 Extremely Heavy Industries Inc.
