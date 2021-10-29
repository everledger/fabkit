#!/usr/bin/env bash

install_network() {
    loginfoln "Installing Fabric dependencies"

    __docker_fabric_pull &
    __spinner
    __docker_third_party_images_pull &
    __spinner
}

__docker_fabric_pull() {
    loginfo "Pulling Fabric images"
    __clear_logdebu
    for image in peer orderer ccenv tools; do
        logdebu "Pulling hyperledger/fabric-$image:${FABKIT_FABRIC_VERSION}"
        docker pull hyperledger/fabric-$image:"${FABKIT_FABRIC_VERSION}" 1>/dev/null 2> >(__throw >&2)
    done

    logdebu "Pulling hyperledger/fabric-ca:${FABKIT_FABRIC_CA_VERSION}"
    docker pull hyperledger/fabric-ca:"${FABKIT_FABRIC_CA_VERSION}" 1>/dev/null 2> >(__throw >&2)

    logdebu "Pulling ${FABKIT_COUCHDB_IMAGE}"
    docker pull "${FABKIT_COUCHDB_IMAGE}" 1>/dev/null 2> >(__throw >&2)
}

__docker_third_party_images_pull() {
    loginfo "Pulling utilities images"
    __clear_logdebu
    logdebu "Pulling ${FABKIT_DOCKER_IMAGE}"
    docker pull "$FABKIT_DOCKER_IMAGE" 1>/dev/null 2> >(__throw >&2)
}

start_network() {
    loginfoln "Starting Fabric network"

    if (docker volume ls | grep -q "$FABKIT_DOCKER_NETWORK") && [[ (-z "${FABKIT_RESET}" || "${FABKIT_RESET}" = "false") ]]; then
        logwarn "Found volumes"
        read -rp "Do you wish to restart the network and reuse this data? (Y/n) " yn
        case $yn in
        [Nn]*) ;;
        *)
            __load_lastrun
            __log_setup
            restart_network &
            __spinner
            return 0
            ;;
        esac
    fi

    stop_network &
    __spinner
    __prune_docker_volumes

    if [ -z "${FABKIT_QUICK_RUN}" ]; then
        (chaincode_build "$FABKIT_CHAINCODE_NAME") &
        __spinner
        (chaincode_test "$FABKIT_CHAINCODE_NAME") &
        __spinner
    fi

    for org in $(seq 1 "${FABKIT_ORGS}"); do
        local command+="docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_NETWORK_PATH}/org${org}.yaml up -d;"
    done

    __set_network_env
    # TODO: create raft profiles for different network topologies (multi-org support)
    if [ "$FABKIT_CONFIGTX_PROFILE_NETWORK" = "$RAFT_ONE_ORG" ]; then
        command+="docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_NETWORK_PATH}/raft.yaml up -d;"
    fi

    (generate_cryptos "$FABKIT_CONFIG_PATH" "$FABKIT_CRYPTOS_PATH") &
    __spinner
    (generate_genesis "$FABKIT_NETWORK_PATH" "$FABKIT_CONFIG_PATH" "$FABKIT_CRYPTOS_PATH" "$FABKIT_CONFIGTX_PROFILE_NETWORK") &
    __spinner
    (generate_channeltx "$FABKIT_CHANNEL_NAME" "$FABKIT_NETWORK_PATH" "$FABKIT_CONFIG_PATH" "$FABKIT_CRYPTOS_PATH" "$FABKIT_CONFIGTX_PROFILE_NETWORK" "$FABKIT_CONFIGTX_PROFILE_CHANNEL" "$FABKIT_ORG_MSP") &
    __spinner

    __set_lastrun

    docker network create "$FABKIT_DOCKER_NETWORK" &>/dev/null || true
    (
        loginfo "Launching Fabric components"
        if ! (eval "$command" &>/dev/null) > >(__throw >&2); then
            echo
            logerr "Failed to launch containers. Possible causes:\n1. Other running networks or containers using the same ports. Clean your docker services and run this command again.\n2. Configuration variables unset. Navigate to the FABKIT_ROOT and check your shell is automatically importing the .env file."
            exit 1
        fi
        sleep 5
    ) &
    __spinner

    __log_setup
    loginfoln "Initializing the network"
    initialize_network
}

