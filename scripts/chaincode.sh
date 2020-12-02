#!/usr/bin/env bash

dep_install() {
    __check_chaincode $1
    local chaincode_name="${1}"

    log "=====================" info
    log "Dependencies: install" info
    log "=====================" info
    echo

    __init_go_mod install ${chaincode_name}
}

dep_update() {
    __check_chaincode $1
    local chaincode_name="${1}"

    log "====================" info
    log "Dependencies: update" info
    log "====================" info
    echo

    __init_go_mod update ${chaincode_name}
}

__init_go_mod() {
    local chaincode_name="${2}"
    cd ${CHAINCODE_PATH}/${chaincode_name} >/dev/null 2>&1 || { log >&2 "${CHAINCODE_PATH}/${chaincode_name} path does not exist" error; exit 1; }

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

chaincode_test() {
    local chaincode_name="${1}"
    __check_chaincode ${chaincode_name}

    # avoid "found no test suites" ginkgo error
    if [ ! `find ${CHAINCODE_PATH}/${chaincode_name} -type f -name "*_test*" ! -path "**/node_modules/*" ! -path "**/vendor/*"` ]; then
        log "No test suites found. Skipping tests..." warning
        return 
    fi

    log "===============" info
	log "Chaincode: test" info
    log "===============" info
    echo

    __check_test_deps
    __init_go_mod install ${chaincode_name}

    if [[ $(__check_deps test) ]]; then
        (docker run --rm -v ${CHAINCODE_PATH}:/usr/src/myapp -w /usr/src/myapp/${chaincode_name} -e CGO_ENABLED=0 -e CORE_CHAINCODE_LOGGING_LEVEL=debug ${GOLANG_DOCKER_IMAGE} sh -c "ginkgo -r -v") || exit 1
    else
	    (cd ${CHAINCODE_PATH}/${chaincode_name} && CORE_CHAINCODE_LOGGING_LEVEL=debug CGO_ENABLED=0 ginkgo -r -v) || exit 1
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
    local chaincode_name="${1}"
    __check_chaincode ${chaincode_name}

    log "================" info
	log "Chaincode: build" info
    log "================" info
    echo

    __init_go_mod install ${chaincode_name}

    if [[ $(__check_deps test) ]]; then
        (docker run --rm -v ${CHAINCODE_PATH}:/usr/src/myapp -w /usr/src/myapp/${chaincode_name} -e CGO_ENABLED=0 ${GOLANG_DOCKER_IMAGE} sh -c "go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_name} 2>/dev/null") || exit 1
    else
	    (cd ${CHAINCODE_PATH}/${chaincode_name} && CGO_ENABLED=0 go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_name} 2>/dev/null) || exit 1
    fi

    log "Build passed!" success
}

__check_chaincode() {
    if [ -z "$1" ]; then
		log "Chaincode name missing" error
		exit 1
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
	local chaincode_path="$3"
    local org="$4"
    local peer="$5"
    local install_path="${CHAINCODE_REMOTE_PATH}/${chaincode_path}"

    set_certs $org $peer
    set_peer_exec

    __init_go_mod install ${chaincode_name}

    # Golang: workaround for chaincode written as modules
    # make the install to work when main files are not in the main directory but in cmd
    if [ ! "$(find ${install_path} -type f -name '*.go' -maxdepth 1 2>/dev/null)" ] && [ -d "${CHAINCODE_PATH}/${chaincode_path}/cmd" ]; then
        install_path+="/cmd"
    fi
    
    log "Installing chaincode $chaincode_name version $chaincode_version from path ${install_path}" info

    # fabric-samples does not use tls for installing (and it won't work with), however this flag is listed in the install command on the official fabric documentation 
    # https://hyperledger-fabric.readthedocs.io/en/release-1.4/commands/peerchaincode.html#peer-chaincode-install
    PEER_EXEC+="peer chaincode install -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p ${install_path} || exit 1"

    __exec_command "${PEER_EXEC}"
}

