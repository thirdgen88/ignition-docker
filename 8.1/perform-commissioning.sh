#!/bin/bash

port="8088"

# usage: health_check DELAY_SECS TARGET|DETAILS
#   ie: health_check 60
#   ie: health_check 60 RUNNING|COMMISSIONING
health_check() {
    local delay=$1
    local target=$2
    local details="null"
    if [[ "${target}" == *"|"* ]]; then
        details=$(printf ${target} | cut -d \| -f 2)
        target=$(printf ${target} | cut -d \| -f 1)
    fi

    # Wait for a short period for the commissioning servlet to come alive
    # TODO(kcollins): fix static port assignment of 8088
    for ((i=${delay};i>0;i--)); do
        raw_json=$(curl -s --max-time 3 -f http://localhost:${port}/StatusPing || true)
        state_value=$(echo ${raw_json} | jq -r '.["state"]')
        details_value=$(echo ${raw_json} | jq -r '.["details"]')
        if [ "${state_value}" == "${target}" -a "${details_value}" == "${details}" ]; then
            break
        fi
        sleep 1
    done
    if [ "$i" -le 0 ]; then
        echo "init     | Commissioning helper function run delay (${delay}) exceeded, exiting."
        exit 0
    fi
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

# usage: perform_commissioning
perform_commissioning() {
    local phase="Commissioning"
    local base_url="http://localhost:${port}"
    local bootstrap_url="${base_url}/bootstrap"
    local get_url="${base_url}/get-step"
    local url="${base_url}/post-step"
    
    commissioning_steps_raw=$(curl -s -f ${bootstrap_url})
    local ignition_edition=$(echo "$commissioning_steps_raw" | jq -r '.edition')
    if [ "${ignition_edition}" == "NOT_SET" ]; then
        local edition_selection="${IGNITION_EDITION}"
        if [ "${IGNITION_EDITION}" == "full" ]; then edition_selection=""; fi
        local edition_selection_payload='{"id":"edition","step":"edition","data":{"edition":"'${edition_selection}'"}}'
        evaluate_post_request "${url}" "${edition_selection_payload}" 201 "${phase}" "Edition Selection"
        echo "init     |  IGNITION_EDITION: ${IGNITION_EDITION}"
        # Reload commissioning steps
        commissioning_steps_raw=$(curl -s -f ${bootstrap_url})
    fi

    echo -n "init     | Gathering required commissioning steps: "
    commissioning_steps=(
        $((echo "$commissioning_steps_raw" | jq -r '.steps | keys | @sh') | tr -d \')
    )
    echo "${commissioning_steps[*]}"

    # activation
    if [[ $commissioning_steps[@]} =~ "activated" ]]; then
        local activation_payload='{"id":"activation","data":{"licenseKey":"'${IGNITION_LICENSE_KEY}'","activationToken":"'${IGNITION_ACTIVATION_TOKEN}'"}}'
        evaluate_post_request "${url}" "${activation_payload}" 201 "${phase}" "Online Activation"
        echo "init     |  IGNITION_LICENSE_KEY: ${IGNITION_LICENSE_KEY}"
    fi

    # authSetup
    if [[ ${commissioning_steps[@]} =~ "authSetup" && "${GATEWAY_PROMPT_PASSWORD}" != "1" ]]; then
        local auth_user="${GATEWAY_ADMIN_USERNAME:=admin}"
        local auth_salt=$(date +%s | sha256sum | head -c 8)
        local auth_pwhash=$(printf %s "${GATEWAY_ADMIN_PASSWORD}${auth_salt}" | sha256sum - | cut -c -64) 
        local auth_password="[${auth_salt}]${auth_pwhash}"
        local auth_payload=$(jq -ncM --arg user "$auth_user" --arg pass "$auth_password" '{ id: "authentication", step:"authSetup", data: { username: $user, password: $pass }}')
        evaluate_post_request "${url}" "${auth_payload}" 201 "${phase}" "Configuring Authentication"

        echo "init     |  GATEWAY_ADMIN_USERNAME: ${GATEWAY_ADMIN_USERNAME}"
        if [ ! -z "$GATEWAY_RANDOM_ADMIN_PASSWORD" ]; then echo "  GATEWAY_RANDOM_ADMIN_PASSWORD: ${GATEWAY_ADMIN_PASSWORD}"; fi
    fi

    # connections
    if [[ ${commissioning_steps[@]} =~ "connections" ]]; then
        # Retrieve default port configuration from get-step payload
        connection_info_raw=$(curl -s -f "${get_url}?step=connections")
        # Register Port Configuration
        local http_port="$(echo ${connection_info_raw} | jq -r '.data[] | select(.name=="httpPort").port')"
        local https_port="$(echo ${connection_info_raw} | jq -r '.data[] | select(.name=="httpsPort").port')"
        local gan_port="$(echo ${connection_info_raw} | jq -r '.data[] | select(.name=="ganPort").port')"
        local use_ssl="${GATEWAY_USESSL:=false}"
        local port_payload='{"id":"connections","step":"connections","data":{"http":'${http_port:=8088}',"https":'${https_port:=8043}',"gan":'${gan_port:=8060}',"useSSL":'${use_ssl}'}}'
        evaluate_post_request "${url}" "${port_payload}" 201 "${phase}" "Configuring Connections"
        echo "init     |  GATEWAY_HTTP_PORT: ${http_port}"
        echo "init     |  GATEWAY_HTTPS_PORT: ${https_port}"
        echo "init     |  GATEWAY_NETWORK_PORT: ${gan_port}"
        echo "init     |  GATEWAY_USESSL: ${GATEWAY_USESSL}"
    fi

    # eula
    if [[ ${commissioning_steps[@]} =~ "eula" ]]; then
        local license_accept_payload='{"id":"license","step":"eula","data":{"accept":true}}'
        evaluate_post_request "${url}" "${license_accept_payload}" 201 "${phase}" "License Acceptance"
        echo "init     |  EULA_STATUS: accepted"
    fi

    # finalize
    if [ "${GATEWAY_PROMPT_PASSWORD}" != "1" ]; then
        local finalize_payload='{"id":"finished","data":{"startGateway":true}}'
        evaluate_post_request "${url}" "${finalize_payload}" 200 "${phase}" "Finalizing Gateway"
        echo "init     |  COMMISSIONING: finalized"
    fi
}

echo "init     | Initiating commissioning helper functions..."
health_check ${IGNITION_COMMISSIONING_DELAY:=30} "RUNNING|COMMISSIONING"
perform_commissioning