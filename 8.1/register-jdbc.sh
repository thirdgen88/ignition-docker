#!/bin/bash
shopt -s nullglob

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
    
    echo "init     | Searching for third-party JDBC drivers..."
    
    # Get List of JDBC Drivers
    mapfile -t JDBC_CLASSNAMES < <( "${SQLITE3[@]}" "SELECT CLASSNAME FROM JDBCDRIVERS;" )
    JDBC_CLASSPATHS=( "${JDBC_CLASSNAMES[@]//.//}" )  # replace dots with slashes for the paths

    # Remove Invalid Symbolic Links
    find "${IGNITION_INSTALL_LOCATION}/user-lib/jdbc" -type l ! -exec test -e {} \; -exec echo "Removing invalid symlink for {}" \; -exec rm {} \;

    # Establish Symbolic Links for new jdbc drivers and tie into db
    for jdbc in /jdbc/*.jar; do
        local jdbc_basename jdbc_sourcepath jdbc_destpath
        jdbc_basename=$(basename "${jdbc}")
        jdbc_sourcepath=${jdbc}
        jdbc_destpath="${IGNITION_INSTALL_LOCATION}/user-lib/jdbc/${jdbc_basename}"
        
        if [ -h "${jdbc_destpath}" ]; then
            echo "init     | Skipping Linked JDBC Driver: ${jdbc_basename}"
            continue
        fi

        # Determine if jdbc driver is a candidate for linking based on searching
        # the list of existing JDBC Classname entries gathered above.
        local jdbc_listing
        jdbc_listing=$(unzip -l "${jdbc}")
        for ((i=0; i<${#JDBC_CLASSPATHS[*]}; i++)); do
            classpath=${JDBC_CLASSPATHS[i]}
            classname=${JDBC_CLASSNAMES[i]}
            case ${jdbc_listing} in
                *$classpath*)
                jdbc_targetclassname=$classname
                break;;
            esac
        done

        # If we didn't find a match, ...
        if [ -z "${jdbc_targetclassname}" ]; then
            continue  # ... skip to next JDBC driver in path
        fi

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

        # Update JDBCDRIVERS table
        echo "init     |  Updating JDBCDRIVERS table for classname ${jdbc_targetclassname}"
        "${SQLITE3[@]}" "UPDATE JDBCDRIVERS SET JARFILE='${jdbc_basename}' WHERE CLASSNAME='${jdbc_targetclassname}'"
    done
}

main