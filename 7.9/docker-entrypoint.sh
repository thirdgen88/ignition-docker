#!/bin/bash
set -eo pipefail
shopt -s nullglob

# Local initialization
INIT_FILE=/usr/local/share/ignition/data/init.properties
CMD=( "$@" )
WRAPPER_OPTIONS=(
    "wrapper.console.loglevel=NONE"
    "wrapper.logfile.format=PTM"
    "wrapper.logfile.rollmode=NONE"
)
JAVA_OPTIONS=( )
GATEWAY_MODULE_RELINK=${GATEWAY_MODULE_RELINK:-false}
GATEWAY_JDBC_RELINK=${GATEWAY_JDBC_RELINK:-false}
GATEWAY_MODULES_ENABLED=${GATEWAY_MODULES_ENABLED:-all}

# Init Properties Helper Functions
# usage: add_to_init KEY ENV_VAR_NAME
#    ie: add_to_init gateway.network.0.Enabled GATEWAY_NETWORK_0_ENABLED
add_to_init () {
    # The below takes the first argument as the key and indirects to the second argument
    # to assign the value.  It will skip if the value is undefined.
    if [ -n "${!2:-}" ]; then
        echo "init     | Added Init Setting ${1}=${!2}"
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

# usage: health_check PHASE_DESC DELAY_SECS
#   ie: health_check "Gateway Commissioning" 60
health_check() {
    local phase="$1"
    local delay=$2

    # Wait for a short period for the commissioning servlet to come alive
    for ((i=delay;i>0;i--)); do
        if curl --max-time 3 -f http://localhost:8088/main/StatusPing 2>&1 | grep -c RUNNING > /dev/null; then   
            break
        fi
        sleep 1
    done
    if [ "$i" -le 0 ]; then
        echo >&2 "Failed to detect RUNNING status during ${phase} after ${delay} delay."
        exit 1
    fi
}

# usage stop_process PID
#   ie: stop_process 123
stop_process() {
    local pid="$1"

    echo 'init     | Shutting down interim provisioning gateway...'
    if ! kill -s TERM "$pid" || ! wait "$pid"; then
        echo >&2 'Ignition initialization process failed.'
        exit 1
    fi
}

# usage enable_disable_modules MODULES_ENABLED
#   ie: enable_disable_modules vision,opc-ua,sql-bridge
enable_disable_modules() {
	local MODULES_ENABLED="${1}"

	if [ "${MODULES_ENABLED}" = "all" ]; then return 0; fi

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
	mapfile -d , -t modules_enabled <<< "$GATEWAY_MODULES_ENABLED"

	# Find the currently present modules in the installation
	mapfile -t modules_list < <(find "${modules_path}" -name '*.modl' -type f -printf "%f\n")

	for module_filename in "${modules_list[@]}"; do
		module_filepath="${modules_path}/${module_filename}"
		module_definition="${module_definition_mappings[${module_filename}]}"

		if [ -z "${module_definition}" ]; then
			printf "\n  Unknown module %s, skipping..." "${module_filename}"
			continue
		fi
		
		# Search for Module Definition in List of Modules Enabled
		module_found=0
		for (( n=0; n<${#modules_enabled[@]}; n++ )); do
			if [ ${module_definition} = "${modules_enabled[$n]}" ]; then
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

# usage: compare_versions IMAGE_VERSION VOLUME_VERSION
#   ie: compare_versions "8.0.2" "7.9.11"
# return values: -3 = unexpected version syntax
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
        echo >&2 "Unexpected version syntax found in image (${image_version})"
        return_value=-3
    elif [ -z "${volume_version}" ]; then
        return_value=1
    elif [ ${#volume_version_arr[@]} -ne 3 ]; then
        echo >&2 "Unexpected version syntax found in volume (${volume_version})"
        return_value=-3
    elif [ "${image_version}" = "${volume_version}" ]; then
        return_value=0
    else
        # Implictly map the upgrade case (no commissioning required) ...
        return_value=2  
        
        for (( i = 0; i < 3; i++ )); do
            if [[ ${volume_version_arr[$i]} < ${image_version_arr[$i]} ]]; then
                return_value=1  # Major Version Upgrade Detected, commissioning will be required
                break
            elif [[ ${volume_version_arr[$i]} > ${image_version_arr[$i]} ]]; then
                echo >&2 "Version mismatch on existing volume (${volume_version}) versus image (${image_version}), Ignition image version must be greater or equal to volume version."
                return_value=-2  # ... and flag lower case (invalid) if detected
                break
            fi
        done        
    fi

    if [[ ${return_value} == -1 ]]; then
        echo >&2 "Unknown error encountered during version comparison, aborting..."
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
    local version_regex_pattern init_file_path image_version volume_version version_check
    version_regex_pattern='([0-9]*)\.([0-9]*)\.([0-9]*)'
    init_file_path="$1"
    image_version=$(grep gateway.version < "${IGNITION_INSTALL_LOCATION}/lib/install-info.txt" | cut -d = -f 2 )

    # Strip "-SNAPSHOT" off...  FOR NIGHTLY BUILDS ONLY
    if [[ ${BUILD_EDITION} == *"NIGHTLY"* ]]; then
        image_version="${image_version//-SNAPSHOT/}"
    fi

    if [ ! -d "${IGNITION_INSTALL_LOCATION}/data/temp" ]; then
        echo "init     | Creating extra temp folder within data volume"
        mkdir -p "${IGNITION_INSTALL_LOCATION}/data/temp"
    fi

    if [ ! -f "${IGNITION_INSTALL_LOCATION}/data/db/config.idb" ]; then
        # Fresh/new instance, case 1
        echo "${image_version}" > "${init_file_path}"
        upgrade_check_result=-1
    else
        if [ -f "${init_file_path}" ]; then
            volume_version=$(cat "${init_file_path}")
        fi
        version_check=$(compare_versions "${image_version}" "${volume_version}")

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
                if [[ ${version_check} == 1 ]]; then 
                    upgrade_check_result=-2
                else
                    upgrade_check_result=1
                fi
                ;;
            *)
                exit "${version_check}"
                ;;
        esac
    fi

    chown "${IGNITION_UID}:${IGNITION_GID}" "${init_file_path}"
}

# Collect additional arguments if we're running the gateway
if [ "$1" = './ignition-gateway' ]; then
    # Examine memory constraints and apply to Java arguments
    if [ -n "${GATEWAY_INIT_MEMORY:-}" ]; then
        if [[ ${GATEWAY_INIT_MEMORY} =~ ^[0-9]+$ && ${GATEWAY_INIT_MEMORY} -ge 256 ]]; then
            WRAPPER_OPTIONS+=(
                "wrapper.java.initmemory=${GATEWAY_INIT_MEMORY}"
                )
        else
            echo >&2 "Invalid minimum memory specification, must be integer in MB >= 256: ${GATEWAY_INIT_MEMORY}"
            exit 1
        fi    
    fi

    if [ -n "${GATEWAY_MAX_MEMORY:-}" ]; then
        if [[ ${GATEWAY_MAX_MEMORY} =~ ^[0-9]+$ && ${GATEWAY_MAX_MEMORY} -ge 512 ]]; then
            WRAPPER_OPTIONS+=(
                "wrapper.java.maxmemory=${GATEWAY_MAX_MEMORY}"
            )
        else
            echo >&2 "Invalid max memory specification, must be integer in MB >= 512: ${GATEWAY_MAX_MEMORY}"
            exit 1
        fi
    fi

    if [[ ${GATEWAY_INIT_MEMORY:-256} -gt ${GATEWAY_MAX_MEMORY:-512} ]]; then
        echo >&2 "Invalid memory specification, min (${GATEWAY_INIT_MEMORY}) must be less than max (${GATEWAY_MAX_MEMORY})"
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
        if [ -n "${!opt}" ]; then
            WRAPPER_OPTIONS+=(
                "${WRAPPER_CUSTOM_OPTIONS[$opt]}=${!opt}"
            )
        fi
    done

    # Combine CMD array with wrapper and explicit java options
    if [ -n "${JAVA_OPTIONS:-}" ]; then
        JAVA_OPTIONS=( "--" "${JAVA_OPTIONS[@]}" )
    fi
    CMD+=(
        "${WRAPPER_OPTIONS[@]}"
        "${JAVA_OPTIONS[@]}"
    )
fi

# Check for no Docker Init Complete file
if [ "$1" = './ignition-gateway' ]; then
    # Check for Upgrade and Mark Initialization File
    check_for_upgrade "${IGNITION_INSTALL_LOCATION}/data/.docker-init-complete"

    if [ ${upgrade_check_result} -lt 0 ]; then
        # Only perform Provisioning on Fresh/New Instance
        if [ ${upgrade_check_result} -eq -1 ]; then        
            # Provision the init.properties file if we've got the environment variables for it
            rm -f /var/lib/ignition/data/init.properties
            add_to_init "SystemName" GATEWAY_SYSTEM_NAME
            add_to_init "UseSSL" GATEWAY_USESSL

            # Perform some corrections on ignition.conf to relative paths (required for 7.9.16 path change issue, see #38)
            sed -E -i 's/^(wrapper\.java\.library\.path\.1=).*$/\1lib/' "${IGNITION_INSTALL_LOCATION}/data/ignition.conf"
            sed -E -i 's/^(wrapper\.java\.additional\.[0-9]+=-Ddata\.dir=).*$/\1data/' "${IGNITION_INSTALL_LOCATION}/data/ignition.conf"
            sed -E -i 's|^(wrapper\.logfile=).*$|\1logs/wrapper.log|' "${IGNITION_INSTALL_LOCATION}/data/ignition.conf"

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
        fi

        # Determine if we are going to be restoring a gateway backup
        if [ -f "/restore.gwbk" ]; then
            export GATEWAY_RESTORE_REQUIRED="1"
        else
            export GATEWAY_RESTORE_REQUIRED="0"
        fi

        # Perform Module Registration and Restore of Gateway Backup
        modules_files=(/modules/*)
        jdbc_files=(/jdbc/*)
        if [[ (-d "/modules" && ${#modules_files[@]} -gt 0) || 
              (-d "/jdbc" && ${#jdbc_files[@]} -gt 0) || 
              "${GATEWAY_RESTORE_REQUIRED}" = "1" ]]; then
            # Initialize Startup Gateway before Attempting Restore
            echo "init     | Ignition initialization process in progress, logged here: /var/log/ignition/provisioning.log"
            "${CMD[@]}" > /var/log/ignition/provisioning.log 2>&1 &
            pid="$!"

            health_check "Startup" "${IGNITION_STARTUP_DELAY:=60}"

            # Gateway Restore
            if [ "${GATEWAY_RESTORE_REQUIRED}" = "1" ]; then
                echo 'init     | Restoring Gateway Backup...'
                printf '\n' | ./gwcmd.sh --restore /restore.gwbk -y
            fi

            stop_process $pid
        fi
    fi

    # Link Additional Modules and prepare Ignition database
    register-modules.sh "${GATEWAY_MODULE_RELINK}" "${IGNITION_INSTALL_LOCATION}/data/db/config.idb"

    # Link Additional JDBC Drivers and prepare Ignition database
    register-jdbc.sh "${GATEWAY_JDBC_RELINK}" "${IGNITION_INSTALL_LOCATION}/data/db/config.idb"
    
    # Perform module enablement/disablement
    enable_disable_modules "${GATEWAY_MODULES_ENABLED}"

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
