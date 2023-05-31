FROM tomcat:9.0.75-jdk11

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
# Note - this should be compared and updated as needed across Tomcat versions - current as of 9.0.75.
COPY conf/server.xml /usr/local/tomcat/conf/
