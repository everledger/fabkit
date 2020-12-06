#!/usr/bin/env bash

source $(pwd)/.env

export GO111MODULE=on
export GOPRIVATE=bitbucket.org/everledger/*
# name of the working directory/project
export WORKSPACE=$(basename ${ROOT})

chaincode_remote_path=${CHAINCODE_REMOTE_MOUNT_PATH}

readonly ONE_ORG="OneOrgOrdererGenesis"
readonly TWO_ORGS="TwoOrgsOrdererGenesis"
readonly THREE_ORGS="ThreeOrgsOrdererGenesis"
readonly RAFT_ONE_ORG="OneOrgOrdererEtcdRaft"

# DO NOT REMOVE
# docker exec command
PEER_EXEC=""
# chaincocode language
CHAINCODE_LANGUAGE=""

help() {
    local help="
        Usage: run.sh [command]
        commands:

        help                                                                                            : this help
    
        dep install [chaincode_name]                                                                    : install all go modules as vendor and init go.mod if does not exist yet
        dep update [chaincode_name]                                                                     : update all go modules and rerun install
            
        ca register                                                                                     : register a new user
        ca enroll                                                                                       : enroll a previously registered user    
        ca reenroll                                                                                     : reenroll a user if its certificate expired
        ca revoke                                                                                       : revoke a user's key/certificate providing a reason
            
        network install                                                                                 : install all the dependencies and docker images
        network start                                                                                   : start the blockchain network and initialize it
        network restart                                                                                 : restart a previously running the blockchain network
        network stop                                                                                    : stop the blockchain network and remove all the docker containers
            
        explorer start                                                                                  : run the blockchain explorer user-interface and analytics
        explorer stop                                                                                   : stop the blockchain explorer user-interface and analytics
    
        channel create [channel_name] [org_no] [peer_no]                                                : generate channel configuration file
        channel update [channel_name] [org_msp] [org_no] [peer_no]                                      : update channel with anchor peers
        channel join [channel_name] [org_no] [peer_no]                                                  : run by a peer to join a channel
    
        generate cryptos [config_path] [cryptos_path]                                                   : generate all the crypto keys and certificates for the network
        generate genesis [base_path] [config_path]                                                      : generate the genesis block for the ordering service
        generate channeltx [channel_name] [base_path] [config_path] [cryptos_path]                      : generate channel configuration files
                           [network_profile] [channel_profile] [org_msp]                
    
        chaincode test [chaincode_path]                                                                 : run unit tests
        chaincode build [chaincode_path]                                                                : run build and test against the binary file
        chaincode zip [chaincode_path]                                                                  : create a zip archive ready for deployment containing chaincode and vendors
        chaincode package [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no]      : package, sign and create deployment spec for chaincode 
        chaincode install [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no]      : install chaincode on a peer
        chaincode instantiate [chaincode_name] [chaincode_version] [channel_name] [org_no] [peer_no]    : instantiate chaincode on a peer for an assigned channel
        chaincode upgrade [chaincode_name] [chaincode_version] [channel_name] [org_no] [peer_no]        : upgrade chaincode with a new version
        chaincode query [channel_name] [chaincode_name] [org_no] [peer_no] [data_in_json]               : run query in the format '{\"Args\":[\"queryFunction\",\"key\"]}'
        chaincode invoke [channel_name] [chaincode_name] [org_no] [peer_no] [data_in_json]              : run invoke in the format '{\"Args\":[\"invokeFunction\",\"key\",\"value\"]}'

        chaincode lifecycle package [chaincode_name] [chaincode_version] [chaincode_path]               : package, sign and create deployment spec for chaincode 
                                    [org_no] [peer_no]
        chaincode lifecycle install [chaincode_name] [chaincode_version] [org_no] [peer_no]             : install chaincode on a peer
        chaincode lifecycle approve [chaincode_name] [chaincode_version] [chaincode_path]               : approve chaincode definition
                                    [channel_name] [sequence_no] [org_no] [peer_no]
        chaincode lifecycle commit [chaincode_name] [chaincode_version] [chaincode_path]                : commit and init chaincode on channel
                                   [channel_name] [sequence_no] [org_no] [peer_no]
        chaincode lifecycle upgrade [chaincode_name] [chaincode_version] [chaincode_path]               : run in sequence package, install, approve and commit
                                   [channel_name] [sequence_no] [org_no] [peer_no]

        benchmark load [jobs] [entries]                                                                 : run benchmark bulk loading of [entries] per parallel [jobs] against a running network
       
        utils tojson                                                                                    : transform a string format with escaped characters to a valid JSON format
        utils tostring                                                                                  : transform a valid JSON format to a string with escaped characters
        "
    
    log "$help" info
}

__yq() {
    docker run --rm -i -v "${PWD}":/workdir ${YQ_DOCKER_IMAGE} yq "$@"
}

__jq() {
    docker run --rm -i -v "${PWD}":/workdir ${JQ_DOCKER_IMAGE} "$@"
}

__set_params() {
    while [[ $# -gt 0 ]]; do
        param="${1}"

        case $param in
        -c|--ci)
            CI=true
            shift
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -r|--reset)
            RESET=true
            shift
            ;;
        -o|--orgs)
            ORGS="${2}"
            shift 2
            ;;
        -v|--version)
            FABRIC_VERSION="${2}"
            shift 2
            ;;
        *) 
            log "${1} paramater not recognized. Please run the help." error
            exit 1
            ;;
        esac
    done
}

__log_setup() {
    log "Setup" info
    echo
    log "FABRIC_VERSION=${FABRIC_VERSION}" info
    log "ORGS=${ORGS:-1}" info
    log "CI=${CI:-false}" info
    log "DEBUG=${DEBUG:-false}" info
    log "RESET=${RESET:-false}" info
    echo
}

__check_fabric_version() {
    if [[ ! "${FABRIC_VERSION}" =~ ${1}.* ]]; then
        log "This command is not enabled on Fabric v${FABRIC_VERSION}. In order to run, update the FABRIC_VERSION value in .env file" error
        exit 1
    fi
}

__check_deps() {
    if [ "${1}" == "deploy" ]; then
        type docker >/dev/null 2>&1 || { log >&2 "docker required but it is not installed. Aborting." error; exit 1; }
        type docker-compose >/dev/null 2>&1 || { log >&2 "docker-compose required but it is not installed. Aborting." error; exit 1; }
    elif [ "${1}" == "test" ]; then
        type go >/dev/null 2>&1 || { log >&2 "Go binary is missing in your PATH. Running the dockerised version..." warning; echo $?; }
    fi
}

__check_docker_daemon() {
    if [ "$(docker info --format '{{json .}}' | grep "Cannot connect" 2>/dev/null)" ]; then 
        log "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" error
        exit 1
    fi
}

log() {
    if [[ ${#} != 2 ]]; then
        echo "usage: ${FUNCNAME} <string> [debug|info|warning|error|success]"
        exit 1
    fi

    local message="${1}"
    local level=$(echo ${2} | awk '{print tolower($0)}')
    local default_colour="\033[0m"

    case $level in 
        header ) colour_code="\033[1;35m" ;;
        error ) colour_code="\033[1;31m" ;;
        success ) colour_code="\033[1;32m" ;;
        warning ) colour_code="\033[1;33m" ;;
        info ) colour_code="\033[1;34m" ;;
        debug ) 
            if [ -z "${DEBUG}" ] || [ "${DEBUG}" == "false" ]; then return; fi
            colour_code="\033[1;36m" ;;
        * ) colour_code=${default_colour} ;;
    esac

    # Print out the message and reset
    echo -e "${colour_code}${message}${default_colour}"
}

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
        log "==> FABRIC IMAGE: hyperledger/fabric-$image:${FABRIC_VERSION}" info
        echo
        docker pull hyperledger/fabric-$image:${FABRIC_VERSION} || exit 1
        docker tag hyperledger/fabric-$image:${FABRIC_VERSION} hyperledger/fabric-$image:latest
        echo
    done

    log "==> FABRIC CA IMAGE: hyperledger/fabric-ca:${FABRIC_CA_VERSION}" info
    echo
    docker pull hyperledger/fabric-ca:${FABRIC_CA_VERSION} || exit 1
    docker tag hyperledger/fabric-ca:${FABRIC_CA_VERSION} hyperledger/fabric-ca:latest
    echo

    log "==> COUCHDB IMAGE: hyperledger/fabric-couchdb:${FABRIC_THIRDPARTY_IMAGE_VERSION}" info
    echo
    docker pull hyperledger/fabric-couchdb:${FABRIC_THIRDPARTY_IMAGE_VERSION} || exit 1
    docker tag hyperledger/fabric-couchdb:${FABRIC_THIRDPARTY_IMAGE_VERSION} hyperledger/fabric-couchdb:latest
    echo
}

__docker_third_party_images_pull() {
    log "==> GOLANG IMAGE: ${GOLANG_DOCKER_IMAGE}" info
    echo
    docker pull ${GOLANG_DOCKER_IMAGE}
    echo
    log "==> JQ IMAGE: ${JQ_DOCKER_IMAGE}" info
    echo
    docker pull ${JQ_DOCKER_IMAGE}
    echo
    log "==> YQ IMAGE: ${YQ_DOCKER_IMAGE}" info
    echo
    docker pull ${YQ_DOCKER_IMAGE}
    echo
}

start_network() {
    # Note: this trick may allow the network to work also in strict-security platform
    rm -rf ./docker.sock 2>/dev/null && ln -sf /var/run ./docker.sock

    if [ -z "${CI}" ] || [ "${CI}" == "false" ]; then
        if [ -d "$DATA_PATH" ] && [ "${RESET}" != "true" ]; then
            log "Found data directory: ${DATA_PATH}" warning
            read -p "Do you wish to restart the network and reuse this data? [yes/no=default] " yn
            case $yn in
                [Yy]* ) 
                    restart_network
                    return 0
                    ;;
                * ) ;;
            esac
        fi

        stop_network

        chaincode_build $CHAINCODE_RELATIVE_PATH
        chaincode_test $CHAINCODE_RELATIVE_PATH
    fi

    log "==============" info
    log "Network: start" info
    log "==============" info
    echo

    local start_command="docker-compose -f ${ROOT}/docker-compose.yaml up -d || exit 1;"

    # TODO: create raft profiles for different network topologies (multi-org support)
    if [ "${CONFIGTX_PROFILE_NETWORK}" == "${RAFT_ONE_ORG}" ]; then
        CONFIGTX_PROFILE_NETWORK=${RAFT_ONE_ORG}
        start_command+="docker-compose -f ${ROOT}/docker-compose.etcdraft.yaml up -d || exit 1;"
    elif [ "${ORGS}" == "2" ] || [ "${CONFIGTX_PROFILE_NETWORK}" == "${TWO_ORGS}" ]; then
        CONFIGTX_PROFILE_NETWORK=${TWO_ORGS}
        CONFIGTX_PROFILE_CHANNEL=TwoOrgsChannel
        start_command+="docker-compose -f ${ROOT}/docker-compose.org2.yaml up -d || exit 1;"
    elif [ "${ORGS}" == "3" ] || [ "${CONFIGTX_PROFILE_NETWORK}" == "${THREE_ORGS}" ]; then
        CONFIGTX_PROFILE_NETWORK=${THREE_ORGS}
        CONFIGTX_PROFILE_CHANNEL=ThreeOrgsChannel
        start_command+="docker-compose -f ${ROOT}/docker-compose.org2.yaml up -d || exit 1;"
        start_command+="docker-compose -f ${ROOT}/docker-compose.org3.yaml up -d || exit 1;"
    fi

    generate_cryptos $CONFIG_PATH $CRYPTOS_PATH
    generate_genesis $NETWORK_PATH $CONFIG_PATH $CRYPTOS_PATH $CONFIGTX_PROFILE_NETWORK
    generate_channeltx $CHANNEL_NAME $NETWORK_PATH $CONFIG_PATH $CRYPTOS_PATH $CONFIGTX_PROFILE_NETWORK $CONFIGTX_PROFILE_CHANNEL $ORG_MSP

    docker network create ${DOCKER_NETWORK} 2>/dev/null

    # After Building and testing chaincode, come back to root directory so that docker-compose can take .env file automatically
    cd ${ROOT}

    eval ${start_command}
	
    sleep 5
	
    initialize_network
}

restart_network() {
    log "================" info
	log "Network: restart" info
    log "================" info
    echo

    if [ ! -d "${DATA_PATH}" ]; then
        log "Data directory not found in: ${DATA_PATH}. Run a normal start." error
        exit 1
    fi

    docker network create ${DOCKER_NETWORK} 2>/dev/null
    
    docker-compose -f ${ROOT}/docker-compose.yaml up --force-recreate -d || exit 1
    if [ "$(find ${DATA_PATH} -type d -name 'peer*org2*' -maxdepth 1 2>/dev/null)" ]; then
        docker-compose -f ${ROOT}/docker-compose.org2.yaml up --force-recreate -d || exit 1
    fi
    if [ "$(find ${DATA_PATH} -type d -name 'peer*org3*' -maxdepth 1 2>/dev/null)" ]; then
        docker-compose -f ${ROOT}/docker-compose.org3.yaml up --force-recreate -d || exit 1
    fi

    log "The chaincode container will be instantiated automatically once the peer executes the first invoke or query" warning
}

stop_network() {
    log "=============" info
	log "Network: stop" info
    log "=============" info
    echo

    docker-compose -f ${ROOT}/docker-compose.yaml down || exit 1
    if [ "$(find ${DATA_PATH} -type d -name 'peer*org2*' -maxdepth 1 2>/dev/null)" ]; then
        docker-compose -f ${ROOT}/docker-compose.org2.yaml down || exit 1
    fi
    if [ "$(find ${DATA_PATH} -type d -name 'peer*org3*' -maxdepth 1 2>/dev/null)" ]; then
        docker-compose -f ${ROOT}/docker-compose.org3.yaml down || exit 1
    fi

    if [[ $(docker ps | grep "hyperledger/explorer") ]]; then
        stop_explorer
    fi

    log "Cleaning docker leftovers containers and images" success
    docker rm -f $(docker ps -a | awk '($2 ~ /${DOCKER_NETWORK}|dev-/) {print $1}') 2>/dev/null
    docker rmi -f $(docker images -qf "dangling=true") 2>/dev/null
    docker rmi -f $(docker images | awk '($1 ~ /^<none>|dev-/) {print $3}') 2>/dev/null
    docker system prune -f 2>/dev/null

    if [ "${RESET}" == "true" ]; then
        __delete_path $DATA_PATH
        return 0
    fi

    if [ -d "${DATA_PATH}" ]; then
        log "!!!!! ATTENTION !!!!!" error
        log "Found data directory: ${DATA_PATH}" error
		read -p "Do you wish to remove this data? [yes/no=default] " yn
		case $yn in
			[Yy]* ) __delete_path $DATA_PATH ;;
			* ) return 0
    	esac
    fi
}

# delete path recursively and asks for root permissions if needed
__delete_path() {
    if [ ! -d "${1}" ]; then 
        log "Directory \"${1}\" does not exist. Skipping delete. All good :)" warning
        return
    fi

    if [ -w "${1}" ]; then
        rm -rf ${1}
    else 
        log "!!!!! ATTENTION !!!!!" error
        log "Directory \"${1}\" requires superuser permissions" error
        read -p "Do you wish to continue? [yes/no=default] " yn
        case $yn in
            [Yy]* ) sudo rm -rf ${1} ;;
            * ) return 0
        esac
    fi
}

initialize_network() {
    log "=============" info
	log "Network: init" info
    log "=============" info
    echo

    
	create_channel $CHANNEL_NAME 1 0
    for org in $(seq 1 ${ORGS})
    do 
        join_channel $CHANNEL_NAME $org 0
    done
    #TODO: Create txns for all orgs and place below command in above
    update_channel $CHANNEL_NAME $ORG_MSP 1 0

    if [[ "${FABRIC_VERSION}" =~ 2.* ]]; then
        lc_chaincode_package $CHAINCODE_NAME $CHAINCODE_VERSION $CHAINCODE_RELATIVE_PATH 1 0
        
        for org in $(seq 1 ${ORGS})
        do 
            lc_chaincode_install $CHAINCODE_NAME $CHAINCODE_VERSION $org 0
            lc_chaincode_approve $CHAINCODE_NAME $CHAINCODE_VERSION $CHANNEL_NAME 1 $org 0 
        done
        
        lc_chaincode_commit $CHAINCODE_NAME $CHAINCODE_VERSION $CHANNEL_NAME 1 1 0
    else
        chaincode_install $CHAINCODE_NAME $CHAINCODE_VERSION $CHAINCODE_RELATIVE_PATH 1 0
        chaincode_instantiate $CHAINCODE_NAME $CHAINCODE_VERSION $CHAINCODE_RELATIVE_PATH $CHANNEL_NAME 1 0 
    fi
}

start_explorer() {
    stop_explorer
    
    log "===============" info
	log "Explorer: start" info
    log "===============" info
    echo

    if [[ ! $(docker ps | grep fabric) ]]; then
        log "No Fabric networks running. First launch ./run.sh start" error
		exit 1
    fi

    if [ ! -d "${CRYPTOS_PATH}" ]; then
        log "Cryptos path ${CRYPTOS_PATH} does not exist." error
    fi

    # replacing private key path in connection profile
    config=${EXPLORER_PATH}/connection-profile/first-network
    admin_key_path="peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"
    private_key="/tmp/crypto/${admin_key_path}/$(ls ${CRYPTOS_PATH}/${admin_key_path})"
    cat ${config}.base.json | __jq -r --arg private_key "$private_key" '.organizations.Org1MSP.adminPrivateKey.path = $private_key' | \
    __jq -r --argjson TLS_ENABLED "$TLS_ENABLED" '.client.tlsEnable = $TLS_ENABLED' > ${config}.json

    # considering tls enabled as default in base
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        sed -i'.bak' -e 's/grpcs/grpc/g' -e 's/https/http/g' ${config}.json && rm ${config}.json.bak
    fi

    docker-compose -f ${EXPLORER_PATH}/docker-compose.yaml up --force-recreate -d || exit 1

    log "Blockchain Explorer default user is exploreradmin/exploreradminpw" warning
    log "Grafana default user is admin/admin" warning
}

stop_explorer() {
    log "==============" info
	log "Explorer: stop" info
    log "==============" info
    echo

    docker-compose -f ${EXPLORER_PATH}/docker-compose.yaml down || exit 1
}

dep_install() {
    __check_chaincode $1
    local chaincode_relative_path="${1}"

    log "=====================" info
    log "Dependencies: install" info
    log "=====================" info
    echo

    __init_go_mod install ${chaincode_relative_path}
}

dep_update() {
    __check_chaincode $1
    local chaincode_relative_path="${1}"

    log "====================" info
    log "Dependencies: update" info
    log "====================" info
    echo

    __init_go_mod update ${chaincode_relative_path}
}

__init_go_mod() {
    local chaincode_relative_path="${2}"
    cd ${CHAINCODE_PATH}/${chaincode_relative_path} >/dev/null 2>&1 || { log >&2 "${CHAINCODE_PATH}/${chaincode_relative_path} path does not exist" error; exit 1; }

    if [ ! -f "./go.mod" ]; then
        go mod init
    fi

    __delete_path vendor 2>/dev/null

    if [ "${1}" == "install" ]; then
        go get ./...
    elif [ "${1}" == "update" ]; then
        go get -u=patch ./...
    fi
    
    go mod tidy
    go mod vendor
}

__replace_config_capabilities() {
    configtx=${CONFIG_PATH}/configtx
    if [[ "${FABRIC_VERSION}" =~ 2.* ]]; then
        cat ${configtx}.base.yaml | __yq w - 'Capabilities.Channel.V2_0' true | \
        __yq w - 'Capabilities.Channel.V1_4_3' false | \
        __yq w - 'Capabilities.Orderer.V2_0' true | \
        __yq w - 'Capabilities.Orderer.V1_4_2' false | \
        __yq w - 'Capabilities.Application.V2_0' true | \
        __yq w - 'Capabilities.Application.V1_4_2' false > ${configtx}.yaml
    else
        cat ${configtx}.base.yaml | __yq w - 'Capabilities.Channel.V2_0' false | \
        __yq w - 'Capabilities.Channel.V1_4_3' true | \
        __yq w - 'Capabilities.Orderer.V2_0' false | \
        __yq w - 'Capabilities.Orderer.V1_4_2' true | \
        __yq w - 'Capabilities.Application.V2_0' false | \
        __yq w - 'Capabilities.Application.V1_4_2' true > ${configtx}.yaml
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

    if [ "${RESET}" == "true" ]; then
        __delete_path ${channel_dir}
    fi

    if [ -d "$channel_dir" ]; then
        log "Channel directory ${channel_dir} already exists" warning
		read -p "Do you wish to re-generate channel config? [yes/no=default] " yn
		case $yn in
			[Yy]* ) ;;
			* ) return 0
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
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
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

    if [ "${RESET}" == "true" ]; then
        __delete_path ${channel_dir}
    fi

    if [ -d "$channel_dir" ]; then
        log "Channel directory ${channel_dir} already exists" warning
		read -p "Do you wish to re-generate channel config? [yes/no=default] " yn
		case $yn in
			[Yy]* ) ;;
			* ) return 0
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
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
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
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
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

    if [ "${RESET}" == "true" ]; then
        __delete_path ${cryptos_path}
        __delete_path ${CRYPTOS_SHARED_PATH}
    fi

    if [ -d "${cryptos_path}" ]; then
        log "crypto-config already exists" warning
		read -p "Do you wish to remove crypto-config and generate new ones? [yes/no=default] " yn
		case $yn in
			[Yy]* ) __delete_path ${cryptos_path} ;;
			* ) ;;
    	esac
    fi

    if [ ! -d "${cryptos_path}" ]; then
        mkdir -p ${cryptos_path}

        # generate crypto material
        docker run --rm -v ${config_path}/crypto-config.yaml:/crypto-config.yaml \
                        -v ${cryptos_path}:/crypto-config \
                        -u $(id -u):$(id -g) \
                        hyperledger/fabric-tools:${FABRIC_VERSION} \
                        cryptogen generate --config=/crypto-config.yaml --output=/crypto-config
        if [ "$?" -ne 0 ]; then
            log "Failed to generate crypto material..." error
            exit 1
        fi
    fi
    
    # copy cryptos into a shared folder available for client applications (sdk)
    if [ -d "${CRYPTOS_SHARED_PATH}" ]; then
        log "Shared crypto-config directory ${CRYPTOS_SHARED_PATH} already exists" warning
		read -p "Do you want to overwrite this shared data with your local crypto-config directory? [yes/no=default] " yn
		case $yn in
			[Yy]* ) 
                __delete_path ${CRYPTOS_SHARED_PATH}
            ;;
			* ) return 0
    	esac
    fi
    mkdir -p ${CRYPTOS_SHARED_PATH}
    cp -r ${cryptos_path}/** ${CRYPTOS_SHARED_PATH}
}

set_certs ()  {
    CORE_PEER_ADDRESS=peer${2}.org${1}.example.com:$((6 + ${1}))051
    CORE_PEER_LOCALMSPID=Org${1}MSP
    CORE_PEER_TLS_ENABLED=false
    CORE_PEER_TLS_CERT_FILE=${CONTAINER_PEER_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/peers/peer${2}.org${1}.example.com/tls/server.crt
    CORE_PEER_TLS_KEY_FILE=${CONTAINER_PEER_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/peers/peer${2}.org${1}.example.com/tls/server.key
    CORE_PEER_TLS_ROOTCERT_FILE=${CONTAINER_PEER_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/peers/peer${2}.org${1}.example.com/tls/ca.crt
    CORE_PEER_MSPCONFIGPATH=${CONTAINER_PEER_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/users/Admin@org${1}.example.com/msp
    ORDERER_CA=${CONTAINER_PEER_BASEPATH}/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

    log "===========================================" info
    log "Peer address: ${CORE_PEER_ADDRESS}" info
    log "Peer cert: ${CORE_PEER_TLS_CERT_FILE}" info
    log "===========================================" info
    echo
}

set_peer_exec() {
    PEER_EXEC="docker exec -e CORE_PEER_ADDRESS=$CORE_PEER_ADDRESS \
            -e CORE_PEER_LOCALMSPID=$CORE_PEER_LOCALMSPID \
            -e CORE_PEER_TLS_ENABLED=$TLS_ENABLED \
            -e CORE_PEER_TLS_CERT_FILE=$CORE_PEER_TLS_CERT_FILE \
            -e CORE_PEER_TLS_KEY_FILE=$CORE_PEER_TLS_KEY_FILE \
            -e CORE_PEER_TLS_ROOTCERT_FILE=$CORE_PEER_TLS_ROOTCERT_FILE \
            -e CORE_PEER_MSPCONFIGPATH=$CORE_PEER_MSPCONFIGPATH \
            $CHAINCODE_UTIL_CONTAINER "
}

__exec_command() {
    echo
    log "Excecuting command: " debug
    echo
    message=${1%"|| exit 1"}
    log "$message" debug
    echo

    eval ${1}
}

create_channel() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "===============" info
    log "Channel: create" info
    log "===============" info
    echo

	local channel_name="$1"
    local org="$2"
    local peer="$3"

    set_certs $org $peer
    set_peer_exec

	log "Creating channel ${channel_name} using configuration file ${CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}_tx.pb" info
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer channel create -o $ORDERER_ADDRESS -c ${channel_name} -f $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}_tx.pb --outputBlock $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block || exit 1"
    else
        PEER_EXEC+="peer channel create -o $ORDERER_ADDRESS -c ${channel_name} -f $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}_tx.pb --outputBlock $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi
         
    __exec_command "${PEER_EXEC}"
}

join_channel() {
 	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "=============" info
    log "Channel: join" info
    log "=============" info
    echo

	local channel_name="$1"
    local org="$2"
    local peer="$3"

    set_certs $org $peer
    set_peer_exec

	log "Joining channel ${channel_name}" info
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer channel join -b ${CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}.block || exit 1"
    else
        PEER_EXEC+="peer channel join -b ${CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}.block --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi

    __exec_command "${PEER_EXEC}"
}

update_channel() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "===============" info
    log "Channel: update" info
    log "===============" info
    echo

	local channel_name="$1"
    local org_msp="$2"
    local org="$3"
    local peer="$4"

    set_certs $org $peer
    set_peer_exec

	log "Updating anchors peers on ${channel_name} using configuration file ${CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors.tx" info
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer channel update -o $ORDERER_ADDRESS -c ${channel_name} -f ${CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors_tx.pb || exit 1"
    else
        PEER_EXEC+="peer channel update -o $ORDERER_ADDRESS -c ${channel_name} -f ${CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors_tx.pb --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi

    __exec_command "${PEER_EXEC}"
}

chaincode_test() {
    local chaincode_relative_path="${1}"
    __check_chaincode ${chaincode_relative_path}
    __get_chaincode_language ${chaincode_relative_path}

    log "===============" info
	log "Chaincode: test" info
    log "===============" info
    echo

    if [ ${CHAINCODE_LANGUAGE} == "golang" ]; then
         # avoid "found no test suites" ginkgo error
        if [ ! `find ${CHAINCODE_PATH}/${chaincode_relative_path} -type f -name "*_test*" ! -path "**/node_modules/*" ! -path "**/vendor/*"` ]; then
            log "No test suites found. Skipping tests..." warning
            return 
        fi

        __check_test_deps
        __init_go_mod install ${chaincode_relative_path}

        if [[ $(__check_deps test) ]]; then
            (docker run --rm -v ${CHAINCODE_PATH}:/usr/src/myapp -w /usr/src/myapp/${chaincode_relative_path} -e CGO_ENABLED=0 -e CORE_CHAINCODE_LOGGING_LEVEL=debug ${GOLANG_DOCKER_IMAGE} sh -c "ginkgo -r -v") || exit 1
        else
            (cd ${CHAINCODE_PATH}/${chaincode_relative_path} && CORE_CHAINCODE_LOGGING_LEVEL=debug CGO_ENABLED=0 ginkgo -r -v) || exit 1
        fi
    fi

    log "Test passed!" success
}

__check_test_deps() {
    type ginkgo >/dev/null 2>&1 || { 
        log >&2 "Ginkgo module missing. Going to install..." warning
        GO111MODULE=off go get -u github.com/onsi/ginkgo/ginkgo
        GO111MODULE=off go get -u github.com/onsi/gomega/...
    }
}

chaincode_build() {
    local chaincode_relative_path="${1}"
    __check_chaincode ${chaincode_relative_path}

    log "================" info
	log "Chaincode: build" info
    log "================" info
    echo

    __get_chaincode_language ${chaincode_relative_path}

    if [ ${CHAINCODE_LANGUAGE} == "golang" ]; then
        __init_go_mod install ${chaincode_relative_path}
        
        if [[ $(__check_deps test) ]]; then
        (docker run --rm -v ${CHAINCODE_PATH}:/usr/src/myapp -w /usr/src/myapp/${chaincode_relative_path} -e CGO_ENABLED=0 ${GOLANG_DOCKER_IMAGE} sh -c "go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_relative_path} 2>/dev/null") || exit 1
        else
            (cd ${CHAINCODE_PATH}/${chaincode_relative_path} && CGO_ENABLED=0 go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_relative_path} 2>/dev/null) || exit 1
        fi
    fi

    log "Build passed!" success
}

__check_chaincode() {
    if [ -z "$1" ]; then
		log "Chaincode name missing" error
		exit 1
	fi
}

__get_chaincode_language() {
    if [ -z "$1" ]; then
		log "Missing chaincode relative path in argument" error
		exit 1
	fi

    if [ -z "$CHAINCODE_PATH" ]; then
        log "CHAINCODE_PATH not set" error
        exit 1
    fi

    local chaincode_relative_path="$1"
    local golang_cc_identifier="func main"
    local java_cc_identifier="public static void main"
     local node_cc_identifier="require('fabric-shim')"

    # check golang
    if [ ! "$( grep --include='*.go' -rnw "${CHAINCODE_PATH}/${chaincode_relative_path}" -e "${golang_cc_identifier}" )" == "" ]; then
        log "Chaincode language is golang" debug
        CHAINCODE_LANGUAGE="golang"
        return
    fi

    # check java
    if [ ! "$( grep --include='*.java' -rnw "${CHAINCODE_PATH}/${chaincode_relative_path}" -e "${java_cc_identifier}" )" == "" ]; then
        log "Chaincode language is java" debug
        CHAINCODE_LANGUAGE="java"
        return
    fi

     # check node 
    if [ ! "$( grep --include='*.js' -rnw "${CHAINCODE_PATH}/${chaincode_relative_path}" -e "${node_cc_identifier}" )" == "" ]; then
        log "Chaincode language is node" debug
        CHAINCODE_LANGUAGE="node"
        return
    fi

    if [ -z "$CHAINCODE_LANGUAGE" ]; then
        log "Error cannot determine chaincode language" error 
        exit 1
    fi
}

__set_chaincode_remote_path() {
    if [ ${CHAINCODE_LANGUAGE} == "golang" ]; then
        case $CHAINCODE_REMOTE_MOUNT_PATH/ in
            /opt/gopath/src/*) 
                log "Chaincode mounted in gopath" debug
                chaincode_remote_path=${CHAINCODE_REMOTE_MOUNT_PATH#/opt/gopath/src/}
                return
                ;;
            *) 
                log "chaincode not mounted in gopath" error
                exit 1
                ;;
        esac
    fi
}

chaincode_install() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] ||  [ -z "$5" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "==================" info
    log "Chaincode: install" info
    log "==================" info
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
	local chaincode_relative_path="$3"
    local org="$4"
    local peer="$5"
    shift 5

    set_certs $org $peer
    set_peer_exec

    __get_chaincode_language ${chaincode_relative_path}
    __set_chaincode_remote_path
    local install_path=""

    if [ ${CHAINCODE_LANGUAGE} == "golang" ]; then
        __init_go_mod install ${chaincode_relative_path}
        # Golang: workaround for chaincode written as modules
        # make the install to work when main files are not in the main directory but in cmd
        if [ ! "$(find ${install_path} -type f -name '*.go' -maxdepth 1 2>/dev/null)" ] && [ -d "${CHAINCODE_PATH}/${chaincode_relative_path}/cmd" ]; then
            install_path+="/cmd"
        fi
    else
        install_path="${CHAINCODE_REMOTE_MOUNT_PATH}/${chaincode_relative_path}"
    fi

    log "Installing chaincode $chaincode_name version $chaincode_version from path ${install_path}" info

    # fabric-samples does not use tls for installing (and it won't work with), however this flag is listed in the install command on the official fabric documentation 
    # https://hyperledger-fabric.readthedocs.io/en/release-1.4/commands/peerchaincode.html#peer-chaincode-install
    PEER_EXEC+="peer chaincode install -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p ${install_path} -l ${CHAINCODE_LANGUAGE} || exit 1"

    __exec_command "${PEER_EXEC}"
}

chaincode_instantiate() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "======================" info
    log "Chaincode: instantiate" info
    log "======================" info
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
    local chaincode_relative_path="$3"
	local channel_name="$4"
    local org="$5"
    local peer="$6"
    shift 6
    local options="$@"
       
    set_certs $org $peer
    set_peer_exec
    __get_chaincode_language $chaincode_relative_path

    log "Instantiating chaincode $chaincode_name version $chaincode_version on channel: ${channel_name}" info

    if [[ ! "${options}" == *"-c"* ]]; then
        if [ -z "${CHAINCODE_ARGS}" ]; then
            options+=" -c '{\"Args\":[]}'"
        else
            options+=" -c '${CHAINCODE_ARGS}'"
        fi
    fi
   
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer chaincode instantiate -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -C ${channel_name} ${options} -l $CHAINCODE_LANGUAGE || exit 1"
    else
        PEER_EXEC+="peer chaincode instantiate -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -C ${channel_name} ${options} -l $CHAINCODE_LANGUAGE --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi

    __exec_command "${PEER_EXEC}"
}

# TODO: to fix after upgrade to v2.0 (package id)
chaincode_upgrade() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "==================" info
    log "Chaincode: upgrade" info
    log "==================" info
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
    local chaincode_relative_path="$3"
	local channel_name="$4"
    local org="$5"
    local peer="$6"
    shift 6
    local options="$@"

    set_certs $org $peer
    set_peer_exec
    __get_chaincode_language $chaincode_relative_path

    log "Upgrading chaincode $chaincode_name to version $chaincode_version on channel: ${channel_name}" info

   if [[ ! "${options}" == *"-c"* ]]; then
        if [ -z "${CHAINCODE_ARGS}" ]; then
            options+=" -c '{\"Args\":[]}'"
        else
            options+=" -c '${CHAINCODE_ARGS}'"
        fi
    fi

    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C ${channel_name} ${options} || exit 1"
    else
        PEER_EXEC+="peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C ${channel_name} ${options} --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi

    __exec_command "${PEER_EXEC}"
}

chaincode_zip() {
    type zip >/dev/null 2>&1 || { log >&2 "zip required but it is not installed. Aborting." error; exit 1; }
    type rsync >/dev/null 2>&1 || { log >&2 "rsync required but it is not installed. Aborting." error; exit 1; }
   
    log "==============" info
    log "Chaincode: zip" info
    log "==============" info
    echo

    local chaincode_relative_path="${1}"
    __check_chaincode ${chaincode_relative_path}

    __get_chaincode_language ${chaincode_relative_path}
    __set_chaincode_remote_path

    if [ ! -d "${DIST_PATH}" ]; then
        mkdir -p ${DIST_PATH}
    fi

    local timestamp=$(date +%Y-%m-%d-%H-%M-%S)

    if [ "$CHAINCODE_LANGUAGE" == "golang" ]; then
        __init_go_mod install ${chaincode_relative_path}

        # trick to allow chaincode packed as modules to work when deployed against remote environments
        log "Copying chaincode files into vendor..." info
        mkdir -p ./vendor/${chaincode_remote_path}/${chaincode_name} && rsync -ar --exclude='vendor' --exclude='META-INF' . ./vendor/${chaincode_remote_path}/${chaincode_name} || { log >&2 "Error copying chaincode into vendor directory." error; exit 1; }
    fi
    
    zip -rq ${DIST_PATH}/$(basename $chaincode_relative_path)_${timestamp}.zip . || { log >&2 "Error creating chaincode archive." error; exit 1; }

    log "Chaincode archive created in: ${DIST_PATH}/$(basename $chaincode_relative_path).${timestamp}.zip" success
}

chaincode_pack() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] ||  [ -z "$5" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    type rsync >/dev/null 2>&1 || { log >&2 "rsync required but it is not installed. Aborting." error; exit 1; }

    log "==================" info
    log "Chaincode: package" info
    log "==================" info
    echo

    local chaincode_name="$1"
	local chaincode_version="$2"
 	local chaincode_relative_path="$3"
    local org="$4"
    local peer="$5"
    shift 5

    set_certs $org $peer
    set_peer_exec

    __get_chaincode_language ${chaincode_relative_path}
    __set_chaincode_remote_path
    local install_path="${chaincode_remote_path}/${chaincode_relative_path}"

    local timestamp=$(date +%Y-%m-%d-%H-%M-%S)

    if [ "$CHAINCODE_LANGUAGE" == "golang" ]; then
        __init_go_mod install ${chaincode_relative_path}

        # trick to allow chaincode packed as modules to work when deployed against remote environments
        log "Copying chaincode files into vendor..." info
        mkdir -p ./vendor/${install_path} && rsync -ar --exclude='vendor' --exclude='META-INF' . ./vendor/${chaincode_remote_path}/${chaincode_name} || { log >&2 "Error copying chaincode into vendor directory." error; exit 1; }
    fi

    log "Packing chaincode $chaincode_name version $chaincode_version from path ${install_path}" info
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer chaincode package dist/${chaincode_name}_${chaincode_version}_${timestamp}.cc -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p ${install_path} -l ${CHAINCODE_LANGUAGE} --cc-package --sign || exit 1"
    else
        PEER_EXEC+="peer chaincode package dist/${chaincode_name}_${chaincode_version}_${timestamp}.cc -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p ${install_path} -l ${CHAINCODE_LANGUAGE} --cc-package --sign --tls --cafile $ORDERER_CA || exit 1"
    fi

    echo $PEER_EXEC

    __exec_command "${PEER_EXEC}"

    log "Chaincode package created in: ${DIST_PATH}/${chaincode_name}_${chaincode_version}_${timestamp}.cc" success
}

invoke() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "==================" info
    log "Chaincode: invoke" info
    log "==================" info
    echo

	local channel_name="$1"
	local chaincode_name="$2"
    local org="$3"
    local peer="$4"
    local request="$5"
    shift 5

    set_certs $org $peer
    set_peer_exec

    log "Invoking chaincode $chaincode_name on channel ${channel_name} as org${org} and peer${peer} with the following params $request" info
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer chaincode invoke -o $ORDERER_ADDRESS -C ${channel_name} -n $chaincode_name -c '$request' '$@' || exit 1"
    else
        PEER_EXEC+="peer chaincode invoke -o $ORDERER_ADDRESS -C ${channel_name} -n $chaincode_name -c '$request' '$@' --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi

    __exec_command "${PEER_EXEC}"
}

query() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "==================" info
    log "Chaincode: query" info
    log "==================" info
    echo

	local channel_name="$1"
	local chaincode_name="$2"
    local org="$3"
    local peer="$4"
    local request="$5"
    shift 5

    set_certs $org $peer
    set_peer_exec

    log "Querying chaincode $chaincode_name on channel ${channel_name} as org${org} and peer${peer} with the following params $request $@" info
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer chaincode query -o $ORDERER_ADDRESS -C ${channel_name} -n $chaincode_name -c '$request' '$@' || exit 1"
    else
        PEER_EXEC+="peer chaincode query -o $ORDERER_ADDRESS -C ${channel_name} -n $chaincode_name -c '$request' '$@' --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi

    __exec_command "${PEER_EXEC}"
}

lc_query_package_id(){
    local chaincode_name="$1"
	local chaincode_version="$2"
    local org="$3"
    local peer="$4"
    shift 4

    set_certs $org $peer
    set_peer_exec

    local chaincode_label="\"${chaincode_name}_${chaincode_version}\""

    log "Chaincode label: $chaincode_label" debug
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer lifecycle chaincode queryinstalled --output json | jq -r '.installed_chaincodes[] | select(.label == ${chaincode_label} ) ' | jq -r '.package_id' || exit 1"
    else
        PEER_EXEC+="peer lifecycle chaincode queryinstalled --tls $TLS_ENABLED --cafile $ORDERER_CA --output json | jq -r '.installed_chaincodes[] | select(.label == ${chaincode_label} ) ' | jq -r '.package_id' || exit 1"
    fi

    export PACKAGE_ID=$(eval ${PEER_EXEC})

    log "Package ID: $PACKAGE_ID" info
}

lc_chaincode_package() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] ||  [ -z "$5" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "============================" info
    log "Chaincode Lifecycle: package" info
    log "============================" info
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
	local chaincode_relative_path="$3"
    local org="$4"
    local peer="$5"
    shift 5

    set_certs $org $peer
    set_peer_exec

    __get_chaincode_language ${chaincode_relative_path}
    __set_chaincode_remote_path
    local install_path="${chaincode_remote_path}/${chaincode_relative_path}"

    if [ ${CHAINCODE_LANGUAGE} == "golang" ]; then
        __init_go_mod install ${chaincode_relative_path}
        # Golang: workaround for chaincode written as modules
        # make the install to work when main files are not in the main directory but in cmd
        if [ ! "$(find ${install_path} -type f -name '*.go' -maxdepth 1 2>/dev/null)" ] && [ -d "${CHAINCODE_PATH}/${chaincode_relative_path}/cmd" ]; then
            install_path+="/cmd"
        fi
    else
        install_path="${CHAINCODE_REMOTE_MOUNT_PATH}/${chaincode_relative_path}"
    fi

    log "Packaging chaincode $chaincode_name version $chaincode_version from path $chaincode_path" info
    # TODO: explore issue which runs into deps error every so often
    PEER_EXEC+="peer lifecycle chaincode package ${chaincode_name}_${chaincode_version}.tar.gz --path ${install_path} --label ${chaincode_name}_${chaincode_version} --lang ${CHAINCODE_LANGUAGE} || exit 1"

    __exec_command "${PEER_EXEC}"
}

lc_chaincode_install() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "============================" info
    log "Chaincode Lifecycle: install" info
    log "============================" info
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
    local org="$3"
    local peer="$4"
    shift 4

    set_certs $org $peer

    log "Installing chaincode $chaincode_name version $chaincode_version" info
    
    set_peer_exec
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer lifecycle chaincode install ${chaincode_name}_${chaincode_version}.tar.gz || exit 1"
    else
        PEER_EXEC+="peer lifecycle chaincode install ${chaincode_name}_${chaincode_version}.tar.gz --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi

    __exec_command "${PEER_EXEC}"
}

lc_chaincode_approve() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "============================" info
    log "Chaincode Lifecycle: approve" info
    log "============================" info
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
    local channel_name="$3"
    local sequence_no="$4"
    local org="$5"
    local peer="$6"
    shift 6

    set_certs $org $peer

    log "Querying chaincode package ID" info
    lc_query_package_id $chaincode_name $chaincode_version $org $peer
    if [ -z "$PACKAGE_ID" ]; then
        log "Package ID is not defined" warning
        return 
    fi
    
    log "Approve chaincode for my organization" info
    # TODO: policy to be passed as input argument
    set_peer_exec
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer lifecycle chaincode approveformyorg --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --package-id $PACKAGE_ID --sequence $sequence_no --waitForEvent --signature-policy \"OR('Org1MSP.member','Org2MSP.member','Org3MSP.member')\" || exit 1"
    else
        PEER_EXEC+="peer lifecycle chaincode approveformyorg --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --package-id $PACKAGE_ID --sequence $sequence_no --waitForEvent --signature-policy \"OR('Org1MSP.member','Org2MSP.member','Org3MSP.member')\" --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi

    __exec_command "${PEER_EXEC}"
}

lc_chaincode_commit() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "===========================" info
    log "Chaincode Lifecycle: commit" info
    log "===========================" info
    echo
    
    local chaincode_name="$1"
	local chaincode_version="$2"
	local channel_name="$3"
    local sequence_no="$4"
    local org="$5"
    local peer="$6"
    shift 6

    if [ -z "$PACKAGE_ID" ]; then
		log "Package ID is not defined" warning

		log "Querying chaincode package ID" info
        lc_query_package_id $chaincode_name $chaincode_version $org $peer

        if [ -z "$PACKAGE_ID" ]; then
            log "Chaincode not installed on peer" error
        fi
	fi

    set_certs $org $peer

    log "Check whether the chaincode definition is ready to be committed" info
    set_peer_exec
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer lifecycle chaincode checkcommitreadiness --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --sequence $sequence_no --output json --signature-policy \"OR('Org1MSP.member','Org2MSP.member','Org3MSP.member')\" || exit 1"
    else
        PEER_EXEC+="peer lifecycle chaincode checkcommitreadiness --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --sequence $sequence_no --output json --signature-policy \"OR('Org1MSP.member','Org2MSP.member','Org3MSP.member')\" --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi
    __exec_command "${PEER_EXEC}"

    log "Commit the chaincode definition to channel" info
    set_peer_exec
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer lifecycle chaincode commit --channelID $channel_name --name $chaincode_name --version $chaincode_version --sequence $sequence_no --init-required --peerAddresses $CORE_PEER_ADDRESS --signature-policy \"OR('Org1MSP.member','Org2MSP.member','Org3MSP.member')\" || exit 1"
    else
        PEER_EXEC+="peer lifecycle chaincode commit --channelID $channel_name --name $chaincode_name --version $chaincode_version --sequence $sequence_no --init-required  --signature-policy \"OR('Org1MSP.member','Org2MSP.member','Org3MSP.member')\" --tls $TLS_ENABLED --cafile $ORDERER_CA "
        cmd=${PEER_EXEC}
        for o in $(seq 1 ${ORGS})
        do 
            #TODO: Create from endorsement policy and make endorsement policy dynamic
            lc_query_package_id $chaincode_name $chaincode_version $o $peer
            if [ ! -z "$PACKAGE_ID" ]; then
                set_certs $o $peer
                cmd+="--peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE "
            fi
        done
        cmd+="|| exit 1"
    fi
    __exec_command "${cmd}"

    log "Query the chaincode definitions that have been committed to the channel" info
    set_certs $org $peer
    set_peer_exec
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer lifecycle chaincode querycommitted --channelID $channel_name --name $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --output json || exit 1"
    else
        PEER_EXEC+="peer lifecycle chaincode querycommitted --channelID $channel_name --name $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --output json --tls $TLS_ENABLED --cafile $ORDERER_CA --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE || exit 1"
    fi
    __exec_command "${PEER_EXEC}"

    log "Init the chaincode" info
    set_peer_exec
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer chaincode invoke -o $ORDERER_ADDRESS --isInit --channelID $channel_name --name $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --waitForEvent -c '{\"Args\":[]}' || exit 1"
    else
        PEER_EXEC+="peer chaincode invoke -o $ORDERER_ADDRESS --isInit --channelID $channel_name --name $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE --tls $TLS_ENABLED --cafile $ORDERER_CA -c '{\"Args\":[]}' --waitForEvent || exit 1"
    fi
    __exec_command "${PEER_EXEC}"
}

lc_chaincode_upgrade() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ] || [ -z "$7" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    lc_chaincode_package $1 $2 $3 $6 $7
    lc_chaincode_install $1 $2 $6 $7
    lc_chaincode_approve $1 $2 $4 $5 $6 $7
    lc_chaincode_commit $1 $2 $4 $5 $6 $7
}

register_user() {
    log "=================" info
    log "CA User: register" info
    log "=================" info
    echo

    __ca_setup register

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${FABRIC_CA_VERSION} \
        sh -c " \
        fabric-ca-client register -d \
            --home /crypto-config \
            --mspdir ${org}/users/${admin} \
            --url ${ca_protocol}${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --id.name $username \
            --id.secret '$password'  \
            --id.affiliation $user_affiliation \
            --id.attrs $user_attributes \
            --id.type $user_type
         "

    log "!! IMPORTANT: Note down these lines containing the information of the registered user" success
}

enroll_user() {
    log "===============" info
    log "CA User: enroll" info
    log "===============" info
    echo

    __ca_setup enroll

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${FABRIC_CA_VERSION} \
        sh -c " \
        fabric-ca-client enroll -d \
            --home /crypto-config \
            --mspdir ${org}/users/${username} \
            --url ${ca_protocol}${username}:'${password}'@${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --enrollment.attrs $user_attributes
        "

    # IMPORTANT: the CA requires this folder in case of the user is an admin
    cp -r ${CRYPTOS_PATH}/${org}/users/${username}/signcerts ${CRYPTOS_PATH}/${org}/users/${username}/admincerts
}

reenroll_user() {
    log "=================" info
    log "CA User: reenroll" info
    log "=================" info
    echo

    __ca_setup enroll

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${FABRIC_CA_VERSION} \
        sh -c " \
        fabric-ca-client reenroll -d \
            --home /crypto-config \
            --mspdir ${org}/users/${username} \
            --url ${ca_protocol}${username}:'${password}'@${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --enrollment.attrs $user_attributes
        "

    # IMPORTANT: the CA requires this folder in case of the user is an admin
    cp -r ${CRYPTOS_PATH}/${org}/users/${username}/signcerts ${CRYPTOS_PATH}/${org}/users/${username}/admincerts
}

revoke_user() {
    log "===============" info
    log "CA User: revoke" info
    log "===============" info
    echo

    __ca_setup revoke

    # reason for the revoke
    reason_list=" 
    1: unspecified
    2: keycompromise
    3: cacompromise
    4: affiliationchange
    5: superseded
    6: cessationofoperation
    7: certificatehold
    8: removefromcrl
    9: privilegewithdrawn
    10: aacompromise"

    while [ -z "$reason" ]; do
        log "Select one of the reason for the revoke from this list: " info
        log "${reason_list}" info
        read -p "Select a number from the list above: [1] " reason
        case $reason in 
            1) reason="unspecified" ;;
            2) reason="keycompromise" ;;
            3) reason="cacompromise" ;;
            4) reason="affiliationchange" ;;
            5) reason="superseded" ;;
            6) reason="cessationofoperation" ;;
            7) reason="certificatehold" ;;
            8) reason="removefromcrl" ;;
            9) reason="privilegewithdrawn" ;;
            10) reason="aacompromise" ;;
            *) log "Please select any of the reason from the list by typying in the corresponding number" warning;;
        esac
    done
    log ${reason} success
    echo

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${FABRIC_CA_VERSION} \
        sh -c " \
        fabric-ca-client revoke -d \
            --home /crypto-config \
            --mspdir ${org}/users/${admin} \
            --url ${ca_protocol}${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --revoke.name $username \
            --revoke.reason $reason
        "
}

__ca_setup() {
    log "Creating docker network..." info
    docker network create ${DOCKER_NETWORK} 2>/dev/null 

    log "Insert the organization name of the user to register/enroll" info
    while [ -z "$org" ]; do
        read -p "Organization: [] " org
    done
    export org
    log $org success
    echo

    users_dir="${CRYPTOS_PATH}/${org}/users"

    # workaround to avoid emtpy or existing directories
    admin_msp="a/s/d/f/g"
    if [ "$1" == "register" ]; then
        # set admin msp path
        while [ ! -d "${admin_msp}" ]; do
            log "Set the root Admin MSP path containing admincert, signcert, etc. directories" info
            log "You can drag&drop in the terminal the top admin directory - e.g. if the certs are in ./admin/msp, simply drag in the ./admin folder " info
            admin_path_default=$(find $NETWORK_PATH -path "*/peerOrganizations/*/Admin*org1*" | head -n 1)
            read -p "Admin name/path: [${admin_path_default}] " admin_path
            admin_path=${admin_path:-${admin_path_default}}
            log "admin path: $admin_path" success
            export admin=$(basename ${admin_path})
            log "admin: $admin" success
            admin_msp=$(dirname $(find ${admin_path} -type d -name signcert* 2>/dev/null) 2>/dev/null)
            log "admin msp: $admin_msp" success

            if [ ! -d "${admin_msp}" ]; then
                log "Admin MSP signcerts directory not found in: ${admin_path}. Please be sure the selected Admin MSP directory exists." warning
            fi
        done

        # avoid to copy the admin directory if it is already in place
        if [ "${users_dir}/${admin}" != "${admin_msp}" ]; then
            # copy the Admin msp to the main cryptos directory
            mkdir -p ${users_dir}/${admin} && cp -r $admin_msp/** ${users_dir}/${admin}
            # TODO: check whether this renaming is still necessary
            # mv ${users_dir}/${admin}/signcert*/* ${users_dir}/${admin}/signcert*/cert.pem
            cp -r ${users_dir}/${admin}/signcert*/ ${users_dir}/${admin}/admincerts/
        else
            log "Admin MSP directory is already in place under ${users_dir}/${admin}. Be sure the certificate are up to date or remove that directory and restart this process." warning
        fi
    fi

    log "Insert the correct Hyperledger Fabric CA version to use (read Troubleshooting section)" info
    log "This should be the same used by your CA server (i.e. at the time of writing, IBPv1 is using 1.1.0)" info
    read -p "CA Version: [${FABRIC_VERSION}] " fabric_version
    export fabric_version=${fabric_version:-${FABRIC_VERSION}}
    log $fabric_version success
    echo

    log "Insert the username of the user to register/enroll" info
    username_default="user_"$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 5; echo)
    read -p "Username: [${username_default}] " username
    export username=${username:-${username_default}}
    mkdir -p ${users_dir}/${username}
    log $username success
    echo

    log "Insert password of the user. It will be used by the CA as secret to generate the user certificate and key" info
    password_default=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20; echo)
    read -p "Password: [${password_default}] " password
    export password=${password:-${password_default}}
    log $password success
    log "!! IMPORTANT: Take note of this password before continuing. If you loose this password you will not be able to manage the credentials of this user any longer." warning
    echo

    log "CA secure connection (https)" info
    read -p "Using TLS secure connection? (if your CA address starts with https)? [yes/no=default] " yn
    case $yn in
        [Yy]* ) 
            export ca_protocol="https://"
            log "Secure TLS connection: enabled" success
            ;;
        * ) 
            export ca_protocol="http://" 
            log "Secure TLS connection: disabled" success
            ;;
    esac
    echo

    log "Set CA TLS certificate path" info
    ca_cert_default=$(find $NETWORK_PATH -name "tlsca*.pem" | head -n 1)
    read -p "CA cert: [${ca_cert_default}] " ca_cert
    ca_cert=${ca_cert:-${ca_cert_default}}
    log $ca_cert success
    # copy the CA certificate to the main cryptos directory
    mkdir -p ${CRYPTOS_PATH}/${org}
    cp $ca_cert ${CRYPTOS_PATH}/${org}/cert.pem
    export ca_cert=$(basename ${CRYPTOS_PATH}/${org}/cert.pem)
    echo

    log "Insert CA hostname and port only (e.g. ca.example.com:7054)" info
    ca_url_default="ca.example.com:7054"
    read -p "CA hostname and port: [${ca_url_default}] " ca_url
    export ca_url=${ca_url:-${ca_url_default}}
    log ${ca_url} success
    echo

    if [ "$1" == "register" ] || [ "$1" == "enroll" ]; then
        log "Insert user attributes (e.g. admin=false:ecert)" info
        log "Wiki: https://hyperledger-fabric-ca.readthedocs.io/en/latest/users-guide.html#registering-a-new-identity" info
        echo
        log "A few examples:" info
        log "If enrolling an admin: 'hf.Registrar.Roles,hf.Registrar.Attributes,hf.AffiliationMgr'" warning
        log "If registering a user: 'admin=false:ecert,email=provapi@everledger.io:ecert,application=provapi'" warning
        log "If enrolling a user: 'admin:opt,email:opt,application:opt'" warning
        read -p "User attributes: [admin=false:ecert] " user_attributes
        export user_attributes=${user_attributes:-"admin=false:ecert"}
        log $user_attributes success
        echo
    fi

    # registering a user requires additional information
    if [ "$1" == "register" ]; then
        log "Insert user type (e.g. client, peer, orderer)" info
        read -p "User type: [client] " user_type
        export user_type=${user_type:-client}
        log $user_type success
        echo

        log "Insert user affiliation (default value is usually enough)" info
        read -p "User affiliation: [${org}] " user_affiliation
        export user_affiliation=${user_affiliation:-${org}}
        log $user_affiliation success
        echo
    fi
}

