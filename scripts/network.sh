#!/usr/bin/env bash

install_network() {
    log "================" info
    log "Network: install" info
    log "================" info
    echo

    __docker_fabric_pull
    __docker_third_party_images_pull
}

__docker_fabric_pull() {
    for image in peer orderer ccenv tools; do
        log "==> FABRIC IMAGE: hyperledger/fabric-$image:${FABKIT_FABRIC_VERSION}" info
        echo
        docker pull hyperledger/fabric-$image:${FABKIT_FABRIC_VERSION} || exit 1
        docker tag hyperledger/fabric-$image:${FABKIT_FABRIC_VERSION} hyperledger/fabric-$image:latest
        echo
    done

    log "==> FABRIC CA IMAGE: hyperledger/fabric-ca:${FABKIT_FABRIC_CA_VERSION}" info
    echo
    docker pull hyperledger/fabric-ca:${FABKIT_FABRIC_CA_VERSION} || exit 1
    docker tag hyperledger/fabric-ca:${FABKIT_FABRIC_CA_VERSION} hyperledger/fabric-ca:latest
    echo

    log "==> COUCHDB IMAGE: hyperledger/fabric-couchdb:${FABKIT_FABRIC_THIRDPARTY_IMAGE_VERSION}" info
    echo
    docker pull hyperledger/fabric-couchdb:${FABKIT_FABRIC_THIRDPARTY_IMAGE_VERSION} || exit 1
    docker tag hyperledger/fabric-couchdb:${FABKIT_FABRIC_THIRDPARTY_IMAGE_VERSION} hyperledger/fabric-couchdb:latest
    echo
}

__docker_third_party_images_pull() {
    log "==> GOLANG IMAGE: ${FABKIT_GOLANG_DOCKER_IMAGE}" info
    echo
    docker pull ${FABKIT_GOLANG_DOCKER_IMAGE}
    echo
    log "==> JQ IMAGE: ${FABKIT_JQ_DOCKER_IMAGE}" info
    echo
    docker pull ${FABKIT_JQ_DOCKER_IMAGE}
    echo
    log "==> YQ IMAGE: ${FABKIT_YQ_DOCKER_IMAGE}" info
    echo
    docker pull ${FABKIT_YQ_DOCKER_IMAGE}
    echo
}

start_network() {
    if [[ ! $(docker volume ls | grep ${FABKIT_DOCKER_NETWORK}) && ! ${FABKIT_RESET} ]]; then
        log "Found volumes" warning
        read -p "Do you wish to restart the network and reuse this data? [yes/no=default] " yn
        case $yn in
        [Yy]*)
            restart_network
            return 0
            ;;
        *) ;;
        esac
    fi

    stop_network

    if [ -z "${FABKIT_QUICK_RUN}" ]; then
        chaincode_build $FABKIT_CHAINCODE_RELATIVE_PATH
        chaincode_test $FABKIT_CHAINCODE_RELATIVE_PATH
    fi

    log "==============" info
    log "Network: start" info
    log "==============" info
    echo

    __chaincode_sync

    local command="docker-compose -f ${FABKIT_ROOT}/docker-compose.yaml up -d || exit 1;"

    # TODO: create raft profiles for different network topologies (multi-org support)
    if [ "${FABKIT_CONFIGTX_PROFILE_NETWORK}" == "${RAFT_ONE_ORG}" ]; then
        FABKIT_CONFIGTX_PROFILE_NETWORK=${RAFT_ONE_ORG}
        command+="docker-compose -f ${FABKIT_ROOT}/docker-compose.etcdraft.yaml up -d || exit 1;"
    elif [ "${FABKIT_ORGS}" == "2" ]; then
        FABKIT_CONFIGTX_PROFILE_NETWORK=${TWO_ORGS}
        FABKIT_CONFIGTX_PROFILE_CHANNEL=TwoOrgsChannel
        command+="docker-compose -f ${FABKIT_ROOT}/docker-compose.org2.yaml up -d || exit 1;"
    elif [ "${FABKIT_ORGS}" == "3" ]; then
        FABKIT_CONFIGTX_PROFILE_NETWORK=${THREE_ORGS}
        FABKIT_CONFIGTX_PROFILE_CHANNEL=ThreeOrgsChannel
        command+="docker-compose -f ${FABKIT_ROOT}/docker-compose.org2.yaml up -d || exit 1;"
        command+="docker-compose -f ${FABKIT_ROOT}/docker-compose.org3.yaml up -d || exit 1;"
    fi

    generate_cryptos $FABKIT_CONFIG_PATH $FABKIT_CRYPTOS_PATH
    generate_genesis $FABKIT_NETWORK_PATH $FABKIT_CONFIG_PATH $FABKIT_CRYPTOS_PATH $FABKIT_CONFIGTX_PROFILE_NETWORK
    generate_channeltx $FABKIT_CHANNEL_NAME $FABKIT_NETWORK_PATH $FABKIT_CONFIG_PATH $FABKIT_CRYPTOS_PATH $FABKIT_CONFIGTX_PROFILE_NETWORK $FABKIT_CONFIGTX_PROFILE_CHANNEL $FABKIT_ORG_MSP

    __set_lastrun
    __log_setup

    docker network create ${FABKIT_DOCKER_NETWORK} 2>/dev/null

    eval ${command}

    sleep 5

    initialize_network
}

