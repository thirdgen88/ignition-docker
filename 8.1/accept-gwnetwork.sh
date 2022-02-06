#!/bin/bash
shopt -s nullglob

DELAY=${1:-120}
declare QUARANTINE TRUSTED
if [[ -d "${IGNITION_INSTALL_LOCATION}/data/gateway-network/server/security/pki/rejected" ]]; then
    QUARANTINE="${IGNITION_INSTALL_LOCATION}/data/gateway-network/server/security/pki/rejected"
    TRUSTED="${IGNITION_INSTALL_LOCATION}/data/gateway-network/server/security/pki/trusted/certs/"
else
    # fall-back for 8.1.13 and older
    QUARANTINE="${IGNITION_INSTALL_LOCATION}/data/certificates/gateway_network/quarantine"
    TRUSTED="$(dirname "${QUARANTINE}")/"
fi


echo "init     | Beginning automatic gateway network certificate acceptance (${DELAY}s)..."

for ((i=DELAY;i>0;i--)); do
    if [[ -d "${QUARANTINE}" ]]; then
        mapfile -t cert_files < <(find "${QUARANTINE}" \( -name '*.der' -or -name '*.pem' -or -name '*.crt' \) -type f)
        for cert_file in "${cert_files[@]}"; do
            cert_file_base=$(basename "${cert_file}")
            echo "init     | Accepting Certificate: ${cert_file_base}"
            mv "${cert_file}" "${TRUSTED}"
        done
    fi
    sleep 1
done

echo "init     | Finished automatic gateway network certificate acceptance."