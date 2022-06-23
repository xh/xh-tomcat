# Changelog

Note that the `next` tag (and JDK-specific variants) is mutable and is rebuilt regularly with any updates to this
project and on a weekly schedule (to pick up ongoing updates to the official `tomcat:8.5` source image).

Versioned builds are immutable and have locked-in a given set of defaults from this project as well as the latest Tomcat
version at the time of the build (recorded in the log entries below). 

See this project's README for details on how images are tagged for use with different supported JDK versions.

## next - under development

* tomcat `8.5` (exact version dependent on build time)

## v2.1.0 - 2022-06-23

* Update `maxPostSize` in `server.xml` overrides from 20mb -> 50mb.
* Establish new tagging / branching scheme detailed in README (as well as this CHANGELOG).
