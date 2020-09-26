#!/bin/bash
set -eo pipefail
shopt -s nullglob

# Local initialization
INIT_FILE=/usr/local/share/ignition/data/init.properties
CMD=( "$@" )
WRAPPER_OPTIONS=( )
JAVA_OPTIONS=( )
GWCMD_OPTIONS=( )
GATEWAY_MODULE_RELINK=${GATEWAY_MODULE_RELINK:-false}
GATEWAY_JDBC_RELINK=${GATEWAY_JDBC_RELINK:-false}
GATEWAY_MODULES_ENABLED=${GATEWAY_MODULES_ENABLED:-all}
IGNITION_EDITION=$(echo ${IGNITION_EDITION:-FULL} | awk '{print tolower($0)}')
EMPTY_VOLUME_PATH="/data"
DATA_VOLUME_LOCATION=$(if [ -d "${EMPTY_VOLUME_PATH}" ]; then echo "${EMPTY_VOLUME_PATH}"; else echo "/var/lib/ignition/data"; fi)

# Init Properties Helper Functions
# usage: add_to_init KEY ENV_VAR_NAME
#    ie: add_to_init gateway.network.0.Enabled GATEWAY_NETWORK_0_ENABLED
add_to_init () {
    # The below takes the first argument as the key and indirects to the second argument
    # to assign the value.  It will skip if the value is undefined.
    if [ ! -z ${!2:-} ]; then
        echo "Added Init Setting ${1}=${!2}"
        echo "${1}=${!2}" >> $INIT_FILE
    fi
}

# Gateway Network Init Properties Helper Function
# usage: add_gw_to_init INDEX
#    ie: add_gw_to_init 0
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

# usage: evaluate_post_request URL PAYLOAD EXPECTED_CODE PHASE DESC
#   ie: evaluate_post_request http://localhost:8088/post-step '{"id":"edition","step":"edition","data":{"edition":"'maker'"}}' 201 "Commissioning" "Edition Selection"
evaluate_post_request() {
    local url="$1"
    local payload="$2"
    local expected_code="$3"
    local phase="$4"
    local desc="$5"

    local response_output_file=$(mktemp)
    local response_output=$(curl -o ${response_output_file} -i -H "content-type: application/json" -d "${payload}" "${url}" 2>&1)
    local response_code_final=$(cat ${response_output_file} | grep -Po '(?<=^HTTP/1\.1 )([0-9]+)' | tail -n 1)

    if [ -z "${response_code_final}" ]; then
        response_code_final="NO HTTP RESPONSE DETECTED"
    fi

    if [ "${response_code_final}" != "${expected_code}" ]; then
        echo >&2 "ERROR: Unexpected Response (${response_code_final}) during ${phase} phase: ${desc}"
        cat >&2 ${response_output_file}
        exit 1
    else
        # Cleanup temp file
        if [ -e "${response_output_file}" ]; then rm "${response_output_file}"; fi
    fi
}

