# See buildRelease for complete matrix of published TOMCAT_VERSION and JDK_VERSION.
ARG TOMCAT_VERSION=10.1.54
ARG JDK_VERSION=jdk17
FROM tomcat:${TOMCAT_VERSION}-${JDK_VERSION}

# Install some useful basic utilities
RUN apt-get update && apt-get install -y nano procps htop dnsutils

# Clean up standard bundled webapps
RUN cd webapps && \
  rm -rf ROOT* && \
  rm -rf docs && \
  rm -rf examples && \
  rm -rf manager && \
  rm -rf host-manager

# Copy in customized server.xml - look for <!-- XH CUSTOMIZATION ... --> comments.
# Note - this should be compared and updated as needed across Tomcat versions - current as of 10.1.54.
COPY conf/server.xml /usr/local/tomcat/conf/
