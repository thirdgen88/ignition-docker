#!/bin/bash
set -euo pipefail
shopt -s nullglob
shopt -s inherit_errexit

# usage register-modules.sh RELINK_ENABLED DB_LOCATION
#   ie: register-modules.sh true /var/lib/ignition/data/db/config.idb
RELINK_ENABLED="${1:-false}"
DB_LOCATION="${2}"
DB_FILE=$(basename "${DB_LOCATION}")

function main() {
    if [ ! -d "/modules" ]; then
        return 0  # Silently exit if there is no /modules path
    elif [ ! -f "${DB_LOCATION}" ]; then
        echo "init     | WARNING: ${DB_FILE} not found, skipping module registration"
        return 0
    fi

    register_modules
}

function register_modules() {
    local SQLITE3=( sqlite3 "${DB_LOCATION}" )

    echo "init     | Searching for third-party modules..."

    # Remove Invalid Symbolic Links
    find "${IGNITION_INSTALL_LOCATION}/user-lib/modules" -type l ! -exec test -e {} \; -exec echo "init     | Removing invalid symlink for {}" \; -exec rm {} \;

    # Establish Symbolic Links for new modules and tie into db
    for module in /modules/*.modl; do
        local module_basename keytool module_sourcepath module_destpath
        module_basename=$(basename "${module}")
        module_sourcepath=${module}
        module_destpath="${IGNITION_INSTALL_LOCATION}/user-lib/modules/${module_basename}"
        keytool=$(which keytool)

        if [ -h "${module_destpath}" ]; then
            echo "init     | Skipping Linked Module: ${module_basename}"
            continue
        fi

        if [ -e "${module_destpath}" ]; then
            if [ "${RELINK_ENABLED}" != true ]; then
                echo "init     | Skipping existing module: ${module_basename}"
                continue
            fi
            echo "init     | Relinking Module: ${module_basename}"
            rm "${module_destpath}"
        else
            echo "init     | Linking Module: ${module_basename}"
        fi
        ln -s "${module_sourcepath}" "${module_destpath}"

        # Populate CERTIFICATES table
        local cert_info subject_name thumbprint next_certificates_id thumbprint_already_exists
        cert_info=$( unzip -qq -c "${module_sourcepath}" certificates.p7b | $keytool -printcert -v | head -n 9 ) 
        thumbprint=$( echo "${cert_info}" | grep -A 2 "Certificate fingerprints" | grep SHA1 | cut -d : -f 2- | sed -e 's/\://g' | awk '{$1=$1;print tolower($0)}' ) 
        subject_name=$( echo "${cert_info}" | grep -A 1 "Certificate\[1\]:" | grep -Po '^Owner: CN=\K(.+)(?=, OU)' | sed -e 's/"//g' )
        echo "init     |  Thumbprint: ${thumbprint}"
        echo "init     |  Subject Name: ${subject_name}"
        next_certificates_id=$( "${SQLITE3[@]}" "SELECT COALESCE(MAX(CERTIFICATES_ID)+1,1) FROM CERTIFICATES" ) 
        thumbprint_already_exists=$( "${SQLITE3[@]}" "SELECT 1 FROM CERTIFICATES WHERE lower(hex(THUMBPRINT)) = '${thumbprint}'" )
        if [ "${thumbprint_already_exists}" != "1" ]; then
            echo "init     |  Accepting Certificate as CERTIFICATES_ID=${next_certificates_id}"
            "${SQLITE3[@]}" "INSERT INTO CERTIFICATES (CERTIFICATES_ID, THUMBPRINT, SUBJECTNAME) VALUES (${next_certificates_id}, x'${thumbprint}', '${subject_name}'); UPDATE SEQUENCES SET val=${next_certificates_id} WHERE name='CERTIFICATES_SEQ'"
        else
            echo "init     |  Thumbprint already found in CERTIFICATES table, skipping INSERT"
        fi

        # Populate EULAS table
        local next_eulas_id license_crc32 module_id module_id_already_exists
        next_eulas_id=$( "${SQLITE3[@]}" "SELECT COALESCE(MAX(EULAS_ID)+1,1) FROM EULAS" ) 
        license_filename=$( unzip -qq -c "${module_sourcepath}" module.xml | grep -oP '(?<=<license>).*(?=</license)' )
        license_crc32=$( unzip -qq -c "${module_sourcepath}" "${license_filename}" | gzip -c | tail -c8 | od -t u4 -N 4 -A n | cut -c 2- ) 
        module_id=$( unzip -qq -c "${module_sourcepath}" module.xml | grep -oP '(?<=<id>).*(?=</id)' ) 
        module_id_already_exists=$( "${SQLITE3[@]}" "SELECT 1 FROM EULAS WHERE MODULEID='${module_id}' AND CRC=${license_crc32}" )
        if [ "${module_id_already_exists}" != "1" ]; then
            echo "init     |  Accepting License on your behalf as EULAS_ID=${next_eulas_id}"
            "${SQLITE3[@]}" "INSERT INTO EULAS (EULAS_ID, MODULEID, CRC) VALUES (${next_eulas_id}, '${module_id}', ${license_crc32}); UPDATE SEQUENCES SET val=${next_eulas_id} WHERE name='EULAS_SEQ'"
        else
            echo "init     |  License EULA already found in EULAS table, skipping INSERT"
        fi
    done
}

main