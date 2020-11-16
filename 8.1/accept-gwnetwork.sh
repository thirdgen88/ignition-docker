#!/bin/bash
shopt -s nullglob

DELAY=${1:-120}
QUARANTINE=/usr/local/share/ignition/data/certificates/gateway_network/quarantine

echo "init     | Beginning automatic gateway network certificate acceptance (${DELAY}s)..."

for ((i=${DELAY};i>0;i--)); do
    cert_files=( ${QUARANTINE}/*.der )
    if ((${#cert_files[@]} != 0)); then
        cert_file=$(basename "${cert_files[@]}")
        echo "init     | Accepting Certificate: ${cert_file}"
        mv "${cert_files[@]}" ${QUARANTINE}/..
    fi
    sleep 1
done

echo "init     | Finished automatic gateway network certificate acceptance."