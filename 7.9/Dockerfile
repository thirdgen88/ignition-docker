FROM ubuntu:22.04 AS downloader
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Install some prerequisite packages
RUN apt-get update && apt-get install -y wget unzip

# Ignition Downloader Parameters
ARG IGNITION_FULL_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/build7.9.21/20220726-1323/zip-installers/Ignition-linux-64-7.9.21.zip"
ARG IGNITION_FULL_AMD64_DOWNLOAD_SHA256="d6ff70b1dbda434d1ec8f3627664240de874b4a39586e9ab01762f9ed096774b"
ARG IGNITION_EDGE_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/build7.9.21/20220726-1323/zip-installers/Ignition-linux-64-7.9.21.zip"
ARG IGNITION_EDGE_AMD64_DOWNLOAD_SHA256="d6ff70b1dbda434d1ec8f3627664240de874b4a39586e9ab01762f9ed096774b"
ARG IGNITION_AMD64_JRE_SUFFIX="nix"

ARG IGNITION_FULL_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/build7.9.21/20220726-1323/zip-installers/Ignition-linux-armhf-7.9.21.zip"
ARG IGNITION_FULL_ARMHF_DOWNLOAD_SHA256="bdcb18cdb95e3d4e9326ca12212fa8524746b6a8e6c2186a0d01a6f6625e8378"
ARG IGNITION_EDGE_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/build7.9.21/20220726-1323/zip-installers/Ignition-Edge-linux-armhf-7.9.21.zip"
ARG IGNITION_EDGE_ARMHF_DOWNLOAD_SHA256="2e639598adc8aeb604a587cf3170a1760b9901026d3ab2beaa17e1972296e0f0"
ARG IGNITION_ARMHF_JRE_SUFFIX="arm32hf"

# gosu Download Parameters
ARG GOSU_VERSION="1.16"
ARG GOSU_AMD64_DOWNLOAD_URL="https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64"
ARG GOSU_AMD64_DOWNLOAD_SHA256="3a4e1fc7430f9e7dd7b0cbbe0bfde26bf4a250702e84cf48a1eb2b631c64cf13"
ARG GOSU_ARMHF_DOWNLOAD_URL="https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-armhf"
ARG GOSU_ARMHF_DOWNLOAD_SHA256="1b670d5426e1ddbb14a14280afb6850a48c219189d4cfe7e6eb2cc08a4fc7785"
ARG GOSU_ARM64_DOWNLOAD_URL="https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-arm64"
ARG GOSU_ARM64_DOWNLOAD_SHA256="23fa49907d5246d2e257de3bf883f57fba47fe1f559f7e732ff16c0f23d2b6a6"

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

# Download gosu based on Detected Architecture
RUN set -exo pipefail; \
    dpkg_arch="$(dpkg --print-architecture | awk '{print toupper($0)}')"; \
    download_url_env="GOSU_${dpkg_arch}_DOWNLOAD_URL"; \
    download_sha256_env="GOSU_${dpkg_arch}_DOWNLOAD_SHA256"; \
    if [[ -n "${!download_url_env}" ]] && [[ -n "${!download_sha256_env}" ]]; then \
    wget -q --ca-certificate=/etc/ssl/certs/ca-certificates.crt -O "gosu" "${!download_url_env}" && \
    echo "${!download_sha256_env}" "gosu" | sha256sum -c -; \
    else \
    echo "Architecture ${dpkg_arch} download targets for gosu not defined, aborting build"; \
    exit 1; \
    fi; \
    chmod a+x "gosu"

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
FROM jre-base as final
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Install some prerequisite packages
RUN apt-get update && \
    apt-get install -y curl gettext procps pwgen zip unzip sqlite3 fontconfig fonts-dejavu libatomic1 tini && \
    rm -rf /var/lib/apt/lists/*

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
COPY --from=downloader /root/gosu /usr/local/bin/
RUN ln -s /dev/stdout /var/log/ignition/wrapper.log && \
    chown -h ${IGNITION_UID}:${IGNITION_GID} /var/log/ignition/wrapper.log

# Declare Healthcheck
HEALTHCHECK --interval=10s --start-period=60s --timeout=3s \
    CMD curl --max-time 3 -f http://localhost:8088/main/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088

# Launch Ignition
USER root
WORKDIR ${IGNITION_INSTALL_LOCATION}

# Update path to include embedded java install location
ENV PATH="${IGNITION_INSTALL_LOCATION}/lib/runtime/jre/bin:${PATH}"

# Copy in Entrypoint and helper scripts
COPY *.sh /usr/local/bin/

STOPSIGNAL SIGINT

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

