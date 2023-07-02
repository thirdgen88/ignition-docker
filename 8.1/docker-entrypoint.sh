#!/usr/bin/env bash
set -eo pipefail
shopt -s nullglob
if [[ "${ENTRYPOINT_DEBUG_ENABLED}" = "true" ]]; then set -x; fi

# Local initialization
INIT_FILE=/usr/local/share/ignition/data/init.properties
XML_FILE=${IGNITION_INSTALL_LOCATION}/data/gateway.xml_clean
CMD=( "$@" )
BASE_WRAPPER_OPTIONS=( 
    "wrapper.console.loglevel=NONE"
    "wrapper.logfile.format=PTM"
    "wrapper.logfile.rollmode=NONE"
)
WRAPPER_OPTIONS=( )
JVM_OPTIONS=( )
APP_OPTIONS=( )
GATEWAY_MODULE_RELINK=${GATEWAY_MODULE_RELINK:-false}
GATEWAY_JDBC_RELINK=${GATEWAY_JDBC_RELINK:-false}
GATEWAY_MODULES_ENABLED=${GATEWAY_MODULES_ENABLED:-all}
GATEWAY_QUICKSTART_ENABLED=${GATEWAY_QUICKSTART_ENABLED:-true}
declare -l GATEWAY_NETWORK_UUID=${GATEWAY_NETWORK_UUID:-}
EMPTY_VOLUME_PATH="/data"
DATA_VOLUME_LOCATION=$( (grep -q -E " ${EMPTY_VOLUME_PATH} " /proc/mounts && echo "${EMPTY_VOLUME_PATH}") || echo "/var/lib/ignition/data" )

# Extraction of Ignition Base Image Version
IMAGE_VERSION=$(grep gateway.version < "${IGNITION_INSTALL_LOCATION}/lib/install-info.txt" | cut -d = -f 2 )
# Strip "-SNAPSHOT" off...  FOR NIGHTLY BUILDS ONLY
if [[ ${BUILD_EDITION} == *"NIGHTLY"* ]]; then
    IMAGE_VERSION="${IMAGE_VERSION//-SNAPSHOT/}"
fi
# Strip "-rcN" off as well, if applicable.
# shellcheck disable=SC2001   # since we really need a regex here
IMAGE_VERSION=$(echo "${IMAGE_VERSION}" | sed 's/-rc[0-9]$//')

# Init Properties Helper Functions
# usage: add_to_init KEY ENV_VAR_NAME
#    ie: add_to_init gateway.network.0.Enabled GATEWAY_NETWORK_0_ENABLED
add_to_init () {
    # The below takes the first argument as the key and indirects to the second argument
    # to assign the value.  It will skip if the value is undefined.
    if [ -n "${!2:-}" ]; then
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
    for key in "${!settings[@]}"; do
        value=${settings[$key]}
        if [ -n "${!value:-}" ]; then
            add_to_init "gateway.network.${1}.${key}" "${value}"
        fi
    done

    # Handle EnableSSL explicitly, default to true if not specified
    enablessl=GATEWAY_NETWORK_${1}_ENABLESSL
    declare "$enablessl=${!enablessl:-true}"
    add_to_init "gateway.network.${1}.EnableSSL" "${enablessl}"

    # If EnableSSL defaulted to true and Port was not specified, default to 8060
    port=GATEWAY_NETWORK_${1}_PORT
    declare "$port=${!port:-8060}"
    add_to_init "gateway.network.${1}.Port" "${port}"
}

