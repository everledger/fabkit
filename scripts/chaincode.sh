#!/usr/bin/env bash

dep_install() {
    __check_param_chaincode $1

    log "=====================" info
    log "Dependencies: install" info
    log "=====================" info
    echo

    local chaincode_relative_path="${1}"
    __set_chaincode_absolute_path $chaincode_relative_path chaincode_path

    __init_go_mod install ${chaincode_path}
}

dep_update() {
    __check_param_chaincode $1

    log "====================" info
    log "Dependencies: update" info
    log "====================" info
    echo

    local chaincode_relative_path="${1}"
    __set_chaincode_absolute_path $chaincode_relative_path chaincode_path

    __init_go_mod update ${chaincode_path}
}

__init_go_mod() {
    local operation=$1
    local chaincode_relative_path=$2

    cd ${chaincode_path} >/dev/null 2>&1 || {
        log >&2 "${chaincode_path} path does not exist" error
        exit 1
    }

    if [ ! -f "./go.mod" ]; then
        go mod init
    fi

    __delete_path vendor 2>/dev/null

    if [ "${operation}" == "install" ]; then
        go get ./...
    elif [ "${operation}" == "update" ]; then
        go get -u=patch ./...
    fi

    go mod tidy
    go mod vendor

    cd $FABKIT_ROOT
}

chaincode_test() {
    __check_param_chaincode $1

    log "===============" info
    log "Chaincode: test" info
    log "===============" info
    echo

    local chaincode_relative_path="${1}"
    __set_chaincode_absolute_path $chaincode_relative_path chaincode_path
    local chaincode_name=$(basename $chaincode_path)
    __get_chaincode_language $chaincode_path chaincode_language

    if [ ${chaincode_language} == "golang" ]; then
        # avoid "found no test suites" ginkgo error
        if [[ ! $(find ${chaincode_path} -type f -name "*_test*" ! -path "**/node_modules/*" ! -path "**/vendor/*") ]]; then
            log "No test suites found. Skipping tests..." warning
            return
        fi

        __check_test_deps
        __init_go_mod install $chaincode_path

        if [[ $(__check_deps test) ]]; then
            (docker run --rm -v ${FABKIT_CHAINCODE_USER_PATH}:/usr/src/myapp -w /usr/src/myapp/${chaincode_name} -e CGO_ENABLED=0 -e CORE_CHAINCODE_LOGGING_LEVEL=debug ${FABKIT_GOLANG_DOCKER_IMAGE} sh -c "ginkgo -r -v") || exit 1
        else
            (cd $chaincode_path && CORE_CHAINCODE_LOGGING_LEVEL=debug CGO_ENABLED=0 ginkgo -r -v) || exit 1
        fi
    fi

    cd $FABKIT_ROOT

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
    __check_param_chaincode $1

    log "================" info
    log "Chaincode: build" info
    log "================" info
    echo

    local chaincode_relative_path="${1}"
    __set_chaincode_absolute_path $chaincode_relative_path chaincode_path
    local chaincode_name=$(basename $chaincode_path)
    __get_chaincode_language $chaincode_path chaincode_language

    if [ "${chaincode_language}" == "golang" ]; then
        __init_go_mod install ${chaincode_path}

        if [[ $(__check_deps test) ]]; then
            (docker run --rm -v ${chaincode_path}:/usr/src/myapp -w /usr/src/myapp/${chaincode_name} -e CGO_ENABLED=0 ${FABKIT_GOLANG_DOCKER_IMAGE} sh -c "go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_name} 2>/dev/null") || exit 1
        else
            (cd ${chaincode_path} && CGO_ENABLED=0 go build -a -installsuffix nocgo ./... && rm -rf ./${chaincode_name} 2>/dev/null) || exit 1
        fi
    fi

    cd $FABKIT_ROOT

    log "Build passed!" success
}

