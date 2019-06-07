FROM openjdk:8-jre
LABEL maintainer "Kevin Collins <kcollins@purelinux.net>"

# Install some prerequisite packages
RUN apt-get update && apt-get install -y gettext procps

# Select Ignition Version and Edition
ARG IGNITION_VERSION="7.7.10"
ARG IGNITION_DOWNLOAD_URL="https://files.inductiveautomation.com/release/build7.7.10/2018112117/ignition-7.7.10-linux-x64-installer.run"
ARG IGNITION_DOWNLOAD_MD5="1a22a4e482197f4a317d8455cd54b4a1"

# Setup Install Targets
ENV IGNITION_INSTALL_LOCATION="/usr/local/share/ignition"
ENV IGNITION_INSTALL_USERNAME="ignition"
ENV IGNITION_INSTALL_USERHOME="/home/ignition"
ENV IGNITION_INSTALL_GROUPNAME="ignition"

# Retrieve Ignition Installer and Perform Ignition Installation
ENV INSTALLER_PATH /root
ENV INSTALLER_NAME "ignition-installer.run"
WORKDIR ${INSTALLER_PATH}

RUN wget -q --referer https://inductiveautomation.com/* -O ${INSTALLER_NAME} ${IGNITION_DOWNLOAD_URL} && \
    echo "${IGNITION_DOWNLOAD_MD5} ${INSTALLER_NAME}" | md5sum -c - && \
    chmod a+x $INSTALLER_NAME && \
    mkdir ${IGNITION_INSTALL_USERHOME} && \
    groupadd -r ${IGNITION_INSTALL_GROUPNAME} && \
    useradd -r -d ${IGNITION_INSTALL_USERHOME} -g ${IGNITION_INSTALL_GROUPNAME} ${IGNITION_INSTALL_USERNAME} && \
    chown ${IGNITION_INSTALL_USERNAME}:${IGNITION_INSTALL_GROUPNAME} ${IGNITION_INSTALL_USERHOME} && \
    ./${INSTALLER_NAME} --username ${IGNITION_INSTALL_USERNAME} --unattendedmodeui none --mode unattended --prefix ${IGNITION_INSTALL_LOCATION} && \
    rm ${INSTALLER_NAME}

# Clean-up symbolic links back to /etc/ignition so we can ensure preservation of instance configuration in /var/lib/ignition
RUN rm /var/lib/ignition/data/gateway.xml && \
    cp /etc/ignition/gateway.xml /var/lib/ignition/data/ && \
    chown ${IGNITION_INSTALL_USERNAME}.root /var/lib/ignition/data/gateway.xml && \
    rm /var/lib/ignition/data/ignition.conf && \
    cp /etc/ignition/ignition.conf /var/lib/ignition/data/ && \
    chown ${IGNITION_INSTALL_USERNAME}.root /var/lib/ignition/data/ignition.conf && \
    rm /var/lib/ignition/data/log4j.properties && \
    cp /etc/ignition/log4j.properties /var/lib/ignition/data/ && \
    chown ${IGNITION_INSTALL_USERNAME}.root /var/lib/ignition/data/log4j.properties && \
    rm -rf /etc/ignition

# Declare Healthcheck
HEALTHCHECK --interval=10s --start-period=60s --timeout=3s \
    CMD curl -f http://localhost:8088/main/StatusPing 2>&1 | grep RUNNING

# Setup Port Expose
EXPOSE 8088 8043 8000

# Launch Ignition
USER ${IGNITION_INSTALL_USERNAME}
WORKDIR ${IGNITION_INSTALL_LOCATION}
RUN mkdir -p jre-tmp

# Setup Entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT [ "docker-entrypoint.sh" ]

CMD [ "./ignition-gateway" \
    , "/var/lib/ignition/data/ignition.conf" \
    , "wrapper.syslog.ident=Ignition Gateway" \
    , "wrapper.pidfile=./Ignition Gateway.pid" \
    , "wrapper.name=Ignition Gateway" \
    , "wrapper.statusfile=./Ignition Gateway.status" \
    , "wrapper.java.statusfile=./Ignition Gateway.java.status" ]  
