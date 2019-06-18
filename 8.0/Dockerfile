FROM debian:stretch-slim
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Select Ignition Version
ARG IGNITION_VERSION="8.0.2"
ARG IGNITION_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/build8.0.2/20190605-1127/Ignition-linux-64-8.0.2.zip"
ARG IGNITION_DOWNLOAD_SHA256="ff43873075c2b3a0dd01041696516ef09f6b7ab3cf16ca3ca334668d52844fd8"

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

# Change to Ignition folder
WORKDIR ${INSTALLER_PATH}/ignition

# Stage data and user-lib in var folder
RUN mkdir -p /var/lib/ignition && \
    mv data /var/lib/ignition/ && \
    mv user-lib /var/lib/ignition/ && \
    mv temp /var/lib/ignition/data && \
    ln -s /var/lib/ignition/data data && \
    ln -s /var/lib/ignition/user-lib user-lib && \
    ln -s /var/lib/ignition/data/temp temp

# Extract embedded Java
RUN tar -C lib/runtime -z -x -f lib/runtime/jre-nix.tar.gz && \
    cp lib/runtime/version lib/runtime/jre-nix/

# RUNTIME IMAGE
FROM debian:stretch-slim
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Install some prerequisite packages
RUN apt-get update && apt-get install -y curl gettext procps pwgen unzip sqlite3

# Setup Install Targets
ENV IGNITION_INSTALL_LOCATION="/usr/local/share/ignition"
ENV IGNITION_INSTALL_USERHOME="/home/ignition"

# Setup dedicated user, map file permissions, and set execution flags
RUN mkdir ${IGNITION_INSTALL_USERHOME} && \
    groupadd -r ignition && \
    useradd -r -d ${IGNITION_INSTALL_USERHOME} -g ignition ignition && \
    chown ignition:ignition ${IGNITION_INSTALL_USERHOME}

# Copy Ignition Installation from Build Image
COPY --chown=ignition:ignition --from=0 /root/ignition ${IGNITION_INSTALL_LOCATION}
COPY --chown=ignition:ignition --from=0 /var/lib/ignition /var/lib/ignition

# Declare Healthcheck
HEALTHCHECK --interval=10s --start-period=60s --timeout=3s \
    CMD curl -f http://localhost:8088/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088 8043 8000

# Launch Ignition
USER ignition
WORKDIR ${IGNITION_INSTALL_LOCATION}

# Copy in Entrypoint and helper scripts
COPY docker-entrypoint.sh /usr/local/bin/
COPY accept-gwnetwork.sh /usr/local/bin/

# Prepare Execution Settings
ENTRYPOINT [ "docker-entrypoint.sh" ]
CMD [ "./ignition-gateway" \
    , "data/ignition.conf" \
    , "wrapper.syslog.ident=Ignition Gateway" \
    , "wrapper.pidfile=./Ignition Gateway.pid" \
    , "wrapper.name=Ignition Gateway" \
    , "wrapper.displayname=Ignition-Gateway" \
    , "wrapper.statusfile=./Ignition Gateway.status" \
    , "wrapper.java.statusfile=./Ignition Gateway.java.status" ]  
