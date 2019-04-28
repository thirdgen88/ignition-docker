#!/bin/bash
set -eo pipefail
shopt -s nullglob

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

# usage: perform_commissioning URL START_FLAG
#   ie: perform_commissioning http://localhost:8088/post-step 1
perform_commissioning() {
    local url="$1"

    # IGNITION_ADMIN_USERNAME
    # IGNITION_ADMIN_PASSWORD
    # IGNITION_RANDOM_ADMIN_PASSWORD
    # IGNITION_HTTP_PORT
    # IGNITION_HTTPS_PORT
    # IGNITION_USESSL
    # Register EULA Acceptance
    local license_accept_payload='{"id":"license","step":"eula","data":{"accept":true}}'
    curl -H "Content-Type: application/json" -d "${license_accept_payload}" ${url} > /dev/null 2>&1

    # Register Authentication Details
    local auth_user="${IGNITION_ADMIN_USERNAME:=admin}"
    local auth_salt=$(date +%s | sha256sum | head -c 8)
    local auth_pwhash=$(echo -en ${IGNITION_ADMIN_PASSWORD}${auth_salt} | sha256sum - | cut -c -64)
    local auth_password="[${auth_salt}]${auth_pwhash}"
    local auth_payload='{"id":"authentication","step":"authSetup","data":{"username":"'${auth_user}'","password":"'${auth_password}'"}}'
    curl -H "Content-Type: application/json" -d "${auth_payload}" ${url} > /dev/null 2>&1

    # Register Port Configuration
    local http_port="${IGNITION_HTTP_PORT:=8088}"
    local https_port="${IGNITION_HTTPS_PORT:=8043}"
    local use_ssl="${IGNITION_USESSL:=false}"
    local port_payload='{"id":"connections","step":"connections","data":{"http":'${http_port}',"https":'${https_port}',"useSSL":'${use_ssl}'}}'
    curl -H "Content-Type: application/json" -d "${port_payload}" ${url} > /dev/null 2>&1

    # Finalize
    if [ "$2" = "1" ]; then
        local start_flag="true"
    else
        local start_flag="false"
    fi
    local finalize_payload='{"id":"finished","data":{"start":'${start_flag}'}}'
    curl -H "Content-Type: application/json" -d "${finalize_payload}" ${url} > /dev/null 2>&1
}

# usage: health_check PHASE_DESC DELAY_SECS
#   ie: health_check "Gateway Commissioning" 60
health_check() {
    local phase="$1"
    local delay=$2

    # Wait for a short period for the commissioning servlet to come alive
    for ((i=${delay};i>0;i--)); do
        if curl -f http://localhost:8088/StatusPing 2>&1 | grep -c RUNNING > /dev/null; then   
            break
        fi
        sleep 1
    done
    if [ "$i" -le 0 ]; then
        echo >&2 "Failed to detect RUNNING status during ${phase} after ${delay} delay."
        exit 1
    fi
}

# usage stop_process PID
#   ie: stop_process 123
stop_process() {
    local pid="$1"

    echo 'Shutting down interim provisioning gateway...'
    if ! kill -s TERM "$pid" || ! wait "$pid"; then
        echo >&2 'Ignition initialization process failed.'
        exit 1
    fi
}

# Check for no Docker Init Complete file
if [ "$1" = './ignition-gateway' -a ! -f "/usr/local/share/ignition/data/.docker-init-complete" ]; then
    # Check Prerequisites
    file_env 'IGNITION_ADMIN_PASSWORD'
    if [ -z "$IGNITION_ADMIN_PASSWORD" -a -z "$IGNITION_RANDOM_ADMIN_PASSWORD" ]; then
        echo >&2 'ERROR: Gateway is not initialized and no password option is specified '
        echo >&2 '  You need to specify either IGNITION_ADMIN_PASSWORD or IGNITION_RANDOM_ADMIN_PASSWORD'
        exit 1
    fi

    # Mark Initialization Complete
    touch /usr/local/share/ignition/data/.docker-init-complete

    # Perform some staging for the rest of the provisioning process
    if [ ! -z "$IGNITION_RANDOM_ADMIN_PASSWORD" ]; then
        export IGNITION_ADMIN_PASSWORD="$(pwgen -1 32)"
    fi
    if [ -f "/restore.gwbk" ]; then
        export IGNITION_RESTORE_REQUIRED="1"
    else
        export IGNITION_RESTORE_REQUIRED="0"
    fi

    # Initialize Startup Gateway before Attempting Restore
    echo "Provisioning will be logged here: ${IGNITION_INSTALL_LOCATION}/logs/provisioning.log"
    "$@" > /usr/local/share/ignition/logs/provisioning.log 2>&1 &
    pid="$!"

    echo "Waiting for commissioning servlet to become active..."
    health_check "Commissioning Phase" 10

    echo "Performing commissioning actions..."
    perform_commissioning "http://localhost:8088/post-step" ${IGNITION_RESTORE_REQUIRED}
    echo "  IGNITION_ADMIN_USERNAME: ${IGNITION_ADMIN_USERNAME}"
    if [ ! -z "$IGNITION_RANDOM_ADMIN_PASSWORD" ]; then echo "  IGNITION_ADMIN_PASSWORD: ${IGNITION_ADMIN_PASSWORD}"; fi
    echo "  IGNITION_HTTP_PORT: ${IGNITION_HTTP_PORT}"
    echo "  IGNITION_HTTPS_PORT: ${IGNITION_HTTPS_PORT}"
    # echo "  IGNITION_USESSL: ${IGNITION_USESSL}"

    # The restore will prepare the backup to be restored on the next gateway startup
    if [ -f "/restore.gwbk" ]; then
        sleep 5
        echo "Commissioning completed, awaiting initial gateway startup prior to restore..."
        health_check "Startup" ${IGNITION_STARTUP_DELAY:=60}

        echo 'Restoring Gateway Backup...'
        printf '\n' | ./gwcmd.sh --restore /restore.gwbk -y
        stop_process $pid
    else
        stop_process $pid
    fi

    echo 'Starting Ignition Gateway...'
fi

exec "$@"
