#!/bin/bash
set -eo pipefail
shopt -s nullglob

# Local initialization
INIT_FILE=/usr/local/share/ignition/data/init.properties
CMD=( "$@" )
WRAPPER_OPTIONS=( )
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

# usage: health_check PHASE_DESC DELAY_SECS
#   ie: health_check "Gateway Commissioning" 60
health_check() {
    local phase="$1"
    local delay=$2

    # Wait for a short period for the commissioning servlet to come alive
    for ((i=${delay};i>0;i--)); do
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
    local image_version_arr=( ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} )
    [[ $volume_version =~ $version_regex_pattern ]]
    local volume_version_arr=( ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} )
    
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
            if [ ${volume_version_arr[$i]} -lt ${image_version_arr[$i]} ]; then
                return_value=1  # Major Version Upgrade Detected, commissioning will be required
                break
            elif [ ${volume_version_arr[$i]} -gt ${image_version_arr[$i]} ]; then
                echo >&2 "Version mismatch on existing volume (${volume_version}) versus image (${image_version}), Ignition image version must be greater or equal to volume version."
                return_value=-2  # ... and flag lower case (invalid) if detected
                break
            fi
        done        
    fi

    if [ ${return_value} -eq -1 ]; then
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
    local version_regex_pattern='([0-9]*)\.([0-9]*)\.([0-9]*)'
    local init_file_path="$1"
    local image_version=$(cat "${IGNITION_INSTALL_LOCATION}/lib/install-info.txt" | grep gateway.version | cut -d = -f 2 )

    # Strip "-SNAPSHOT" off...  FOR NIGHTLY BUILDS ONLY
    if [[ ${BUILD_EDITION} == *"NIGHTLY"* ]]; then
        image_version=$(echo ${image_version} | sed "s/-SNAPSHOT$//")
    fi

    if [ ! -d "${IGNITION_INSTALL_LOCATION}/data/temp" ]; then
        echo "Creating extra temp folder within data volume"
        mkdir -p "${IGNITION_INSTALL_LOCATION}/data/temp"
    fi

    if [ ! -f "${IGNITION_INSTALL_LOCATION}/data/db/config.idb" ]; then
        # Fresh/new instance, case 1
        echo "${image_version}" > "${init_file_path}"
        upgrade_check_result=-1
    else
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
                echo "${image_version}" > "${init_file_path}"
                # Correlate the result of the version check
                if [ ${version_check} -eq 1 ]; then 
                    upgrade_check_result=-2
                else
                    upgrade_check_result=1
                fi
                ;;
            *)
                exit ${version_check}
                ;;
        esac
    fi
}

# Collect additional arguments if we're running the gateway
if [ "$1" = './ignition-gateway' ]; then
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
        fi

        # Determine if we are going to be restoring a gateway backup
        if [ -f "/restore.gwbk" ]; then
            export GATEWAY_RESTORE_REQUIRED="1"
        else
            export GATEWAY_RESTORE_REQUIRED="0"
        fi

        # Perform Module Registration and Restore of Gateway Backup
        if [[ (-d "/modules" && $(ls -1 /modules | wc -l) > 0) || 
              (-d "/jdbc" && $(ls -1 /jdbc | wc -l) > 0) || 
              "${GATEWAY_RESTORE_REQUIRED}" = "1" ]]; then
            # Initialize Startup Gateway before Attempting Restore
            echo "Ignition initialization process in progress, logged here: /var/log/ignition/provisioning.log"
            "${CMD[@]}" > /var/log/ignition/provisioning.log 2>&1 &
            pid="$!"

            health_check "Startup" ${IGNITION_STARTUP_DELAY:=60}

            # Gateway Restore
            if [ "${GATEWAY_RESTORE_REQUIRED}" = "1" ]; then
                echo 'Restoring Gateway Backup...'
                printf '\n' | ./gwcmd.sh --restore /restore.gwbk -y
            fi

            stop_process $pid
        fi
    fi

    # Link Additional Modules and prepare Ignition database
    register_modules ${GATEWAY_MODULE_RELINK} "${IGNITION_INSTALL_LOCATION}/data/db/config.idb"

    # Link Additional JDBC Drivers and prepare Ignition database
    register_jdbc ${GATEWAY_JDBC_RELINK} "${IGNITION_INSTALL_LOCATION}/data/db/config.idb"
    
    # Perform module enablement/disablement
    enable_disable_modules ${GATEWAY_MODULES_ENABLED}

    echo 'Starting Ignition Gateway...'
fi

exec "${CMD[@]}"