restart_network() {
    log "================" info
    log "Network: restart" info
    log "================" info
    echo

    if [[ ! $(docker volume ls | grep ${FABKIT_DOCKER_NETWORK}) ]]; then
        log "No volumes from a previous run found. Run a normal start." error
        exit 1
    fi

    __load_lastrun
    __log_setup

    docker network create ${FABKIT_DOCKER_NETWORK} 2>/dev/null

    local command="docker-compose -f ${FABKIT_ROOT}/docker-compose.yaml up --force-recreate -d || exit 1;"
    for ((i = 2; i <= $FABKIT_ORGS; i++)); do
        command+="docker-compose -f ${FABKIT_ROOT}/docker-compose.org${i}.yaml up --force-recreate -d || exit 1;"
    done
    eval ${command}

    log "The chaincode container will be instantiated automatically once the peer executes the first invoke or query" warning
}

stop_network() {
    log "=============" info
    log "Network: stop" info
    log "=============" info
    echo

    local command="docker-compose -f ${FABKIT_ROOT}/docker-compose.yaml down --remove-orphans || exit 1;"
    for ((i = 2; i <= $FABKIT_ORGS; i++)); do
        command+="docker-compose -f ${FABKIT_ROOT}/docker-compose.org${i}.yaml down --remove-orphans || exit 1;"
    done
    eval ${command}

    if [[ $(docker ps | grep "hyperledger/explorer") ]]; then
        stop_explorer
    fi

    log "Cleaning docker leftovers containers and images" info
    docker rm -f $(docker ps -a | awk '($2 ~ /${FABKIT_DOCKER_NETWORK}|dev-/) {print $1}') 2>/dev/null
    docker rmi -f $(docker images -qf "dangling=true") 2>/dev/null
    docker rmi -f $(docker images | awk '($1 ~ /^<none>|dev-/) {print $3}') 2>/dev/null
    docker system prune -f 2>/dev/null

    if [ "${FABKIT_RESET}" == "true" ]; then
        docker volume prune -f $(docker volume ls | awk '($2 ~ /${FABKIT_DOCKER_NETWORK}/) {print $2}') 2>/dev/null
        return 0
    fi

    if [[ $(docker volume ls | grep ${FABKIT_DOCKER_NETWORK}) ]]; then
        log "!!!!! ATTENTION !!!!!" error
        log "Found volumes" error
        read -p "Do you wish to remove this data? [yes/no=default] " yn
        case $yn in
        [Yy]*)
            docker volume prune -f $(docker volume ls | awk '($2 ~ /${FABKIT_DOCKER_NETWORK}/) {print $2}') 2>/dev/null
            ;;
        *) return 0 ;;
        esac
    fi
}

initialize_network() {
    log "=============" info
    log "Network: init" info
    log "=============" info
    echo

    create_channel $FABKIT_CHANNEL_NAME 1 0
    for org in $(seq 1 ${FABKIT_ORGS}); do
        join_channel $FABKIT_CHANNEL_NAME $org 0
    done
    #TODO: Create txns for all orgs and place below command in above
    update_channel $FABKIT_CHANNEL_NAME $FABKIT_ORG_MSP 1 0

    if [[ "${FABKIT_FABRIC_VERSION}" =~ 2.* ]]; then
        lc_chaincode_package $FABKIT_CHAINCODE_NAME $FABKIT_CHAINCODE_VERSION $FABKIT_CHAINCODE_RELATIVE_PATH 1 0

        for org in $(seq 1 ${FABKIT_ORGS}); do
            lc_chaincode_install $FABKIT_CHAINCODE_NAME $FABKIT_CHAINCODE_VERSION $org 0
            lc_chaincode_approve $FABKIT_CHAINCODE_NAME $FABKIT_CHAINCODE_VERSION $FABKIT_CHANNEL_NAME 1 $org 0
        done

        lc_chaincode_commit $FABKIT_CHAINCODE_NAME $FABKIT_CHAINCODE_VERSION $FABKIT_CHANNEL_NAME 1 1 0
    else
        for org in $(seq 1 ${FABKIT_ORGS}); do
            chaincode_install $FABKIT_CHAINCODE_NAME $FABKIT_CHAINCODE_VERSION $FABKIT_CHAINCODE_RELATIVE_PATH $org 0
        done
        chaincode_instantiate $FABKIT_CHAINCODE_NAME $FABKIT_CHAINCODE_VERSION $FABKIT_CHANNEL_NAME 1 0
    fi
}

