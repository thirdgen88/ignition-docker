#!/bin/bash
shopt -s nullglob

DELAY=${1:-60}
QUARANTINE=/var/lib/ignition/data/certificates/gateway_network/quarantine

echo "Beginning automatic gateway network certificate acceptance (${DELAY}s)..."

for ((i=${DELAY};i>0;i--)); do
    cert_files=( ${QUARANTINE}/*.der )
    if ((${#cert_files[@]} != 0)); then
        cert_file=$(basename "${cert_files[@]}")
        echo "Accepting Certificate: ${cert_file}"
        mv "${cert_files[@]}" ${QUARANTINE}/..
    fi
    sleep 1
done

echo "Finished automatic gateway network certificate acceptance."