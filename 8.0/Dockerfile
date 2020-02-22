FROM debian:stretch-slim
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Select Ignition Version
ARG IGNITION_VERSION="8.0.10"
ARG IGNITION_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.0.10-SNAPSHOT/Ignition-linux-64-8.0.10-SNAPSHOT.zip"

# Install some prerequisite packages
RUN apt-get update && apt-get install -y wget unzip fontconfig fonts-dejavu

# Retrieve Ignition Installer and Perform Ignition Installation
ENV INSTALLER_PATH /root
ENV INSTALLER_NAME "ignition-install.zip"
WORKDIR ${INSTALLER_PATH}

# Download Installation Zip File
RUN wget -q --referer https://inductiveautomation.com/* -O ${INSTALLER_NAME} ${IGNITION_DOWNLOAD_URL}

# Extract Installation Zip File
RUN mkdir ignition && \
    unzip -q ${INSTALLER_NAME} -d ignition/ && \
    chmod +x ignition/gwcmd.sh ignition/ignition-gateway ignition/ignition.sh

# Change to Ignition folder
WORKDIR ${INSTALLER_PATH}/ignition

# Stage data, temp, logs and user-lib in var folders
RUN mkdir -p /var/lib/ignition && \
    mv data /var/lib/ignition/ && \
    mv user-lib /var/lib/ignition/ && \
    mv temp /var/lib/ignition/data && \
    mv logs /var/log/ignition && \
    ln -s /var/lib/ignition/data data && \
    ln -s /var/lib/ignition/user-lib user-lib && \
    ln -s /var/lib/ignition/data/temp temp && \
    ln -s /var/log/ignition logs

# Extract embedded Java
RUN tar -C lib/runtime -z -x -f lib/runtime/jre-nix.tar.gz && \
    cp lib/runtime/version lib/runtime/jre-nix/

# RUNTIME IMAGE
FROM debian:stretch-slim
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Install some prerequisite packages
RUN apt-get update && apt-get install -y curl gettext procps pwgen zip unzip sqlite3

# Setup Install Targets
ENV IGNITION_INSTALL_LOCATION="/usr/local/share/ignition"
ENV IGNITION_INSTALL_USERHOME="/home/ignition"

# Build Arguments for UID/GID
ARG IGNITION_UID
ENV IGNITION_UID ${IGNITION_UID:-999}
ARG IGNITION_GID
ENV IGNITION_GID ${IGNITION_GID:-999}

# Setup dedicated user, map file permissions, and set execution flags
RUN mkdir ${IGNITION_INSTALL_USERHOME} && \
    (getent group ${IGNITION_GID} > /dev/null 2>&1 || groupadd -r ignition -g ${IGNITION_GID}) && \
    (getent passwd ${IGNITION_UID} > /dev/null 2>&1 || useradd -r -d ${IGNITION_INSTALL_USERHOME} -u ${IGNITION_UID} -g ${IGNITION_GID} ignition) && \
    chown ${IGNITION_UID}:${IGNITION_GID} ${IGNITION_INSTALL_USERHOME}

# Copy Ignition Installation from Build Image
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=0 /root/ignition ${IGNITION_INSTALL_LOCATION}
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=0 /var/lib/ignition /var/lib/ignition
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=0 /var/log/ignition /var/log/ignition

# Declare Healthcheck
HEALTHCHECK --interval=10s --start-period=60s --timeout=3s \
    CMD curl -f http://localhost:8088/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088 8043 8000

# Launch Ignition
USER ${IGNITION_UID}
WORKDIR ${IGNITION_INSTALL_LOCATION}

# Update path to include embedded java install location
ENV PATH="${IGNITION_INSTALL_LOCATION}/lib/runtime/jre-nix/bin:${PATH}"

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