# usage: add_to_xml KEY ENV_VAR_NAME
#   ie: add_to_xml gateway.publicAddress.httpPort GATEWAY_PUBLIC_HTTP_PORT
add_to_xml() {
    # TODO(kcollins): this currently expects the gateway XML elements to be line-delimited, 
    #                 should use an XML parser ideally.
    local operation="Added"

    # The below takes the first argument as the key and indirects to the second argument
    # to assign the value.  It will skip if the value is undefined.
    if [ -n "${!2:-}" ]; then
        existing_key_search=$(grep "key=\"${1}\"" < "${XML_FILE}" || echo NONE)
        if [ "${existing_key_search}" != "NONE" ]; then
            # remove existing entry
            sed -i "/${1}/d" "${XML_FILE}"
            operation="Updated"
        fi
        # inject at end of list
        sed -i 's|</properties>|<entry key="'"${1}"'">'"${!2}"'</entry>\n</properties>|' "${XML_FILE}"
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

    if [[ -n "${val:-}" ]]; then
        export "$var"="$val"
    fi
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
            MODULES_ENABLED="alarm-notification,allen-bradley-drivers,logix-driver,mitsubishi-driver,modbus-driver-v2,omron-driver,opc-ua,perspective,reporting,serial-support-gateway,sfc,siemens-drivers,sql-bridge,tag-historian,udp-tcp-drivers,user-manual,web-developer"
        else
            return 0
        fi
    fi

    echo -n "init     | Processing Module Enable/Disable... "

    # Perform removal of built-in modules
    declare -A module_definition_mappings=(
        ["Alarm Notification-module.modl"]="alarm-notification"
        ["Allen-Bradley Drivers-module.modl"]="allen-bradley-drivers"
        ["BACnet Driver-module.modl"]="bacnet-driver"
        ["DNP3-Driver.modl"]="dnp3-driver"
        ["Enterprise Administration-module.modl"]="enterprise-administration"
        ["IEC 61850 Driver-module.modl"]="iec-61850-driver"
        ["Logix Driver-module.modl"]="logix-driver"
        ["Mitsubishi-Driver.modl"]="mitsubishi-driver"
        ["Mobile-module.modl"]="mobile-module"
        ["Modbus Driver v2-module.modl"]="modbus-driver-v2"
        ["Omron-Driver.modl"]="omron-driver"
        ["OPC-UA-module.modl"]="opc-ua"
        ["Perspective-module.modl"]="perspective"
        ["Reporting-module.modl"]="reporting"
        ["Serial Support Client-module.modl"]="serial-support-client"
        ["Serial Support Gateway-module.modl"]="serial-support-gateway"
        ["SFC-module.modl"]="sfc"
        ["Siemens Drivers-module.modl"]="siemens-drivers"
        ["SMS Notification-module.modl"]="sms-notification"
        ["SQL Bridge-module.modl"]="sql-bridge"
        ["Symbol Factory-module.modl"]="symbol-factory"
        ["Tag Historian-module.modl"]="tag-historian"
        ["UDP and TCP Drivers-module.modl"]="udp-tcp-drivers"
        ["User Manual-module.modl"]="user-manual"
        ["Vision-module.modl"]="vision"
        ["Voice Notification-module.modl"]="voice-notification"
        ["Web Browser Module.modl"]="web-browser"
        ["Web Developer Module.modl"]="web-developer"
    )

    # Create modules-disabled directory if doesn't already exist
    modules_path="${IGNITION_INSTALL_LOCATION}/user-lib/modules"
    modules_disabled_path="${IGNITION_INSTALL_LOCATION}/user-lib/modules-disabled"
    if [ ! -d "${modules_disabled_path}" ]; then
        mkdir -p "${modules_disabled_path}"
    fi

    # Read an array modules_enabled with the list of enabled module definitions
    IFS=',' read -ra modules_enabled <<< "${MODULES_ENABLED}"

    # Find the currently present modules in the installation
    mapfile -d '' modules_list < <(find "${modules_path}" -name '*.modl' -type f -print0)

    for module_filepath in "${modules_list[@]}"; do
        module_filename=$(basename "${module_filepath}")
        module_definition="${module_definition_mappings[${module_filename}]}"

        if [ -z "${module_definition}" ]; then
            printf "\n  Unknown module %s, skipping..." "${module_filename}"
            continue
        fi
        
        # Search for Module Definition in List of Modules Enabled
        module_found=0
        for (( n=0; n<${#modules_enabled[@]}; n++ )); do
            if [ "${module_definition}" = "${modules_enabled[$n]}" ]; then
                module_found+=1
                break
            fi
        done
        
        # If we didn't find it, move to disabled path
        if [ ${module_found} -eq 0 ]; then
            printf "\n  Disabling '%s'" "${module_filename}"
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
    local quickstart_already_complete
    quickstart_already_complete=$( "${SQLITE3[@]}" "SELECT 1 FROM SRFEATURES WHERE moduleid = '' and featurekey = 'quickStart'" )
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
    local image_version_arr=( "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" )
    [[ $volume_version =~ $version_regex_pattern ]]
    local volume_version_arr=( "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" )
    
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
            if [[ ${volume_version_arr[$i]} -lt ${image_version_arr[$i]} ]]; then
                return_value=1  # Major Version Upgrade Detected, commissioning will be required
                break
            elif [[ ${volume_version_arr[$i]} -gt ${image_version_arr[$i]} ]]; then
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
    local volume_version
    local version_check
    local empty_volume_check
    empty_volume_check=$(grep -q -E " ${EMPTY_VOLUME_PATH} " /proc/mounts; echo $?)

    if [ ! -f "${DATA_VOLUME_LOCATION}/db/config.idb" ]; then
        # Fresh/new instance, case 1
        echo "${IMAGE_VERSION}" > "${init_file_path}"
        upgrade_check_result=-1

        # Check if we're using an empty-volume mode
        if [[ ${empty_volume_check} -eq 0 ]]; then
            echo "init     | New Volume detected at /data, copying existing image files prior to Gateway Launch..."
            # Move in-image data volume contents to /data to seed the volume
            cp -Ru --preserve=links "${IGNITION_INSTALL_LOCATION}/data/"* "${DATA_VOLUME_LOCATION}/"
            # Replace symbolic links in base install location
            rm -f "${IGNITION_INSTALL_LOCATION}/data" \
                "${IGNITION_INSTALL_LOCATION}/webserver/metro-keystore" \
                "${IGNITION_INSTALL_LOCATION}/webserver/csr.pfx" \
                "${IGNITION_INSTALL_LOCATION}/webserver/ssl.pfx"
            ln -s "${DATA_VOLUME_LOCATION}" "${IGNITION_INSTALL_LOCATION}/data"
            ln -s "${DATA_VOLUME_LOCATION}/local/metro-keystore" "${IGNITION_INSTALL_LOCATION}/webserver/metro-keystore"
            ln -s "${DATA_VOLUME_LOCATION}/local/csr.pfx" "${IGNITION_INSTALL_LOCATION}/webserver/csr.pfx"
            ln -s "${DATA_VOLUME_LOCATION}/local/ssl.pfx" "${IGNITION_INSTALL_LOCATION}/webserver/ssl.pfx"
            # Drop another symbolic link in original location for compatibility
            rm -rf /var/lib/ignition/data
            ln -s "${DATA_VOLUME_LOCATION}" /var/lib/ignition/data
        fi
    else
        # Check if we're using an empty-volume mode (concurrent run)
        if [[ ${empty_volume_check} -eq 0 ]]; then
            echo "init     | Existing Volume detected at /data, relinking data volume locations prior to Gateway Launch..."
            # Replace symbolic links in base install location
            rm -f "${IGNITION_INSTALL_LOCATION}/data" \
                "${IGNITION_INSTALL_LOCATION}/webserver/metro-keystore" \
                "${IGNITION_INSTALL_LOCATION}/webserver/csr.pfx" \
                "${IGNITION_INSTALL_LOCATION}/webserver/ssl.pfx"
            ln -s "${DATA_VOLUME_LOCATION}" "${IGNITION_INSTALL_LOCATION}/data"
            ln -s "${DATA_VOLUME_LOCATION}/local/metro-keystore" "${IGNITION_INSTALL_LOCATION}/webserver/metro-keystore"
            ln -s "${DATA_VOLUME_LOCATION}/local/csr.pfx" "${IGNITION_INSTALL_LOCATION}/webserver/csr.pfx"
            ln -s "${DATA_VOLUME_LOCATION}/local/ssl.pfx" "${IGNITION_INSTALL_LOCATION}/webserver/ssl.pfx"
            # Remove the in-image data folder (that presumably is still fresh, extra safety check here)
            # and place a symbolic link to the /data volume for compatibility
            if [ ! -a "/var/lib/ignition/data/db/config.idb" ]; then
                rm -rf /var/lib/ignition/data
                ln -s "${DATA_VOLUME_LOCATION}" /var/lib/ignition/data
            else
                echo "init     | WARNING: Existing gateway instance detected in /var/lib/ignition/data, skipping purge/relink to ${DATA_VOLUME_LOCATION}..."
            fi
        fi

        if [ ! -d "${DATA_VOLUME_LOCATION}/local" ]; then
            echo "init     | Creating missing data/local folder..."
            mkdir -p "${DATA_VOLUME_LOCATION}/local"
        fi

        if [ -f "${DATA_VOLUME_LOCATION}/metro-keystore" ]; then
            echo -n "init     | metro-keystore found in legacy location at '${DATA_VOLUME_LOCATION}'"
            set +e
            if [ -s "${DATA_VOLUME_LOCATION}/metro-keystore" ]; then
                echo ", attempting to migrate to '${DATA_VOLUME_LOCATION}/local'..."
                cp "${DATA_VOLUME_LOCATION}/metro-keystore" "${DATA_VOLUME_LOCATION}/local/"
            else
                echo " with zero size, removing..."
            fi
            rm "${DATA_VOLUME_LOCATION}/metro-keystore"
            set -e
        fi

        if [ -f "${init_file_path}" ]; then
            volume_version=$(cat "${init_file_path}")
        fi
        version_check=$(compare_versions "${IMAGE_VERSION}" "${volume_version}")

        case ${version_check} in
            0)
                upgrade_check_result=0
                ;;
            1 | 2)
                # Init file present, upgrade required
                echo "init     | Detected Ignition Volume from prior version (${volume_version:-unknown}), running Upgrader"
                java -classpath "lib/core/common/common.jar" com.inductiveautomation.ignition.common.upgrader.Upgrader . data logs file=ignition.conf
                echo "${IMAGE_VERSION}" > "${init_file_path}"
                # Correlate the result of the version check
                if [ "${version_check}" -eq 1 ]; then 
                    upgrade_check_result=-2
                else
                    upgrade_check_result=1
                fi
                ;;
            -1)
                echo >&2 "init     | Unknown error encountered during version comparison, aborting..."
                exit "${version_check}"
                ;;
            -2)
                echo >&2 "init     | Version mismatch on existing volume (${volume_version}) versus image (${IMAGE_VERSION}), Ignition image version must be greater or equal to volume version."
                exit "${version_check}"
                ;;
            -3)
                echo >&2 "init     | Unexpected version syntax found in volume (${volume_version})"
                exit "${version_check}"
                ;;
            -4)
                echo >&2 "init     | Unexpected version syntax found in image (${IMAGE_VERSION})"
                exit "${version_check}"
                ;;
            *)
                echo >&2 "init     | Unexpected error (${version_check}) during upgrade checks"
                exit "${version_check}"
                ;;
        esac
    fi

    chown "${IGNITION_UID}:${IGNITION_GID}" "${init_file_path}"
}

