#!/usr/bin/env bash

install_network() {
    loginfo "Installing Fabric dependencies"

    __docker_fabric_pull &
    keep_me_busy
    __docker_third_party_images_pull &
    keep_me_busy
}

__docker_fabric_pull() {
    loginfo "Pulling Fabric images"
    for image in peer orderer ccenv tools; do
        logdebu "Pulling hyperledger/fabric-$image:${FABKIT_FABRIC_VERSION}"
        docker pull hyperledger/fabric-$image:${FABKIT_FABRIC_VERSION} &>/dev/null || exit 1
        docker tag hyperledger/fabric-$image:${FABKIT_FABRIC_VERSION} hyperledger/fabric-$image:latest &>/dev/null || exit 1
    done

    logdebu "\nPulling hyperledger/fabric-ca:${FABKIT_FABRIC_CA_VERSION}"
    docker pull hyperledger/fabric-ca:${FABKIT_FABRIC_CA_VERSION} &>/dev/null || exit 1
    docker tag hyperledger/fabric-ca:${FABKIT_FABRIC_CA_VERSION} hyperledger/fabric-ca:latest &>/dev/null || exit 1

    logdebu "\nPulling hyperledger/fabric-couchdb:${FABKIT_FABRIC_THIRDPARTY_IMAGE_VERSION}"
    docker pull hyperledger/fabric-couchdb:${FABKIT_FABRIC_THIRDPARTY_IMAGE_VERSION} &>/dev/null || exit 1
    docker tag hyperledger/fabric-couchdb:${FABKIT_FABRIC_THIRDPARTY_IMAGE_VERSION} hyperledger/fabric-couchdb:latest &>/dev/null || exit 1
}

__docker_third_party_images_pull() {
    loginfo "Pulling utilities images"
    logdebu "\nPulling ${FABKIT_GOLANG_DOCKER_IMAGE}"
    docker pull "$FABKIT_GOLANG_DOCKER_IMAGE" &>/dev/null || exit 1
    logdebu "\nPulling ${FABKIT_JQ_DOCKER_IMAGE}"
    docker pull "$FABKIT_JQ_DOCKER_IMAGE" &>/dev/null || exit 1
    logdebu "\nPulling ${FABKIT_YQ_DOCKER_IMAGE}"
    docker pull "$FABKIT_YQ_DOCKER_IMAGE" &>/dev/null || exit 1
}

start_network() {
    loginfo "Starting Fabric network\n"

    if [[ $(docker volume ls | grep ${FABKIT_DOCKER_NETWORK}) && ! ${FABKIT_RESET} ]]; then
        logwarn "Found volumes"
        read -rp "Do you wish to restart the network and reuse this data? [yes/no=default] " yn
        case $yn in
        [Yy]*)
            restart_network &
            keep_me_busy
            return 0
            ;;
        *) ;;
        esac
    fi

    stop_network &
    keep_me_busy

    if [ -z "${FABKIT_QUICK_RUN}" ]; then
        (chaincode_build "$FABKIT_CHAINCODE_NAME") &
        keep_me_busy
        (chaincode_test "$FABKIT_CHAINCODE_NAME") &
        keep_me_busy
    fi

    for org in $(seq 1 "${FABKIT_ORGS}"); do
        local command+="docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_NETWORK_PATH}/org${org}.yaml up -d &>/dev/null || exit 1;"
    done

    # TODO: create raft profiles for different network topologies (multi-org support)
    if [ "${FABKIT_CONFIGTX_PROFILE_NETWORK}" == "${RAFT_ONE_ORG}" ]; then
        FABKIT_CONFIGTX_PROFILE_NETWORK=${RAFT_ONE_ORG}
        command+="docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_NETWORK_PATH}/raft.yaml up -d &>/dev/null || exit 1;"
    elif [ "${FABKIT_ORGS}" == "2" ]; then
        FABKIT_CONFIGTX_PROFILE_NETWORK=${TWO_ORGS}
        FABKIT_CONFIGTX_PROFILE_CHANNEL=TwoOrgsChannel
    elif [ "${FABKIT_ORGS}" == "3" ]; then
        FABKIT_CONFIGTX_PROFILE_NETWORK=${THREE_ORGS}
        FABKIT_CONFIGTX_PROFILE_CHANNEL=ThreeOrgsChannel
    fi

    (generate_cryptos "$FABKIT_CONFIG_PATH" "$FABKIT_CRYPTOS_PATH") &
    keep_me_busy
    (generate_genesis "$FABKIT_NETWORK_PATH" "$FABKIT_CONFIG_PATH" "$FABKIT_CRYPTOS_PATH" "$FABKIT_CONFIGTX_PROFILE_NETWORK") &
    keep_me_busy
    (generate_channeltx "$FABKIT_CHANNEL_NAME" "$FABKIT_NETWORK_PATH" "$FABKIT_CONFIG_PATH" "$FABKIT_CRYPTOS_PATH" "$FABKIT_CONFIGTX_PROFILE_NETWORK" "$FABKIT_CONFIGTX_PROFILE_CHANNEL" "$FABKIT_ORG_MSP") &
    keep_me_busy

    __set_lastrun

    docker network create "$FABKIT_DOCKER_NETWORK" &>/dev/null || exit 1

    (loginfo "Launching containers" && eval ${command} && sleep 5) &
    keep_me_busy

    __log_setup
    loginfo "Initializing the network\n"
    initialize_network
}