# usage: perform_commissioning URL RESTORE_FLAG
#   ie: perform_commissioning http://localhost:8088/post-step 1
perform_commissioning() {
    local url="$1"
    local restore_flag_value="$2"
    local phase="Commissioning"

    echo "Performing commissioning actions..."

    # Select Edition - Full, Edge, Maker
    if [ "${EDITION_PHASE_REQUIRED}" == "1" ]; then
        local edition_selection="${IGNITION_EDITION}"
        if [ "${IGNITION_EDITION}" == "full" ]; then edition_selection=""; fi
        local edition_selection_payload='{"id":"edition","step":"edition","data":{"edition":"'${edition_selection}'"}}'
        evaluate_post_request "${url}" "${edition_selection_payload}" 201 "${phase}" "Edition Selection"
        echo "  IGNITION_EDITION: ${IGNITION_EDITION}"
    fi

    # Register EULA Acceptance
    local license_accept_payload='{"id":"license","step":"eula","data":{"accept":true}}'
    evaluate_post_request "${url}" "${license_accept_payload}" 201 "${phase}" "License Acceptance"
    echo "  EULA_STATUS: accepted"
    
    # Perform Activation (currently only for Maker edition)
    if [ ${IGNITION_EDITION} == "maker" -a "${MAKER_EDITION_SUPPORTED}" == "1" ]; then
        local activation_payload='{"id":"activation","data":{"licenseKey":"'${IGNITION_LICENSE_KEY}'","activationToken":"'${IGNITION_ACTIVATION_TOKEN}'"}}'
        evaluate_post_request "${url}" "${activation_payload}" 201 "${phase}" "Online Activation"
        echo "  IGNITION_LICENSE_KEY: ${IGNITION_LICENSE_KEY}"
    fi

    # Register Authentication Details
    if [ ${upgrade_check_result} -eq -1 ]; then
        local auth_user="${GATEWAY_ADMIN_USERNAME:=admin}"
        local auth_salt=$(date +%s | sha256sum | head -c 8)
        local auth_pwhash=$(echo -en ${GATEWAY_ADMIN_PASSWORD}${auth_salt} | sha256sum - | cut -c -64)
        local auth_password="[${auth_salt}]${auth_pwhash}"
        local auth_payload='{"id":"authentication","step":"authSetup","data":{"username":"'${auth_user}'","password":"'${auth_password}'"}}'
        evaluate_post_request "${url}" "${auth_payload}" 201 "${phase}" "Configuring Authentication"

        echo "  GATEWAY_ADMIN_USERNAME: ${GATEWAY_ADMIN_USERNAME}"
        if [ ! -z "$GATEWAY_RANDOM_ADMIN_PASSWORD" ]; then echo "  GATEWAY_RANDOM_ADMIN_PASSWORD: ${GATEWAY_ADMIN_PASSWORD}"; fi
    fi

    # Register Port Configuration
    local http_port="${GATEWAY_HTTP_PORT:=8088}"
    local https_port="${GATEWAY_HTTPS_PORT:=8043}"
    local use_ssl="${GATEWAY_USESSL:=false}"
    local port_payload='{"id":"connections","step":"connections","data":{"http":'${http_port}',"https":'${https_port}',"useSSL":'${use_ssl}'}}'
    evaluate_post_request "${url}" "${port_payload}" 201 "${phase}" "Configuring Connections"
    echo "  GATEWAY_HTTP_PORT: ${GATEWAY_HTTP_PORT}"
    echo "  GATEWAY_HTTPS_PORT: ${GATEWAY_HTTPS_PORT}"
    # echo "  GATEWAY_USESSL: ${GATEWAY_USESSL}"

    local finalize_key="start"
    if [ "${EDITION_PHASE_REQUIRED}" == "1" ]; then
        finalize_key="startGateway"
    fi
    local finalize_payload='{"id":"finished","data":{"'${finalize_key}'":true}}'
    evaluate_post_request "${url}" "${finalize_payload}" 200 "${phase}" "Finalizing Gateway"
}