__exec_jobs() {
    local jobs=$1
    local entries=$2

    if [ -z "$jobs" ]; then
        echo "Provide a number of jobs to run in parallel"
        exit 1
    fi
    if [ -z "$entries" ]; then
        echo "Provide a number of entries per job"
        exit 1
    fi

    log "==================" info
    log "Network: benchmark" info
    log "==================" info
    echo

    log "Running in parallel:
    Jobs: $jobs
    Entries: $entries
    " info

    start_time="$(date -u +%s)"
    
    for i in $(seq 1 $jobs); do
        __loader $entries & 
    done

    for job in $(jobs -p); do
        wait $job
    done 

    end_time="$(date -u +%s)"

    elapsed="$(($end_time - $start_time))"
    log "Total of $elapsed seconds elapsed for process" warning

    log "$(( $jobs * $entries )) entries added" success
}

__loader() {
    for i in $(seq 1 $1); do 
        key=$(LC_CTYPE=C cat /dev/urandom | tr -cd 'A-Z0-9' | fold -w 14 | head -n 1)
        value="$i"

        invoke mychannel mychaincode "{\"Args\":[\"put\",\"${key}\",\"${value}\"]}" &>/dev/null
    done
}

tostring() {
    echo "$@" | __jq tostring
}

tojson() {
    echo "$@" | __jq .
}

