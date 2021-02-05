# Ignition Version
ARG IGNITION_VERSION="8.1.2"

# Default Build Edition - STABLE or NIGHTLY
ARG BUILD_EDITION="STABLE"

FROM ubuntu:latest AS downloader
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"
ARG IGNITION_VERSION
ARG BUILD_EDITION

# Install some prerequisite packages
RUN apt-get update && apt-get install -y wget unzip

# Ignition Downloader Parameters
ARG IGNITION_STABLE_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.2/20210203-1115/Ignition-linux-64-8.1.2.zip"
ARG IGNITION_STABLE_AMD64_DOWNLOAD_SHA256="8ac797c63e0c2371484bc780c0bfa8c2c5bdb6d0a92132372caeac8fc2ad80f0"
ARG IGNITION_NIGHTLY_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.1.3-SNAPSHOT/Ignition-linux-64-8.1.3-SNAPSHOT.zip"
ARG IGNITION_NIGHTLY_AMD64_DOWNLOAD_SHA256="notused"
ARG IGNITION_AMD64_JRE_SUFFIX="nix"

ARG IGNITION_STABLE_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.2/20210203-1115/Ignition-linux-armhf-8.1.2.zip"
ARG IGNITION_STABLE_ARMHF_DOWNLOAD_SHA256="0a6aba86849d2d1fd2c8f2774bda7bc1d3f8072cb5effc258bb6631a37055e4b"
ARG IGNITION_NIGHTLY_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.1.3-SNAPSHOT/Ignition-linux-armhf-8.1.3-SNAPSHOT.zip"
ARG IGNITION_NIGHTLY_ARMHF_DOWNLOAD_SHA256="notused"
ARG IGNITION_ARMHF_JRE_SUFFIX="arm32hf"
ARG IGNITION_STABLE_ARM64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.2/20210203-1115/Ignition-linux-aarch64-8.1.2.zip"
ARG IGNITION_STABLE_ARM64_DOWNLOAD_SHA256="681bc83fcfb682cbf297553899e6e66aa75b09b385ec1d05aa72bd7220952d8e"
ARG IGNITION_NIGHTLY_ARM64_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.1.3-SNAPSHOT/Ignition-linux-aarch64-8.1.3-SNAPSHOT.zip"
ARG IGNITION_NIGHTLY_ARM64_DOWNLOAD_SHA256="notused"
ARG IGNITION_ARM64_JRE_SUFFIX="aarch64"

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

# Add jre-tmp folder in base ignition location
RUN mkdir -p jre-tmp

# Stage data, temp, logs and user-lib in var folders
RUN mkdir -p /var/lib/ignition && \
    mv data /var/lib/ignition/ && \
    mv user-lib /var/lib/ignition/ && \
    mv logs /var/log/ignition && \
    ln -s /var/lib/ignition/data data && \
    ln -s /var/lib/ignition/user-lib user-lib && \
    ln -s /var/log/ignition logs && \
    ln -s /var/lib/ignition/data/metro-keystore webserver/metro-keystore

# Extract embedded Java based on architecture
RUN set -exo pipefail; \
    dpkg_arch="$(dpkg --print-architecture | awk '{print toupper($0)}')"; \
    jre_suffix_env="IGNITION_${dpkg_arch}_JRE_SUFFIX"; \
    if [ -n "${!jre_suffix_env}" ]; then \
        tar -C lib/runtime -z -x -f lib/runtime/jre-${!jre_suffix_env}.tar.gz && \
            grep JAVA_VERSION= lib/runtime/jre-${!jre_suffix_env}/release \
            | cut -d'=' -f2- | sed 's/"//g' > lib/runtime/jre-${!jre_suffix_env}/version && \
        ln -s jre-${!jre_suffix_env} lib/runtime/jre; \
    else \
        echo "Architecture ${dpkg_arch} JRE suffix target not defined, aborting build"; \
        exit 1; \
    fi

# RUNTIME IMAGE
FROM ubuntu:20.04 as final
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"
ARG IGNITION_VERSION
ARG BUILD_EDITION

# Capture BUILD_EDITION into environment variable
ENV BUILD_EDITION ${BUILD_EDITION:-FULL}

# Install some prerequisite packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl gettext procps pwgen zip unzip sqlite3 fontconfig fonts-dejavu jq tini locales && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

# Setup Install Targets and Locale Settings
ENV IGNITION_INSTALL_LOCATION="/usr/local/share/ignition" \
    IGNITION_INSTALL_USERHOME="/home/ignition" \
    LANG='en_US.UTF-8' LANGUAGE='en_US:en' LC_ALL='en_US.UTF-8'

# Build Arguments for UID/GID
ARG IGNITION_UID
ARG IGNITION_GID
ENV IGNITION_UID=${IGNITION_UID:-999} \
    IGNITION_GID=${IGNITION_GID:-999}

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
    CMD curl --max-time 3 -f http://localhost:8088/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088 8060 8043 8000

# Launch Ignition
USER ${IGNITION_UID}
WORKDIR ${IGNITION_INSTALL_LOCATION}

# Update path to include embedded java install location
ENV PATH="${IGNITION_INSTALL_LOCATION}/lib/runtime/jre/bin:${PATH}"

# Copy in Entrypoint and helper scripts
COPY *.sh /usr/local/bin/

# Prepare Execution Settings
ENTRYPOINT [ "tini", "-g", "--", "/usr/local/bin/docker-entrypoint.sh" ]
CMD [ "./ignition-gateway" \
    , "data/ignition.conf" \
    , "wrapper.syslog.ident=Ignition-Gateway" \
    , "wrapper.pidfile=./Ignition-Gateway.pid" \
    , "wrapper.name=Ignition-Gateway" \
    , "wrapper.displayname=Ignition-Gateway" \
    , "wrapper.statusfile=./Ignition-Gateway.status" \
    , "wrapper.java.statusfile=./Ignition-Gateway.java.status" ]  
