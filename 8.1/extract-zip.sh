#!/usr/bin/env bash
set -eo pipefail

declare LAUNCHER_PATH="lib/core/launch"
declare MODULE_PATH="user-lib/modules"
declare -a ZIP_EXCLUSION_MODULE_LIST
declare -a ZIP_EXCLUSION_ARCHITECTURE_LIST
declare -a ZIP_EXCLUSION_RESOURCE_LIST
declare -A ZIP_EXCLUSION_MODULE_CHOICES=(
    ["alarm-notification"]="${MODULE_PATH}/Alarm Notification-module.modl"
    ["allen-bradley-drivers"]="${MODULE_PATH}/Allen-Bradley Drivers-module.modl"
    ["bacnet-driver"]="${MODULE_PATH}/BACnet Driver-module.modl"
    ["dnp3-driver"]="${MODULE_PATH}/DNP3-Driver.modl"
    ["enterprise-administration"]="${MODULE_PATH}/Enterprise Administration-module.modl"
    ["logix-driver"]="${MODULE_PATH}/Logix Driver-module.modl"
    ["mobile-module"]="${MODULE_PATH}/Mobile-module.modl"
    ["modbus-driver-v2"]="${MODULE_PATH}/Modbus Driver v2-module.modl"
    ["omron-driver"]="${MODULE_PATH}/Omron-Driver.modl"
    ["opc-ua"]="${MODULE_PATH}/OPC-UA-module.modl"
    ["perspective"]="${MODULE_PATH}/Perspective-module.modl"
    ["reporting"]="${MODULE_PATH}/Reporting-module.modl"
    ["serial-support-client"]="${MODULE_PATH}/Serial Support Client-module.modl"
    ["serial-support-gateway"]="${MODULE_PATH}/Serial Support Gateway-module.modl"
    ["sfc"]="${MODULE_PATH}/SFC-module.modl"
    ["siemens-drivers"]="${MODULE_PATH}/Siemens Drivers-module.modl"
    ["sms-notification"]="${MODULE_PATH}/SMS Notification-module.modl"
    ["sql-bridge"]="${MODULE_PATH}/SQL Bridge-module.modl"
    ["symbol-factory"]="${MODULE_PATH}/Symbol Factory-module.modl"
    ["tag-historian"]="${MODULE_PATH}/Tag Historian-module.modl"
    ["udp-tcp-drivers"]="${MODULE_PATH}/UDP and TCP Drivers-module.modl"
    ["user-manual"]="${MODULE_PATH}/User Manual-module.modl"
    ["vision"]="${MODULE_PATH}/Vision-module.modl"
    ["voice-notification"]="${MODULE_PATH}/Voice Notification-module.modl"
    ["web-browser"]="${MODULE_PATH}/Web Browser Module.modl"
    ["web-developer"]="${MODULE_PATH}/Web Developer Module.modl"
)
declare -a ZIP_EXCLUSION_RESOURCE_CHOICES=(
    "designerlauncher"
    "perspectiveworkstation"
    "visionclientlauncher"
    "jxbrowser"
)
declare -A ZIP_EXCLUSION_ARCHITECTURE_CHOICES=(
    ["mac"]=".dmg"
    ["linux64"]=".tar.gz"
    ["win64"]=".exe"
)
declare -A ZIP_EXCLUSION_RESOURCEARCH_CHOICES
for resource in "${ZIP_EXCLUSION_RESOURCE_CHOICES[@]}"; do
    for arch in "${!ZIP_EXCLUSION_ARCHITECTURE_CHOICES[@]}"; do
        file_extension="${ZIP_EXCLUSION_ARCHITECTURE_CHOICES[${arch}]}"
        ZIP_EXCLUSION_RESOURCEARCH_CHOICES["${resource}-${arch}"]="${LAUNCHER_PATH}/${resource}${file_extension}"
    done
done

