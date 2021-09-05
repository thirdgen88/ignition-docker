#!/bin/bash
set -euo pipefail
shopt -s nullglob
shopt -s inherit_errexit

# usage register_jdbc RELINK_ENABLED DB_LOCATION
#   ie: register_jdbc true /var/lib/ignition/data/db/config.idb
RELINK_ENABLED="${1:-false}"
DB_LOCATION="${2}"
DB_FILE=$(basename "${DB_LOCATION}")

function main() {
    if [ ! -d "/jdbc" ]; then
        return 0  # Silently exit if there is no /jdbc path
    elif [ ! -f "${DB_LOCATION}" ]; then
        echo "init     | WARNING: ${DB_FILE} not found, skipping jdbc registration"
        return 0
    fi

    register_jdbc
}

function register_jdbc() {
    local SQLITE3=( sqlite3 "${DB_LOCATION}" )
    local jdbc_destbase="${IGNITION_INSTALL_LOCATION}/user-lib/jdbc"
    
    echo "init     | Searching for third-party JDBC drivers..."
    
    # Get List of JDBC Drivers
    mapfile -t JDBC_CLASSNAMES < <( "${SQLITE3[@]}" "SELECT CLASSNAME FROM JDBCDRIVERS;" )
    JDBC_CLASSPATHS=( "${JDBC_CLASSNAMES[@]//.//}" )  # replace dots with slashes for the paths

    # Remove Invalid Symbolic Links
    find "${jdbc_destbase}" -type l ! -exec test -e {} \; -exec echo "Removing invalid symlink for {}" \; -exec rm {} \;

    # Correlate entries in db with files via classpath.  This JDBC_ORIGINAL array will be used to purge other JDBC jars
    # from `${IGNITION_INSTALL_LOCATION}/user-lib/jdbc` that conflict with those we are linking in from `/jdbc`.
    # This will help ensure that the desired JAR is loaded instead of others that may be lingering on the filesystem.
    declare -A JDBC_ORIGINAL
    for jdbc in "${IGNITION_INSTALL_LOCATION}"/user-lib/jdbc/*.jar; do
        if [[ -h "${jdbc}" ]]; then
            continue  # skip symlinks
        fi
        unzip_listing_file=$(mktemp /tmp/jdbc_unzip_listing-XXXXXX.txt)
        unzip -l "${jdbc}" > "${unzip_listing_file}"
        for classpath in ${JDBC_CLASSPATHS[*]}; do
            if grep -Pq "\s+${classpath}\.class$" < "${unzip_listing_file}"; then
                JDBC_ORIGINAL["${classpath}"]+="${JDBC_ORIGINAL["${classpath}"]:+|}${jdbc}"
            fi
        done
        rm "${unzip_listing_file}"
    done

    # Establish Symbolic Links for new jdbc drivers and tie into db
    for jdbc in /jdbc/*.jar; do
        local jdbc_basename jdbc_sourcepath jdbc_destpath
        jdbc_basename=$(basename "${jdbc}")
        jdbc_sourcepath=${jdbc}
        jdbc_destpath="${jdbc_destbase}/${jdbc_basename}"
        
        # If we already see a symbolic link at the destination, take no further actions on behalf of this
        # JDBC JAR since we've presumably already done our work last time.
        if [ -h "${jdbc_destpath}" ]; then
            echo "init     | Skipping Linked JDBC Driver: ${jdbc_basename}"
            continue
        fi  # otherwise ...

        # Determine if jdbc driver is an active candidate for linking based on searching
        # the list of existing JDBC Classname entries gathered above.
        # NOTE: if this fails to match, we'll still link the JAR so the user can configure
        #       the driver in the Gateway webpage after startup.  
        local jdbc_listing
        jdbc_listing=$(unzip -l "${jdbc}")
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

        # Perform the linking from `/jdbc` into `user-lib/jdbc`
        if [ -e "${jdbc_destpath}" ]; then
            if [ "${RELINK_ENABLED}" != true ]; then
                echo "init     | Skipping existing JDBC driver: ${jdbc_basename}"
                continue
            fi
            echo "init     | Relinking JDBC Driver: ${jdbc_basename}"
            rm "${jdbc_destpath}"
        else
            echo "init     | Linking JDBC Driver: ${jdbc_basename}"
        fi
        ln -s "${jdbc_sourcepath}" "${jdbc_destpath}"

        # If we didn't find a matching class path, we'll skip to the next JDBC driver here after linking
        # so that the user can configure a JDBC driver against the freshly linked JAR.
        if [ -z "${jdbc_targetclassname}" ]; then
            continue  # ... skip to next JDBC driver in path
        fi

        # Remove built-in JDBC jars that conflict with our active linked-in versions (to ensure that the linked one is loaded)
        set +u  # temporarily disable error on unbound variables since this next statement is a dynamic indirect
        if [[ ${JDBC_ORIGINAL[${jdbc_targetclasspath}]} ]]; then
            IFS='|' read -r -a jdbc_original_files <<< "${JDBC_ORIGINAL[${jdbc_targetclasspath}]}"
            for f in ${jdbc_original_files[*]}; do
                if [[ -f "$f" ]]; then
                    echo "init     | Removing conflicting JDBC driver '$(basename "${f}")'"
                    rm -f "$f"
                fi
            done
        fi
        set -u

        # Update JDBCDRIVERS table
        # NOTE:  this JARFILE field appears to only be used to delete the JAR file from the filesystem and doesn't control
        #        which one is loaded.
        echo "init     |  Updating JDBCDRIVERS table for classname ${jdbc_targetclassname}"
        "${SQLITE3[@]}" "UPDATE JDBCDRIVERS SET JARFILE='${jdbc_basename}' WHERE CLASSNAME='${jdbc_targetclassname}'"
    done
}

main