__check_param_chaincode() {
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

    local chaincode_relative_path="$1"
    local __result=$2
    local __chaincode_language=""
    local golang_cc_identifier="func main"
    local java_cc_identifier="public static void main"
    local node_cc_identifier="require('fabric-shim')"

    if [[ $(find "${chaincode_relative_path}" ! -path "**/vendor/*" -type f -iname '*.go' -exec grep -l "${golang_cc_identifier}" {} \;) ]]; then
        __chaincode_language="golang"
    elif [[ $(find "${chaincode_relative_path}" -type f -iname '*.java' -exec grep -l "${java_cc_identifier}" {} \;) ]]; then
        __chaincode_language="java"
    elif [[ $(find "${chaincode_relative_path}" ! -path "**/node_modules/*" -type f \( -iname \*.js -o -iname \*.ts \) -exec grep -l "${node_cc_identifier}" {} \;) ]]; then
        __chaincode_language="node"
    else
        log "Error cannot determine chaincode language" error
        exit 1
    fi

    log "Chaincode language: $__chaincode_language" debug

    eval $__result="'$__chaincode_language'"
}

__chaincode_sync() {
    if [[ ! -d ${FABKIT_CHAINCODE_USER_PATH} ]]; then
        mkdir -p ${FABKIT_CHAINCODE_USER_PATH}
    fi

    rsync -aur --exclude='vendor' --exclude='node_modules' ${FABKIT_CHAINCODE_PATH}/golang/ ${FABKIT_CHAINCODE_PATH}/java/ ${FABKIT_CHAINCODE_PATH}/node/ ${FABKIT_CHAINCODE_USER_PATH} || exit 1
}

__copy_user_chaincode() {
    local chaincode_absolute_path=$1
    local chaincode_internal_path="$(find ${FABKIT_CHAINCODE_PATH} -type d -iname $(basename $chaincode_absolute_path))"

    if ! [[ -d $chaincode_absolute_path || -d $chaincode_internal_path ]]; then
        log "Path does not exist: ${chaincode_absolute_path}" error
        exit 1
    fi

    if [[ ! -d ${FABKIT_CHAINCODE_USER_PATH} ]]; then
        mkdir -p ${FABKIT_CHAINCODE_USER_PATH}
    fi

    if [[ ! "$chaincode_absolute_path" =~ ^/ && -d $chaincode_internal_path ]]; then
        chaincode_absolute_path=$chaincode_internal_path
    fi

    rsync -aur --exclude='vendor' --exclude='node_modules' ${chaincode_absolute_path} ${FABKIT_CHAINCODE_USER_PATH} || exit 1
}

__set_chaincode_absolute_path() {
    local __chaincode_relative_path=$1
    local __result=$2

    __copy_user_chaincode $__chaincode_relative_path

    local __chaincode_path="${FABKIT_CHAINCODE_USER_PATH}/$(basename ${__chaincode_relative_path})"

    log "Chaincode absolute path: ${__chaincode_path}" debug

    eval $__result="'$__chaincode_path'"
}