restart_network() {
    loginfo "Restarting Fabric network"
    echo

    if [[ ! $(docker volume ls | grep ${FABKIT_DOCKER_NETWORK}) ]]; then
        logerr "No volumes from a previous run found. Run a normal start.\n"
        exit 1
    fi

    __load_lastrun
    __log_setup

    docker network create "$FABKIT_DOCKER_NETWORK" &>/dev/null | exit 1

    for org in $(seq 1 "$FABKIT_ORGS"); do
        local command+="docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_NETWORK_PATH}/org${org}.yaml --force-recreate -d &>/dev/null || exit 1;"
    done
    eval ${command}

    logwarn "The chaincode container will be instantiated automatically once the peer executes the first invoke or query\n"
}

stop_network() {
    loginfo "Stopping network and removing components"

    for org in $(seq 1 "$FABKIT_ORGS"); do
        local command+="docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_NETWORK_PATH}/org${org}.yaml down --remove-orphans &>/dev/null || exit 1;"
    done
    eval ${command}

    if [[ $(docker ps | grep "hyperledger/explorer") ]]; then
        stop_explorer &
        keep_me_busy
    fi

    logdebu "Cleaning docker leftovers containers and images\n"
    docker rm -f $(docker ps -a | awk '($2 ~ /${FABKIT_DOCKER_NETWORK}|dev-/) {print $1}') &>/dev/null
    docker rmi -f $(docker images -qf "dangling=true") &>/dev/null
    docker rmi -f $(docker images | awk '($1 ~ /^<none>|dev-/) {print $3}') &>/dev/null
    docker system prune -f &>/dev/null

    if [ "${FABKIT_RESET}" == "true" ]; then
        docker volume prune -f $(docker volume ls | awk '($2 ~ /${FABKIT_DOCKER_NETWORK}/) {print $2}') &>/dev/null
        return 0
    fi

    if [[ $(docker volume ls | grep ${FABKIT_DOCKER_NETWORK}) ]]; then
        logerr "!!!!! ATTENTION !!!!!\n"
        logerr "Found volumes\n"
        read -rp "Do you wish to remove this data? [yes/no=default] " yn
        case $yn in
        [Yy]*)
            docker volume prune -f $(docker volume ls | awk '($2 ~ /${FABKIT_DOCKER_NETWORK}/) {print $2}') &>/dev/null
            ;;
        *) return 0 ;;
        esac
    fi
}

initialize_network() {
    (create_channel "$FABKIT_CHANNEL_NAME" 1 0) &
    keep_me_busy
    for org in $(seq 1 "${FABKIT_ORGS}"); do
        (join_channel "$FABKIT_CHANNEL_NAME" "$org" 0) &
        keep_me_busy
    done

    #TODO: [FND-101] Update channel with anchor peers for all orgs
    (update_channel "$FABKIT_CHANNEL_NAME" "$FABKIT_ORG_MSP" 1 0) &
    keep_me_busy

    if [[ "${FABKIT_FABRIC_VERSION}" =~ 2.* ]]; then
        (lc_chaincode_package "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHAINCODE_NAME" 1 0) &
        keep_me_busy

        for org in $(seq 1 "${FABKIT_ORGS}"); do
            (lc_chaincode_install "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$org" 0) &
            keep_me_busy
            (lc_chaincode_approve "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHANNEL_NAME" 1 "$org" 0) &
            keep_me_busy
        done

        (lc_chaincode_commit "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHANNEL_NAME" 1 1 0) &
        keep_me_busy
    else
        for org in $(seq 1 "${FABKIT_ORGS}"); do
            (chaincode_install "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHAINCODE_NAME" "$org" 0) &
            keep_me_busy
        done
        (chaincode_instantiate "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHANNEL_NAME" 1 0) &
        keep_me_busy
    fi
}