chaincode_instantiate() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "======================" info
    log "Chaincode: instantiate" info
    log "======================" info
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
	local channel_name="$3"
    local org="$4"
    local peer="$5"
    shift 5

    set_certs $org $peer
    set_peer_exec

    log "Instantiating chaincode $chaincode_name version $chaincode_version into channel ${channel_name}" info
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer chaincode instantiate -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -C ${channel_name} -c '{\"Args\":[]}' \"$@\" || exit 1"
    else
        PEER_EXEC+="peer chaincode instantiate -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -C ${channel_name} -c '{\"Args\":[]}' \"$@\" --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
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
	local channel_name="$3"
    local org="$4"
    local peer="$5"
    shift 5

    set_certs $org $peer
    set_peer_exec

    log "Upgrading chaincode $chaincode_name to version $chaincode_version into channel ${channel_name}" info
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C ${channel_name} -c '{\"Args\":[]}' \"$@\" || exit 1"
    else
        PEER_EXEC+="peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C ${channel_name} -c '{\"Args\":[]}' \"$@\" --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
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

    local chaincode_name="${1}"
    __check_chaincode ${chaincode_name}

    __init_go_mod install ${chaincode_name}

    if [ ! -d "${DIST_PATH}" ]; then
        mkdir -p ${DIST_PATH}
    fi

    local timestamp=$(date +%Y-%m-%d-%H-%M-%S)

    # trick to allow chaincode packed as modules to work when deployed against remote environments
    log "Copying chaincode files into vendor..." info
    mkdir -p ./vendor/${CHAINCODE_REMOTE_PATH}/${chaincode_name} && rsync -ar --exclude='vendor' --exclude='META-INF' . ./vendor/${CHAINCODE_REMOTE_PATH}/${chaincode_name} || { log >&2 "Error copying chaincode into vendor directory." error; exit 1; }

    zip -rq ${DIST_PATH}/${chaincode_name}_${timestamp}.zip . || { log >&2 "Error creating chaincode archive." error; exit 1; }

    log "Chaincode archive created in: ${DIST_PATH}/${chaincode_name}.${timestamp}.zip" success
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
	local chaincode_path="$3"
    local org="$4"
    local peer="$5"
    local install_path="${CHAINCODE_REMOTE_PATH}/${chaincode_path}"

    set_certs $org $peer
    set_peer_exec

    __init_go_mod install ${chaincode_name}

    local timestamp=$(date +%Y-%m-%d-%H-%M-%S)

    # trick to allow chaincode packed as modules to work when deployed against remote environments
    log "Copying chaincode files into vendor..." info
    mkdir -p ./vendor/${CHAINCODE_REMOTE_PATH}/${chaincode_name} && rsync -ar --exclude='vendor' --exclude='META-INF' . ./vendor/${CHAINCODE_REMOTE_PATH}/${chaincode_name} || { log >&2 "Error copying chaincode into vendor directory." error; exit 1; }

    log "Packing chaincode $chaincode_name version $chaincode_version from path ${install_path}" info
    
    if [ -z "$TLS_ENABLED" ] || [ "$TLS_ENABLED" == "false" ]; then
        PEER_EXEC+="peer chaincode package dist/${chaincode_name}_${chaincode_version}_${timestamp}.cc -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p ${install_path} -s -S || exit 1"
    else
        PEER_EXEC+="peer chaincode package dist/${chaincode_name}_${chaincode_version}_${timestamp}.cc -o $ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p ${install_path} -s -S --tls $TLS_ENABLED --cafile $ORDERER_CA || exit 1"
    fi

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
	local chaincode_path="$3"
    local org="$4"
    local peer="$5"
    local install_path="${CHAINCODE_REMOTE_PATH}/${chaincode_path}"
    shift 5

    set_certs $org $peer

    __init_go_mod install ${chaincode_name}

    # TODO: Retrieve the chaincode language from the directory name
    cc_lang="golang"

    # TODO: Perform this check only if cc_lang is golang
    # Golang: workaround for chaincode written as modules
    # make the install to work when main files are not in the main directory but in cmd
    if [ ! "$(find ${install_path} -type f -name '*.go' -maxdepth 1 2>/dev/null)" ] && [ -d "${CHAINCODE_PATH}/${chaincode_path}/cmd" ]; then
        install_path+="/cmd"
    fi

    log "Packaging chaincode $chaincode_name version $chaincode_version from path $chaincode_path" info
    # TODO: explore issue which runs into deps error every so often
    set_peer_exec
    PEER_EXEC+="peer lifecycle chaincode package ${chaincode_name}_${chaincode_version}.tar.gz --path ${install_path} --label ${chaincode_name}_${chaincode_version} --lang ${cc_lang} || exit 1"

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

    __init_go_mod install ${chaincode_name}

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
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ] || [ -z "$7" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "============================" info
    log "Chaincode Lifecycle: approve" info
    log "============================" info
    echo

	local chaincode_name="$1"
	local chaincode_version="$2"
	local chaincode_path="$3"
    local channel_name="$4"
    local sequence_no="$5"
    local org="$6"
    local peer="$7"
    shift 7

    set_certs $org $peer

    __init_go_mod install ${chaincode_name}

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
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ] || [ -z "$7" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    log "===========================" info
    log "Chaincode Lifecycle: commit" info
    log "===========================" info
    echo
    
    local chaincode_name="$1"
	local chaincode_version="$2"
	local chaincode_path="$3"
	local channel_name="$4"
    local sequence_no="$5"
    local org="$6"
    local peer="$7"
    shift 7

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

lc_chaincode_deploy() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ] || [ -z "$7" ]; then
		log "Incorrect usage of $FUNCNAME. Please consult the help: ./run.sh help" error
		exit 1
	fi

    lc_chaincode_package $1 $2 $3 $6 $7
    lc_chaincode_install $1 $2 $6 $7
    lc_chaincode_approve "$@"
    lc_chaincode_commit "$@"
}