restart_network() {
    loginfo "Restarting Fabric network "

    docker network create "$FABKIT_DOCKER_NETWORK" &>/dev/null || true

    for org in $(seq 1 "$FABKIT_ORGS"); do
        local command+="docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_NETWORK_PATH}/org${org}.yaml up -d;"
    done
    if (eval "$command") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Failed to restart containers"
        exit 1
    fi

    __clear_logdebu
    echo
    logwarn "The chaincode container will be instantiated automatically once the peer executes the first invoke or query"
}

__prune_docker_volumes() {
    docker volume prune -f $(docker volume ls | awk '($2 ~ /${FABKIT_DOCKER_NETWORK}/) {print $2}') &>/dev/null
}

__check_docker_volumes() {
    if [ "${FABKIT_RESET:-}" = "true" ]; then
        __prune_docker_volumes
    elif docker volume ls | grep -q "$FABKIT_DOCKER_NETWORK"; then
        logwarn "!!!!! ATTENTION !!!!!"
        logwarn "Found volumes"
        read -rp "Do you wish to remove this data? (y/N) " yn
        case $yn in
        [Yy]*)
            (
                stop_network
                __prune_docker_volumes
            ) &
            __spinner
            ;;
        *)
            (
                stop_network
            ) &
            __spinner
            ;;
        esac
    else
        (
            stop_network
        ) &
        __spinner
    fi
}

__check_previous_network() {
    if ! docker volume ls | grep -q "$FABKIT_DOCKER_NETWORK"; then
        echo
        logwarn "No volumes from a previous run found. Running a normal start..."
        start_network
    else
        (restart_network) &
        __spinner
    fi
}

stop_network() {
    loginfo "Stopping network and removing components"

    for org in $(seq 1 "$FABKIT_ORGS"); do
        local command+="docker-compose --env-file ${FABKIT_ROOT}/.env -f ${FABKIT_NETWORK_PATH}/org${org}.yaml down --remove-orphans;"
    done
    if (eval "$command") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Failed to stop running containers"
        exit 1
    fi

    if docker ps | grep -q "hyperledger/explorer"; then
        echo -en "\n\033[3C→ "
        stop_explorer
    fi

    if docker ps | grep -q "fabric-console"; then
        echo -en "\n\033[3C→ "
        stop_console
    fi

    __clear_logdebu
    logdebu "Cleaning docker leftovers containers and images"
    docker rm -f $(docker ps -a | awk '($2 ~ /${FABKIT_DOCKER_NETWORK}|dev-/) {print $1}') &>/dev/null || true
    docker rmi -f $(docker images -qf "dangling=true") &>/dev/null || true
    docker rmi -f $(docker images | awk '($1 ~ /^<none>|dev-/) {print $3}') &>/dev/null || true
}

