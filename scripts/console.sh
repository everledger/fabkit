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

    __clear_logdebu
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
    docker volume prune -f $(docker volume ls | awk '($2 ~ /console/) {print $2}') &>/dev/null || true
}

__generate_assets() {
    local assets_path="${FABKIT_CONSOLE_PATH}/assets"
    local templates_path="${FABKIT_CONSOLE_PATH}/templates"

    rm -fr "${assets_path}"
    mkdir -p "${assets_path}/Certificate_Authorities"
    mkdir -p "${assets_path}/Ordering_Services"
    mkdir -p "${assets_path}/Peers"
    mkdir -p "${assets_path}/Organizations"

    local ORG1_CAINFO="${assets_path}/org1_ca.json"
    # ORDERER_CAINFO=${assets_path}/orderer_ca.json

    curl -k https://localhost:7054/cainfo >"${ORG1_CAINFO}"
    local ORG1_ROOT_CERT=$(jq .result.CAChain "${ORG1_CAINFO}" -r)

    # curl -k https://localhost:9054/cainfo > "${ORDERER_CAINFO}"
    # ORDERER_ROOT_CERT=$(jq .result.CAChain "${ORDERER_CAINFO}" -r)
    ORDERER_ROOT_CERT=$ORG1_ROOT_CERT

    # Create CA Imports
    jq --arg ORG1_ROOT_CERT "$ORG1_ROOT_CERT" '.tls_cert = $ORG1_ROOT_CERT' "${templates_path}/Certificate_Authorities/org1ca-local_ca.json" >"${assets_path}/Certificate_Authorities/org1ca-local_ca.json"
    jq --arg ORDERER_ROOT_CERT "$ORDERER_ROOT_CERT" '.tls_cert = $ORDERER_ROOT_CERT' "${templates_path}/Certificate_Authorities/ordererca-local_ca.json" >"${assets_path}/Certificate_Authorities/ordererca-local_ca.json"

    # Create Peer Imports
    jq --arg ORG1_ROOT_CERT "$ORG1_ROOT_CERT" \
        '.msp.component.tls_cert = $ORG1_ROOT_CERT | .msp.ca.root_certs[0] = $ORG1_ROOT_CERT | .msp.tlsca.root_certs[0] = $ORG1_ROOT_CERT | .pem = $ORG1_ROOT_CERT | .tls_cert = $ORG1_ROOT_CERT | .tls_ca_root_cert = $ORG1_ROOT_CERT' \
        "${templates_path}/Peers/org1_peer1-local_peer.json" >"${assets_path}/Peers/org1_peer1-local_peer.json"

    # Create Orderer Imports
    jq --arg ORDERER_ROOT_CERT "$ORDERER_ROOT_CERT" \
        '.msp.component.tls_cert = $ORDERER_ROOT_CERT | .msp.ca.root_certs[0] = $ORDERER_ROOT_CERT | .msp.tlsca.root_certs[0] = $ORDERER_ROOT_CERT | .pem = $ORDERER_ROOT_CERT | .tls_cert = $ORDERER_ROOT_CERT | .tls_ca_root_cert = $ORDERER_ROOT_CERT' \
        "${templates_path}/Ordering_Services/orderer-local_orderer.json" >"${assets_path}/Ordering_Services/orderer-local_orderer.json"

    # Create MSP Imports
    jq --arg ORG1_ROOT_CERT "$ORG1_ROOT_CERT" \
        '.root_certs[0] = $ORG1_ROOT_CERT | .tls_root_certs[0] = $ORG1_ROOT_CERT | .fabric_node_ous.admin_ou_identifier.certificate = $ORG1_ROOT_CERT | .fabric_node_ous.client_ou_identifier.certificate = $ORG1_ROOT_CERT | .fabric_node_ous.orderer_ou_identifier.certificate = $ORG1_ROOT_CERT | .fabric_node_ous.peer_ou_identifier.certificate = $ORG1_ROOT_CERT' \
        "${templates_path}/Organizations/org1msp_msp.json" >"${assets_path}/Organizations/org1msp_msp.json"

    jq --arg ORDERER_ROOT_CERT "$ORDERER_ROOT_CERT" \
        '.root_certs[0] = $ORDERER_ROOT_CERT | .tls_root_certs[0] = $ORDERER_ROOT_CERT | .fabric_node_ous.admin_ou_identifier.certificate = $ORDERER_ROOT_CERT | .fabric_node_ous.client_ou_identifier.certificate = $ORDERER_ROOT_CERT | .fabric_node_ous.orderer_ou_identifier.certificate = $ORDERER_ROOT_CERT | .fabric_node_ous.peer_ou_identifier.certificate = $ORDERER_ROOT_CERT' \
        "${templates_path}/Organizations/orderermsp_msp.json" >"${assets_path}/Organizations/orderermsp_msp.json"

    rm "${ORG1_CAINFO}"
    cd "${assets_path}" && zip -rq "${FABKIT_DIST_PATH}/console_assets.zip" .
}
