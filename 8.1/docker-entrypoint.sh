#!/bin/bash
set -eo pipefail
shopt -s nullglob

# Local initialization
INIT_FILE=/usr/local/share/ignition/data/init.properties
XML_FILE=${IGNITION_INSTALL_LOCATION}/data/gateway.xml_clean
CMD=( "$@" )
WRAPPER_OPTIONS=( )
JAVA_OPTIONS=( )
GWCMD_OPTIONS=( )
GATEWAY_MODULE_RELINK=${GATEWAY_MODULE_RELINK:-false}
GATEWAY_JDBC_RELINK=${GATEWAY_JDBC_RELINK:-false}
GATEWAY_MODULES_ENABLED=${GATEWAY_MODULES_ENABLED:-all}
GATEWAY_QUICKSTART_ENABLED=${GATEWAY_QUICKSTART_ENABLED:-true}
EMPTY_VOLUME_PATH="/data"
DATA_VOLUME_LOCATION=$(if [ -d "${EMPTY_VOLUME_PATH}" ]; then echo "${EMPTY_VOLUME_PATH}"; else echo "/var/lib/ignition/data"; fi)

# Additional local initialization (used by background scripts)
export IGNITION_EDITION=$(echo ${IGNITION_EDITION:-FULL} | awk '{print tolower($0)}')