initialize_network() {
    (create_channel "$FABKIT_CHANNEL_NAME" 1 0) &
    __spinner
    for org in $(seq 1 "${FABKIT_ORGS}"); do
        (join_channel "$FABKIT_CHANNEL_NAME" "$org" 0) &
        __spinner
    done

    #TODO: [FND-101] Update channel with anchor peers for all orgs
    (update_channel "$FABKIT_CHANNEL_NAME" "$FABKIT_ORG_MSP" 1 0) &
    __spinner

    if [[ "${FABKIT_FABRIC_VERSION}" =~ ^2.* ]]; then
        (lifecycle_chaincode_package "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHAINCODE_NAME" 1 0) &
        __spinner

        for org in $(seq 1 "${FABKIT_ORGS}"); do
            (lifecycle_chaincode_install "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$org" 0) &
            __spinner
            (lifecycle_chaincode_approve "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHANNEL_NAME" 1 "$org" 0) &
            __spinner
        done

        (lifecycle_chaincode_commit "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHANNEL_NAME" 1 1 0) &
        __spinner
    else
        for org in $(seq 1 "${FABKIT_ORGS}"); do
            (chaincode_install "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHAINCODE_NAME" "$org" 0) &
            __spinner
        done
        (chaincode_instantiate "$FABKIT_CHAINCODE_NAME" "$FABKIT_CHAINCODE_VERSION" "$FABKIT_CHANNEL_NAME" 1 0) &
        __spinner
    fi

    local key="mydiamond"
    local value='{\"cut_grade\":\"excellent\",\"color_grade\":\"d\",\"clarity_grade\":\"vs1\",\"carat_weight\":0.31,\"origin\":\"russia\",\"certifier\":\"GIA\",\"certificate_no\":\"5363986006\",\"uri\":\"https://provenance.everledger.io/time-lapse/GIA/5363986006\"}'
    echo
    logsucc "Great! Your blockchain network is up and running 🚀 now you can try to run a couple of simple commands:"
    echo
    echo "Let's add a new diamond! ✨💎✨"
    loghead "\tfabkit chaincode invoke mychannel mygocc 1 0 '{\"Args\":[\"put\",\"$key\",\"$value\"]}'\n"
    echo "And then let's fetch it! 🤩 (tip: click on the uri link to explore its journey 🌎)"
    loghead "\tfabkit chaincode query mychannel mygocc 1 0 '{\"Args\":[\"get\",\"$key\"]}'\n"
    echo
    echo "Find more available commands at: $(loginfo "https://github.com/everledger/fabkit/blob/master/docs/chaincode.md")"
}