__replace_config_capabilities() {
    configtx=${FABKIT_CONFIG_PATH}/configtx
    if [[ "${FABKIT_FABRIC_VERSION}" =~ 2.* ]]; then
        cat ${configtx}.base.yaml | __yq e '.Capabilities.Channel.V2_0 = true |
            .Capabilities.Channel.V1_4_3 = false |
            .Capabilities.Orderer.V2_0 = true |
            .Capabilities.Orderer.V1_4_2 = false |
            .Capabilities.Application.V2_0 = true |
            .Capabilities.Application.V1_4_2 = false' - >${configtx}.yaml
    else
        cat ${configtx}.base.yaml | __yq e '.Capabilities.Channel.V2_0 = false |
            .Capabilities.Channel.V1_4_3 = true |
            .Capabilities.Orderer.V2_0 = false |
            .Capabilities.Orderer.V1_4_2 = true |
            .Capabilities.Application.V2_0 = false |
            .Capabilities.Application.V1_4_2 = true' - >${configtx}.yaml
    fi
}

# generate genesis block
# $1: base path
# $2: config path
# $3: cryptos directory
# $4: network profile name
generate_genesis() {
    if [ -z "$1" ]; then
        log "Base path missing" error
        exit 1
    fi
    if [ -z "$2" ]; then
        log "Config path missing" error
        exit 1
    fi
    if [ -z "$3" ]; then
        log "Crypto material path missing" error
        exit 1
    fi
    if [ -z "$4" ]; then
        log "Network profile name" error
        exit 1
    fi

    local base_path="$1"
    local config_path="$2"
    local channel_dir="${base_path}/channels/orderer-system-channel"
    local cryptos_path="$3"
    local network_profile="$4"

    if [ "${FABKIT_RESET}" == "true" ]; then
        __delete_path ${channel_dir}
    fi

    if [ -d "$channel_dir" ]; then
        log "Channel directory ${channel_dir} already exists" warning
        read -p "Do you wish to re-generate channel config? [yes/no=default] " yn
        case $yn in
        [Yy]*) ;;
        *) return 0 ;;
        esac
        __delete_path $channel_dir
    fi

    log "========================" info
    log "Generating genesis block" info
    log "========================" info
    echo
    log "Base path: $base_path" debug
    log "Config path: $config_path" debug
    log "Cryptos path: $cryptos_path" debug
    log "Network profile: $network_profile" debug

    if [ ! -d "$channel_dir" ]; then
        mkdir -p $channel_dir
    fi

    __replace_config_capabilities

    # generate genesis block for orderer
    docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
        -v ${channel_dir}:/channels/orderer-system-channel \
        -v ${cryptos_path}:/crypto-config \
        -u $(id -u):$(id -g) \
        -e FABRIC_CFG_PATH=/ \
        hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
        bash -c " \
                        configtxgen -profile $network_profile -channelID orderer-system-channel -outputBlock /channels/orderer-system-channel/genesis_block.pb /configtx.yaml;
                        configtxgen -inspectBlock /channels/orderer-system-channel/genesis_block.pb
                    "
    if [ "$?" -ne 0 ]; then
        log "Failed to generate orderer genesis block..." error
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
        log "Channel name missing" error
        exit 1
    fi
    if [ -z "$2" ]; then
        log "Base path missing" error
        exit 1
    fi
    if [ -z "$3" ]; then
        log "Config path missing" error
        exit 1
    fi
    if [ -z "$4" ]; then
        log "Crypto material path missing" error
        exit 1
    fi
    if [ -z "$5" ]; then
        log "Network profile missing" error
        exit 1
    fi
    if [ -z "$6" ]; then
        log "Channel profile missing" error
        exit 1
    fi
    if [ -z "$7" ]; then
        log "MSP missing" error
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
        __delete_path ${channel_dir}
    fi

    if [ -d "$channel_dir" ]; then
        log "Channel directory ${channel_dir} already exists" warning
        read -p "Do you wish to re-generate channel config? [yes/no=default] " yn
        case $yn in
        [Yy]*) ;;
        *) return 0 ;;
        esac
        __delete_path $channel_dir
    fi

    log "=========================" info
    log "Generating channel config" info
    log "=========================" info
    echo
    log "Channel: $channel_name" debug
    log "Base path: $base_path" debug
    log "Config path: $config_path" debug
    log "Cryptos path: $cryptos_path" debug
    log "Channel dir: $channel_dir" debug
    log "Network profile: $network_profile" debug
    log "Channel profile: $channel_profile" debug
    log "Org MSP: $org_msp" debug

    if [ ! -d "$channel_dir" ]; then
        mkdir -p $channel_dir
    fi

    __replace_config_capabilities

    # generate channel configuration transaction
    docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
        -v ${channel_dir}:/channels/${channel_name} \
        -v ${cryptos_path}:/crypto-config \
        -u $(id -u):$(id -g) \
        -e FABRIC_CFG_PATH=/ \
        hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
        bash -c " \
                        configtxgen -profile $channel_profile -outputCreateChannelTx /channels/${channel_name}/${channel_name}_tx.pb -channelID ${channel_name} /configtx.yaml;
                        configtxgen -inspectChannelCreateTx /channels/${channel_name}/${channel_name}_tx.pb
                    "
    if [ "$?" -ne 0 ]; then
        log "Failed to generate channel configuration transaction..." error
        exit 1
    fi

    # generate anchor peer transaction
    docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
        -v ${channel_dir}:/channels/${channel_name} \
        -v ${cryptos_path}:/crypto-config \
        -u $(id -u):$(id -g) \
        -e FABRIC_CFG_PATH=/ \
        hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
        configtxgen -profile $channel_profile -outputAnchorPeersUpdate /channels/${channel_name}/${org_msp}_anchors_tx.pb -channelID ${channel_name} -asOrg $org_msp /configtx.yaml
    if [ "$?" -ne 0 ]; then
        log "Failed to generate anchor peer update for $org_msp..." error
        exit 1
    fi
}

