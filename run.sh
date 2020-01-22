#!/usr/bin/env bash

source $(pwd)/.env

export GO111MODULE=on
export GOPRIVATE=bitbucket.org/everledger/*

help() {
    local help="
        Usage: run.sh [command]
        commands:

        help                                                                        : this help

        dep install [chaincode_name]                                                : install all go modules as vendor and init go.mod if does not exist yet
        dep update [chaincode_name]                                                 : update all go modules and rerun install
        
        ca register                                                                 : register a new user
        ca enroll                                                                   : enroll a previously registered user    
        ca reenroll                                                                 : reenroll a user if its certificate expired
        ca revoke                                                                   : revoke a user's key/certificate providing a reason
        
        network install                                                             : install all the dependencies and docker images
        network start                                                               : start the blockchain network and initialize it
        network restart                                                             : restart a previously running the blockchain network
        network stop                                                                : stop the blockchain network and remove all the docker containers
        
        explorer start                                                              : run the blockchain explorer user-interface and analytics
        explorer stop                                                               : stop the blockchain explorer user-interface and analytics

        channel create [channel_name]                                               : generate channel configuration file
        channel update [channel_name] [org]                                         : update channel with anchor peers
        channel join [channel_name]                                                 : run by a peer to join a channel

        generate cryptos [config_path] [cryptos_path]                               : generate all the crypto keys and certificates for the network
        generate genesis [base_path] [config_path]                                  : generate the genesis block for the ordering service
        generate channeltx [channel_name] [base_path] [config_path] [cryptos_path]  : generate channel configuration files
                           [network_profile] [channel_profile] [org_msp]            

        chaincode test [chaincode_path]                                             : run unit tests
        chaincode build [chaincode_path]                                            : run build and test against the binary file
        chaincode pack [chaincode_path]                                             : create an archive ready for deployment containing chaincode and vendors
        chaincode install [chaincode_name] [chaincode_version] [chaincode_path]     : install chaincode on a peer
        chaincode instantiate [chaincode_name] [chaincode_version] [channel_name]   : instantiate chaincode on a peer for an assigned channel
        chaincode upgrade [chaincode_name] [chaincode_version] [channel_name]       : upgrade chaincode with a new version
        chaincode query [channel_name] [chaincode_name] [data_in_json]              : run query in the format '{\"Args\":[\"queryFunction\",\"key\"]}'
        chaincode invoke [channel_name] [chaincode_name] [data_in_json]             : run invoke in the format '{\"Args\":[\"invokeFunction\",\"key\",\"value\"]}'
        
        benchmark load [jobs] [entries]                                             : run benchmark bulk loading of [entries] per parallel [jobs] against a running network
        "
    echoc "$help" dark cyan
}

check_dependencies() {
    if [ "${1}" == "deploy" ]; then
        type docker >/dev/null 2>&1 || { echoc >&2 "docker required but it is not installed. Aborting." light red; exit 1; }
        type docker-compose >/dev/null 2>&1 || { echoc >&2 "docker-compose required but it is not installed. Aborting." light red; exit 1; }
    elif [ "${1}" == "test" ]; then
        type go >/dev/null 2>&1 || { echoc >&2 "Go binary is missing in your PATH. Running the dockerised version..." light yellow; echo $?; }
    fi
}

# echoc: Prints the user specified string to the screen using the specified colour.
#
# Parameters: ${1} - The string to print
#             ${2} - The intensity of the colour.
#             ${3} - The colour to use for printing the string.
#
#             NOTE: The following color options are available:
#
#                   [0|1]30, [dark|light] black
#                   [0|1]31, [dark|light] red
#                   [0|1]32, [dark|light] green
#                   [0|1]33, [dark|light] yellow
#                   [0|1]34, [dark|light] blue
#                   [0|1]35, [dark|light] purple
#                   [0|1]36, [dark|light] cyan
#
echoc() {
    if [[ ${#} != 3 ]]; then
        echo "usage: ${FUNCNAME} <string> [light|dark] [black|red|green|yellow|blue|pruple|cyan]"
        exit 1
    fi

    local message=${1}

    case $2 in
        dark) intensity=0 ;;
        light) intensity=1 ;;
    esac

    if [[ -z $intensity ]]; then
        echo "${2} intensity not recognised"
        exit 1
    fi

    case $3 in 
        black) colour_code=${intensity}30 ;;
        red) colour_code=${intensity}31 ;;
        green) colour_code=${intensity}32 ;;
        yellow) colour_code=${intensity}33 ;;
        blue) colour_code=${intensity}34 ;;
        purple) colour_code=${intensity}35 ;;
        cyan) colour_code=${intensity}36 ;;
    esac
        
    if [[ -z $colour_code ]]; then
        echo "${1} colour not recognised"
        exit 1
    fi

    colour_code=${colour_code:1}

    # Print out the message
    echo "${message}" | awk '{print "\033['${intensity}';'${colour_code}'m" $0 "\033[1;0m"}'
}

install_network() {
    echoc "================" dark cyan
	echoc "Network: install" dark cyan
    echoc "================" dark cyan
    echo
	echoc "Pulling Go docker image" light cyan
	docker pull ${GOLANG_DOCKER_IMAGE}:${GOLANG_DOCKER_TAG}

	__docker_fabric_pull
	__docker_third_party_images_pull
}

__docker_fabric_pull() {
    for image in peer orderer ca ccenv tools; do
        echoc "==> FABRIC IMAGE: $image" light cyan
        echo
        docker pull hyperledger/fabric-$image:${FABRIC_VERSION} || exit 1
        docker tag hyperledger/fabric-$image:${FABRIC_VERSION} hyperledger/fabric-$image:latest
    done
}

__docker_third_party_images_pull() {
    for image in couchdb; do
        echoc "==> THIRDPARTY DOCKER IMAGE: $image" light cyan
        echo
        docker pull hyperledger/fabric-$image:$FABRIC_THIRDPARTY_IMAGE_VERSION || exit 1
        docker tag hyperledger/fabric-$image:$FABRIC_THIRDPARTY_IMAGE_VERSION hyperledger/fabric-$image:latest
    done
}

start_network() {
    # Note: this trick may allow the network to work also in strict-security platform
    rm -rf ./docker.sock 2>/dev/null && ln -sf /var/run ./docker.sock

    if [ ! "${1}" == "-ci" ]; then
        if [ -d "$DATA_PATH" ]; then
            echoc "Found data directory: ${DATA_PATH}" light yellow
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

        build_chaincode $CHAINCODE_NAME
        test_chaincode $CHAINCODE_NAME
    fi

    echoc "==============" dark cyan
    echoc "Network: start" dark cyan
    echoc "==============" dark cyan
    echo

	generate_cryptos $CONFIG_PATH $CRYPTOS_PATH
    generate_genesis $NETWORK_PATH $CONFIG_PATH $CRYPTOS_PATH $CONFIGTX_PROFILE_NETWORK
    generate_channeltx $CHANNEL_NAME $NETWORK_PATH $CONFIG_PATH $CRYPTOS_PATH $CONFIGTX_PROFILE_NETWORK $CONFIGTX_PROFILE_CHANNEL $ORG_MSP
    
    docker network create ${DOCKER_NETWORK} 2>/dev/null
    
    docker-compose -f ${ROOT}/docker-compose.yaml up -d || exit 1
	
    sleep 5
	
    initialize_network
}

restart_network() {
    echoc "================" dark cyan
	echoc "Network: restart" dark cyan
    echoc "================" dark cyan
    echo

    if [ ! -d "$DATA_PATH" ]; then
        echoc "Data directory not found in: ${DATA_PATH}. Run a normal start." light red
        exit 1
    fi

    __delete_shared
    
    docker-compose -f ${ROOT}/docker-compose.yaml up --force-recreate -d || exit 1

    echoc "The chaincode container will be instantiated automatically once the peer executes the first invoke or query" light yellow
}

stop_network() {
    echoc "=============" dark cyan
	echoc "Network: stop" dark cyan
    echoc "=============" dark cyan

    docker-compose -f ${ROOT}/docker-compose.yaml down || exit 1

    __delete_shared

    if [[ $(docker ps | grep "hyperledger/explorer") ]]; then
        stop_explorer
    fi

    echoc "Cleaning docker leftovers containers and images" light green
    docker rm -f $(docker ps -a | awk '($2 ~ /fabric|dev-/) {print $1}') 2>/dev/null
    docker rmi -f $(docker images -qf "dangling=true") 2>/dev/null
    docker rmi -f $(docker images | awk '($1 ~ /^<none>|dev-/) {print $3}') 2>/dev/null

    if [ -d "$DATA_PATH" ]; then
        echoc "!!!!! ATTENTION !!!!!" light red
        echoc "Found data directory: ${DATA_PATH}" light red
		read -p "Do you wish to remove this data? [yes/no=default] " yn
		case $yn in
			[Yy]* ) __delete_path $DATA_PATH ;;
			* ) return 0
    	esac
    fi
}

__delete_shared() {
    # always remove shared directory
    __delete_path ${SHARED_DATA_PATH}
}

# delete path recursively and asks for root permissions if needed
__delete_path() {
    if [ ! -d "${1}" ]; then 
        echoc "Directory \"${1}\" does not exist. Skipping delete. All good :)" light yellow
        return
    fi

    if [ -w "${1}" ]; then
        rm -rf ${1}
    else 
        echoc "!!!!! ATTENTION !!!!!" light red
        echoc "Directory \"${1}\" requires superuser permissions" light red
        read -p "Do you wish to continue? [yes/no=default] " yn
        case $yn in
            [Yy]* ) sudo rm -rf ${1} ;;
            * ) return 0
        esac
    fi
}

initialize_network() {
    echoc "=============" dark cyan
	echoc "Network: init" dark cyan
    echoc "=============" dark cyan
    echo

	create_channel $CHANNEL_NAME
	join_channel $CHANNEL_NAME
	update_channel $CHANNEL_NAME $ORG_MSP
	install_chaincode $CHAINCODE_NAME $CHAINCODE_VERSION $CHAINCODE_NAME
	instantiate_chaincode $CHAINCODE_NAME $CHAINCODE_VERSION $CHANNEL_NAME
}

start_explorer() {
    stop_explorer
    
    echoc "===============" dark cyan
	echoc "Explorer: start" dark cyan
    echoc "===============" dark cyan
    echo

    if [[ ! $(docker ps | grep fabric) ]]; then
        echoc "No Fabric networks running. First launch ./run.sh start" dark red
		exit 1
    fi

    if [ ! -d "${CRYPTOS_PATH}" ]; then
        echoc "Cryptos path ${CRYPTOS_PATH} does not exist." dark red
    fi

    # replacing private key path in connection profile
    type jq >/dev/null 2>&1 || { echoc >&2 "jq required but it is not installed. Aborting." light red; exit 1; }
    config=$(ls -d ${EXPLORER_PATH}/connection-profile/*)
    admin_key_path="peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore"
    private_key="/tmp/crypto/${admin_key_path}/$(ls ${CRYPTOS_PATH}/${admin_key_path})"
    cat $config | jq -r --arg private_key "$private_key" '.organizations.Org1MSP.adminPrivateKey.path = $private_key' > tmp && mv tmp $config

    __delete_shared

    docker-compose -f ${EXPLORER_PATH}/docker-compose.yaml up --force-recreate -d || exit 1

    echoc "Blockchain Explorer default user is admin/adminpw" light yellow
    echoc "Grafana default user is admin/admin" light yellow
}

stop_explorer() {
    echoc "==============" dark cyan
	echoc "Explorer: stop" dark cyan
    echoc "==============" dark cyan
    echo

    docker-compose -f ${EXPLORER_PATH}/docker-compose.yaml down || exit 1
}

dep_install() {
    __check_chaincode $1
    local chaincode_name="${1}"

    echoc "=====================" dark cyan
    echoc "Dependencies: install" dark cyan
    echoc "=====================" dark cyan
    echo

    cd ${CHAINCODE_PATH}/${chaincode_name} || exit 1
    __init_go_mod install
}

dep_update() {
    __check_chaincode $1
    local chaincode_name="${1}"

    echoc "====================" dark cyan
    echoc "Dependencies: update" dark cyan
    echoc "====================" dark cyan
    echo

    cd ${CHAINCODE_PATH}/${chaincode_name} || exit 1
    __init_go_mod update
}

__init_go_mod() {
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

test_chaincode() {
    __check_chaincode $1
    local chaincode_name="${1}"

    echoc "===============" dark cyan
	echoc "Chaincode: test" dark cyan
    echoc "===============" dark cyan
    echo

    if [[ $(check_dependencies test) ]]; then
        (docker run --rm  -v ${CHAINCODE_PATH}:/usr/src/myapp -w /usr/src/myapp/${chaincode_name} -e CGO_ENABLED=0 -e CORE_CHAINCODE_LOGGING_LEVEL=debug ${GOLANG_DOCKER_IMAGE}:${GOLANG_DOCKER_TAG} sh -c "go test ./... -v") || exit 1
    else
	    (cd ${CHAINCODE_PATH}/${chaincode_name} && CORE_CHAINCODE_LOGGING_LEVEL=debug CGO_ENABLED=0 go test ./... -v) || exit 1
    fi

    echoc "Test passed!" light green
}

build_chaincode() {
    __check_chaincode $1
    local chaincode_name="${1}"

    echoc "================" dark cyan
	echoc "Chaincode: build" dakr cyan
    echoc "================" dark cyan
    echo

    if [[ $(check_dependencies test) ]]; then
        (docker run --rm -v ${CHAINCODE_PATH}:/usr/src/myapp -w /usr/src/myapp/${chaincode_name} -e CGO_ENABLED=0 ${GOLANG_DOCKER_IMAGE}:${GOLANG_DOCKER_TAG} sh -c "go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_name} 2>/dev/null") || exit 1
    else
	    (cd $CHAINCODE_PATH/${chaincode_name} && CGO_ENABLED=0 go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_name} 2>/dev/null) || exit 1
    fi

    echoc "Build passed!" light green
}

pack_chaincode() {
    type zip >/dev/null 2>&1 || { echoc >&2 "zip required but it is not installed. Aborting." light red; exit 1; }

    echoc "===============" dark cyan
    echoc "Chaincode: pack" dark cyan
    echoc "===============" dark cyan
    echo

    __check_chaincode $1
    local chaincode_name="${1}"

    cd $CHAINCODE_PATH/${chaincode_name} >/dev/null 2>&1 || { echoc >&2 "$CHAINCODE_PATH/${chaincode_name} path does not exist" light red; exit 1; }
    __init_go_mod install

    if [ ! -d "${DIST_PATH}" ]; then
        mkdir -p ${DIST_PATH}
    fi

    local timestamp=$(date -u +%s)
    zip -rq ${DIST_PATH}/${chaincode_name}.${timestamp}.zip . || { echoc >&2 "Error creating chaincode archive." light red; exit 1; }

    echoc "Chaincode archive created in: ${DIST_PATH}/${chaincode_name}.${timestamp}.zip" light green
}

__check_chaincode() {
    if [ -z "$1" ]; then
		echoc "Chaincode name missing" dark red
		exit 1
	fi
}

# generate genesis block
# $1: base path
# $2: config path
# $3: cryptos directory
# $4: network profile name
generate_genesis() {
    if [ -z "$1" ]; then
		echoc "Base path missing" dark red
		exit 1
	fi
    if [ -z "$2" ]; then
		echoc "Config path missing" dark red
		exit 1
	fi
    if [ -z "$3" ]; then
		echoc "Crypto material path missing" dark red
		exit 1
	fi
    if [ -z "$4" ]; then
		echoc "Network profile name" dark red
		exit 1
	fi

    local base_path="$1"
    local config_path="$2"
    local channel_dir="${base_path}/channels/orderer-system-channel"
    local cryptos_path="$3"
    local network_profile="$4"

    if [ -d "$channel_dir" ]; then
        echoc "Channel directory ${channel_dir} already exists" light yellow
		read -p "Do you wish to re-generate channel config? [yes/no=default] " yn
		case $yn in
			[Yy]* ) ;;
			* ) return 0
    	esac
        __delete_path $channel_dir
        mkdir -p $channel_dir
    fi

    echoc "========================" dark cyan
    echoc "Generating genesis block" dark cyan
    echoc "========================" dark cyan
    echo
	echoc "Base path: $base_path" light cyan
	echoc "Config path: $config_path" light cyan
	echoc "Cryptos path: $cryptos_path" light cyan
	echoc "Network profile: $network_profile" light cyan

    # generate genesis block for orderer
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/orderer-system-channel \
                    -v ${cryptos_path}:/crypto-config \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    bash -c " \
                        configtxgen -profile $network_profile -channelID orderer-system-channel -outputBlock /channels/orderer-system-channel/genesis_block.pb /configtx.yaml;
                        configtxgen -inspectBlock /channels/orderer-system-channel/genesis_block.pb
                    "
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate orderer genesis block..." dark red
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
		echoc "Channel name missing" dark red
		exit 1
	fi
    if [ -z "$2" ]; then
		echoc "Base path missing" dark red
		exit 1
	fi
    if [ -z "$3" ]; then
		echoc "Config path missing" dark red
		exit 1
	fi
    if [ -z "$4" ]; then
		echoc "Crypto material path missing" dark red
		exit 1
	fi
    if [ -z "$5" ]; then
		echoc "Network profile missing" dark red
		exit 1
	fi
    if [ -z "$6" ]; then
		echoc "Channel profile missing" dark red
		exit 1
	fi
    if [ -z "$7" ]; then
		echoc "MSP missing" dark red
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
        echoc "Channel directory ${channel_dir} already exists" light yellow
		read -p "Do you wish to re-generate channel config? [yes/no=default] " yn
		case $yn in
			[Yy]* ) ;;
			* ) return 0
    	esac
        __delete_path $channel_dir
        mkdir -p $channel_dir
    fi 

    echoc "=========================" dark cyan
    echoc "Generating channel config" dark cyan
    echoc "=========================" dark cyan
    echo
	echoc "Channel: $channel_name" light cyan
	echoc "Base path: $base_path" light cyan
	echoc "Config path: $config_path" light cyan
	echoc "Cryptos path: $cryptos_path" light cyan
	echoc "Channel dir: $channel_dir" light cyan
	echoc "Network profile: $network_profile" light cyan
	echoc "Channel profile: $channel_profile" light cyan
	echoc "Org MSP: $org_msp" light cyan

	# generate channel configuration transaction
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/${channel_name} \
                    -v ${cryptos_path}:/crypto-config \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    bash -c " \
                        configtxgen -profile $channel_profile -outputCreateChannelTx /channels/${channel_name}/${channel_name}_tx.pb -channelID $channel_name /configtx.yaml;
                        configtxgen -inspectChannelCreateTx /channels/${channel_name}/${channel_name}_tx.pb
                    "
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate channel configuration transaction..." dark red
		exit 1
	fi

	# generate anchor peer transaction
	docker run --rm -v ${config_path}/configtx.yaml:/configtx.yaml \
                    -v ${channel_dir}:/channels/${channel_name} \
                    -v ${cryptos_path}:/crypto-config \
                    -e FABRIC_CFG_PATH=/ \
                    hyperledger/fabric-tools:${FABRIC_VERSION} \
                    configtxgen -profile $channel_profile -outputAnchorPeersUpdate /channels/${channel_name}/${org_msp}_anchors_tx.pb -channelID $channel_name -asOrg $org_msp /configtx.yaml
	if [ "$?" -ne 0 ]; then
		echoc "Failed to generate anchor peer update for $org_msp..." dark red
		exit 1
	fi
}

# generate crypto config
# $1: crypto-config.yml file path
# $2: certificates output directory
generate_cryptos() {
    if [ -z "$1" ]; then
		echoc "Config path missing" dark red
		exit 1
	fi
    if [ -z "$2" ]; then
		echoc "Cryptos path missing" dark red
		exit 1
	fi

    local config_path="$1"
    local cryptos_path="$2"

    echoc "==================" dark cyan
    echoc "Generating cryptos" dark cyan
    echoc "==================" dark cyan
    echo
    echoc "Config path: $config_path" light cyan
    echoc "Cryptos path: $cryptos_path" light cyan

    if [ -d "${cryptos_path}" ]; then
        echoc "crypto-config already exists" light yellow
		read -p "Do you wish to remove crypto-config? [yes/no=default] " yn
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
                        hyperledger/fabric-tools:${FABRIC_VERSION} \
                        cryptogen generate --config=/crypto-config.yaml --output=/crypto-config
        if [ "$?" -ne 0 ]; then
            echoc "Failed to generate crypto material..." dark red
            exit 1
        fi
    fi
    
    # copy cryptos into a shared folder available for client applications (sdk)
    if [ -d "${CRYPTOS_SHARED_PATH}" ]; then
        echoc "Shared crypto-config directory ${CRYPTOS_SHARED_PATH} already exists" light yellow
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

create_channel() {
	if [ -z "$1" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

    echoc "===============" dark cyan
    echoc "Channel: create" dark cyan
    echoc "===============" dark cyan
    echo

	local channel_name="$1"

	echoc "Creating channel $channel_name using configuration file $CHANNELS_CONFIG_PATH/$channel_name/${channel_name}_tx.pb" light cyan
	docker exec $CHAINCODE_UTIL_CONTAINER peer channel create -o $ORDERER_ADDRESS -c $channel_name -f $CHANNELS_CONFIG_PATH/$channel_name/${channel_name}_tx.pb --outputBlock $CHANNELS_CONFIG_PATH/$channel_name/${channel_name}.block
}

join_channel() {
 	if [ -z "$1" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

    echoc "=============" dark cyan
    echoc "Channel: join" dark cyan
    echoc "=============" dark cyan
    echo

	local channel_name="$1"

	echoc "Joining channel $channel_name" light cyan
    docker exec $CHAINCODE_UTIL_CONTAINER peer channel join -b $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block
}

update_channel() {
	if [ -z "$1" ] || [ -z "$2" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

    echoc "===============" dark cyan
    echoc "Channel: update" dark cyan
    echoc "===============" dark cyan
    echo

	local channel_name="$1"
    local org_msp="$2"

	echoc "Updating anchors peers $channel_name using configuration file $CHANNELS_CONFIG_PATH/$channel_name/${org_msp}_anchors.tx" light cyan
	docker exec $CHAINCODE_UTIL_CONTAINER peer channel update -o $ORDERER_ADDRESS -c $channel_name -f $CHANNELS_CONFIG_PATH/${channel_name}/${org_msp}_anchors_tx.pb
}

install_chaincode() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

    echoc "==================" dark cyan
    echoc "Chaincode: install" dark cyan
    echoc "==================" dark cyan
    echo

    __init_go_mod install

	local chaincode_name="$1"
	local chaincode_version="$2"
	local chaincode_path="$3"

    echoc "Installing chaincode $chaincode_name version $chaincode_version from path $chaincode_path" light cyan
    docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode install -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p ${CHAINCODE_REMOTE_PATH}/${chaincode_path}
}

instantiate_chaincode() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

    echoc "======================" dark cyan
    echoc "Chaincode: instantiate" dark cyan
    echoc "======================" dark cyan
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
	local channel_name="$3"

    echoc "Instantiating chaincode $chaincode_name version $chaincode_version into channel $channel_name" light cyan
	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode instantiate -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -C $channel_name -c '{"Args":[]}'
}

upgrade_chaincode() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

    echoc "==================" dark cyan
    echoc "Chaincode: upgrade" dark cyan
    echoc "==================" dark cyan
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
	local channel_name="$3"

	build_chaincode $chaincode_name
	test_chaincode $chaincode_name
	install_chaincode $chaincode_name $chaincode_version $chaincode_name

    echoc "Upgrading chaincode $chaincode_name to version $chaincode_version into channel $channel_name" light cyan
	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C $channel_name -c '{"Args":[]}'
}

invoke() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

    echoc "==================" dark cyan
    echoc "Chaincode: invoke" dark cyan
    echoc "==================" dark cyan
    echo

	local channel_name="$1"
	local chaincode_name="$2"
	local request="$3"

	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode invoke -o $ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c "$request"
}

query() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echoc "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" dark red
		exit 1
	fi

    echoc "==================" dark cyan
    echoc "Chaincode: query" dark cyan
    echoc "==================" dark cyan
    echo

	local channel_name="$1"
	local chaincode_name="$2"
	local request="$3"

	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode query -o $ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c "$request"
}

register_user() {
    echoc "=================" dark cyan
    echoc "CA User: register" dark cyan
    echoc "=================" dark cyan
    echo

    __ca_setup register

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${fabric_version} \
        sh -c " \
        fabric-ca-client register -d \
            --home /crypto-config \
            --mspdir ${org}/users/admin \
            --url ${ca_protocol}${ca_url} \
            --tls.certfiles ${ca_cert} \
            --id.name $username \
            --id.secret $password  \
            --id.affiliation $user_affiliation \
            --id.attrs $user_attributes \
            --id.type $user_type
         "

    echoc "!! IMPORTANT: Note down these lines containing the information of the registered user" light green
}

enroll_user() {
    echoc "===============" dark cyan
    echoc "CA User: enroll" dark cyan
    echoc "===============" dark cyan
    echo

    __ca_setup enroll

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${fabric_version} \
        sh -c " \
        fabric-ca-client enroll -d \
            --home /crypto-config \
            --mspdir ${org}/users/${username} \
            --url ${ca_protocol}${username}:${password}@${ca_url} \
            --tls.certfiles $ca_cert \
            --enrollment.attrs $user_attributes
        "

    # IMPORTANT: the CA requires this folder in case of the user is an admin
    cp -r ${CRYPTOS_PATH}/${org}/users/${username}/signcerts ${CRYPTOS_PATH}/${org}/users/${username}/admincerts
}

reenroll_user() {
    echoc "=================" dark cyan
    echoc "CA User: reenroll" dark cyan
    echoc "=================" dark cyan
    echo

    __ca_setup enroll

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${fabric_version} \
        sh -c " \
        fabric-ca-client reenroll -d \
            --home /crypto-config \
            --mspdir ${org}/users/${username} \
            --url ${ca_protocol}${username}:${password}@${ca_url} \
            --tls.certfiles $ca_cert \
            --enrollment.attrs $user_attributes
        "

    # IMPORTANT: the CA requires this folder in case of the user is an admin
    cp -r ${CRYPTOS_PATH}/${org}/users/${username}/signcerts ${CRYPTOS_PATH}/${org}/users/${username}/admincerts
}

revoke_user() {
    echoc "===============" dark cyan
    echoc "CA User: revoke" dark cyan
    echoc "===============" dark cyan
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
        echoc "Select one of the reason for the revoke from this list: " light blue
        echoc "${reason_list}" light blue
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
            *) echoc "Please select any of the reason from the list by typying in the corresponding number" light yellow;;
        esac
    done
    echoc ${reason} light green
    echo

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${fabric_version} \
        sh -c " \
        fabric-ca-client revoke -d \
            --home /crypto-config \
            --mspdir ${org}/users/admin \
            --url ${ca_protocol}${ca_url} \
            --tls.certfiles $ca_cert \
            --revoke.name $username \
            --revoke.reason $reason
        "
}

__ca_setup() {
    echoc "Insert the organization name of the user to register/enroll" light blue
    while [ -z "$org" ]; do
        read -p "Organization: [] " org
    done
    export org
    echoc $org light green
    echo

    users_dir="${CRYPTOS_PATH}/${org}/users"

    if [ "$1" == "register" ]; then
        # set admin msp path
        while [ ! -d "${users_dir}/admin" ]; do
            echoc "Set Admin MSP path containing admincerts, signcerts, etc. directories" light blue
            admin_msp_default=$(find $NETWORK_PATH -path "*/peerOrganizations/*/Admin*" -type d -name "msp" | head -n 1)
            read -p "CA cert: [${admin_msp_default}] " admin_msp
            admin_msp=${admin_msp:-${admin_msp_default}}
            echoc $admin_msp light green
            # copy the Admin msp to the main cryptos directory
            mkdir -p ${users_dir} && cp -r $admin_msp ${users_dir}/admin
            mv ${users_dir}/admin/signcerts/* ${users_dir}/admin/signcerts/cert.pem
            cp -r ${users_dir}/admin/signcerts/ ${users_dir}/admin/admincerts/
            echo

            if [ ! -d "${users_dir}/admin" ]; then
                echoc "Admin directory not found in: ${users_dir}/admin. Please be sure the selected Admin MSP directory exists." light yellow
            fi
        done
    fi

    echoc "Insert the correct Hyperledger Fabric CA version to use (read Troubleshooting section)" light blue
    echoc "This should be the same used by your CA server (i.e. at the time of writing, IBPv1 is using 1.1.0)" light blue
    read -p "CA Version: [${FABRIC_VERSION}] " fabric_version
    export fabric_version=${fabric_version:-${FABRIC_VERSION}}
    echoc $fabric_version light green
    echo

    echoc "Insert the username of the user to register/enroll" light blue
    username_default="user_"$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 5; echo)
    read -p "Username: [${username_default}] " username
    export username=${username:-${username_default}}
    echoc $username light green
    echo

    echoc "Insert password of the user. It will be used by the CA as secret to generate the user certificate and key" light blue
    password_default=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20; echo)
    read -p "Password: [${password_default}] " password
    export password=${password:-${password_default}}
    echoc $password light green
    echoc "!! IMPORTANT: Take note of this password before continuing. If you loose this password you will not be able to manage the credentials of this user any longer." light yellow
    echo

    echoc "CA secure connection (https)" light blue
    read -p "Using TLS secure connection? (if your CA address starts with https)? [yes/no=default] " yn
    case $yn in
        [Yy]* ) 
            export ca_protocol="https://"
            echoc "Secure TLS connection: enabled" light green
            ;;
        * ) 
            export ca_protocol="http://" 
            echoc "Secure TLS connection: disabled" light green
            ;;
    esac
    echo

    echoc "Set CA TLS certificate path" light blue
    ca_cert_default=$(find $NETWORK_PATH -name "tlsca*.pem" | head -n 1)
    read -p "CA cert: [${ca_cert_default}] " ca_cert
    ca_cert=${ca_cert:-${ca_cert_default}}
    echoc $ca_cert light green
    # copy the CA certificate to the main cryptos directory
    cp $ca_cert ${CRYPTOS_PATH}/${org}/cert.pem
    export ca_cert=$(basename ${CRYPTOS_PATH}/${org}/cert.pem)
    echo

    echoc "Insert CA hostname and port only (e.g. ca.example.com:7054)" light blue
    ca_url_default="ca.example.com:7054"
    read -p "CA hostname and port: [${ca_url_default}] " ca_url
    export ca_url=${ca_url:-${ca_url_default}}
    echoc ${ca_url} light green
    echo

    if [ "$1" == "register" ] || [ "$1" == "enroll" ]; then
        echoc "Insert user attributes (e.g. admin=false:ecert)" light blue
        echoc "Wiki: https://hyperledger-fabric-ca.readthedocs.io/en/latest/users-guide.html#registering-a-new-identity" light blue
        echo
        echoc "A few examples:" light blue
        echoc "If enrolling an admin: 'hf.Registrar.Roles,hf.Registrar.Attributes,hf.AffiliationMgr'" light yellow
        echoc "If registering a user: 'admin=false:ecert,email=provapi@everledger.io:ecert,application=provapi'" light yellow
        echoc "If enrolling a user: 'admin:opt,email:opt,application:opt'" light yellow
        read -p "User attributes: [admin=false:ecert] " user_attributes
        export user_attributes=${user_attributes:-"admin=false:ecert"}
        echoc $user_attributes light green
        echo
    fi

    # registering a user requires additional information
    if [ "$1" == "register" ]; then
        echoc "Insert user type (e.g. client, peer, orderer)" light blue
        read -p "User type: [client] " user_type
        export user_type=${user_type:-client}
        echoc $user_type light green
        echo

        echoc "Insert user affiliation (default value is usually enough)" light blue
        read -p "User affiliation: [${org}] " user_affiliation
        export user_affiliation=${user_affiliation:-${org}}
        echoc $user_affiliation light green
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

    echoc "==================" dark cyan
    echoc "Network: benchmark" dark cyan
    echoc "==================" dark cyan
    echo

    echoc "Running in parallel:
    Jobs: $jobs
    Entries: $entries
    " light cyan

    start_time="$(date -u +%s)"
    
    for i in $(seq 1 $jobs); do
        __loader $entries & 
    done

    for job in $(jobs -p); do
        wait $job
    done 

    end_time="$(date -u +%s)"

    elapsed="$(($end_time - $start_time))"
    echoc "Total of $elapsed seconds elapsed for process" light yellow

    echoc "$(( $jobs * $entries )) entries added" light green
}

__loader() {
    for i in $(seq 1 $1); do 
        key=$(LC_CTYPE=C cat /dev/urandom | tr -cd 'A-Z0-9' | fold -w 14 | head -n 1)
        value="$i"

        invoke mychannel mychaincode "{\"Args\":[\"put\",\"${key}\",\"${value}\"]}" &>/dev/null
    done
}

readonly func="$1"
shift

if [ "$func" == "network" ]; then
    readonly param="$1"
    shift
    if [ "$param" == "install" ]; then
        check_dependencies deploy
        install_network
    elif [ "$param" == "start" ]; then
        check_dependencies deploy
        start_network "$@"
    elif [ "$param" == "restart" ]; then
        check_dependencies deploy
        restart_network
    elif [ "$param" == "stop" ]; then
        stop_network
        help
        exit 1
    fi
elif [ "$func" == "explorer" ]; then
    readonly param="$1"
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
    readonly param="$1"
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
    readonly param="$1"
    shift
    if [ "$param" == "install" ]; then
        install_chaincode "$@"
    elif [ "$param" == "instantiate" ]; then
        instantiate_chaincode "$@"
    elif [ "$param" == "upgrade" ]; then
        upgrade_chaincode "$@"
    elif [ "$param" == "test" ]; then
        test_chaincode "$@"
    elif [ "$param" == "build" ]; then
        build_chaincode "$@"
    elif [ "$param" == "pack" ]; then
        pack_chaincode "$@"
    elif [ "$param" == "query" ]; then
        query "$@"
    elif [ "$param" == "invoke" ]; then
        invoke "$@"
    else
        help
        exit 1
    fi
elif [ "$func" == "generate" ]; then
    readonly param="$1"
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
    readonly param="$1"
    shift
    if [ "$param" == "register" ]; then
        register_user "$@"
    elif [ "$param" == "enroll" ]; then
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
    readonly param="$1"
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
    readonly param="$1"
    shift
    if [ "$param" == "load" ]; then
        check_dependencies deploy
        __exec_jobs "$@"
    else
        help
        exit 1
    fi
else
    help
    exit 1
fi