FROM openjdk:8-jre
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Install some prerequisite packages
RUN apt-get update && apt-get install -y gettext procps

# Select Ignition Version
ENV IGNITION_VERSION="7.9.4"
ENV IGNITION_DOWNLOAD_URL="https://s3.amazonaws.com/files.inductiveautomation.com/release/ia/build7.9.4/20170829-1101/Ignition-7.9.4-linux-x64-installer.run"
ENV IGNITION_DOWNLOAD_MD5="b60bc5173dd61cf0273a7394006328dd"

# Retrieve Ignition Installer
ENV INSTALLER_PATH /root
ENV INSTALLER_NAME "ignition-installer.run"
WORKDIR ${INSTALLER_PATH}
RUN wget -q -O ${INSTALLER_NAME} ${IGNITION_DOWNLOAD_URL} && \
    echo "${IGNITION_DOWNLOAD_MD5} ${INSTALLER_NAME}" | md5sum -c - && \
    chmod a+x $INSTALLER_NAME

# Setup Install Targets
ENV IGNITION_INSTALL_LOCATION="/usr/local/share/ignition"
ENV IGNITION_INSTALL_USERNAME="ignition"
ENV IGNITION_INSTALL_GROUPNAME="ignition"

# Perform Ignition Installation
RUN groupadd -r ${IGNITION_INSTALL_GROUPNAME} && useradd -r -g ${IGNITION_INSTALL_GROUPNAME} ${IGNITION_INSTALL_USERNAME}
RUN ./${INSTALLER_NAME} --username ${IGNITION_INSTALL_USERNAME} --unattendedmodeui none --mode unattended --prefix ${IGNITION_INSTALL_LOCATION}

# Declare Healthcheck
HEALTHCHECK --interval=10s --start-period=45s --timeout=3s \
    CMD curl -f http://localhost:8088/main/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088 8043 8000

# Launch Ignition
USER ${IGNITION_INSTALL_USERNAME}
WORKDIR ${IGNITION_INSTALL_LOCATION}
ENTRYPOINT [ "./ignition-gateway" \
    , "/var/lib/ignition/data/ignition.conf" \
    , "wrapper.syslog.ident=Ignition Gateway" \
    , "wrapper.pidfile=./Ignition Gateway.pid" \
    , "wrapper.name=Ignition Gateway" \
    , "wrapper.statusfile=./Ignition Gateway.status" \
    , "wrapper.java.statusfile=./Ignition Gateway.java.status" ]  