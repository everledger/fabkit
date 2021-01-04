#!/usr/bin/env bash

start_explorer() {
    stop_explorer

    log "===============" info
    log "Explorer: start" info
    log "===============" info
    echo

    if [[ ! $(docker ps | grep fabric) ]]; then
        log "No Fabric networks running. First launch fabkit start" error
        exit 1
    fi

    if [ ! -d "${CRYPTOS_PATH}" ]; then
        log "Cryptos path ${CRYPTOS_PATH} does not exist." error
    fi

    # replacing private key path in connection profile
    config=${EXPLORER_PATH}/connection-profile/first-network
    admin_key_path="peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"
    private_key="/tmp/crypto/${admin_key_path}/$(ls ${CRYPTOS_PATH}/${admin_key_path})"
    cat ${config}.base.json | __jq -r --arg private_key "$private_key" '.organizations.Org1MSP.adminPrivateKey.path = $private_key' |
        __jq -r --argjson TLS_ENABLED "$TLS_ENABLED" '.client.tlsEnable = $TLS_ENABLED' >${config}.json

    # considering tls enabled as default in base
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        sed -i'.bak' -e 's/grpcs/grpc/g' -e 's/https/http/g' ${config}.json && rm ${config}.json.bak
    fi

    docker-compose -f ${EXPLORER_PATH}/docker-compose.yaml up --force-recreate -d || exit 1

    log "Blockchain Explorer default user is exploreradmin/exploreradminpw - http://localhost:8090" warning
    log "Grafana default user is admin/admin - http://localhost:3000" warning
}

stop_explorer() {
    log "==============" info
    log "Explorer: stop" info
    log "==============" info
    echo

    docker-compose -f ${EXPLORER_PATH}/docker-compose.yaml down || exit 1
}