readonly func="$1"
shift

if [ "$func" == "network" ]; then
    __check_deps deploy
    __check_docker_daemon
    param="$1"
    shift
    if [ "$param" == "install" ]; then
        install_network
    elif [ "$param" == "start" ]; then
        __set_params "$@"
        __log_setup
        start_network "$@"
    elif [ "$param" == "restart" ]; then
        restart_network
    elif [ "$param" == "stop" ]; then
        stop_network
    else
        help
        exit 1
    fi
elif [ "$func" == "explorer" ]; then
    __check_deps deploy
    __check_docker_daemon
    param="$1"
    shift
    if [ "$param" == "start" ]; then
        start_explorer
    elif [ "$param" == "stop" ]; then
        stop_explorer
    else
        help
        exit 1
    fi
elif [ "$func" == "dep" ]; then
    param="$1"
    shift
    if [ "$param" == "install" ]; then
        dep_install "$@"
    elif [ "$param" == "update" ]; then
        dep_update "$@"
    else
        help
        exit 1
    fi
elif [ "$func" == "chaincode" ]; then
    param="$1"
    shift
    if [ "$param" == "lifecycle" ]; then
        __check_fabric_version 2
        param="$1"
        shift
        if [ "$param" == "package" ]; then
            __check_deps deploy
            __check_docker_daemon
            lc_chaincode_package "$@"
        elif [ "$param" == "install" ]; then
            __check_deps deploy
            __check_docker_daemon
            lc_chaincode_install "$@"
        elif [ "$param" == "approve" ]; then
            __check_deps deploy
            __check_docker_daemon
            lc_chaincode_approve "$@"
        elif [ "$param" == "commit" ]; then
            __check_deps deploy
            __check_docker_daemon
            lc_chaincode_commit "$@"
        elif [ "$param" == "upgrade" ]; then
            __check_deps deploy
            __check_docker_daemon
            lc_chaincode_upgrade "$@"
        else
            help
            exit 1
        fi
    elif [ "$param" == "install" ]; then
        __check_fabric_version 1
        __check_deps deploy
        __check_docker_daemon
        chaincode_install "$@"
    elif [ "$param" == "instantiate" ]; then
        __check_fabric_version 1
        __check_deps deploy
        __check_docker_daemon
        chaincode_instantiate "$@"
    elif [ "$param" == "upgrade" ]; then
        __check_fabric_version 1
        __check_deps deploy
        __check_docker_daemon
        chaincode_upgrade "$@"
    elif [ "$param" == "test" ]; then
        chaincode_test "$@"
    elif [ "$param" == "build" ]; then
        chaincode_build "$@"
    elif [ "$param" == "package" ]; then
        __check_fabric_version 1
        __check_deps deploy
        __check_docker_daemon
        chaincode_pack "$@"
    elif [ "$param" == "zip" ]; then
        chaincode_zip "$@"
    elif [ "$param" == "query" ]; then
        __check_deps deploy
        __check_docker_daemon
        query "$@"
    elif [ "$param" == "invoke" ]; then
        __check_deps deploy
        __check_docker_daemon
        invoke "$@"
    else
        help
        exit 1
    fi
