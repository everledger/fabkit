#!/usr/bin/env bash

start_console() {
    loginfoln "Starting console"

    if ! docker ps | grep -q "fabric"; then
        logerr "No Fabric networks running. First launch fabkit start"
        exit 1
    fi

    if [ ! -d "${FABKIT_CRYPTOS_PATH}" ]; then
        logerr "Cryptos path ${FABKIT_CRYPTOS_PATH} does not exist."
        exit 1
    fi

    (stop_console) &
    __spinner

    (
        if loginfo "Launching Console components" && docker-compose --env-file "${FABKIT_ROOT}/.env" -f "${FABKIT_CONSOLE_PATH}/docker-compose.yaml" up --force-recreate -d 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
            logerr "Failed to launch containers"
            exit 1
        fi
    ) &
    __spinner

    __generate_assets

    echo "Blockchain Console default user is admin/password - $(logsucc http://localhost:3000)"
}

stop_console() {
    loginfo "Stopping console"

    if docker-compose --env-file "${FABKIT_ROOT}/.env" -f "${FABKIT_CONSOLE_PATH}/docker-compose.yaml" down 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Failed to stop containers"
        exit 1
    fi
    docker volume rm -f $(docker volume ls | awk '($2 ~ /console/) {print $2}') &>/dev/null || true
}

