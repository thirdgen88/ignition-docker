FROM debian:stretch-slim
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Select Ignition Version
ARG IGNITION_VERSION="8.0.0"
ARG IGNITION_DOWNLOAD_URL="https://s3.amazonaws.com/files.inductiveautomation.com/release/ia/build8.0.0/20190407-1858/zip-installers/Ignition-linux-64-8.0.0.zip"
ARG IGNITION_DOWNLOAD_SHA256="6e793f00124a13c00f37ea717ababae95a4e9f8702c1639040021862d08a625e"

# Install some prerequisite packages
RUN apt-get update && apt-get install -y wget unzip

# Retrieve Ignition Installer and Perform Ignition Installation
ENV INSTALLER_PATH /root
ENV INSTALLER_NAME "ignition-install.zip"
WORKDIR ${INSTALLER_PATH}

# Download Installation Zip File
RUN wget -q --referer https://inductiveautomation.com/* -O ${INSTALLER_NAME} ${IGNITION_DOWNLOAD_URL} && \
    echo "${IGNITION_DOWNLOAD_SHA256} ${INSTALLER_NAME}" | sha256sum -c -

# Extract Installation Zip File
RUN mkdir ignition && \
    unzip -q ${INSTALLER_NAME} -d ignition/ && \
    chmod +x ignition/gwcmd.sh ignition/ignition-gateway ignition/ignition.sh

# Extract embedded Java
RUN tar -C ignition/lib/runtime -z -x -f ignition/lib/runtime/jre-nix.tar.gz && \
    cp ignition/lib/runtime/version ignition/lib/runtime/jre-nix/ && \
    rm ignition/lib/runtime/jre-*.tar.gz && \
    rm ignition/lib/runtime/jre-*.zip

# RUNTIME IMAGE
FROM debian:stretch-slim
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Install some prerequisite packages
RUN apt-get update && apt-get install -y curl gettext procps pwgen

# Setup Install Targets
ENV IGNITION_INSTALL_LOCATION="/usr/local/share/ignition"
ENV IGNITION_INSTALL_USERNAME="ignition"
ENV IGNITION_INSTALL_USERHOME="/home/ignition"
ENV IGNITION_INSTALL_GROUPNAME="ignition"

# Copy Ignition Installation from Build Image
COPY --from=0 /root/ignition ${IGNITION_INSTALL_LOCATION}

# Setup dedicated user, map file permissions, and set execution flags
RUN mkdir ${IGNITION_INSTALL_USERHOME} && \
    groupadd -r ${IGNITION_INSTALL_GROUPNAME} && \
    useradd -r -d ${IGNITION_INSTALL_USERHOME} -g ${IGNITION_INSTALL_GROUPNAME} ${IGNITION_INSTALL_USERNAME} && \
    chown ${IGNITION_INSTALL_USERNAME}:${IGNITION_INSTALL_GROUPNAME} ${IGNITION_INSTALL_USERHOME} && \
    chown -R ${IGNITION_INSTALL_USERNAME}.${IGNITION_INSTALL_GROUPNAME} ${IGNITION_INSTALL_LOCATION}

# Declare Healthcheck
HEALTHCHECK --interval=10s --start-period=60s --timeout=3s \
    CMD curl -f http://localhost:8088/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088 8043 8000

# Launch Ignition
USER ${IGNITION_INSTALL_USERNAME}
WORKDIR ${IGNITION_INSTALL_LOCATION}

# Setup Entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT [ "docker-entrypoint.sh" ]

CMD [ "./ignition-gateway" \
    , "data/ignition.conf" \
    , "wrapper.syslog.ident=Ignition Gateway" \
    , "wrapper.pidfile=./Ignition Gateway.pid" \
    , "wrapper.name=Ignition Gateway" \
    , "wrapper.displayname=Ignition-Gateway" \
    , "wrapper.statusfile=./Ignition Gateway.status" \
    , "wrapper.java.statusfile=./Ignition Gateway.java.status" ]  
