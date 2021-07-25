# Ignition Version
ARG IGNITION_VERSION="8.1.7"
# IGNITION_RC_VERSION should be something like `8.1.8-rc1` when applicable
ARG IGNITION_RC_VERSION="8.1.8-rc1"

# Default Build Edition - STABLE or NIGHTLY
ARG BUILD_EDITION="STABLE"

FROM ubuntu:latest AS downloader
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"
ARG IGNITION_VERSION
ARG BUILD_EDITION

# Install some prerequisite packages
RUN apt-get update && apt-get install -y wget unzip

# Ignition Downloader Parameters
ARG IGNITION_STABLE_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.7/20210603-1403/Ignition-linux-64-8.1.7.zip"
ARG IGNITION_STABLE_AMD64_DOWNLOAD_SHA256="6e6fcd731fc1a1acb564bde3f64822e9dd566a65c31e403db1934c8092554e26"
ARG IGNITION_RC_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.8-rc1/20210720-1004/Ignition-linux-64-8.1.8-rc1.zip"
ARG IGNITION_RC_AMD64_DOWNLOAD_SHA256="607af97d6de7dbf0a443bfce3bb1256e3fe0a47b2f89b8d9c3e50f3b64ea9bd7"
ARG IGNITION_NIGHTLY_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.1.9-SNAPSHOT/Ignition-linux-64-8.1.9-SNAPSHOT.zip"
ARG IGNITION_NIGHTLY_AMD64_DOWNLOAD_SHA256="notused"
ARG IGNITION_AMD64_JRE_SUFFIX="nix"

ARG IGNITION_STABLE_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.7/20210603-1403/Ignition-linux-armhf-8.1.7.zip"
ARG IGNITION_STABLE_ARMHF_DOWNLOAD_SHA256="1bdf6e9b6bbde65dac955400a2acdabcfe9711f2bde41cbfb1d78ffcbcb8442d"
ARG IGNITION_RC_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.8-rc1/20210720-1004/Ignition-linux-armhf-8.1.8-rc1.zip"
ARG IGNITION_RC_ARMHF_DOWNLOAD_SHA256="b0a4cf3201868d1d6293294db95205f9e1ba1cae2423e3af6f9cbb02acc72095"
ARG IGNITION_NIGHTLY_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.1.9-SNAPSHOT/Ignition-linux-armhf-8.1.9-SNAPSHOT.zip"
ARG IGNITION_NIGHTLY_ARMHF_DOWNLOAD_SHA256="notused"
ARG IGNITION_ARMHF_JRE_SUFFIX="arm32hf"
ARG IGNITION_STABLE_ARM64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.7/20210603-1403/Ignition-linux-aarch64-8.1.7.zip"
ARG IGNITION_STABLE_ARM64_DOWNLOAD_SHA256="c280c82715673833a0f2a1b56cbde982fc9bd48dd6f07069869255f25dbb00eb"
ARG IGNITION_RC_ARM64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.1.8-rc1/20210720-1004/Ignition-linux-aarch64-8.1.8-rc1.zip"
ARG IGNITION_RC_ARM64_DOWNLOAD_SHA256="0b16bb6d148a166dac6325abdd8ffe28272f6790e97e2d2270181e7a9a55fb5a"
ARG IGNITION_NIGHTLY_ARM64_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.1.9-SNAPSHOT/Ignition-linux-aarch64-8.1.9-SNAPSHOT.zip"
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
    ln -s /var/lib/ignition/data/metro-keystore webserver/metro-keystore

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
    chown ${IGNITION_UID}:${IGNITION_GID} ${IGNITION_INSTALL_USERHOME} && \
    mkdir -p /data && chown ${IGNITION_UID}:${IGNITION_GID} /data

# Copy Ignition Installation from Build Image
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=downloader /root/ignition ${IGNITION_INSTALL_LOCATION}
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=downloader /var/lib/ignition /var/lib/ignition
COPY --chown=${IGNITION_UID}:${IGNITION_GID} --from=downloader /var/log/ignition /var/log/ignition
RUN ln -s /dev/stdout /var/log/ignition/wrapper.log

# Declare Healthcheck
HEALTHCHECK --interval=10s --start-period=60s --timeout=3s \
    CMD curl --max-time 3 -f http://localhost:${GATEWAY_HTTP_PORT:-8088}/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088

# Launch Ignition
USER ${IGNITION_UID}
WORKDIR ${IGNITION_INSTALL_LOCATION}

# Update path to include embedded java install location
ENV PATH="${IGNITION_INSTALL_LOCATION}/lib/runtime/jre/bin:${PATH}"

# Copy in Entrypoint and helper scripts
COPY *.sh /usr/local/bin/

STOPSIGNAL SIGINT

# Prepare Execution Settings
ENTRYPOINT [ "tini", "-g", "--", "/usr/local/bin/docker-entrypoint.sh" ]
CMD [ "./ignition-gateway" ]