__generate_assets() {
    local assets_path="${FABKIT_CONSOLE_PATH}/assets"
    local templates_path="${FABKIT_CONSOLE_PATH}/templates"
    local assets_file="${FABKIT_DIST_PATH}/console_assets.zip"

    rm -rf "${assets_path}" &>/dev/null
    mkdir -p "${assets_path}/Certificate_Authorities"
    mkdir -p "${assets_path}/Ordering_Services"
    mkdir -p "${assets_path}/Peers"
    mkdir -p "${assets_path}/Organizations"

    local orderer_root_cert=""
    for org in $(seq 1 "${FABKIT_ORGS}"); do
        # extract org root cert from ca info
        local org_root_cert=$(curl -sk http"$(if [ "${FABKIT_TLS_ENABLED:-}" = "true" ]; then echo "s"; fi)"://localhost:$((6 + org))054/cainfo | __run "$FABKIT_ROOT" jq -r .result.CAChain)

        # create org ca import
        if ( 
            (__run "$FABKIT_ROOT" jq --arg org_root_cert "$org_root_cert" "'.tls_cert = \"$org_root_cert\" | .msp.ca.root_certs[0] = \"$org_root_cert\"'" "${templates_path}/Certificate_Authorities/orgca-local_ca.json" >"${assets_path}/Certificate_Authorities/org${org}ca-local_ca.json") &&
                sed -i'.bak' -e "s/%ORG%/${org}/g" -e "s/%PORT_INDEX%/$((6 + org))/g" "${assets_path}/Certificate_Authorities/org${org}ca-local_ca.json" && rm "${assets_path}/Certificate_Authorities/org${org}ca-local_ca.json.bak" &>/dev/null
        ) 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
            logerr "Error creating org${org} ca import"
            exit 1
        fi

        # TODO: repeat for number of peers
        # create peer import
        if ( 
            (__run "$FABKIT_ROOT" jq --arg org_root_cert "$org_root_cert" \
                "'.msp.component.tls_cert = \"$org_root_cert\" | .msp.ca.root_certs[0] = \"$org_root_cert\" | .msp.tlsca.root_certs[0] = \"$org_root_cert\" | .pem = \"$org_root_cert\" | .tls_cert = \"$org_root_cert\" | .tls_ca_root_cert = \"$org_root_cert\"'" \
                "${templates_path}/Peers/org_peer-local_peer.json" >"${assets_path}/Peers/org${org}_peer0-local_peer.json") &&
                sed -i'.bak' -e "s/%ORG%/${org}/g" -e "s/%PORT_INDEX%/$((6 + org))/g" "${assets_path}/Peers/org${org}_peer0-local_peer.json" && rm "${assets_path}/Peers/org${org}_peer0-local_peer.json.bak" &>/dev/null
        ) 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
            logerr "Error creating org${org} peer import"
            exit 1
        fi

        # create org msp import
        if ( 
            (__run "$FABKIT_ROOT" jq --arg org_root_cert "$org_root_cert" \
                "'.root_certs[0] = \"$org_root_cert\" | .tls_root_certs[0] = \"$org_root_cert\" | .fabric_node_ous.admin_ou_identifier.certificate = \"$org_root_cert\" | .fabric_node_ous.client_ou_identifier.certificate = \"$org_root_cert\" | .fabric_node_ous.orderer_ou_identifier.certificate = \"$org_root_cert\" | .fabric_node_ous.peer_ou_identifier.certificate = \"$org_root_cert\"'" \
                "${templates_path}/Organizations/orgmsp_msp.json" >"${assets_path}/Organizations/org${org}msp_msp.json") &&
                sed -i'.bak' -e "s/%ORG%/${org}/g" "${assets_path}/Organizations/org${org}msp_msp.json" && rm "${assets_path}/Organizations/org${org}msp_msp.json.bak" &>/dev/null
        ) 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
            logerr "Error creating org${org} msp import"
            exit 1
        fi

        if [ "${org}" -eq 1 ]; then
            orderer_root_cert=$org_root_cert

            # TODO: if an orderer ca msp is defined, retrieve its root certificate with curl pointing to the right address
            # local orderer_root_cert=$(curl -sk http"$(if [ "${FABKIT_TLS_ENABLED:-}" = "true" ]; then echo "s"; fi)"://localhost:$((6 + org))$((0 + org))54/cainfo | __run "$FABKIT_ROOT" jq -r .result.CAChain)

            # create orderer ca import
            # if (__run "$FABKIT_ROOT" jq --arg orderer_root_cert "$orderer_root_cert" "'.tls_cert = \"$orderer_root_cert\"'" "${templates_path}/Certificate_Authorities/ordererca-local_ca.json" >"${assets_path}/Certificate_Authorities/ordererca-local_ca.json") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
            #     logerr "Error creating orderer ca import"
            #     exit 1
            # fi

            # create orderers import
            if (__run "$FABKIT_ROOT" jq --arg orderer_root_cert "$orderer_root_cert" \
                "'.msp.component.tls_cert = \"$orderer_root_cert\" | .msp.ca.root_certs[0] = \"$orderer_root_cert\" | .msp.tlsca.root_certs[0] = \"$orderer_root_cert\" | .pem = \"$orderer_root_cert\" | .tls_cert = \"$orderer_root_cert\" | .tls_ca_root_cert = \"$orderer_root_cert\"'" \
                "${templates_path}/Ordering_Services/orderer-local_orderer.json" >"${assets_path}/Ordering_Services/orderer-local_orderer.json") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
                logerr "Error creating orderers import"
                exit 1
            fi

            # create orderer msp import
            if (__run "$FABKIT_ROOT" jq --arg orderer_root_cert "$orderer_root_cert" \
                "'.root_certs[0] = \"$orderer_root_cert\" | .tls_root_certs[0] = \"$orderer_root_cert\" | .fabric_node_ous.admin_ou_identifier.certificate = \"$orderer_root_cert\" | .fabric_node_ous.client_ou_identifier.certificate = \"$orderer_root_cert\" | .fabric_node_ous.orderer_ou_identifier.certificate = \"$orderer_root_cert\" | .fabric_node_ous.peer_ou_identifier.certificate = \"$orderer_root_cert\"'" \
                "${templates_path}/Organizations/orderermsp_msp.json" >"${assets_path}/Organizations/orderermsp_msp.json") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
                logerr "Error creating orderer msp import"
                exit 1
            fi
        fi
    done

    cd "${assets_path}" && rm -rf "${assets_file}" &>/dev/null && zip -rq "${assets_file}" .
}
