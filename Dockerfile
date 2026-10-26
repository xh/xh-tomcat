# See buildRelease for complete matrix of published TOMCAT_VERSION and JDK_VERSION.
ARG TOMCAT_VERSION=10.1.61
ARG JDK_VERSION=jdk17
FROM tomcat:${TOMCAT_VERSION}-${JDK_VERSION}

# Tomcat line (e.g. tc10, tc11) matching TOMCAT_VERSION - selects the server.xml under conf/.
ARG TOMCAT_LINE=tc10

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

# Copy in customized server.xml for the Tomcat line - look for <!-- XH CUSTOMIZATION ... --> comments.
# Note - each should be compared and updated as needed across Tomcat versions - conf/tc10 is current
# as of 10.1.61, conf/tc11 as of 11.0.27.
COPY conf/${TOMCAT_LINE}/server.xml /usr/local/tomcat/conf/