# Init Properties Helper Functions
# usage: add_to_init KEY ENV_VAR_NAME
#    ie: add_to_init gateway.network.0.Enabled GATEWAY_NETWORK_0_ENABLED
add_to_init () {
    # The below takes the first argument as the key and indirects to the second argument
    # to assign the value.  It will skip if the value is undefined.
    if [ ! -z ${!2:-} ]; then
        echo "init     | Added Init Setting ${1}=${!2}"
        echo "${1}=${!2}" >> "${INIT_FILE}"
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

# usage: add_to_xml KEY ENV_VAR_NAME
#   ie: add_to_xml gateway.publicAddress.httpPort GATEWAY_PUBLIC_HTTP_PORT
add_to_xml() {
    # TODO(kcollins): this currently expects the gateway XML elements to be line-delimited, 
    #                 should use an XML parser ideally.
    local operation="Added"

    # The below takes the first argument as the key and indirects to the second argument
    # to assign the value.  It will skip if the value is undefined.
    if [ ! -z ${!2:-} ]; then
        existing_key_search=$(cat ${XML_FILE} | grep key=\"${1}\" || echo NONE)
        if [ "${existing_key_search}" != "NONE" ]; then
            # remove existing entry
            sed -i "/${1}/d" "${XML_FILE}"
            operation="Updated"
        fi
        # inject at end of list
        sed -i 's|</properties>|<entry key="'${1}'">'${!2}'</entry>\n</properties>|' "${XML_FILE}"
        echo "init     | ${operation} Gateway XML Setting ${1}=${!2}"
    fi    
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
        echo >&2 "init     | error: both $var and $fileVar are set (but are exclusive)"
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

    echo -n "init     | Processing Module Enable/Disable... "

    # Perform removal of built-in modules
    declare -A module_definition_mappings
    module_definition_mappings["Alarm Notification-module.modl"]="alarm-notification"
    module_definition_mappings["Allen-Bradley Drivers-module.modl"]="allen-bradley-drivers"
    module_definition_mappings["BACnet Driver-module.modl"]="bacnet-driver"
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

# usage disable_quickstart DB_LOCATION
#   ie: disable_quickstart /var/lib/ignition/data/db/config.idb
disable_quickstart() {
    local DB_LOCATION="${1}"
    local SQLITE3=( sqlite3 "${DB_LOCATION}" )

    local quickstart_already_complete=$( "${SQLITE3[@]}" "SELECT 1 FROM SRFEATURES WHERE moduleid = '' and featurekey = 'quickStart'" )
    if [ "${quickstart_already_complete}" != "1" ]; then
        echo "init     | Disabling QuickStart Function"
        "${SQLITE3[@]}" "INSERT INTO SRFEATURES ( moduleid, featurekey ) VALUES ('', 'quickStart')"
    fi
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

    if [ ! -f "${DATA_VOLUME_LOCATION}/db/config.idb" ]; then
        # Fresh/new instance, case 1
        echo "${image_version}" > "${init_file_path}"
        upgrade_check_result=-1

        # Check if we're using an empty-volume mode
        if [ "${DATA_VOLUME_LOCATION}" == "${EMPTY_VOLUME_PATH}" ]; then
            echo "init     | New Volume detected at /data, copying existing image files prior to Gateway Launch..."
            # Move in-image data volume contents to /data to seed the volume
            cp -dpRu ${IGNITION_INSTALL_LOCATION}/data/* "${DATA_VOLUME_LOCATION}/"
            # Replace symbolic links in base install location
            rm "${IGNITION_INSTALL_LOCATION}/data" "${IGNITION_INSTALL_LOCATION}/webserver/metro-keystore"
            ln -s "${DATA_VOLUME_LOCATION}" "${IGNITION_INSTALL_LOCATION}/data"
            ln -s "${DATA_VOLUME_LOCATION}/metro-keystore" "${IGNITION_INSTALL_LOCATION}/webserver/metro-keystore"
            # Drop another symbolic link in original location for compatibility
            rm -rf /var/lib/ignition/data
            ln -s "${DATA_VOLUME_LOCATION}" /var/lib/ignition/data
        fi
    else
        # Check if we're using an empty-volume mode (concurrent run)
        if [ "${DATA_VOLUME_LOCATION}" == "${EMPTY_VOLUME_PATH}" ]; then
            echo "init     | Existing Volume detected at /data, relinking data volume locations prior to Gateway Launch..."
            # Replace symbolic links in base install location
            rm "${IGNITION_INSTALL_LOCATION}/data" "${IGNITION_INSTALL_LOCATION}/webserver/metro-keystore"
            ln -s "${DATA_VOLUME_LOCATION}" "${IGNITION_INSTALL_LOCATION}/data"
            ln -s "${DATA_VOLUME_LOCATION}/metro-keystore" "${IGNITION_INSTALL_LOCATION}/webserver/metro-keystore"
            # Remove the in-image data folder (that presumably is still fresh, extra safety check here)
            # and place a symbolic link to the /data volume for compatibility
            if [ ! -a "/var/lib/ignition/data/db/config.idb" ]; then
                rm -rf /var/lib/ignition/data
                ln -s "${DATA_VOLUME_LOCATION}" /var/lib/ignition/data
            else
                echo "init     | WARNING: Existing gateway instance detected in /var/lib/ignition/data, skipping purge/relink to ${DATA_VOLUME_LOCATION}..."
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
                echo "init     | Detected Ignition Volume from prior version (${volume_version:-unknown}), running Upgrader"
                java -classpath "lib/core/common/common.jar" com.inductiveautomation.ignition.common.upgrader.Upgrader . data logs file=ignition.conf
                echo "${image_version}" > "${init_file_path}"
                # Correlate the result of the version check
                if [ ${version_check} -eq 1 ]; then 
                    upgrade_check_result=-2
                else
                    upgrade_check_result=1
                fi
                ;;
            -1)
                echo >&2 "init     | Unknown error encountered during version comparison, aborting..."
                exit ${version_check}
                ;;
            -2)
                echo >&2 "init     | Version mismatch on existing volume (${volume_version}) versus image (${image_version}), Ignition image version must be greater or equal to volume version."
                exit ${version_check}
                ;;
            -3)
                echo >&2 "init     | Unexpected version syntax found in volume (${volume_version})"
                exit ${version_check}
                ;;
            -4)
                echo >&2 "init     | Unexpected version syntax found in image (${image_version})"
                exit ${version_check}
                ;;
            *)
                echo >&2 "init     | Unexpected error (${version_check}) during upgrade checks"
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
            echo >&2 "init     | Missing ENV variables, must specify activation token and license key for edition: ${IGNITION_EDITION}"
            exit 1
        fi
    else
        case ${IGNITION_EDITION} in
          maker | full | edge)
            ;;
          *)
            echo >&2 "init     | Invalid edition (${IGNITION_EDITION}) specified, must be 'maker', 'edge', or 'full'"
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
            echo >&2 "init     | Invalid minimum memory specification, must be integer in MB: ${GATEWAY_INIT_MEMORY}"
            exit 1
        fi    
    fi

    if [ ! -z ${GATEWAY_MAX_MEMORY:-} ]; then
        if [ ${GATEWAY_MAX_MEMORY} -ge 512 2> /dev/null ]; then
            WRAPPER_OPTIONS+=(
                "wrapper.java.maxmemory=${GATEWAY_MAX_MEMORY}"
            )
        else
            echo >&2 "init     | Invalid max memory specification, must be integer in MB: ${GATEWAY_MAX_MEMORY}"
            exit 1
        fi
    fi

    if [ ${GATEWAY_INIT_MEMORY:-256} -gt ${GATEWAY_MAX_MEMORY:-512} ]; then
        echo >&2 "init     | Invalid memory specification, min (${GATEWAY_MIN_MEMORY}) must be less than max (${GATEWAY_MAX_MEMORY})"
        exit 1
    fi

    # Check for double-volume mounts to both `/data` (empty-volume mount functionality) and `/var/lib/ignition/data` (original)
    empty_volume_check=$(grep -q -E " ${EMPTY_VOLUME_PATH} " /proc/mounts; echo $?)
    std_volume_check=$(grep -q -E " /var/lib/ignition/data " /proc/mounts; echo $?)
    if [[ ${empty_volume_check} -eq 0 && ${std_volume_check} -eq 0 ]]; then
        echo >&2 "init     | ERROR: Double Volume Link (to both /var/lib/ignition/data and ${EMPTY_VOLUME_PATH}) Detected, aborting..."
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
            if [ -z "$GATEWAY_ADMIN_PASSWORD" -a -z "$GATEWAY_RANDOM_ADMIN_PASSWORD" -a "$GATEWAY_SKIP_COMMISSIONING" != "1" ]; then
                echo 'init     | WARNING: Gateway is not initialized and no password option is specified '
                echo 'init     |   Disabling automated gateway commissioning, manual input will be required'
                export GATEWAY_PROMPT_PASSWORD=1
            fi

            # Compute random password if env variable is defined
            if [ ! -z "$GATEWAY_RANDOM_ADMIN_PASSWORD" ]; then
               export GATEWAY_ADMIN_PASSWORD="$(pwgen -1 32)"
            fi

            # Provision the init.properties file if we've got the environment variables for it
            rm -f "${DATA_VOLUME_LOCATION}/init.properties"
            add_to_init "SystemName" GATEWAY_SYSTEM_NAME
            add_to_init "UseSSL" GATEWAY_USESSL

            GATEWAY_PUBLIC_HTTP_PORT=${GATEWAY_PUBLIC_HTTP_PORT:-}
            GATEWAY_PUBLIC_HTTPS_PORT=${GATEWAY_PUBLIC_HTTPS_PORT:-}
            GATEWAY_PUBLIC_ADDRESS=${GATEWAY_PUBLIC_ADDRESS:-}
            if [ ! -z "${GATEWAY_PUBLIC_HTTP_PORT}${GATEWAY_PUBLIC_HTTPS_PORT}${GATEWAY_PUBLIC_ADDRESS}" ]; then
                # Something is defined, check individuals
                common_errors=( )
                if [[ ! ${GATEWAY_PUBLIC_HTTP_PORT} =~ ^[0-9]+$ ]]; then
                    common_errors+=( 'init     |   - HTTP Port not specified or is invalid' )
                fi
                if [[ ! ${GATEWAY_PUBLIC_HTTPS_PORT} =~ ^[0-9]+$ ]]; then
                    common_errors+=( 'init     |   - HTTPS Port not specified or is invalid' )
                fi
                if [ -z "${GATEWAY_PUBLIC_ADDRESS}" ]; then
                    common_errors+=( 'init     |   - Address not specified' )
                fi
                if [ ${#common_errors[@]} -gt 0 ]; then
                    echo >&2 'init     | ERROR: Gateway Public HTTP/HTTPS/Address must be specified together:'
                    for error in "${common_errors[@]}"; do
                        echo >&2 "$error"
                    done
                    exit 1
                fi
                
                GATEWAY_PUBLIC_AUTODETECT="false"

                add_to_xml 'gateway.publicAddress.autoDetect' GATEWAY_PUBLIC_AUTODETECT
                add_to_xml 'gateway.publicAddress.address' GATEWAY_PUBLIC_ADDRESS
                add_to_xml 'gateway.publicAddress.httpPort' GATEWAY_PUBLIC_HTTP_PORT
                add_to_xml 'gateway.publicAddress.httpsPort' GATEWAY_PUBLIC_HTTPS_PORT
            fi

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
    fi
    
    # Gateway Restore
    if [ "${GATEWAY_RESTORE_REQUIRED}" = "1" ]; then
        # Set restore path based on disabled startup condition
        if [ "${GATEWAY_RESTORE_DISABLED}" == "1" ]; then
            restore_file_path="${IGNITION_INSTALL_LOCATION}/data/__restore_disabled_$(( $(date '+%s%N') / 1000000)).gwbk"
        else
            restore_file_path="${IGNITION_INSTALL_LOCATION}/data/__restore_$(( $(date '+%s%N') / 1000000)).gwbk"
        fi

        echo 'init     | Placing restore file into location...'
        cp /restore.gwbk "${restore_file_path}"

        # Update gateway backup with module, jdbc definitions
        pushd "${IGNITION_INSTALL_LOCATION}/temp" > /dev/null 2>&1
        unzip -q "${restore_file_path}" db_backup_sqlite.idb
        disable_quickstart "${IGNITION_INSTALL_LOCATION}/temp/db_backup_sqlite.idb"
        register-modules.sh ${GATEWAY_MODULE_RELINK} "${IGNITION_INSTALL_LOCATION}/temp/db_backup_sqlite.idb"
        register-jdbc.sh ${GATEWAY_JDBC_RELINK} "${IGNITION_INSTALL_LOCATION}/temp/db_backup_sqlite.idb"
        zip -q -f "${restore_file_path}" db_backup_sqlite.idb || if [ ${ZIP_EXIT_CODE:=$?} == 12 ]; then echo "No changes to internal database needed for linked modules, jdbc drivers, or quickstart disable."; else echo "Unknown error (${ZIP_EXIT_CODE}) encountered during re-packaging of config db, exiting." && exit ${ZIP_EXIT_CODE}; fi
        popd > /dev/null 2>&1
    else
        target_db="${IGNITION_INSTALL_LOCATION}/data/db/config.idb"
        if [ -f "${target_db}" ]; then
            register-modules.sh ${GATEWAY_MODULE_RELINK} "${target_db}"
            register-jdbc.sh ${GATEWAY_JDBC_RELINK} "${target_db}"
        else
            register-modules.sh ${GATEWAY_MODULE_RELINK} "${target_db}" &
            register-jdbc.sh ${GATEWAY_JDBC_RELINK} "${target_db}" &
        fi
    fi

    # Perform module enablement/disablement
    enable_disable_modules ${GATEWAY_MODULES_ENABLED}

    # Initiate Commissioning Helper in Background
    if [ "${GATEWAY_SKIP_COMMISSIONING}" != "1" ]; then
        perform-commissioning.sh &
    fi
    
    echo 'init     | Starting Ignition Gateway...'
fi

"${CMD[@]}"
