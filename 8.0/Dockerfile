# Ignition Version
ARG IGNITION_VERSION="8.0.12"

FROM ubuntu:latest AS downloader
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"
ARG IGNITION_VERSION

# Install some prerequisite packages
RUN apt-get update && apt-get install -y wget unzip

# Ignition Downloader Parameters
ARG IGNITION_FULL_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.0.12/20200421-1530/Ignition-linux-64-8.0.12.zip"
ARG IGNITION_FULL_AMD64_DOWNLOAD_SHA256="1ee93619a308d8dd9645089215876671f9a00c61e78fc1d2ea99e2f20a9cb5b9"
ARG IGNITION_EDGE_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.0.12/20200421-1530/Ignition-Edge-linux-64-8.0.12.zip"
ARG IGNITION_EDGE_AMD64_DOWNLOAD_SHA256="9b161bbeb01c8f518e6300f6a64993a42755816e1b5c9bd563fb23cf7f0b40d3"
ARG IGNITION_NIGHTLY_FULL_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.0.14-SNAPSHOT/Ignition-linux-64-8.0.14-SNAPSHOT.zip"
ARG IGNITION_NIGHTLY_FULL_AMD64_DOWNLOAD_SHA256="notused"
ARG IGNITION_NIGHTLY_EDGE_AMD64_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.0.14-SNAPSHOT/Ignition-Edge-linux-64-8.0.14-SNAPSHOT.zip"
ARG IGNITION_NIGHTLY_EDGE_AMD64_DOWNLOAD_SHA256="notused"
ARG IGNITION_AMD64_JRE_SUFFIX="nix"

ARG IGNITION_FULL_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.0.12/20200421-1530/Ignition-linux-armhf-8.0.12.zip"
ARG IGNITION_FULL_ARMHF_DOWNLOAD_SHA256="7e9aba6cf155e52a3aaa5b2322a810c8e500ec62270b84a3fe197e9bc1507cca"
ARG IGNITION_EDGE_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/release/ia/8.0.12/20200421-1530/Ignition-Edge-linux-armhf-8.0.12.zip"
ARG IGNITION_EDGE_ARMHF_DOWNLOAD_SHA256="f56e0702479e4d1084966691263f971c9d1ec9a62a7e94e63409fed689ad6111"
ARG IGNITION_NIGHTLY_FULL_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.0.14-SNAPSHOT/Ignition-linux-armhf-8.0.14-SNAPSHOT.zip"
ARG IGNITION_NIGHTLY_FULL_ARMHF_DOWNLOAD_SHA256="notused"
ARG IGNITION_NIGHTLY_EDGE_ARMHF_DOWNLOAD_URL="https://files.inductiveautomation.com/builds/nightly/8.0.14-SNAPSHOT/Ignition-Edge-linux-armhf-8.0.14-SNAPSHOT.zip"
ARG IGNITION_NIGHTLY_EDGE_ARMHF_DOWNLOAD_SHA256="notused"
ARG IGNITION_ARMHF_JRE_SUFFIX="arm32hf"

# Default Build Edition - FULL, EDGE, NIGHTLY_FULL, or NIGHTLY_EDGE
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
        wget -q --referer https://inductiveautomation.com/* -O "${INSTALLER_NAME}" "${!download_url_env}" && \
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
    ln -s /var/log/ignition logs

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
FROM debian:buster-slim as final
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"
ARG IGNITION_VERSION

# Install some prerequisite packages
RUN apt-get update && apt-get install -y curl gettext procps pwgen zip unzip sqlite3 fontconfig fonts-dejavu

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
    CMD curl --max-time 3 -f http://localhost:8088/StatusPing 2>&1 | grep RUNNING

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

# Unpack common jar if necessary for compatibility with upgrader
RUN common_jar="lib/core/common/common-${IGNITION_VERSION}.jar"; \
    common_jar_pack="${common_jar}.pack.gz"; \
    if [ ! -f "${common_jar}" -a -f "${common_jar_pack}" ]; then \
    unpack200 "${common_jar_pack}" "${common_jar}"; \
    fi

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
