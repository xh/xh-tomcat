# Changelog

Note that the `next` tag (and JDK-specific variants) is mutable and is rebuilt regularly with any updates to this
project and on a weekly schedule (to pick up ongoing updates to the official `tomcat:8.5` source image).

Versioned builds are immutable and have locked-in a given set of defaults from this project as well as the latest Tomcat
version at the time of the build (recorded in the log entries below).

See this project's README for details on how images are tagged for use with different supported JDK versions.

## next - under development

* tomcat `8.5` (exact version dependent on build time)

## v2.1.0 - 2022-06-23 (tagged as next-jdk17) + 2023-05-25 (tagged as 2.1.0-jdk17)

* Tomcat 8.5.81
* Update `maxPostSize` in `server.xml` overrides from 20mb -> 50mb.

Note: This image was published with the `next-jdkXX` tag with the above version of Tomcat in June 2022, where it
remained in "next" status (without any further updates) for almost a year. We are now (May 2023) completing the intended
work to move to stable `x.y.z` tags + regularly rebuilt `next` tags across this set of images. Going forward, the `next`
tag will have a newer version of Tomcat based on the latest stable build of the official image, as detailed above.
Applications that were using the `next` tag prior to 2023-05-25 and wish to get back to the same underlying version
of Tomcat can spec the `2.1.0-jdkxx` tag, although we recommend moving to the latest versioned tag instead. The `next`
tag should be reserved for testing or apps that for some reason require a "snapshot" style build of this image.


------------------------------------------

📫☎️🌎 info@xh.io | <https://xh.io>

Copyright © 2023 Extremely Heavy Industries Inc.