# usage: health_check PHASE_DESC DELAY_SECS TARGET|DETAILS
#   ie: health_check "Gateway Commissioning" 60
health_check() {
    local phase="$1"
    local delay=$2
    local target=$3
    local details="null"
    if [[ "${target}" == *"|"* ]]; then
        details=$(printf ${target} | cut -d \| -f 2)
        target=$(printf ${target} | cut -d \| -f 1)
    fi
        

    # Wait for a short period for the commissioning servlet to come alive
    for ((i=${delay};i>0;i--)); do
        raw_json=$(curl -s --max-time 3 -f http://localhost:8088/StatusPing || true)
        state_value=$(echo ${raw_json} | jq -r '.["state"]')
        details_value=$(echo ${raw_json} | jq -r '.["details"]')
        if [ "${state_value}" == "${target}" -a "${details_value}" == "${details}" ]; then
                break
        fi
        sleep 1
    done
    if [ "$i" -le 0 ]; then
        echo >&2 "Failed to detect ${target} status during ${phase} after ${delay} delay."
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

# usage register_jdbc RELINK_ENABLED DB_LOCATION
#   ie: register_jdbc true /var/lib/ignition/data/db/config.idb
register_jdbc() {
    if [ ! -d "/jdbc" ]; then
        return 0  # Silently exit if there is no /jdbc path
    else
        echo "Searching for third-party JDBC drivers..."
    fi

    local RELINK_ENABLED="${1:-false}"
    local DB_LOCATION="${2}"
    local SQLITE3=( sqlite3 "${DB_LOCATION}" )

    # Get List of JDBC Drivers
    JDBC_CLASSNAMES=( $( "${SQLITE3[@]}" "SELECT CLASSNAME FROM JDBCDRIVERS;") )
    JDBC_CLASSPATHS=( $(echo ${JDBC_CLASSNAMES[@]} | sed 's/\./\//g') )

    # Remove Invalid Symbolic Links
    find ${IGNITION_INSTALL_LOCATION}/user-lib/jdbc -type l ! -exec test -e {} \; -exec echo "Removing invalid symlink for {}" \; -exec rm {} \;

    # Establish Symbolic Links for new jdbc drivers and tie into db
    for jdbc in /jdbc/*.jar; do
        local jdbc_basename=$(basename "${jdbc}")
        local jdbc_sourcepath=${jdbc}
        local jdbc_destpath="${IGNITION_INSTALL_LOCATION}/user-lib/jdbc/${jdbc_basename}"
        local jdbc_targetclasspath=""
        
        if [ -h "${jdbc_destpath}" ]; then
            echo "Skipping Linked JDBC Driver: ${jdbc_basename}"
            continue
        fi

        # Determine if jdbc driver is a candidate for linking based on searching
        # the list of existing JDBC Classname entries gathered above.
        local jdbc_listing=$(unzip -l ${jdbc})
        for ((i=0; i<${#JDBC_CLASSPATHS[*]}; i++)); do
            classpath=${JDBC_CLASSPATHS[i]}
            classname=${JDBC_CLASSNAMES[i]}
            case ${jdbc_listing} in
                *$classpath*)
                jdbc_targetclasspath=$classpath
                jdbc_targetclassname=$classname
                break;;
            esac
        done

        # If we didn't find a match, ...
        if [ -z ${jdbc_targetclassname} ]; then
            continue  # ... skip to next JDBC driver in path
        fi

        if [ -e "${jdbc_destpath}" ]; then
            if [ "${RELINK_ENABLED}" != true ]; then
                echo "Skipping existing JDBC driver: ${jdbc_basename}"
                continue
            fi
            echo "Relinking JDBC Driver: ${jdbc_basename}"
            rm "${jdbc_destpath}"
        else
            echo "Linking JDBC Driver: ${jdbc_basename}"
        fi
        ln -s "${jdbc_sourcepath}" "${jdbc_destpath}"

        # Update JDBCDRIVERS table
        echo "  Updating JDBCDRIVERS table for classname ${jdbc_targetclassname}"
        "${SQLITE3[@]}" "UPDATE JDBCDRIVERS SET JARFILE='${jdbc_basename}' WHERE CLASSNAME='${jdbc_targetclassname}'"
    done
}

# usage enable_disable_modules MODULES_ENABLED
#   ie: enable_disable_modules vision,opc-ua,sql-bridge 0
enable_disable_modules() {
    local MODULES_ENABLED="${1}"

    if [ "${MODULES_ENABLED}" = "all" ]; then 
        if [ "${IGNITION_EDITION}" == "maker" ]; then
            # Reset MODULES_ENABLED based on supported modules for Maker Edition, necessary
            # when restoring from backup, where the native edition selection commissioning doesn't
            # handle purging the modules from the base install automatically.
            MODULES_ENABLED="alarm-notification,allen-bradley-drivers,logix-driver,modbus-driver-v2,omron-driver,opc-ua,perspective,reporting,serial-support-gateway,sfc,siemens-drivers,sql-bridge,tag-historian,udp-tcp-drivers,user-manual,web-developer"
        else
            return 0
        fi
    fi

    echo -n "Processing Module Enable/Disable... "

    # Perform removal of built-in modules
    declare -A module_definition_mappings
    module_definition_mappings["Alarm Notification-module.modl"]="alarm-notification"
    module_definition_mappings["Allen-Bradley Drivers-module.modl"]="allen-bradley-drivers"
    module_definition_mappings["DNP3-Driver.modl"]="dnp3-driver"
    module_definition_mappings["Enterprise Administration-module.modl"]="enterprise-administration"
    module_definition_mappings["Logix Driver-module.modl"]="logix-driver"
    module_definition_mappings["Mobile-module.modl"]="mobile-module"
    module_definition_mappings["Modbus Driver v2-module.modl"]="modbus-driver-v2"
    module_definition_mappings["Omron-Driver.modl"]="omron-driver"
    module_definition_mappings["OPC-UA-module.modl"]="opc-ua"
    module_definition_mappings["Perspective-module.modl"]="perspective"
    module_definition_mappings["Reporting-module.modl"]="reporting"
    module_definition_mappings["Serial Support Client-module.modl"]="serial-support-client"
    module_definition_mappings["Serial Support Gateway-module.modl"]="serial-support-gateway"
    module_definition_mappings["SFC-module.modl"]="sfc"
    module_definition_mappings["Siemens Drivers-module.modl"]="siemens-drivers"
    module_definition_mappings["SMS Notification-module.modl"]="sms-notification"
    module_definition_mappings["SQL Bridge-module.modl"]="sql-bridge"
    module_definition_mappings["Symbol Factory-module.modl"]="symbol-factory"
    module_definition_mappings["Tag Historian-module.modl"]="tag-historian"
    module_definition_mappings["UDP and TCP Drivers-module.modl"]="udp-tcp-drivers"
    module_definition_mappings["User Manual-module.modl"]="user-manual"
    module_definition_mappings["Vision-module.modl"]="vision"
    module_definition_mappings["Voice Notification-module.modl"]="voice-notification"
    module_definition_mappings["Web Browser Module.modl"]="web-browser"
    module_definition_mappings["Web Developer Module.modl"]="web-developer"

    # Create modules-disabled directory if doesn't already exist
    modules_path="${IGNITION_INSTALL_LOCATION}/user-lib/modules"
    modules_disabled_path="${IGNITION_INSTALL_LOCATION}/user-lib/modules-disabled"
    if [ ! -d "${modules_disabled_path}" ]; then
        mkdir -p "${modules_disabled_path}"
    fi

    # Read an array modules_enabled with the list of enabled module definitions
    mapfile -d , -t modules_enabled <<< "$MODULES_ENABLED"

    # Find the currently present modules in the installation
    mapfile -t modules_list < <(find "${modules_path}" -name '*.modl' -type f -printf "%f\n")

    for module_filename in "${modules_list[@]}"; do
        module_filepath="${modules_path}/${module_filename}"
        module_definition="${module_definition_mappings[${module_filename}]}"

        if [ -z "${module_definition}" ]; then
            printf "\n  Unknown module ${module_filename}, skipping..."
            continue
        fi
        
        # Search for Module Definition in List of Modules Enabled
        module_found=0
        for (( n=0; n<${#modules_enabled[@]}; n++ )); do
            if [ ${module_definition} = ${modules_enabled[$n]} ]; then
                module_found+=1
                break
            fi
        done
        
        # If we didn't find it, move to disabled path
        if [ ${module_found} -eq 0 ]; then
            printf "\n  Disabling '${module_filename}'"
            mv "${module_filepath}" "${modules_disabled_path}/"
        fi
    done
    echo
}

# usage register_modules RELINK_ENABLED DB_LOCATION
#   ie: register_modules true /var/lib/ignition/data/db/config.idb
register_modules() {
    if [ ! -d "/modules" ]; then
        return 0  # Silently exit if there is no /modules path
    else
        echo "Searching for third-party modules..."
    fi

    local RELINK_ENABLED="${1:-false}"
    local DB_LOCATION="${2}"
    local SQLITE3=( sqlite3 "${DB_LOCATION}" )

    # Remove Invalid Symbolic Links
    find ${IGNITION_INSTALL_LOCATION}/user-lib/modules -type l ! -exec test -e {} \; -exec echo "Removing invalid symlink for {}" \; -exec rm {} \;

    # Establish Symbolic Links for new modules and tie into db
    for module in /modules/*.modl; do
        local module_basename=$(basename "${module}")
        local module_sourcepath=${module}
        local module_destpath="${IGNITION_INSTALL_LOCATION}/user-lib/modules/${module_basename}"
        local keytool=$(which keytool)

        if [ -h "${module_destpath}" ]; then
            echo "Skipping Linked Module: ${module_basename}"
            continue
        fi

        if [ -e "${module_destpath}" ]; then
            if [ "${RELINK_ENABLED}" != true ]; then
                echo "Skipping existing module: ${module_basename}"
                continue
            fi
            echo "Relinking Module: ${module_basename}"
            rm "${module_destpath}"
        else
            echo "Linking Module: ${module_basename}"
        fi
        ln -s "${module_sourcepath}" "${module_destpath}"

        # Populate CERTIFICATES table
        local cert_info=$( unzip -qq -c "${module_sourcepath}" certificates.p7b | $keytool -printcert -v | head -n 9 )
        local thumbprint=$( echo "${cert_info}" | grep -A 2 "Certificate fingerprints" | grep SHA1 | cut -d : -f 2- | sed -e 's/\://g' | awk '{$1=$1;print tolower($0)}' )
        local subject_name=$( echo "${cert_info}" | grep -A 1 "Certificate\[1\]:" | grep -Po '^Owner: CN=\K(.+)(?=, OU)' | sed -e 's/"//g' )
        echo "  Thumbprint: ${thumbprint}"
        echo "  Subject Name: ${subject_name}"
        local next_certificates_id=$( "${SQLITE3[@]}" "SELECT COALESCE(MAX(CERTIFICATES_ID)+1,1) FROM CERTIFICATES" )
        local thumbprint_already_exists=$( "${SQLITE3[@]}" "SELECT 1 FROM CERTIFICATES WHERE lower(hex(THUMBPRINT)) = '${thumbprint}'" )
        if [ "${thumbprint_already_exists}" != "1" ]; then
            echo "  Accepting Certificate as CERTIFICATES_ID=${next_certificates_id}"
            "${SQLITE3[@]}" "INSERT INTO CERTIFICATES (CERTIFICATES_ID, THUMBPRINT, SUBJECTNAME) VALUES (${next_certificates_id}, x'${thumbprint}', '${subject_name}'); UPDATE SEQUENCES SET val=${next_certificates_id} WHERE name='CERTIFICATES_SEQ'"
        else
            echo "  Thumbprint already found in CERTIFICATES table, skipping INSERT"
        fi

        # Populate EULAS table
        local next_eulas_id=$( "${SQLITE3[@]}" "SELECT COALESCE(MAX(EULAS_ID)+1,1) FROM EULAS" )
        local license_crc32=$( unzip -qq -c "${module_sourcepath}" license.html | gzip -c | tail -c8 | od -t u4 -N 4 -A n | cut -c 2- )
        local module_id=$( unzip -qq -c "${module_sourcepath}" module.xml | grep -oP '(?<=<id>).*(?=</id)' )
        local module_id_already_exists=$( "${SQLITE3[@]}" "SELECT 1 FROM EULAS WHERE MODULEID='${module_id}' AND CRC=${license_crc32}" )
        if [ "${module_id_already_exists}" != "1" ]; then
            echo "  Accepting License on your behalf as EULAS_ID=${next_eulas_id}"
            "${SQLITE3[@]}" "INSERT INTO EULAS (EULAS_ID, MODULEID, CRC) VALUES (${next_eulas_id}, '${module_id}', ${license_crc32}); UPDATE SEQUENCES SET val=${next_eulas_id} WHERE name='EULAS_SEQ'"
        else
            echo "  License EULA already found in EULAS table, skipping INSERT"
        fi
    done
}

# usage: compare_versions IMAGE_VERSION VOLUME_VERSION
#   ie: compare_versions "8.0.2" "7.9.11"
# return values: -4 = unexpected version syntax in image version
#                -3 = unexpected version syntax in volume version
#                -2 = image version is lower than volume version - invalid configuration!
#                -1 = unknown comparison result
#                 0 = image version is equal to volume version - no action required
#                 1 = image version is greater than volume version or volume version is empty - upgrade required w/ commissioning
#                 2 = image version is greater than volume version - upgrade required w/o commissioning
compare_versions() {
    local return_value=-1
    local version_regex_pattern='^([0-9]*)\.([0-9]*)\.([0-9]*)$'
    local image_version="$1"
    local volume_version="$2"

    # Extract Version Numbers
    [[ $image_version =~ $version_regex_pattern ]]
    local image_version_arr=( ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} )
    [[ $volume_version =~ $version_regex_pattern ]]
    local volume_version_arr=( ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} )
    
    if [ ${#image_version_arr[@]} -ne 3 ]; then
        return_value=-4
    elif [ -z "${volume_version}" ]; then
        # Special Case for detecting Ignition 8 images that might not have a volume version declared in the init file path
        if [ -L "${IGNITION_INSTALL_LOCATION}/data" ]; then
            return_value=2  # bypass commissioning
        else
            return_value=1
        fi
    elif [ ${#volume_version_arr[@]} -ne 3 ]; then
        return_value=-3
    elif [ "${image_version}" = "${volume_version}" ]; then
        return_value=0
    else
        # Implictly map the upgrade case (no commissioning required) ...
        return_value=2  
        
        for (( i = 0; i < 3; i++ )); do
            if [ ${volume_version_arr[$i]} -lt ${image_version_arr[$i]} ]; then
                return_value=1  # Major Version Upgrade Detected, commissioning will be required
                break
            elif [ ${volume_version_arr[$i]} -gt ${image_version_arr[$i]} ]; then
                return_value=-2  # ... and flag lower case (invalid) if detected
                break
            fi
        done        
    fi

    echo ${return_value}
}

# usage: check_for_upgrade INIT_COMPLETE_FILEPATH
#   ie: check_for_upgrade "/usr/local/share/ignition/data/.docker-init-complete"
# return values: -2 = Upgrade Performed, Major Upgrade Detected
#                -1 = Init file missing, fresh/new instance
#                 0 = No upgrade needed
#                 1 = Upgrade Performed, Minor Upgrade Detected
check_for_upgrade() {
    local version_regex_pattern='([0-9]*)\.([0-9]*)\.([0-9]*)'
    local init_file_path="$1"
    local image_version=$(cat "${IGNITION_INSTALL_LOCATION}/lib/install-info.txt" | grep gateway.version | cut -d = -f 2 )

    # Strip "-SNAPSHOT" off...  FOR NIGHTLY BUILDS ONLY
    if [[ ${BUILD_EDITION} == *"NIGHTLY"* ]]; then
        image_version=$(echo ${image_version} | sed "s/-SNAPSHOT$//")
    fi

    # Check version compatibility for Maker edition
    local version_check=$(compare_versions "${image_version}" "8.0.14")
    if [ ${version_check} -lt 0 -a "${IGNITION_EDITION}" == "maker" ]; then
        echo >&2 "Maker Edition not supported until 8.0.14"
        exit ${version_check}
    else
        export MAKER_EDITION_SUPPORTED=1
    fi

    # Evaluate version to determine if Edition Selection phase is required in Gateway Commissioning
    if [ ${version_check} -ge 0 ]; then  # We're greater or equal to 8.0.14 (set above)
        export EDITION_PHASE_REQUIRED=1
    else
        export EDITION_PHASE_REQUIRED=0
    fi

    if [ ! -f "${DATA_VOLUME_LOCATION}/db/config.idb" ]; then
        # Fresh/new instance, case 1
        echo "${image_version}" > "${init_file_path}"
        upgrade_check_result=-1

        # Check if we're using an empty-volume mode
        if [ "${DATA_VOLUME_LOCATION}" == "${EMPTY_VOLUME_PATH}" ]; then
            # Move in-image data volume contents to /data to seed the volume
            mv ${IGNITION_INSTALL_LOCATION}/data/* "${DATA_VOLUME_LOCATION}/"
            # Replace symbolic links in base install location
            rm "${IGNITION_INSTALL_LOCATION}/data" "${IGNITION_INSTALL_LOCATION}/temp"
            ln -s "${DATA_VOLUME_LOCATION}" "${IGNITION_INSTALL_LOCATION}/data"
            ln -s "${DATA_VOLUME_LOCATION}/temp" "${IGNITION_INSTALL_LOCATION}/temp"
            # Drop another symbolic link in original location for compatibility
            rmdir /var/lib/ignition/data
            ln -s "${DATA_VOLUME_LOCATION}" /var/lib/ignition/data
        fi
    else
        # Check if we're using an empty-volume mode (concurrent run)
        if [ "${DATA_VOLUME_LOCATION}" == "${EMPTY_VOLUME_PATH}" ]; then
            # Replace symbolic links in base install location
            rm "${IGNITION_INSTALL_LOCATION}/data" "${IGNITION_INSTALL_LOCATION}/temp"
            ln -s "${DATA_VOLUME_LOCATION}" "${IGNITION_INSTALL_LOCATION}/data"
            ln -s "${DATA_VOLUME_LOCATION}/temp" "${IGNITION_INSTALL_LOCATION}/temp"
            # Remove the in-image data folder (that presumably is still fresh, extra safety check here)
            # and place a symbolic link to the /data volume for compatibility
            if [ ! -a "/var/lib/ignition/data/db/config.idb" ]; then
                rm -rf /var/lib/ignition/data
                ln -s "${DATA_VOLUME_LOCATION}" /var/lib/ignition/data
            else
                echo "WARNING: Existing gateway instance detected in /var/lib/ignition/data, skipping purge/relink to ${DATA_VOLUME_LOCATION}..."
            fi
        fi

        if [ -f "${init_file_path}" ]; then
            local volume_version=$(cat ${init_file_path})
        fi
        local version_check=$(compare_versions "${image_version}" "${volume_version}")

        case ${version_check} in
            0)
                upgrade_check_result=0
                ;;
            1 | 2)
                # Init file present, upgrade required
                echo "Detected Ignition Volume from prior version (${volume_version:-unknown}), running Upgrader"
                java -classpath "lib/core/common/common.jar" com.inductiveautomation.ignition.common.upgrader.Upgrader . data logs file=ignition.conf
                echo "Performing additional required volume updates"
                mkdir -p "${DATA_VOLUME_LOCATION}/temp"
                echo "${image_version}" > "${init_file_path}"
                # Correlate the result of the version check
                if [ ${version_check} -eq 1 ]; then 
                    upgrade_check_result=-2
                else
                    upgrade_check_result=1
                fi
                ;;
            -1)
                echo >&2 "Unknown error encountered during version comparison, aborting..."
                exit ${version_check}
                ;;
            -2)
                echo >&2 "Version mismatch on existing volume (${volume_version}) versus image (${image_version}), Ignition image version must be greater or equal to volume version."
                exit ${version_check}
                ;;
            -3)
                echo >&2 "Unexpected version syntax found in volume (${volume_version})"
                exit ${version_check}
                ;;
            -4)
                echo >&2 "Unexpected version syntax found in image (${image_version})"
                exit ${version_check}
                ;;
            *)
                echo >&2 "Unexpected error (${version_check}) during upgrade checks"
                exit ${version_check}
                ;;
        esac
    fi
}

# Collect additional arguments if we're running the gateway
if [ "$1" = './ignition-gateway' ]; then
    # Validate environment variables surrounding IGNITION_EDITION
    file_env 'IGNITION_ACTIVATION_TOKEN'
    file_env 'IGNITION_LICENSE_KEY'
    if [[ ${IGNITION_EDITION} =~ "maker" ]]; then
        # Ensure that License Key and Activation Tokens are supplied
        if [ -z "${IGNITION_ACTIVATION_TOKEN+x}" -o -z "${IGNITION_LICENSE_KEY+x}" ]; then
            echo >&2 "Missing ENV variables, must specify activation token and license key for edition: ${IGNITION_EDITION}"
            exit 1
        fi
    else
        case ${IGNITION_EDITION} in
          maker | full | edge)
            ;;
          *)
            echo >&2 "Invalid edition (${IGNITION_EDITION}) specified, must be 'maker', 'edge', or 'full'"
            exit 1
            ;;
        esac
    fi

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

    # Check for double-volume mounts to both `/data` (empty-volume mount functionality) and `/var/lib/ignition/data` (original)
    empty_volume_check=$(grep -q -E " ${EMPTY_VOLUME_PATH} " /proc/mounts; echo $?)
    std_volume_check=$(grep -q -E " /var/lib/ignition/data " /proc/mounts; echo $?)
    if [[ ${empty_volume_check} -eq 0 && ${std_volume_check} -eq 0 ]]; then
        echo >&2 "ERROR: Double Volume Link (to both /var/lib/ignition/data and ${EMPTY_VOLUME_PATH}) Detected, aborting..."
        exit 1
    fi

    # Collect any other declared wrapper custom options by checking if any of the environment
    # variables are defined.  Ones that are defined will be added to the wrapper options.
    declare -A WRAPPER_CUSTOM_OPTIONS=(
        [WRAPPER_CONSOLE_FLUSH]=wrapper.console.flush
        [WRAPPER_CONSOLE_LOGLEVEL]=wrapper.console.loglevel
        [WRAPPER_CONSOLE_FORMAT]=wrapper.console.format
        [WRAPPER_SYSLOG_LOGLEVEL]=wrapper.syslog.loglevel
        [WRAPPER_SYSLOG_LOCAL_HOST]=wrapper.syslog.local.host
        [WRAPPER_SYSLOG_REMOTE_HOST]=wrapper.syslog.remote.host
        [WRAPPER_SYSLOG_REMOTE_PORT]=wrapper.syslog.remote.port
    )
    for opt in "${!WRAPPER_CUSTOM_OPTIONS[@]}"; do
        if [ ! -z ${!opt} ]; then
            WRAPPER_OPTIONS+=(
                "${WRAPPER_CUSTOM_OPTIONS[$opt]}=${!opt}"
            )
        fi
    done

    # Combine CMD array with wrapper and explicit java options
    if [ ! -z ${JAVA_OPTIONS:-} ]; then
        JAVA_OPTIONS=( "--" "${JAVA_OPTIONS[@]}" )
    fi
    CMD+=(
        "${WRAPPER_OPTIONS[@]}"
        "${JAVA_OPTIONS[@]}"
    )

    # Check for Upgrade and Mark Initialization File
    check_for_upgrade "${DATA_VOLUME_LOCATION}/.docker-init-complete"

    if [ ${upgrade_check_result} -lt 0 ]; then
        # Only perform Provisioning on Fresh/New Instance
        if [ ${upgrade_check_result} -eq -1 ]; then
            # Check Prerequisites
            file_env 'GATEWAY_ADMIN_PASSWORD'
            if [ -z "$GATEWAY_ADMIN_PASSWORD" -a -z "$GATEWAY_RANDOM_ADMIN_PASSWORD" ]; then
                echo >&2 'ERROR: Gateway is not initialized and no password option is specified '
                echo >&2 '  You need to specify either GATEWAY_ADMIN_PASSWORD or GATEWAY_RANDOM_ADMIN_PASSWORD'
                exit 1
            fi

            # Compute random password if env variable is defined
            if [ ! -z "$GATEWAY_RANDOM_ADMIN_PASSWORD" ]; then
               export GATEWAY_ADMIN_PASSWORD="$(pwgen -1 32)"
            fi

            # Provision the init.properties file if we've got the environment variables for it
            rm -f "${DATA_VOLUME_LOCATION}/init.properties"
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

            # Perform some staging for the rest of the provisioning process
            if [ -f "/restore.gwbk" ]; then
                export GATEWAY_RESTORE_REQUIRED="1"
            else
                export GATEWAY_RESTORE_REQUIRED="0"
            fi
        fi
    
        # Initialize Gateway
        echo "Provisioning will be logged here: ${IGNITION_INSTALL_LOCATION}/logs/provisioning.log"
        "${CMD[@]}" > ${IGNITION_INSTALL_LOCATION}/logs/provisioning.log 2>&1 &
        pid="$!"

        echo "Waiting for commissioning servlet to become active..."
        health_check "Commissioning Phase" ${IGNITION_COMMISSIONING_DELAY:=30} "RUNNING|COMMISSIONING"
        perform_commissioning "http://localhost:8088/post-step"
        health_check "Post Commissioning" ${IGNITION_STARTUP_DELAY:=120} "RUNNING"
        stop_process $pid
    fi
    
    # Gateway Restore
    if [ "${GATEWAY_RESTORE_REQUIRED}" = "1" ]; then
        # Set restore path based on disabled startup condition
        if [ "${GATEWAY_RESTORE_DISABLED}" == "1" ]; then
            restore_file_path="${IGNITION_INSTALL_LOCATION}/data/__restore_disabled_$(( $(date '+%s%N') / 1000000)).gwbk"
        else
            restore_file_path="${IGNITION_INSTALL_LOCATION}/data/__restore_$(( $(date '+%s%N') / 1000000)).gwbk"
        fi

        echo 'Placing restore file into location...'
        cp /restore.gwbk "${restore_file_path}"

        if [[ (-d "/modules" && $(ls -1 /modules | wc -l) > 0) || (-d "/jdbc" && $(ls -1 /jdbc | wc -l) > 0) ]]; then
            pushd "${IGNITION_INSTALL_LOCATION}/temp" > /dev/null 2>&1
            unzip -q "${restore_file_path}" db_backup_sqlite.idb
            register_modules ${GATEWAY_MODULE_RELINK} "${IGNITION_INSTALL_LOCATION}/temp/db_backup_sqlite.idb"
            register_jdbc ${GATEWAY_JDBC_RELINK} "${IGNITION_INSTALL_LOCATION}/temp/db_backup_sqlite.idb"
            zip -q -f "${restore_file_path}" db_backup_sqlite.idb || if [ ${ZIP_EXIT_CODE:=$?} == 12 ]; then echo "No changes to internal database needed for linked modules."; else echo "Unknown error (${ZIP_EXIT_CODE}) encountered during re-packaging of config db, exiting." && exit ${ZIP_EXIT_CODE}; fi
            popd > /dev/null 2>&1
        fi
    else
        register_modules ${GATEWAY_MODULE_RELINK} "${IGNITION_INSTALL_LOCATION}/data/db/config.idb"
        register_jdbc ${GATEWAY_JDBC_RELINK} "${IGNITION_INSTALL_LOCATION}/data/db/config.idb"
    fi

    # Perform module enablement/disablement
    enable_disable_modules ${GATEWAY_MODULES_ENABLED}

    echo 'Starting Ignition Gateway...'
fi

exec "${CMD[@]}"