# usage: retrieve_ignition_edition
# return value: a valid IGNITION_EDITION value from either the ignition.conf if not explicitly set via the environment.
retrieve_ignition_edition() {
    local -l ignition_edition

    # Check ignition.conf if we're not driven by an environment variable
    if [[ ! -v IGNITION_EDITION ]]; then
        ignition_edition=$(grep -Po '(?i)(?<=wrapper.java.additional.\d=-Dedition=)(edge|maker|standard)' < "${IGNITION_INSTALL_LOCATION}/data/ignition.conf")
    else
        ignition_edition="${IGNITION_EDITION:-standard}"
    fi

    if [[ "${ignition_edition}" =~ ^maker|edge|standard|$ ]]; then
        echo "${ignition_edition:-standard}"  # the default of standard will fill in the empty case
    else
        echo >&2 "init     | WARNING: Invalid edition (${IGNITION_EDITION}) specified, should be 'maker', 'edge', or 'standard'; using 'standard'."
        echo "standard"
    fi
}

# Only collect additional arguments if we're not running a shell
if [[ "$1" != 'bash' && "$1" != 'sh' && "$1" != '/bin/sh' ]]; then
    if [[ "$1" != './ignition-gateway' ]]; then
        # CLI arguments are treated as JVM args, collect them for passing into java wrapper
        set -o noglob
        for arg in "${CMD[@]}"; do
            case $arg in
                wrapper.*)
                    WRAPPER_OPTIONS+=( "${arg}" )
                    ;;
                *)
                    JVM_OPTIONS+=( "${arg}" )
                    ;;
            esac
        done
        set +o noglob

        # Display captured arguments to log
        if [[ ${#WRAPPER_OPTIONS[@]} -gt 0 ]]; then
            echo "init     | Detected additional wrapper arguments:"
            printf "init     |   %s\n" "${WRAPPER_OPTIONS[@]}"
        fi
        if [[ ${#JVM_OPTIONS[@]} -gt 0 ]]; then
            echo "init     | Detected additional JVM arguments:"
            printf "init     |   %s\n" "${JVM_OPTIONS[@]}"
        fi

        # Override CMD array now that processing is complete
        CMD=( './ignition-gateway' )
    fi

    # Stage other base-level wrapper args
    CMD+=( 
        "data/ignition.conf"
        "wrapper.syslog.ident=Ignition-Gateway"
        "wrapper.pidfile=./Ignition-Gateway.pid"
        "wrapper.name=Ignition-Gateway"
        "wrapper.displayname=Ignition-Gateway"
        "wrapper.statusfile=./Ignition-Gateway.status"
        "wrapper.java.statusfile=./Ignition-Gateway.java.status"
    )

    # Validate environment variables surrounding IGNITION_EDITION
    file_env 'IGNITION_ACTIVATION_TOKEN'
    file_env 'IGNITION_LICENSE_KEY'
    if [[ "${IGNITION_EDITION:-}" =~ ^maker$ ]]; then
        # Ensure that License Key and Activation Tokens are supplied
        if [ -z "${IGNITION_ACTIVATION_TOKEN+x}" ] || [ -z "${IGNITION_LICENSE_KEY+x}" ]; then
            echo >&2 "init     | Missing ENV variables, must specify activation token and license key for edition: ${IGNITION_EDITION}"
            exit 1
        fi
    fi

    # Examine memory constraints and apply to Java arguments
    if [ -n "${GATEWAY_INIT_MEMORY:-}" ]; then
        if [[ ${GATEWAY_INIT_MEMORY} =~ ^[0-9]+$ && ${GATEWAY_INIT_MEMORY} -ge 256 ]]; then
            WRAPPER_OPTIONS+=(
                "wrapper.java.initmemory=${GATEWAY_INIT_MEMORY}"
                )
        else
            echo >&2 "init     | Invalid minimum memory specification, must be integer in MB >= 256: ${GATEWAY_INIT_MEMORY}"
            exit 1
        fi
    fi

    if [ -n "${GATEWAY_MAX_MEMORY:-}" ]; then
        if [[ ${GATEWAY_MAX_MEMORY} =~ ^[0-9]+$ && ${GATEWAY_MAX_MEMORY} -ge 512 ]]; then
            WRAPPER_OPTIONS+=(
                "wrapper.java.maxmemory=${GATEWAY_MAX_MEMORY}"
            )
        else
            echo >&2 "init     | Invalid max memory specification, must be integer in MB >= 512: ${GATEWAY_MAX_MEMORY}"
            exit 1
        fi
    fi

    if [[ ${GATEWAY_INIT_MEMORY:-256} -gt ${GATEWAY_MAX_MEMORY:-${GATEWAY_INIT_MEMORY:-256}} ]]; then
        echo >&2 "init     | Invalid memory specification, min (${GATEWAY_INIT_MEMORY}) must be less than max (${GATEWAY_MAX_MEMORY})"
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
        [WRAPPER_CONSOLE_LOGLEVEL]=wrapper.logfile.loglevel
        [WRAPPER_CONSOLE_FORMAT]=wrapper.logfile.format
        [WRAPPER_SYSLOG_LOGLEVEL]=wrapper.syslog.loglevel
        [WRAPPER_SYSLOG_LOCAL_HOST]=wrapper.syslog.local.host
        [WRAPPER_SYSLOG_REMOTE_HOST]=wrapper.syslog.remote.host
        [WRAPPER_SYSLOG_REMOTE_PORT]=wrapper.syslog.remote.port
    )
    for opt in "${!WRAPPER_CUSTOM_OPTIONS[@]}"; do
        if [ -n "${!opt}" ]; then
            WRAPPER_OPTIONS+=(
                "${WRAPPER_CUSTOM_OPTIONS[$opt]}=${!opt}"
            )
        fi
    done

    if [[ "${GATEWAY_DEBUG_ENABLED}" == "1" ]]; then
        JVM_OPTIONS+=( 
            "-Xdebug"
            "-Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=*:8000"
        )
    fi

    # Add hosted launchers option when launchers are absent from the filesystem
    declare -a launch_files=( 
        "${IGNITION_INSTALL_LOCATION}/lib/core/launch/perspectiveworkstation."*
        "${IGNITION_INSTALL_LOCATION}/lib/core/launch/visionclientlauncher."*
        "${IGNITION_INSTALL_LOCATION}/lib/core/launch/designerlauncher."*
    )
    if (( ${#launch_files[@]} == 0 )); then
        echo "init     | Launchers absent from image, enabling hosted launchers."
        JVM_OPTIONS+=( "-Dignition.hostedLaunchers=true" )
    fi

    # Collect JVM Arguments
    if [[ ${#JVM_OPTIONS[@]} -gt 0 ]]; then
        jvm_args_filepath=$(mktemp --tmpdir="${IGNITION_INSTALL_LOCATION}/temp" ignition_jvm_args-XXXXXXX)
        printf "#encoding=UTF-8\n" >> "${jvm_args_filepath}"
        for opt in "${JVM_OPTIONS[@]}"; do
            printf "%s\n" "${opt}" >> "${jvm_args_filepath}"
        done
        chown "${IGNITION_UID}:${IGNITION_GID}" "${jvm_args_filepath}"
        WRAPPER_OPTIONS+=( "wrapper.java.additional_file=${jvm_args_filepath}" )
    fi

    # Add separator for App Arguments
    if [[ ${#APP_OPTIONS[@]} -gt 0 ]]; then
        APP_OPTIONS=( "--" "${APP_OPTIONS[@]}" )
    fi

    CMD+=(
        "${BASE_WRAPPER_OPTIONS[@]}"
        "${WRAPPER_OPTIONS[@]}"
        "${APP_OPTIONS[@]}"
    )

    # Check for Upgrade and Mark Initialization File
    check_for_upgrade "${DATA_VOLUME_LOCATION}/.docker-init-complete"

    if [ ${upgrade_check_result} -lt 0 ]; then
        # Only perform Provisioning on Fresh/New Instance
        if [ ${upgrade_check_result} -eq -1 ]; then
            # Check Prerequisites
            file_env 'GATEWAY_ADMIN_PASSWORD'
            if [ -z "$GATEWAY_ADMIN_PASSWORD" ] && [ -z "$GATEWAY_RANDOM_ADMIN_PASSWORD" ] && [ "$GATEWAY_SKIP_COMMISSIONING" != "1" ]; then
                echo 'init     | WARNING: Gateway is not initialized and no password option is specified '
                echo 'init     |   Disabling automated gateway commissioning, manual input will be required'
                export GATEWAY_PROMPT_PASSWORD=1
            fi

            # Compute random password if env variable is defined
            if [ -n "$GATEWAY_RANDOM_ADMIN_PASSWORD" ]; then
               GATEWAY_ADMIN_PASSWORD="$(pwgen -1 32)"
               export GATEWAY_ADMIN_PASSWORD
            fi

            # Provision the init.properties file if we've got the environment variables for it
            rm -f "${DATA_VOLUME_LOCATION}/init.properties"
            add_to_init "SystemName" GATEWAY_SYSTEM_NAME
            add_to_init "UseSSL" GATEWAY_USESSL

            GATEWAY_PUBLIC_HTTP_PORT=${GATEWAY_PUBLIC_HTTP_PORT:-}
            GATEWAY_PUBLIC_HTTPS_PORT=${GATEWAY_PUBLIC_HTTPS_PORT:-}
            GATEWAY_PUBLIC_ADDRESS=${GATEWAY_PUBLIC_ADDRESS:-}
            if [ -n "${GATEWAY_PUBLIC_HTTP_PORT}${GATEWAY_PUBLIC_HTTPS_PORT}${GATEWAY_PUBLIC_ADDRESS}" ]; then
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
                
                # shellcheck disable=SC2034
                GATEWAY_PUBLIC_AUTODETECT="false"

                add_to_xml 'gateway.publicAddress.autoDetect' GATEWAY_PUBLIC_AUTODETECT
                add_to_xml 'gateway.publicAddress.address' GATEWAY_PUBLIC_ADDRESS
                add_to_xml 'gateway.publicAddress.httpPort' GATEWAY_PUBLIC_HTTP_PORT
                add_to_xml 'gateway.publicAddress.httpsPort' GATEWAY_PUBLIC_HTTPS_PORT
            fi

            # Look for declared HOST variables and add the other associated ones via add_gw_to_init
            looper=GATEWAY_NETWORK_${i:=0}_HOST
            while [ -n "${!looper:-}" ]; do
                # Add all available env parameters for this host to the init file
                add_gw_to_init $i
                # Index to the next HOST variable
                looper=GATEWAY_NETWORK_$((++i))_HOST
            done

            # Enable Gateway Network Certificate Auto Accept if Declared
            if [ "${GATEWAY_NETWORK_AUTOACCEPT_DELAY}" -gt 0 ] 2>/dev/null; then
                accept-gwnetwork.sh "${GATEWAY_NETWORK_AUTOACCEPT_DELAY}" &
            fi

            # Map in the Gateway Network UUID if Declared
            if [ -n "${GATEWAY_NETWORK_UUID}" ]; then
                if [[ "${GATEWAY_NETWORK_UUID}" =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]]; then
                    echo "${GATEWAY_NETWORK_UUID}" > "${IGNITION_INSTALL_LOCATION}/data/.uuid"
                else
                    echo >&2 "init     | WARN: GATEWAY_NETWORK_UUID doesn't match expected pattern, skipping..."
                fi
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
        gwcmd_restore_args=( "--restore" "/restore.gwbk" "-y" "-m" )
        if [[ "${GATEWAY_RESTORE_DISABLED}" == "1" ]]; then
            gwcmd_restore_args+=( "-d" )
        fi

        echo 'init     | Issuing gwcmd restore command'
        gwcmd_restore_log="${IGNITION_INSTALL_LOCATION}/logs/gwcmd_restore.log"
        ./gwcmd.sh "${gwcmd_restore_args[@]}" > "${gwcmd_restore_log}" 2>&1
        readarray -d '' restore_file_paths < <( find "${IGNITION_INSTALL_LOCATION}/data/" -maxdepth 1 -name "__restore_*.gwbk" -print0 )
        if [[ ${#restore_file_paths[@]} -eq 0 ]]; then
            echo >&2 "init     | ERROR: error attempting to restore, see '${gwcmd_restore_log}' for output of gwcmd"
            exit 1
        elif [[ ${#restore_file_paths[@]} -gt 1 ]]; then
            echo "init     | WARNING: Multiple restore gwbk files detected in data folder, removing all but latest:"
            printf "init     |     %s\n" "${restore_file_paths[@]}"
            for i in $(seq 0 $((${#restore_file_paths[@]}-2))); do
                rm -f "${restore_file_paths[$i]}"
            done
        fi

        # Update gateway backup with module, jdbc definitions
        echo 'init     | Updating restore file with module/jdbc definitions...'
        restore_file_path="${restore_file_paths[-1]}"
        pushd "${IGNITION_INSTALL_LOCATION}/temp" > /dev/null 2>&1
        unzip -q "${restore_file_path}" db_backup_sqlite.idb
        disable_quickstart "${IGNITION_INSTALL_LOCATION}/temp/db_backup_sqlite.idb"
        register-modules.sh "${GATEWAY_MODULE_RELINK}" "${IGNITION_INSTALL_LOCATION}/temp/db_backup_sqlite.idb"
        register-jdbc.sh "${GATEWAY_JDBC_RELINK}" "${IGNITION_INSTALL_LOCATION}/temp/db_backup_sqlite.idb"
        zip -q -f "${restore_file_path}" db_backup_sqlite.idb || if [[ ${ZIP_EXIT_CODE:=$?} == 12 ]]; then echo "init     | No changes to internal database needed for linked modules, jdbc drivers, or quickstart disable."; else echo "init     | Unknown error (${ZIP_EXIT_CODE}) encountered during re-packaging of config db, exiting." && exit ${ZIP_EXIT_CODE}; fi
        popd > /dev/null 2>&1

        # Perform environmental fixes to restored ignition.conf (seems to default to jre-nix even if on aarch64)
        sed -E -i 's|^(set.JAVA_HOME=).*$|\1lib/runtime/jre|' "${IGNITION_INSTALL_LOCATION}/data/ignition.conf"
    else
        target_db="${IGNITION_INSTALL_LOCATION}/data/db/config.idb"
        register-modules.sh "${GATEWAY_MODULE_RELINK}" "${target_db}"
        register-jdbc.sh "${GATEWAY_JDBC_RELINK}" "${target_db}"
    fi

    # Initialize edition selection environment variable, possibly based on restored ignition.conf
    IGNITION_EDITION=$(retrieve_ignition_edition)
    export IGNITION_EDITION

    # Perform module enablement/disablement
    enable_disable_modules "${GATEWAY_MODULES_ENABLED}"

    # Export environment variables for auto-commissioning unless skip is set
    if [ "${GATEWAY_SKIP_COMMISSIONING}" != "1" ]; then
        if [[ $(compare_versions "${IMAGE_VERSION}" "8.1.8") -ge 0 ]]; then
            # Auto-commissioning logic built into 8.1.8+
            export ACCEPT_IGNITION_EULA=${ACCEPT_IGNITION_EULA:-Y}
            export GATEWAY_HTTP_PORT=${GATEWAY_HTTP_PORT:-8088}
            export GATEWAY_HTTPS_PORT=${GATEWAY_HTTPS_PORT:-8043}
            export GATEWAY_GAN_PORT=${GATEWAY_GAN_PORT:-8060}
        else
            perform-commissioning.sh &
        fi
    fi
    
    # Stage tini as init replacement
    set -- tini -g -- "${CMD[@]}"

    # Check for running as root and adjust ownership as needed, then stage dropdown to `ignition` user for gateway launch.
    if [ "$(id -u)" = "0" ] && [ "${IGNITION_UID}" != "0" ]; then
        # Obtain ignition UID/GID
        ignition_uid_current=$(id -u ignition)
        ignition_gid_current=$(id -g ignition)

        if [[ "${ignition_uid_current}" != "${IGNITION_UID}" ]] && ! getent passwd "${IGNITION_UID}" > /dev/null; then
            echo "init     | Adjusting UID of 'ignition' user from ${ignition_uid_current} to ${IGNITION_UID}"
            usermod -u "${IGNITION_UID}" ignition
        fi
        if [[ "${ignition_gid_current}" != "${IGNITION_GID}" ]] && ! getent group "${IGNITION_GID}" > /dev/null; then
            echo "init     | Adjusting GID of 'ignition' user from ${ignition_gid_current} to ${IGNITION_GID}"
            groupmod -g "${IGNITION_GID}" ignition
        fi

        # Ensure ownership of stdout for logging
        chown "${IGNITION_UID}:${IGNITION_GID}" logs/wrapper.log

        # Adjust ownership of Ignition install files
        ignition_paths=(
            "${IGNITION_INSTALL_LOCATION}"
            "/var/lib/ignition"
            "/var/log/ignition"
        )
        readarray -d '' pa_ignition_files < <(find "${ignition_paths[@]}" \! \( -user "${IGNITION_UID}" -group "${IGNITION_GID}" \) -print0)
        if (( ${#pa_ignition_files[@]} > 0 )); then
            batch_size=500
            echo "init     | Adjusting ownership of ${#pa_ignition_files[@]} Ignition installation files (batch size ${batch_size})..."
            looper=0
            pa_ignition_files_batch=( "${pa_ignition_files[@]:$looper:$batch_size}" )
            while (( ${#pa_ignition_files_batch[@]} > 0 )); do
                # ignore failures with '|| true' here due to potentially broken symlink to metro-keystore (fresh launch)
                chown -h -f "${IGNITION_UID}:${IGNITION_GID}" "${pa_ignition_files_batch[@]}" || true
                looper=$((looper+batch_size))
                pa_ignition_files_batch=( "${pa_ignition_files[@]:$looper:$batch_size}" )
            done
        fi

        echo "init     | Staging user step-down from 'root'"
        set -- gosu "${IGNITION_UID}:${IGNITION_GID}" "$@"
    fi

    echo 'init     | Starting Ignition Gateway...'
fi

exec "$@"