# generate crypto config
# $1: crypto-config.yml file path
# $2: certificates output directory
generate_cryptos() {
    if [ -z "$1" ]; then
        log "Config path missing" error
        exit 1
    fi
    if [ -z "$2" ]; then
        log "Cryptos path missing" error
        exit 1
    fi

    local config_path="$1"
    local cryptos_path="$2"

    log "==================" info
    log "Generating cryptos" info
    log "==================" info
    echo
    log "Config path: $config_path" debug
    log "Cryptos path: $cryptos_path" debug

    if [ "${FABKIT_RESET}" == "true" ]; then
        __delete_path ${cryptos_path}
        __delete_path ${FABKIT_CRYPTOS_USER_PATH}
    fi

    if [ -d "${cryptos_path}" ]; then
        log "crypto-config already exists" warning
        read -p "Do you wish to remove crypto-config and generate new ones? [yes/no=default] " yn
        case $yn in
        [Yy]*) __delete_path ${cryptos_path} ;;
        *) ;;
        esac
    fi

    if [ ! -d "${cryptos_path}" ]; then
        mkdir -p ${cryptos_path}

        # generate crypto material
        docker run --rm -v ${config_path}/crypto-config.yaml:/crypto-config.yaml \
            -v ${cryptos_path}:/crypto-config \
            -u $(id -u):$(id -g) \
            hyperledger/fabric-tools:${FABKIT_FABRIC_VERSION} \
            cryptogen generate --config=/crypto-config.yaml --output=/crypto-config
        if [ "$?" -ne 0 ]; then
            log "Failed to generate crypto material..." error
            exit 1
        fi
    fi

    # copy cryptos into a shared folder available for client applications (sdk)
    if [ -d "${FABKIT_CRYPTOS_USER_PATH}" ]; then
        log "Shared crypto-config directory ${FABKIT_CRYPTOS_USER_PATH} already exists" warning
        read -p "Do you want to overwrite this shared data with your local crypto-config directory? [yes/no=default] " yn
        case $yn in
        [Yy]*)
            __delete_path ${FABKIT_CRYPTOS_USER_PATH}
            ;;
        *) return 0 ;;
        esac
    fi
    mkdir -p ${FABKIT_CRYPTOS_USER_PATH}
    cp -r ${cryptos_path}/** ${FABKIT_CRYPTOS_USER_PATH}
}
