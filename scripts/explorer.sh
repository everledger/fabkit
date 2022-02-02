#!/usr/bin/env bash

start_explorer() {
    loginfoln "Starting explorer"

    if ! docker ps | grep -q "fabric"; then
        logerr "No Fabric networks running. First launch fabkit start"
        exit 1
    fi

    if [ ! -d "${FABKIT_CRYPTOS_PATH}" ]; then
        logerr "Cryptos path ${FABKIT_CRYPTOS_PATH} does not exist."
        exit 1
    fi

    __clear_logdebu
    (stop_explorer) &
    __spinner

    # replacing private key path in connection profile
    config="${FABKIT_EXPLORER_PATH}/connection-profile/first-network"
    admin_key_path="peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"
    private_key="/tmp/crypto/${admin_key_path}/$(ls ${FABKIT_CRYPTOS_PATH}/${admin_key_path})"
    if (cat "${config}.base.json" | __run "$FABKIT_ROOT" jq -r "'.organizations.Org1MSP.adminPrivateKey.path = \"$private_key\" | .client.tlsEnable = $FABKIT_TLS_ENABLED'" >"${config}.json") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error in replacing private key in explorer configuration"
        exit 1
    fi

    # considering tls enabled as default in base
    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        sed -i'.bak' -e 's/grpcs/grpc/g' -e 's/https/http/g' "${config}.json" && rm "${config}.json.bak" 1>/dev/null 2> >(__throw >&2)
    fi

    (
        if loginfo "Launching Explorer components" && docker-compose --env-file "${FABKIT_ROOT}/.env" -f "${FABKIT_EXPLORER_PATH}/docker-compose.yaml" up --force-recreate -d 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
            logerr "Failed to launch containers"
            exit 1
        fi
    ) &
    __spinner

    echo "Blockchain Explorer default user is exploreradmin/exploreradminpw - $(logsucc http://localhost:8090)"
    echo "Grafana default user is admin/admin - $(logsucc http://localhost:3333)"
}

stop_explorer() {
    loginfo "Stopping explorer"

    if docker-compose --env-file "${FABKIT_ROOT}/.env" -f "${FABKIT_EXPLORER_PATH}/docker-compose.yaml" down 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Failed to stop containers"
        exit 1
    fi
    docker volume rm -f $(docker volume ls | awk '($2 ~ /explorer/) {print $2}') &>/dev/null || true
}