function main() {
    local -a module_exclusion_list
    local -a resource_exclusion_list
    local extraction_base_path="ignition"
    local resource_exclusion resource_target module_exclusion module_target
    local -a zip_exclusion_architecture_list

    # Gather up file exclusions for modules
    for module in "${ZIP_EXCLUSION_MODULE_LIST[@]}"; do
        module_target="${module// }"
        module_exclusion="${ZIP_EXCLUSION_MODULE_CHOICES[${module_target}]}"
        if [[ -n "${module_exclusion}" ]]; then
            module_exclusion_list+=("${module_exclusion}")
        fi
    done

    # Gather up file exclusions for resource, by-architecture
    if [[ -z "${ZIP_EXCLUSION_ARCHITECTURE_LIST[*]}" ]]; then
        zip_exclusion_architecture_list=("${!ZIP_EXCLUSION_ARCHITECTURE_CHOICES[@]}")
    else
        zip_exclusion_architecture_list=("${ZIP_EXCLUSION_ARCHITECTURE_LIST[@]}")
    fi

    for arch in "${zip_exclusion_architecture_list[@]}"; do
        for resource in "${ZIP_EXCLUSION_RESOURCE_LIST[@]}"; do
            resource_target="${resource// }-${arch}"
            resource_exclusion="${ZIP_EXCLUSION_RESOURCEARCH_CHOICES[${resource_target}]}"
            if [[ -n "${resource_exclusion}" ]]; then
                resource_exclusion_list+=("${resource_exclusion}")
            fi
        done
    done

    # mkdir -p "${extraction_base_path}"
    eval ${DEBUG:+echo} unzip -q "${INSTALLER_NAME}" -x "${module_exclusion_list[@]}" "${resource_exclusion_list[@]}" -d "${extraction_base_path}/"
    chmod +x "${extraction_base_path}/ignition-gateway" "${extraction_base_path}/"*.sh
}

PARAMS=""

function storeArg() {
    local arg_name="$1"
    local arg_value="$2"
    local arg_delimiter="${3:-}"
    declare -n arg_ptr="$1"

    if [ -n "${arg_value}" ] && [ "${arg_value:0:1}" != "-" ]; then
        if [ -n "${arg_delimiter}" ]; then
            IFS="${arg_delimiter}"; read -ra arg_ptr <<< "${arg_value}"
        else
            # shellcheck disable=SC2178,SC2034
            arg_ptr="${arg_value}"
        fi
    else
        echo "Error: missing argument for '${arg_name}'"
        exit 1
    fi
}

# Collect and Process Arguments
while (( "$#" )); do
    case "$1" in
        -f|--installer-file)
            storeArg "INSTALLER_NAME" "$2"
            shift 2
            ;;
        -xr|--exclude-resources)
            storeArg "ZIP_EXCLUSION_RESOURCE_LIST" "$2" ","
            shift 2
            ;;
        -xm|--exclude-modules)
            storeArg "ZIP_EXCLUSION_MODULE_LIST" "$2" ","
            shift 2
            ;;
        -xa|--exclude-architectures)
            storeArg "ZIP_EXCLUSION_ARCHITECTURE_LIST" "$2" ","
            shift 2
            ;;  
        -d|--debug)
            storeArg "DEBUG" "1"
            shift 1
            ;;
        --*=|-*) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            exit 1
            ;;
        *) # preserve positional arguments
            PARAMS="${PARAMS} $1"
            shift
            ;;
    esac
done

# Usage Help
if [[ -z "${INSTALLER_NAME:-}" ]]; then
    echo "Usage: extract-zip.sh -f <INSTALLER_PATH>"
    echo "                     [-xr <EXCLUDED_RESOURCE>,...]"
    echo "                     [-xm <EXCLUDED_MODULE>,...]"
    echo "                     [-xa <EXCLUDED_ARCHITECTURE>,...]"
    echo "                     [-d | --debug]"
    echo ""
    echo "Where:"
    echo "<EXCLUDED_RESOURCE> is one of:"
    for resource in "${ZIP_EXCLUSION_RESOURCE_CHOICES[@]}"; do printf "    %q\n" "${resource}"; done
    echo ""
    echo "<EXCLUDED_MODULE> is one of:"
    for module in "${!ZIP_EXCLUSION_MODULE_CHOICES[@]}"; do printf "    %q\n" "${module}"; done
    echo ""
    echo "<EXCLUDED_ARCHITECURE> is one of:"
    for arch in "${!ZIP_EXCLUSION_ARCHITECTURE_CHOICES[@]}"; do printf "    %q\n" "${arch}"; done
    exit 1
fi

# set positional arguments in their proper place
eval set -- "${PARAMS}"

main