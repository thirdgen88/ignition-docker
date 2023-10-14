# Default Build Edition - STABLE or NIGHTLY
ARG BUILD_EDITION="STABLE"

FROM ubuntu-base AS downloader
LABEL maintainer="Kevin Collins <kcollins@purelinux.net>"
ARG BUILD_EDITION

# Install some prerequisite packages
RUN apt-get update && apt-get install -y wget unzip xmlstarlet

# Ignition Downloader Parameters
ARG IGNITION_STABLE_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.32/20230912-1210/Ignition-linux-x86-64-8.1.32.zip"
ARG IGNITION_STABLE_AMD64_DOWNLOAD_SHA256="d1a6f0fc06fa69cf28d71b2e5047b174c5a0282b8b604f82e4934e45a8884efc"
ARG IGNITION_AMD64_JRE_SUFFIX="nix"

ARG IGNITION_STABLE_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.32/20230912-1210/Ignition-linux-armhf-32-8.1.32.zip"
ARG IGNITION_STABLE_ARMHF_DOWNLOAD_SHA256="27044390a82dcc86c0416d62a18350ec8abbf8ac6fb6e0b4af89fb836318778a"
ARG IGNITION_ARMHF_JRE_SUFFIX="arm32hf"

ARG IGNITION_STABLE_ARM64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.32/20230912-1210/Ignition-linux-aarch-64-8.1.32.zip"
ARG IGNITION_STABLE_ARM64_DOWNLOAD_SHA256="06e61a3155adfbdaa95f7b581b0e0cd1d228ac27288dc0226f75f272a6ac4744"
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
        echo "Architecture ${dpkg_arch} download targets for Ignition not defined, aborting build"; \
        exit 1; \
    fi

# gosu Download Parameters
ARG GOSU_VERSION="1.16"
ARG GOSU_AMD64_DOWNLOAD_URL="https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64"
ARG GOSU_AMD64_DOWNLOAD_SHA256="3a4e1fc7430f9e7dd7b0cbbe0bfde26bf4a250702e84cf48a1eb2b631c64cf13"
ARG GOSU_ARMHF_DOWNLOAD_URL="https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-armhf"
ARG GOSU_ARMHF_DOWNLOAD_SHA256="1b670d5426e1ddbb14a14280afb6850a48c219189d4cfe7e6eb2cc08a4fc7785"
ARG GOSU_ARM64_DOWNLOAD_URL="https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-arm64"
ARG GOSU_ARM64_DOWNLOAD_SHA256="23fa49907d5246d2e257de3bf883f57fba47fe1f559f7e732ff16c0f23d2b6a6"

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

# Zip File Exclusion Build Argument
ARG ZIP_EXCLUSION_RESOURCE_LIST
ARG ZIP_EXCLUSION_MODULE_LIST
ARG ZIP_EXCLUSION_ARCHITECTURE_LIST

# Extract Installation Zip File
COPY extract-zip.sh .
RUN ./extract-zip.sh -f "${INSTALLER_NAME}" \
    "${ZIP_EXCLUSION_RESOURCE_LIST:+-xr}" "${ZIP_EXCLUSION_RESOURCE_LIST}" \
    "${ZIP_EXCLUSION_MODULE_LIST+:-xm}" "${ZIP_EXCLUSION_MODULE_LIST}" \
    "${ZIP_EXCLUSION_ARCHITECTURE_LIST:+-xa}" "${ZIP_EXCLUSION_ARCHITECTURE_LIST}"

# Change to Ignition folder
WORKDIR ${INSTALLER_PATH}/ignition

# Modify ignition.sh file
RUN sed -E -i 's/^(PIDFILE_CHECK_PID=true)/#\1/' ignition.sh

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
    mkdir -p /var/lib/ignition/data/local && \
    ln -s /var/lib/ignition/data/local/ssl.pfx webserver/ssl.pfx && \
    ln -s /var/lib/ignition/data/local/csr.pfx webserver/csr.pfx && \
    ln -s /var/lib/ignition/data/local/metro-keystore webserver/metro-keystore

# Extract embedded Java based on architecture
RUN set -exo pipefail; \
    dpkg_arch="$(dpkg --print-architecture | awk '{print toupper($0)}')"; \
    jre_suffix_env="IGNITION_${dpkg_arch}_JRE_SUFFIX"; \
    if [ -n "${!jre_suffix_env}" ]; then \
        ./ignition.sh checkRuntimes && \
        ln -s jre-${!jre_suffix_env} lib/runtime/jre; \
    else \
        echo "Architecture ${dpkg_arch} JRE suffix target not defined, aborting build"; \
        exit 1; \
    fi

# Modify base logback configuration to be colorized by default
RUN xmlstarlet ed --inplace \
    -d "/configuration/@debug" \
    -u "/configuration/appender[@name='SysoutAppender']/encoder/pattern" \
        -v "%highlight(%.-1p) %boldCyan([%-30c{1}]:) %m %X%n" \
    -s "/configuration/appender[@name='SysoutAppender']" \
        -t elem -n withJansi -v "true" \
    data/logback.xml

# RUNTIME IMAGE
FROM ubuntu-base as final
LABEL maintainer="Kevin Collins <kcollins@purelinux.net>"
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
    chown ${IGNITION_UID}:${IGNITION_GID} ${IGNITION_INSTALL_USERHOME} && \
    mkdir -p /data && chown ${IGNITION_UID}:${IGNITION_GID} /data

# Copy Ignition Installation from Build Image
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=downloader /root/ignition ${IGNITION_INSTALL_LOCATION}
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=downloader /var/lib/ignition /var/lib/ignition
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=downloader /var/log/ignition /var/log/ignition
COPY --from=downloader /root/gosu /usr/local/bin/
RUN ln -s /dev/stdout /var/log/ignition/wrapper.log && \
    chown -h ${IGNITION_UID}:${IGNITION_GID} /var/log/ignition/wrapper.log

# Declare Healthcheck
HEALTHCHECK --interval=10s --start-period=60s --timeout=3s \
    CMD curl --max-time 3 -f http://localhost:${GATEWAY_HTTP_PORT:-8088}/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088

# Launch Ignition
USER root
WORKDIR ${IGNITION_INSTALL_LOCATION}

# Update path to include embedded java install location
ENV PATH="${IGNITION_INSTALL_LOCATION}/lib/runtime/jre/bin:${PATH}"

# Copy in Entrypoint and helper scripts
COPY --chmod=0755 accept-gwnetwork.sh \
    docker-entrypoint.sh \
    perform-commissioning.sh \
    register-jdbc.sh \
    register-modules.sh \
    /usr/local/bin/

STOPSIGNAL SIGINT

# Prepare Execution Settings
ENTRYPOINT [ "/usr/local/bin/docker-entrypoint.sh" ]
CMD [ "./ignition-gateway" ]
