# Ignition Version
ARG IGNITION_VERSION="7.9.19"

FROM ubuntu:latest AS downloader
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"
ARG IGNITION_VERSION

# Install some prerequisite packages
RUN apt-get update && apt-get install -y wget unzip

# Ignition Downloader Parameters
ARG IGNITION_FULL_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/build7.9.19/20220315-0901/zip-installers/Ignition-linux-64-7.9.19.zip"
ARG IGNITION_FULL_AMD64_DOWNLOAD_SHA256="557a45140c3c6eecdaa282d4f2cded7f2a3693287d79c232e87537cfd3eeb54c"
ARG IGNITION_EDGE_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/build7.9.19/20220315-0901/zip-installers/Ignition-linux-64-7.9.19.zip"
ARG IGNITION_EDGE_AMD64_DOWNLOAD_SHA256="557a45140c3c6eecdaa282d4f2cded7f2a3693287d79c232e87537cfd3eeb54c"
ARG IGNITION_AMD64_JRE_SUFFIX="nix"

ARG IGNITION_FULL_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/build7.9.19/20220315-0901/zip-installers/Ignition-linux-armhf-7.9.19.zip"
ARG IGNITION_FULL_ARMHF_DOWNLOAD_SHA256="38c1b68395d71ca63e0bfa876875d30048264555d1d30a2e85e3e9fc7cd91c9a"
ARG IGNITION_EDGE_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/build7.9.19/20220315-0901/zip-installers/Ignition-Edge-linux-armhf-7.9.19.zip"
ARG IGNITION_EDGE_ARMHF_DOWNLOAD_SHA256="176dc1e86f6719b80b6907ca6833ee4b83d9d1f9e7cdd2fd1dc58b9d4fd38d0a"
ARG IGNITION_ARMHF_JRE_SUFFIX="arm32hf"

# Default Build Edition - FULL, EDGE
ARG BUILD_EDITION="FULL"

# Retrieve Ignition Installer and Perform Ignition Installation
ENV INSTALLER_PATH /root
ENV INSTALLER_NAME "ignition-install.zip"
WORKDIR ${INSTALLER_PATH}

# Set to Bash Shell Execution instead of /bin/sh
SHELL [ "/bin/bash", "-c" ]

# Download Installation Zip File based on Detected Architecture
RUN set -exo pipefail; \
    dpkg_arch="$(dpkg --print-architecture | awk '{print toupper($0)}')"; \
    download_url_env="IGNITION_${BUILD_EDITION}_${dpkg_arch}_DOWNLOAD_URL"; \
    download_sha256_env="IGNITION_${BUILD_EDITION}_${dpkg_arch}_DOWNLOAD_SHA256"; \
    if [ -n "${!download_url_env}" ] && [ -n "${!download_sha256_env}" ]; then \
    wget -q --ca-certificate=/etc/ssl/certs/ca-certificates.crt --referer https://inductiveautomation.com/* -O "${INSTALLER_NAME}" "${!download_url_env}" && \
        if [[ ${BUILD_EDITION} != *"NIGHTLY"* ]]; then echo "${!download_sha256_env}" "${INSTALLER_NAME}" | sha256sum -c -; fi ; \
    else \
        echo "Architecture ${dpkg_arch} download targets not defined, aborting build"; \
        exit 1; \
    fi


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
    ln -s /var/lib/ignition/data/temp /var/lib/ignition/temp && \
    ln -s /var/log/ignition logs && \
    ln -s /var/lib/ignition/data/metro-keystore webserver/metro-keystore

# Apply Ignition Edge marker if applicable
RUN if [[ "${BUILD_EDITION}" == *"EDGE"* ]]; then \
      prev_index=$(grep -Po "(?<=^wrapper\.java\.additional\.)([0-9]+)" /var/lib/ignition/data/ignition.conf | tail -1); \
      grep -q -P "^wrapper\.java\.additional\.([0-9]+)=-Dedition=edge" /var/lib/ignition/data/ignition.conf ; \
      if [ $? = 1 ]; then sed -i "/^wrapper\.java\.additional\.${prev_index}/a wrapper.java.additional.$(( ${prev_index} + 1 ))=-Dedition=edge" /var/lib/ignition/data/ignition.conf; fi; \
    fi

# Remove Serial Support Gateway Module if on ARMHF
RUN set -exo pipefail; \
    dpkg_arch="$(dpkg --print-architecture | awk '{print toupper($0)}')"; \
    if [ "${dpkg_arch}" = "ARMHF" ]; then \
        rm -f "user-lib/modules/Serial Support Gateway-module.modl"; \
    fi

# RUNTIME IMAGE
FROM adoptopenjdk:8-jre-hotspot-bionic as final
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"
ARG IGNITION_VERSION

# Install some prerequisite packages
RUN apt-get update && apt-get install -y curl gettext procps pwgen zip unzip sqlite3 fontconfig fonts-dejavu libatomic1

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
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=downloader /root/ignition ${IGNITION_INSTALL_LOCATION}
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=downloader /var/lib/ignition /var/lib/ignition
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=downloader /var/log/ignition /var/log/ignition

# Declare Healthcheck
HEALTHCHECK --interval=10s --start-period=60s --timeout=3s \
    CMD curl --max-time 3 -f http://localhost:8088/main/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088 8043 8000

# Launch Ignition
USER ${IGNITION_UID}
WORKDIR ${IGNITION_INSTALL_LOCATION}

# Update path to include embedded java install location
ENV PATH="${IGNITION_INSTALL_LOCATION}/lib/runtime/jre/bin:${PATH}"

# Copy in Entrypoint and helper scripts
COPY docker-entrypoint.sh /usr/local/bin/
COPY accept-gwnetwork.sh /usr/local/bin/

# Prepare Execution Settings
ENTRYPOINT [ "docker-entrypoint.sh" ]
CMD [ "./ignition-gateway" \
    , "data/ignition.conf" \
    , "wrapper.syslog.ident=Ignition-Gateway" \
    , "wrapper.pidfile=./Ignition-Gateway.pid" \
    , "wrapper.name=Ignition-Gateway" \
    , "wrapper.displayname=Ignition-Gateway" \
    , "wrapper.statusfile=./Ignition-Gateway.status" \
    , "wrapper.java.statusfile=./Ignition-Gateway.java.status" ]  