__replace_config_capabilities() {
    configtx=${FABKIT_CONFIG_PATH}/configtx
    if [[ "${FABKIT_FABRIC_VERSION}" =~ 2.* ]]; then
        __yq <"${configtx}.base.yaml" e '.Capabilities.Channel.V2_0 = true |
            .Capabilities.Channel.V1_4_3 = false |
            .Capabilities.Orderer.V2_0 = true |
            .Capabilities.Orderer.V1_4_2 = false |
            .Capabilities.Application.V2_0 = true |
            .Capabilities.Application.V1_4_2 = false' - >"${configtx}.yaml" || exit 1
    else
        __yq <"${configtx}.base.yaml" e '.Capabilities.Channel.V2_0 = false |
            .Capabilities.Channel.V1_4_3 = true |
            .Capabilities.Orderer.V2_0 = false |
            .Capabilities.Orderer.V1_4_2 = true |
            .Capabilities.Application.V2_0 = false |
            .Capabilities.Application.V1_4_2 = true' - >"${configtx}.yaml" || exit 1
    fi
}

# generate genesis block
# $1: base path
# $2: config path
# $3: cryptos directory
# $4: network profile name
generate_genesis() {
    if [ -z "$1" ]; then
        logerr "Base path missing\n"
        exit 1
    fi
    if [ -z "$2" ]; then
        logerr "Config path missing\n"
        exit 1
    fi
    if [ -z "$3" ]; then
        logerr "Crypto material path missing\n"
        exit 1
    fi
    if [ -z "$4" ]; then
        logerr "Network profile name\n"
        exit 1
    fi

    local base_path="$1"
    local config_path="$2"
    local channel_dir="${base_path}/channels/orderer-system-channel"
    local cryptos_path="$3"
    local network_profile="$4"

    if [ "${FABKIT_RESET}" == "true" ]; then
        __delete_path "$channel_dir"
    fi

    if [ -d "$channel_dir" ]; then
        logwarn "Channel directory ${channel_dir} already exists\n"
        read -rp "Do you wish to re-generate channel config? [yes/no=default] " yn
        case $yn in
        [Yy]*) ;;
        *) return 0 ;;
        esac
        __delete_path "$channel_dir"
    fi

    loginfo "Generating genesis block"
    logdebu "Base path: $base_path\n"
    logdebu "Config path: $config_path\n"
    logdebu "Cryptos path: $cryptos_path\n"

    if [ ! -d "$channel_dir" ]; then
        mkdir -p "$channel_dir"
    fi

    __replace_config_capabilities

    # generate genesis block for orderer
    if ! docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${config_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}/configtx.yaml:/configtx.yaml" \
        -v "${channel_dir/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/channels/orderer-system-channel" \
        -v "${cryptos_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/crypto-config" \
        -u "$(id -u):$(id -g)" \
        -e FABRIC_CFG_PATH=/ \
        hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
        bash -c " \
            configtxgen -profile $network_profile -channelID orderer-system-channel -outputBlock /channels/orderer-system-channel/genesis_block.pb /configtx.yaml;
            configtxgen -inspectBlock /channels/orderer-system-channel/genesis_block.pb >/channels/orderer-system-channel/genesis_block.pb.json
        " &>/dev/null; then
        logerr "Failed to generate orderer genesis block...\n"
        exit 1
    fi
}

# generate channel config
# $1: channel_name
# $2: base path
# $3: configtx.yml file path
# $4: cryptos directory
# $5: network profile name
# $6: channel profile name
# $7: org msp
generate_channeltx() {
    if [ -z "$1" ]; then
        logerr "Channel name missing\n"
        exit 1
    fi
    if [ -z "$2" ]; then
        logerr "Base path missing\n"
        exit 1
    fi
    if [ -z "$3" ]; then
        logerr "Config path missing\n"
        exit 1
    fi
    if [ -z "$4" ]; then
        logerr "Crypto material path missing\n"
        exit 1
    fi
    if [ -z "$5" ]; then
        logerr "Network profile missing\n"
        exit 1
    fi
    if [ -z "$6" ]; then
        logerr "Channel profile missing\n"
        exit 1
    fi
    if [ -z "$7" ]; then
        logerr "MSP missing\n"
        exit 1
    fi

    local channel_name="$1"
    local base_path="$2"
    local config_path="$3"
    local cryptos_path="$4"
    local channel_dir="${base_path}/channels/${channel_name}"
    local network_profile="$5"
    local channel_profile="$6"
    local org_msp="$7"

    if [ "${FABKIT_RESET}" == "true" ]; then
        __delete_path "$channel_dir"
    fi

    if [ -d "$channel_dir" ]; then
        logwarn "Channel directory ${channel_dir} already exists\n"
        read -rp "Do you wish to re-generate channel config? [yes/no=default] " yn
        case $yn in
        [Yy]*) ;;
        *) return 0 ;;
        esac
        __delete_path "$channel_dir"
    fi

    loginfo "Generating channel config"
    logdebu "Channel: $channel_name\n"
    logdebu "Base path: $base_path\n"
    logdebu "Config path: $config_path\n"
    logdebu "Cryptos path: $cryptos_path\n"
    logdebu "Channel dir: $channel_dir\n"
    logdebu "Network profile: $network_profile\n"
    logdebu "Channel profile: $channel_profile\n"
    logdebu "Org MSP: $org_msp\n"

    if [ ! -d "$channel_dir" ]; then
        mkdir -p "$channel_dir"
    fi

    __replace_config_capabilities

    # generate channel configuration transaction
    if ! docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${config_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}/configtx.yaml:/configtx.yaml" \
        -v "${channel_dir/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/channels/${channel_name}" \
        -v "${cryptos_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/crypto-config" \
        -u "$(id -u):$(id -g)" \
        -e FABRIC_CFG_PATH=/ \
        hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
        bash -c " \
            configtxgen -profile $channel_profile -outputCreateChannelTx /channels/${channel_name}/${channel_name}_tx.pb -channelID ${channel_name} /configtx.yaml;
            configtxgen -inspectChannelCreateTx /channels/${channel_name}/${channel_name}_tx.pb >/channels/${channel_name}/${channel_name}_tx.pb.json
        " &>/dev/null; then
        logerr "Failed to generate channel configuration transaction...\n"
        exit 1
    fi

    # generate anchor peer transaction
    if ! docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${config_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}/configtx.yaml:/configtx.yaml" \
        -v "${channel_dir/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/channels/${channel_name}" \
        -v "${cryptos_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/crypto-config" \
        -u "$(id -u):$(id -g)" \
        -e FABRIC_CFG_PATH=/ \
        hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
        configtxgen -profile "$channel_profile" -outputAnchorPeersUpdate "/channels/${channel_name}/${org_msp}_anchors_tx.pb" -channelID "$channel_name" -asOrg "$org_msp" /configtx.yaml &>/dev/null; then
        logerr "Failed to generate anchor peer update for $org_msp...\n"
        exit 1
    fi
}

# generate crypto config
# $1: crypto-config.yml file path
# $2: certificates output directory
generate_cryptos() {
    if [ -z "$1" ]; then
        logerr "Config path missing\n"
        exit 1
    fi
    if [ -z "$2" ]; then
        logerr "Cryptos path missing\n"
        exit 1
    fi

    local config_path="$1"
    local cryptos_path="$2"

    loginfo "Generating cryptos"
    logdebu "Config path: $config_path\n"
    logdebu "Cryptos path: $cryptos_path\n"

    if [ "${FABKIT_RESET}" == "true" ]; then
        __delete_path "$cryptos_path"
    fi

    if [ -d "${cryptos_path}" ]; then
        logwarn "crypto-config already exists\n"
        read -rp "Do you wish to remove crypto-config and generate new ones? [yes/no=default] " yn
        case $yn in
        [Yy]*) __delete_path "$cryptos_path" ;;
        *) ;;
        esac
    fi

    if [ ! -d "${cryptos_path}" ]; then
        mkdir -p "$cryptos_path"

        # generate crypto material
        if ! docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
            -v "${config_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}/crypto-config.yaml:/crypto-config.yaml" \
            -v "${cryptos_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/crypto-config" \
            -u "$(id -u):$(id -g)" \
            hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
            cryptogen generate --config=/crypto-config.yaml --output=/crypto-config &>/dev/null; then
            logerr "Failed to generate crypto material...\n"
            exit 1
        fi
    fi
}
