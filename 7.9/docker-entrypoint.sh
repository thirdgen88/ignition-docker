#!/bin/bash
set -eo pipefail
shopt -s nullglob

# Local initialization
INIT_FILE=/var/lib/ignition/data/init.properties
CMD=( "$@" )
WRAPPER_OPTIONS=( )
JAVA_OPTIONS=( )

# Init Properties Helper Functions
add_to_init () {
    # The below takes the first argument as the key and indirects to the second argument
    # to assign the value.  It will skip if the value is undefined.
    if [ ! -z ${!2:-} ]; then
        echo "Added Init Setting ${1}=${!2}"
        echo "${1}=${!2}" >> $INIT_FILE
    fi
}

# Gateway Network Init Properties Helper Function
add_gw_to_init () {
    # This function will add any other defined variables (via add_to_init) for a gateway
    # network connection definition.

    declare -A settings
    settings=( [PingRate]=GATEWAY_NETWORK_${1}_PINGRATE
               [Enabled]=GATEWAY_NETWORK_${1}_ENABLED
               [Host]=GATEWAY_NETWORK_${1}_HOST
               )

    # Loop through the settings above and add_to_init
    for key in ${!settings[@]}; do
        value=${settings[$key]}
        if [ ! -z ${!value:-} ]; then
            add_to_init gateway.network.${1}.${key} ${value}
        fi
    done

    # Handle EnableSSL explicitly, default to true if not specified
    enablessl=GATEWAY_NETWORK_${1}_ENABLESSL
    declare "$enablessl=${!enablessl:-true}"
    add_to_init gateway.network.${1}.EnableSSL ${enablessl}

    # If EnableSSL defaulted to true and Port was not specified, default to 8060
    port=GATEWAY_NETWORK_${1}_PORT
    declare "$port=${!port:-8060}"
    add_to_init gateway.network.${1}.Port ${port}
}

# Examine memory constraints and apply to Java arguments
if [ ! -z ${GATEWAY_INIT_MEMORY:-} ]; then
    if [ ${GATEWAY_INIT_MEMORY} -ge 256 2> /dev/null ]; then
        WRAPPER_OPTIONS+=(
            "wrapper.java.initmemory=${GATEWAY_INIT_MEMORY}"
            )
    else
        echo >&2 "Invalid minimum memory specification, must be integer in MB: ${GATEWAY_INIT_MEMORY}"
        exit 1
    fi    
fi

if [ ! -z ${GATEWAY_MAX_MEMORY:-} ]; then
    if [ ${GATEWAY_MAX_MEMORY} -ge 512 2> /dev/null ]; then
        WRAPPER_OPTIONS+=(
            "wrapper.java.maxmemory=${GATEWAY_MAX_MEMORY}"
        )
    else
        echo >&2 "Invalid max memory specification, must be integer in MB: ${GATEWAY_MAX_MEMORY}"
        exit 1
    fi
fi

if [ ${GATEWAY_INIT_MEMORY:-256} -gt ${GATEWAY_MAX_MEMORY:-512} ]; then
    echo >&2 "Invalid memory specification, min (${GATEWAY_MIN_MEMORY}) must be less than max (${GATEWAY_MAX_MEMORY})"
    exit 1
fi

# Combine CMD array with wrapper and explicit java options
if [ ! -z ${JAVA_OPTIONS:-} ]; then
    JAVA_OPTIONS=( "--" "${JAVA_OPTIONS[@]}" )
fi
CMD+=(
    "${WRAPPER_OPTIONS[@]}"
    "${JAVA_OPTIONS[@]}"
)

# Check for no Docker Init Complete file
if [ ! -f "/var/lib/ignition/data/.docker-init-complete" ]; then
    # Mark Initialization Complete
    touch /var/lib/ignition/data/.docker-init-complete
    
    # Provision the init.properties file if we've got the environment variables for it
    rm -f /var/lib/ignition/data/init.properties
    add_to_init "SystemName" GATEWAY_SYSTEM_NAME
    add_to_init "UseSSL" GATEWAY_USESSL

    # Look for declared HOST variables and add the other associated ones via add_gw_to_init
    looper=GATEWAY_NETWORK_${i:=0}_HOST
    while [ ! -z ${!looper:-} ]; do
        # Add all available env parameters for this host to the init file
        add_gw_to_init $i
        # Index to the next HOST variable
        looper=GATEWAY_NETWORK_$((++i))_HOST
    done

    # Enable Gateway Network Certificate Auto Accept if Declared
    if [ "${GATEWAY_NETWORK_AUTOACCEPT_DELAY}" -gt 0 ] 2>/dev/null; then
        accept-gwnetwork.sh ${GATEWAY_NETWORK_AUTOACCEPT_DELAY} &
    fi

    # Attempt Gateway Restore if file exists
    if [ -f "/restore.gwbk" ]; then
        # Initialize Startup Gateway before Attempting Restore
        "${CMD[@]}" &
        pid="$!"

        # Wait up to 60 seconds (default) for Startup Gateway to come online
        echo "Ignition initialization process in progress..."
        for ((i=${IGNITION_STARTUP_DELAY:=60};i>0;i--)); do
            if curl -f http://localhost:8088/main/StatusPing 2>&1 | grep -c RUNNING > /dev/null; then   
                break
            fi
            sleep 1
        done
        if [ "$i" -le 0 ]; then
            echo >&2 "Ignition initialization process failed after ${IGNITION_STARTUP_DELAY} delay."
            exit 1
        fi

        # The restore will prepare the backup to be restored on the next gateway startup
        echo 'Restoring Gateway Backup...'
        ./gwcmd.sh --restore /restore.gwbk -y
        
        # Stopping the gateway we started earlier so that the final startup will then take the backup
        # and put everything in place.
        echo 'Restarting Ignition Gateway...'
        if ! kill -s TERM "$pid" || ! wait "$pid"; then
            echo >&2 'Ignition initialization process failed.'
            exit 1
        fi
    fi
fi

exec "${CMD[@]}"