__replace_config_capabilities() {
    configtx=${FABKIT_CONFIG_PATH}/configtx
    if [[ "${FABKIT_FABRIC_VERSION}" =~ ^2.* ]]; then
        if (cat "${configtx}.base.yaml" | __run "$FABKIT_ROOT" yq "e '.Capabilities.Channel.V2_0 = true |
            .Capabilities.Channel.V1_4_3 = false |
            .Capabilities.Orderer.V2_0 = true |
            .Capabilities.Orderer.V1_4_2 = false |
            .Capabilities.Application.V2_0 = true |
            .Capabilities.Application.V1_4_2 = false' -" >"${configtx}.yaml") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
            logerr "Error in replacing Fabric capabilities"
            exit 1
        fi
    else
        if (cat "${configtx}.base.yaml" | __run "$FABKIT_ROOT" yq "e '.Capabilities.Channel.V2_0 = false |
            .Capabilities.Channel.V1_4_3 = true |
            .Capabilities.Orderer.V2_0 = false |
            .Capabilities.Orderer.V1_4_2 = true |
            .Capabilities.Application.V2_0 = false |
            .Capabilities.Application.V1_4_2 = true' -" >"${configtx}.yaml") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
            logerr "Error in replacing Fabric capabilities"
            exit 1
        fi
    fi
}

__set_network_env() {
    if [ "$FABKIT_CONFIGTX_PROFILE_NETWORK" = "$RAFT_ONE_ORG" ]; then
        FABKIT_CONFIGTX_PROFILE_NETWORK=${RAFT_ONE_ORG}
    elif [ "${FABKIT_ORGS}" = "2" ]; then
        FABKIT_CONFIGTX_PROFILE_NETWORK=${TWO_ORGS}
        FABKIT_CONFIGTX_PROFILE_CHANNEL=TwoOrgsChannel
    elif [ "${FABKIT_ORGS}" = "3" ]; then
        FABKIT_CONFIGTX_PROFILE_NETWORK=${THREE_ORGS}
        FABKIT_CONFIGTX_PROFILE_CHANNEL=ThreeOrgsChannel
    fi

    if [[ "${FABKIT_FABRIC_VERSION}" =~ ^1.* || "${FABKIT_FABRIC_VERSION}" =~ ^2.[012].* ]]; then
        export FABKIT_COUCHDB_IMAGE="hyperledger/fabric-couchdb:${FABKIT_FABRIC_THIRDPARTY_IMAGE_VERSION}"
    fi
}

# generate genesis block
# $1: base path
# $2: config path
# $3: cryptos directory
# $4: network profile name
generate_genesis() {
    loginfo "Generating genesis block"

    if [ -z "$1" ]; then
        logerr "Base path missing"
        exit 1
    fi
    if [ -z "$2" ]; then
        logerr "Config path missing"
        exit 1
    fi
    if [ -z "$3" ]; then
        logerr "Crypto material path missing"
        exit 1
    fi
    if [ -z "$4" ]; then
        logerr "Network profile name"
        exit 1
    fi

    local base_path="$1"
    local config_path="$2"
    local channel_dir="${base_path}/channels/orderer-system-channel"
    local cryptos_path="$3"
    local network_profile="$4"

    if [ "${FABKIT_RESET:-}" = "true" ] || [ -z "${FABKIT_INTERACTIVE}" ] || [ "${FABKIT_INTERACTIVE}" = "false" ]; then
        __delete_path "$channel_dir"
    else
        if [ -d "$channel_dir" ]; then
            logwarn "Channel directory ${channel_dir} already exists"
            read -rp "Do you wish to re-generate channel config? (y/N) " yn
            case $yn in
            [Yy]*) ;;
            *) return 0 ;;
            esac
            __delete_path "$channel_dir"
        fi
    fi

    __clear_logdebu
    logdebu "Base path: $base_path"
    logdebu "Config path: $config_path"
    logdebu "Cryptos path: $cryptos_path"
    logdebu "Network profile: $network_profile"

    if [ ! -d "$channel_dir" ]; then
        mkdir -p "$channel_dir"
    fi

    __replace_config_capabilities

    # generate genesis block for orderer
    if (docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${config_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}/configtx.yaml:/configtx.yaml" \
        -v "${channel_dir/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/channels/orderer-system-channel" \
        -v "${cryptos_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/crypto-config" \
        -u "$(id -u):$(id -g)" \
        -e FABRIC_CFG_PATH=/ \
        hyperledger/fabric-tools:"$FABKIT_FABRIC_VERSION" \
        bash -c " \
            configtxgen -profile $network_profile -channelID orderer-system-channel -outputBlock /channels/orderer-system-channel/genesis_block.pb /configtx.yaml &&
            configtxgen -inspectBlock /channels/orderer-system-channel/genesis_block.pb >/channels/orderer-system-channel/genesis_block.pb.json
        " 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal") > >(__throw >&2); then
        # TODO: grab error log from docker logs fabric-cli
        logerr "Failed to generate orderer genesis block"
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
    loginfo "Generating channel config"

    if [ -z "$1" ]; then
        logerr "Channel name missing"
        exit 1
    fi
    if [ -z "$2" ]; then
        logerr "Base path missing"
        exit 1
    fi
    if [ -z "$3" ]; then
        logerr "Config path missing"
        exit 1
    fi
    if [ -z "$4" ]; then
        logerr "Crypto material path missing"
        exit 1
    fi
    if [ -z "$5" ]; then
        logerr "Network profile missing"
        exit 1
    fi
    if [ -z "$6" ]; then
        logerr "Channel profile missing"
        exit 1
    fi
    if [ -z "$7" ]; then
        logerr "MSP missing"
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

    if [ -d "$channel_dir" ]; then
        if [ "${FABKIT_RESET:-}" = "true" ] || [ -z "${FABKIT_INTERACTIVE}" ] || [ "${FABKIT_INTERACTIVE}" = "false" ]; then
            __delete_path "$channel_dir"
        else
            logwarn "Channel directory ${channel_dir} already exists"
            read -rp "Do you wish to re-generate channel config? (y/N) " yn
            case $yn in
            [Yy]*) ;;
            *) return 0 ;;
            esac
            __delete_path "$channel_dir"

        fi
    fi

    __clear_logdebu
    logdebu "Channel: $channel_name"
    logdebu "Base path: $base_path"
    logdebu "Config path: $config_path"
    logdebu "Cryptos path: $cryptos_path"
    logdebu "Channel dir: $channel_dir"
    logdebu "Network profile: $network_profile"
    logdebu "Channel profile: $channel_profile"
    logdebu "Org MSP: $org_msp"

    if [ ! -d "$channel_dir" ]; then
        mkdir -p "$channel_dir"
    fi

    __replace_config_capabilities

    # generate channel configuration transaction
    if (docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${config_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}/configtx.yaml:/configtx.yaml" \
        -v "${channel_dir/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/channels/${channel_name}" \
        -v "${cryptos_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/crypto-config" \
        -u "$(id -u):$(id -g)" \
        -e FABRIC_CFG_PATH=/ \
        hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
        bash -c " \
            configtxgen -profile $channel_profile -outputCreateChannelTx /channels/${channel_name}/${channel_name}_tx.pb -channelID ${channel_name} /configtx.yaml &&
            configtxgen -inspectChannelCreateTx /channels/${channel_name}/${channel_name}_tx.pb >/channels/${channel_name}/${channel_name}_tx.pb.json
        " 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal") > >(__throw >&2); then
        logerr "Failed to generate channel configuration transaction"
        exit 1
    fi

    # generate anchor peer transaction
    if (docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${config_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}/configtx.yaml:/configtx.yaml" \
        -v "${channel_dir/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/channels/${channel_name}" \
        -v "${cryptos_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/crypto-config" \
        -u "$(id -u):$(id -g)" \
        -e FABRIC_CFG_PATH=/ \
        hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
        configtxgen -profile "$channel_profile" -outputAnchorPeersUpdate "/channels/${channel_name}/${org_msp}_anchors_tx.pb" -channelID "$channel_name" -asOrg "$org_msp" /configtx.yaml 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal") > >(__throw >&2); then
        logerr "Failed to generate anchor peer update for $org_msp"
        exit 1
    fi
}

# generate crypto config
# $1: crypto-config.yml file path
# $2: certificates output directory
generate_cryptos() {
    if [ -z "$1" ]; then
        logerr "Config path missing"
        exit 1
    fi
    if [ -z "$2" ]; then
        logerr "Cryptos path missing"
        exit 1
    fi

    local config_path="$1"
    local cryptos_path="$2"

    loginfo "Generating cryptos"
    __clear_logdebu
    logdebu "Config path: $config_path"
    logdebu "Cryptos path: $cryptos_path"

    if [ "${FABKIT_RESET:-}" = "true" ] || [ -z "${FABKIT_INTERACTIVE}" ] || [ "${FABKIT_INTERACTIVE}" = "false" ]; then
        __delete_path "$cryptos_path"
    else
        if [ -d "${cryptos_path}" ]; then
            logwarn "crypto-config already exists"
            read -rp "Do you wish to remove crypto-config and generate new ones? (y/N) " yn
            case $yn in
            [Yy]*) __delete_path "$cryptos_path" ;;
            *) ;;
            esac
        fi
    fi

    if [ ! -d "${cryptos_path}" ]; then
        mkdir -p "$cryptos_path"

        # generate crypto material
        if (docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
            -v "${config_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}/crypto-config.yaml:/crypto-config.yaml" \
            -v "${cryptos_path/$FABKIT_ROOT/$FABKIT_HOST_ROOT}:/crypto-config" \
            -u "$(id -u):$(id -g)" \
            hyperledger/fabric-tools:"${FABKIT_FABRIC_VERSION}" \
            cryptogen generate --config=/crypto-config.yaml --output=/crypto-config 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal") > >(__throw >&2); then
            logerr "Failed to generate crypto material"
            exit 1
        fi
    fi
}
