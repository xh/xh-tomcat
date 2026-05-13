# See buildRelease for complete matrix of published TOMCAT_VERSION and JDK_VERSION.
ARG TOMCAT_VERSION=10.1.55
ARG JDK_VERSION=jdk17
FROM tomcat:${TOMCAT_VERSION}-${JDK_VERSION}

# Upgrade to get latest security patches, delete apt cache.
RUN apt-get update && \
    apt-get upgrade -y && \
    rm -rf /var/lib/apt/lists/*

# Clean up standard bundled webapps.
RUN cd webapps && \
  rm -rf ROOT* && \
  rm -rf docs && \
  rm -rf examples && \
  rm -rf manager && \
  rm -rf host-manager

# Copy in customized server.xml - look for <!-- XH CUSTOMIZATION ... --> comments.
# Note - this should be compared and updated as needed across Tomcat versions - current as of 10.1.54.
COPY conf/server.xml /usr/local/tomcat/conf/