elif [ "$func" == "generate" ]; then
    __check_deps deploy
    __check_docker_daemon
    param="$1"
    shift
    if [ "$param" == "cryptos" ]; then
        generate_cryptos "$@"
    elif [ "$param" == "genesis" ]; then
        generate_genesis "$@"
    elif [ "$param" == "channeltx" ]; then
        generate_channeltx "$@"
    else
        help
        exit 1
    fi
elif [ "$func" == "ca" ]; then
    __check_deps deploy
    __check_docker_daemon
    param="$1"
    shift
    if [ "$param" == "register" ]; then
        register_user "$@"
    elif [ "$param" == "enroll" ]; then
        __check_deps deploy
        enroll_user "$@"
    elif [ "$param" == "reenroll" ]; then
        reenroll_user "$@"
    elif [ "$param" == "revoke" ]; then
        revoke_user "$@"
    else
        help
        exit 1
    fi
elif [ "$func" == "channel" ]; then
    __check_deps deploy
    __check_docker_daemon
    param="$1"
    shift
    if [ "$param" == "create" ]; then
        create_channel "$@"
    elif [ "$param" == "update" ]; then
        update_channel "$@"
    elif [ "$param" == "join" ]; then
        join_channel "$@"
    else
        help
        exit 1
    fi
elif [ "$func" == "benchmark" ]; then
    param="$1"
    shift
    if [ "$param" == "load" ]; then
        __check_deps deploy
        __exec_jobs "$@"
    else
        help
        exit 1
    fi
elif [ "$func" == "utils" ]; then
    param="$1"
    shift
    if [ "$param" == "tostring" ]; then
        tostring "$@"
    elif [ "$param" == "tojson" ]; then
        tojson "$@"
    else
        help
        exit 1
    fi
else
    help
    exit 1
fi