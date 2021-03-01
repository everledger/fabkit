#!/usr/bin/env bash

start_explorer() {
    loginfo "Starting explorer"
    echo

    (stop_explorer) &
    __spinner

    if [[ ! $(docker ps | grep fabric) ]]; then
        logerr "No Fabric networks running. First launch fabkit start"
        exit 1
    fi

    if [ ! -d "${FABKIT_CRYPTOS_PATH}" ]; then
        logerr "Cryptos path ${FABKIT_CRYPTOS_PATH} does not exist."
        exit 1
    fi

    # replacing private key path in connection profile
    config="${FABKIT_EXPLORER_PATH}/connection-profile/first-network"
    admin_key_path="peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"
    private_key="/tmp/crypto/${admin_key_path}/$(ls ${FABKIT_CRYPTOS_PATH}/${admin_key_path})"
    cat ${config}.base.json | __jq -r --arg private_key "$private_key" '.organizations.Org1MSP.adminPrivateKey.path = $private_key' |
        __jq -r --argjson FABKIT_TLS_ENABLED "$FABKIT_TLS_ENABLED" '.client.tlsEnable = $FABKIT_TLS_ENABLED' >${config}.json || exit 1

    # considering tls enabled as default in base
    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        sed -i'.bak' -e 's/grpcs/grpc/g' -e 's/https/http/g' ${config}.json && rm ${config}.json.bak 1>/dev/null 2> >(__throw >&2)
    fi

    (loginfo "Launching containers" && docker-compose --env-file "${FABKIT_ROOT}/.env" -f "${FABKIT_EXPLORER_PATH}/docker-compose.yaml" up --force-recreate -d &>/dev/null) &
    __spinner

    echo "Blockchain Explorer default user is exploreradmin/exploreradminpw - $(logsucc http://localhost:8090)"
    echo "Grafana default user is admin/admin - $(logsucc http://localhost:3000)"
}

stop_explorer() {
    loginfo "Stopping explorer"

    docker-compose --env-file "${FABKIT_ROOT}/.env" -f "${FABKIT_EXPLORER_PATH}/docker-compose.yaml" down &>/dev/null || exit 1
    docker volume prune -f $(docker volume ls | awk '($2 ~ /explorer/) {print $2}') &>/dev/null || true
}
