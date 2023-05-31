# Changelog

Note that the `next-jdkXX` tags are mutable and are rebuilt after any updates to this project and on a weekly schedule.
This ensures the `next` series tags pick up ongoing updates to the official `tomcat:9.0` base image.

Versioned builds are immutable and have locked-in the latest Tomcat version at the time of the build (recorded in the
log entries below). These are recommended for production use in applications, to ensure a known-good version of Tomcat
is used for deployments, without the possibility of unexpected container updates from one app build to the next.

See this project's README for details on how images are tagged for use with different supported JDK versions.

## next - under development

* Tomcat `9.0` (exact version dependent on build time)
* Increase maxPostSize limit imposed by Tomcat to 100mb.

## v2.2.0 - 2023-05-25

* Tomcat 8.5.89
* Skipped install of `vim` to minimize exposure to reported vulnerabilities within that package.

## v2.1.0 - 2022-06-23 (tagged as next-jdkXX) + 2023-05-25 (tagged as 2.1.0-jdkXX)

* Tomcat 8.5.81
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
