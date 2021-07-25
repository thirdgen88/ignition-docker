#!/bin/bash
shopt -s nullglob

DELAY=${1:-120}
QUARANTINE=/usr/local/share/ignition/data/certificates/gateway_network/quarantine

echo "init     | Beginning automatic gateway network certificate acceptance (${DELAY}s)..."

for ((i=DELAY;i>0;i--)); do
    if [[ -d "${QUARANTINE}" ]]; then
        mapfile -t cert_files < <(find "${QUARANTINE}" -name '*.der' -type f)
        for cert_file in "${cert_files[@]}"; do
            cert_file_base=$(basename "${cert_file}")
            echo "init     | Accepting Certificate: ${cert_file_base}"
            mv "${cert_file}" "${QUARANTINE}/.."
        done
    fi
    sleep 1
done

echo "init     | Finished automatic gateway network certificate acceptance."