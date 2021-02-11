#!/usr/bin/env bash

start_explorer() {
    stop_explorer

    loginfo "===============\n"
    loginfo "Explorer: start\n"
    loginfo "===============\n"
    echo

    if [[ ! $(docker ps | grep fabric) ]]; then
        logerr "No Fabric networks running. First launch fabkit start\n"
        exit 1
    fi

    if [ ! -d "${FABKIT_CRYPTOS_PATH}" ]; then
        logerr "Cryptos path ${FABKIT_CRYPTOS_PATH} does not exist.\n"
    fi

    # replacing private key path in connection profile
    config=${FABKIT_EXPLORER_PATH}/connection-profile/first-network
    admin_key_path="peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"
    private_key="/tmp/crypto/${admin_key_path}/$(ls ${FABKIT_CRYPTOS_PATH}/${admin_key_path})"
    cat ${config}.base.json | __jq -r --arg private_key "$private_key" '.organizations.Org1MSP.adminPrivateKey.path = $private_key' |
        __jq -r --argjson FABKIT_TLS_ENABLED "$FABKIT_TLS_ENABLED" '.client.tlsEnable = $FABKIT_TLS_ENABLED' >${config}.json

    # considering tls enabled as default in base
    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        sed -i'.bak' -e 's/grpcs/grpc/g' -e 's/https/http/g' ${config}.json && rm ${config}.json.bak
    fi

    docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_EXPLORER_PATH}/docker-compose.yaml up --force-recreate -d || exit 1

    logwarn "Blockchain Explorer default user is exploreradmin/exploreradminpw - http://localhost:8090\n"
    logwarn "Grafana default user is admin/admin - http://localhost:3000\n"
}

stop_explorer() {
    loginfo "==============\n"
    loginfo "Explorer: stop\n"
    loginfo "==============\n"
    echo

    docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_EXPLORER_PATH}/docker-compose.yaml down || exit 1
    docker volume prune -f $(docker volume ls | awk '($2 ~ /explorer/) {print $2}') 2>/dev/null
}