__set_chaincode_remote_path() {
    local __chaincode_relative_path=$1
    local __chaincode_language=$2
    local __result=$3

    local __chaincode_name=$(basename $__chaincode_relative_path)

    if [ "${__chaincode_language}" == "golang" ]; then
        case $FABKIT_CHAINCODE_REMOTE_PATH/ in
        /opt/gopath/src/*)
            local __chaincode_remote_path="${FABKIT_CHAINCODE_REMOTE_PATH#/opt/gopath/src/}/${__chaincode_name}"
            ;;
        *)
            log "Chaincode not mounted in gopath" error
            exit 1
            ;;
        esac
    # TODO: complete for each supported chaincode language
    else
        local __chaincode_remote_path="${FABKIT_CHAINCODE_REMOTE_PATH}/${__chaincode_name}"
    fi

    log "Chaincode remote path: ${__chaincode_remote_path}" debug

    eval $__result="'$__chaincode_remote_path'"
}

__rename_chaincode_path_to_name() {
    local __chaincode_path=$1
    local __chaincode_name=$2
    local __result=$3
    local __output_path="${__chaincode_path%/chaincodes/*}/chaincodes/${__chaincode_name}"

    mv $__chaincode_path $__output_path

    eval $__result="'$__output_path'"
}

__set_chaincode_options() {
    local operation=$1
    local __result=$2
    local __options=""
    local is_args_set=false
    shift 2

    in="$@"
    log "All params: $in" debug

    # TODO: Offer support for multiple options
    while [[ $# -gt 0 ]]; do
        param=$1

        case $param in
        *"{\"Args\":"*)
            if [[ "$operation" =~ ^(invoke|instantiate|upgrade)$ ]]; then
                __options=" -c $(tostring $param)"
                is_args_set=true
            fi
            shift
            ;;
        -c | --ctor)
            if [[ "$operation" =~ ^(invoke|instantiate|upgrade)$ ]]; then
                __options+=" $param $(tostring $2)"
                is_args_set=true
            fi
            shift 2
            ;;
        -C | --collections-config | --channelID | --connectionProfile)
            if [[ "$operation" =~ ^(instantiate|upgrade|commit|approve)$ ]]; then
                __options+=" $param $(tostring $2)"
            fi
            shift 2
            ;;
        -P | --policy)
            if [[ "$operation" =~ ^(instantiate|upgrade)$ ]]; then
                __options+=" $param \"$(tostring $2)\""
            fi
            shift 2
            ;;
        *)
            __options+=" $(tostring $param)"
            shift
            ;;
        esac
    done

    if [[ "$operation" =~ ^(invoke|instantiate|upgrade)$ ]] && [ "${is_args_set}" == "false" ]; then
        __options+=' -c "{\"Args\":[]}"'
    fi

    log "Options: $__options" debug

    eval $__result="'$__options'"
}

chaincode_install() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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

    __set_chaincode_options install options $@
    __set_certs $org $peer
    __set_peer_exec cmd

    __set_chaincode_absolute_path $chaincode_relative_path chaincode_path
    __get_chaincode_language $chaincode_path chaincode_language

    if [ "${chaincode_language}" == "golang" ]; then
        __set_chaincode_module_main $chaincode_path result
        chaincode_path=$result
    fi

    __rename_chaincode_path_to_name $chaincode_path $chaincode_name result
    chaincode_path=$result

    __set_chaincode_remote_path $chaincode_path $chaincode_language chaincode_remote_path

    log "Installing chaincode $chaincode_name version $chaincode_version from path $chaincode_path" info

    cmd+="peer chaincode install -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p $chaincode_remote_path -l $chaincode_language $options"

    __exec_command "${cmd}"
}

chaincode_instantiate() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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

    __set_chaincode_options instantiate options $@
    __get_chaincode_language ${FABKIT_CHAINCODE_USER_PATH}/${chaincode_name} chaincode_language

    __set_certs $org $peer
    __set_peer_exec cmd

    log "Instantiating chaincode $chaincode_name version $chaincode_version on channel $channel_name" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer chaincode instantiate -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -C $channel_name -l $chaincode_language $options"
    else
        cmd+="peer chaincode instantiate -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -C $channel_name -l $chaincode_language $options --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${cmd}"
}

chaincode_upgrade() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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

    __set_certs $org $peer
    __set_peer_exec cmd

    __set_chaincode_options upgrade options $@
    __get_chaincode_language $chaincode_relative_path chaincode_language

    log "Upgrading chaincode $chaincode_name to version $chaincode_version on channel: ${channel_name}" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C ${channel_name} -l ${chaincode_language} $options"
    else
        cmd+="peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C ${channel_name} -l ${chaincode_language} $options --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${cmd}"
}

__chaincode_module_pack() {
    local chaincode_path=$1

    # trick to allow chaincode packed as modules to work when deployed against remote environments
    log "Copying chaincode files into vendor..." info
    mkdir -p ./vendor/${chaincode_path} && rsync -ar --exclude='vendor' --exclude='META-INF' . ./vendor/${chaincode_path} || {
        log >&2 "Error copying chaincode into vendor directory." error
        exit 1
    }
}

__set_chaincode_module_main() {
    local __chaincode_path=$1
    local __result=$2

    __init_go_mod install $__chaincode_path
    # Golang: workaround for chaincode written as modules
    # make the install to work when main files are not in the main directory but in cmd
    if [[ ! $(find ${__chaincode_path} -type f -name '*.go' -maxdepth 1 2>/dev/null) && -d "${__chaincode_path}/cmd" ]]; then
        __chaincode_path+="/cmd"
    fi

    eval $__result="'$__chaincode_path'"
}

chaincode_zip() {
    type zip >/dev/null 2>&1 || {
        log >&2 "zip required but it is not installed. Aborting." error
        exit 1
    }
    type rsync >/dev/null 2>&1 || {
        log >&2 "rsync required but it is not installed. Aborting." error
        exit 1
    }

    __check_param_chaincode $1

    log "==============" info
    log "Chaincode: zip" info
    log "==============" info
    echo

    local chaincode_relative_path="${1}"
    __set_chaincode_absolute_path $chaincode_relative_path chaincode_path
    __get_chaincode_language $chaincode_path chaincode_language

    if [ "$chaincode_language" == "golang" ]; then
        __init_go_mod install $chaincode_path
        __chaincode_module_pack $chaincode_path
    fi

    local timestamp=$(date +%Y-%m-%d-%H-%M-%S)
    local filename="$(basename $chaincode_path)_${timestamp}.zip"

    if [ ! -d "${FABKIT_DIST_USER_PATH}" ]; then
        mkdir -p ${FABKIT_DIST_USER_PATH}
    fi

    log "Zipping chaincode $chaincode_name from path ${chaincode_path} " info

    zip -rqj ${FABKIT_DIST_USER_PATH}/${filename} $chaincode_path/** || {
        log >&2 "Error creating chaincode archive." error
        exit 1
    }

    log "Chaincode archive created in: ${FABKIT_DIST_USER_PATH}/${filename}" success
}

chaincode_pack() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
        exit 1
    fi

    type rsync >/dev/null 2>&1 || {
        log >&2 "rsync required but it is not installed. Aborting." error
        exit 1
    }

    __check_param_chaincode $1

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

    __set_certs $org $peer
    __set_peer_exec cmd

    __set_chaincode_absolute_path $chaincode_relative_path chaincode_path
    __get_chaincode_language $chaincode_path chaincode_language
    __set_chaincode_remote_path $chaincode_path $chaincode_language chaincode_remote_path

    if [ "$chaincode_language" == "golang" ]; then
        __init_go_mod install $chaincode_path
        __chaincode_module_pack $chaincode_path
    fi

    local timestamp=$(date +%Y-%m-%d-%H-%M-%S)
    local filename="${chaincode_name}@${chaincode_version}_${timestamp}.cc"

    if [ ! -d "${FABKIT_DIST_USER_PATH}" ]; then
        mkdir -p ${FABKIT_DIST_USER_PATH}
    fi

    log "Packing chaincode $chaincode_name version $chaincode_version from path $chaincode_path " info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer chaincode package dist/${filename} -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p $chaincode_remote_path -l $chaincode_language --cc-package --sign"
    else
        cmd+="peer chaincode package dist/${filename} -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p $chaincode_remote_path -l $chaincode_language --cc-package --sign --tls --cafile $ORDERER_CA"
    fi

    __exec_command "${cmd}"

    log "Chaincode package created in: ${FABKIT_DIST_USER_PATH}/${filename}" success
}

invoke() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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
    shift 4

    __set_chaincode_options invoke options $@
    __set_certs $org $peer
    __set_peer_exec cmd

    log "Invoking chaincode $chaincode_name on channel ${channel_name} as org${org} and peer${peer} with the following params '$options'" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer chaincode invoke -o $FABKIT_ORDERER_ADDRESS -C $channel_name -n $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --waitForEvent $options"
    else
        cmd+="peer chaincode invoke -o $FABKIT_ORDERER_ADDRESS -C $channel_name -n $chaincode_name --waitForEvent $options --peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${cmd}"
}

query() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
        exit 1
    fi

    log "================" info
    log "Chaincode: query" info
    log "================" info
    echo

    local channel_name="$1"
    local chaincode_name="$2"
    local org="$3"
    local peer="$4"
    local request="$5"
    shift 5

    __set_chaincode_options query options $@
    __set_certs $org $peer
    __set_peer_exec cmd

    log "Querying chaincode $chaincode_name on channel ${channel_name} as org${org} and peer${peer} with the following params '$request $@'" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer chaincode query -o $FABKIT_ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c '$request' $options"
    else
        cmd+="peer chaincode query -o $FABKIT_ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c '$request' $options --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${cmd}"
}

lc_query_package_id() {
    local chaincode_name="$1"
    local chaincode_version="$2"
    local org="$3"
    local peer="$4"
    shift 4

    __set_certs $org $peer
    __set_peer_exec cmd

    local chaincode_label="\"${chaincode_name}_${chaincode_version}\""

    log "Chaincode label: $chaincode_label" debug
    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer lifecycle chaincode queryinstalled --output json | jq -r '.installed_chaincodes[] | select(.label == ${chaincode_label})' | jq -r '.package_id'"
    else
        cmd+="peer lifecycle chaincode queryinstalled --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA --output json | jq -r '.installed_chaincodes[] | select(.label == ${chaincode_label})' | jq -r '.package_id'"
    fi

    export PACKAGE_ID=$(eval ${cmd})

    log "Package ID: $PACKAGE_ID" info
}

lc_chaincode_package() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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

    __set_chaincode_options package options $@
    __set_certs $org $peer
    __set_peer_exec cmd

    __set_chaincode_absolute_path $chaincode_relative_path chaincode_path
    __get_chaincode_language $chaincode_path chaincode_language

    if [ "${chaincode_language}" == "golang" ]; then
        __set_chaincode_module_main $chaincode_path result
        chaincode_path=$result
    fi

    __rename_chaincode_path_to_name $chaincode_path $chaincode_name result
    chaincode_path=$result

    __set_chaincode_remote_path $chaincode_path $chaincode_language chaincode_remote_path

    log "Packaging chaincode $chaincode_name version $chaincode_version from path $chaincode_path" info

    cmd+="peer lifecycle chaincode package ${chaincode_name}_${chaincode_version}.tar.gz --path $chaincode_remote_path --label ${chaincode_name}_${chaincode_version} --lang $chaincode_language $options"

    __exec_command "${cmd}"
}

lc_chaincode_install() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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

    __set_chaincode_options install options $@
    __set_certs $org $peer
    __set_peer_exec cmd

    log "Installing chaincode $chaincode_name version $chaincode_version" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer lifecycle chaincode install ${chaincode_name}_${chaincode_version}.tar.gz $options"
    else
        cmd+="peer lifecycle chaincode install ${chaincode_name}_${chaincode_version}.tar.gz $options --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${cmd}"
}

lc_chaincode_approve() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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

    __set_chaincode_options approve options $@
    # TODO: Accept as input or build dynamically
    local signature_policy='OR("Org1MSP.member","Org2MSP.member","Org3MSP.member")'

    log "Querying chaincode package ID" info
    lc_query_package_id $chaincode_name $chaincode_version $org $peer
    if [ -z "$PACKAGE_ID" ]; then
        log "Package ID is not defined" warning
        return
    fi

    __set_certs $org $peer
    __set_peer_exec cmd

    log "Approve chaincode for my organization" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer lifecycle chaincode approveformyorg --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --package-id $PACKAGE_ID --sequence $sequence_no --waitForEvent --signature-policy '${signature_policy}' $options"
    else
        cmd+="peer lifecycle chaincode approveformyorg --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --package-id $PACKAGE_ID --sequence $sequence_no --waitForEvent --signature-policy '${signature_policy}' $options --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA "
    fi

    __exec_command "${cmd}"
}

lc_chaincode_commit() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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

    __set_chaincode_options commit options $@

    # TODO: Accept as input or build dynamically
    local signature_policy='OR("Org1MSP.member","Org2MSP.member","Org3MSP.member")'

    if [ -z "$PACKAGE_ID" ]; then
        log "Package ID is not defined" warning

        log "Querying chaincode package ID" info
        lc_query_package_id $chaincode_name $chaincode_version $org $peer

        if [ -z "$PACKAGE_ID" ]; then
            log "Chaincode not installed on peer" error
        fi
    fi

    __set_certs $org $peer
    __set_peer_exec cmd

    log "Check whether the chaincode definition is ready to be committed" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer lifecycle chaincode checkcommitreadiness --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --sequence $sequence_no --output json --signature-policy '${signature_policy}' $options"
    else
        cmd+="peer lifecycle chaincode checkcommitreadiness --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --sequence $sequence_no --output json --signature-policy '${signature_policy}' $options --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
    fi
    __exec_command "${cmd}"

    log "Commit the chaincode definition to channel" info
    __set_peer_exec cmd
    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer lifecycle chaincode commit --channelID $channel_name --name $chaincode_name --version $chaincode_version --sequence $sequence_no --init-required --peerAddresses $CORE_PEER_ADDRESS --signature-policy '${signature_policy}' $options"
    else
        cmd+="peer lifecycle chaincode commit --channelID $channel_name --name $chaincode_name --version $chaincode_version --sequence $sequence_no --init-required  --signature-policy '${signature_policy}' $options --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
        forall=${cmd}
        for o in $(seq 1 ${FABKIT_ORGS}); do
            #TODO: Create from endorsement policy and make endorsement policy dynamic
            lc_query_package_id $chaincode_name $chaincode_version $o $peer
            if [ ! -z "$PACKAGE_ID" ]; then
                __set_certs $o $peer
                forall+=" --peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE "
            fi
        done
    fi
    __exec_command "${forall}"

    log "Query the chaincode definitions that have been committed to the channel" info

    __set_certs $org $peer
    __set_peer_exec cmd
    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer lifecycle chaincode querycommitted --channelID $channel_name --name $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --output json"
    else
        cmd+="peer lifecycle chaincode querycommitted --channelID $channel_name --name $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --output json --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE"
    fi
    __exec_command "${cmd}"

    log "Init the chaincode" info

    invoke $channel_name $chaincode_name $org $peer $@ --isInit
}

# TODO: Enable fabric options for chaincode deploy
lc_chaincode_deploy() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ] || [ -z "$7" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
        exit 1
    fi

    local chaincode_name="$1"
    local chaincode_version="$2"
    local chaincode_relative_path="$3"
    local channel_name="$4"
    local sequence_no="$5"
    local org="$6"
    local peer="$7"
    shift 7

    lc_chaincode_package $chaincode_name $chaincode_version $chaincode_relative_path $org $peer $@
    for o in $(seq 1 ${FABKIT_ORGS}); do
        lc_chaincode_install $chaincode_name $chaincode_version $o $peer $@
        lc_chaincode_approve $chaincode_name $chaincode_version $channel_name $sequence_no $o $peer $@
    done
    lc_chaincode_commit $chaincode_name $chaincode_version $channel_name $sequence_no $org $peer $@
}
