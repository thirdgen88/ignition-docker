#!/bin/bash
set -eo pipefail
shopt -s nullglob

# Check for Restore Backup File and no Docker Init Complete file
if [ -f "/restore.gwbk" -a ! -f "/var/lib/ignition/data/.docker-init-complete" ]; then
    # Mark Initialization Complete
    touch /var/lib/ignition/data/.docker-init-complete
    
    # Initialize Startup Gateway before Attempting Restore
    "$@" &
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

exec "$@"
