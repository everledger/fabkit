#!/usr/bin/env bash

__check_fabric_version() {
    if [[ ! "${FABKIT_FABRIC_VERSION}" =~ ${1}.* ]]; then
        logerr "This command is not enabled on Fabric v${FABKIT_FABRIC_VERSION}. In order to run, run your network with the flag: -v|--version [version]"
        exit 1
    fi
}

__check_deps() {
    local docker_version="$(docker version --format '{{.Server.Version}}')"
    if ! (type -p docker &>/dev/null && [[ "((${docker_version//./}))" -ge "((${FABKIT_DOCKER_VERSION_SUPPORTED//./}))" ]]); then
        logerr "docker >= ${FABKIT_DOCKER_VERSION_SUPPORTED} is required"
        exit 1
    fi

    local docker_compose_version=$(docker-compose version --short)
    if ! (type -p docker-compose &>/dev/null && [[ "((${docker_compose_version//./}))" -ge "((${FABKIT_DOCKER_COMPOSE_VERSION_SUPPORTED//./}))" ]]); then
        logerr "docker-compose >= ${FABKIT_DOCKER_COMPOSE_VERSION_SUPPORTED} is required"
        exit 1
    fi
}

__check_docker_daemon() {
    if docker info --format '{{json .}}' | grep "Cannot connect" &>/dev/null; then
        logerr "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?"
        exit 1
    fi
}

# delete path recursively and asks for root permissions if needed
__delete_path() {
    if [[ ! -e "$1" ]]; then
        return
    fi

    if [[ -w "$1" ]]; then
        rm -rf "$1"
    else
        logerr "!!!!! ATTENTION !!!!!"
        logerr "Directory \"${1}\" requires superuser permissions"
        read -rp "Do you wish to continue? [yes/no=default] " yn
        case $yn in
        [Yy]*) sudo rm -rf "$1" ;;
        *) return ;;
        esac
    fi
}

__set_certs() {
    CORE_PEER_ADDRESS=peer${2}.org${1}.example.com:$((6 + ${1}))051
    CORE_PEER_LOCALMSPID=Org${1}MSP
    CORE_PEER_TLS_ENABLED=${FABKIT_TLS_ENABLED}
    CORE_PEER_TLS_CERT_FILE=${FABKIT_PEER_REMOTE_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/peers/peer${2}.org${1}.example.com/tls/server.crt
    CORE_PEER_TLS_KEY_FILE=${FABKIT_PEER_REMOTE_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/peers/peer${2}.org${1}.example.com/tls/server.key
    CORE_PEER_TLS_ROOTCERT_FILE=${FABKIT_PEER_REMOTE_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/peers/peer${2}.org${1}.example.com/tls/ca.crt
    CORE_PEER_MSPCONFIGPATH=${FABKIT_PEER_REMOTE_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/users/Admin@org${1}.example.com/msp
    ORDERER_CA=${FABKIT_PEER_REMOTE_BASEPATH}/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

    logdebu "Peer address: ${CORE_PEER_ADDRESS}"
    logdebu "Peer cert: ${CORE_PEER_TLS_CERT_FILE}"
}

__set_peer_exec() {
    local __result=$1
    local __cmd="docker exec -e CORE_PEER_ADDRESS=$CORE_PEER_ADDRESS \
            -e CORE_PEER_LOCALMSPID=$CORE_PEER_LOCALMSPID \
            -e CORE_PEER_TLS_ENABLED=$FABKIT_TLS_ENABLED \
            -e CORE_PEER_TLS_CERT_FILE=$CORE_PEER_TLS_CERT_FILE \
            -e CORE_PEER_TLS_KEY_FILE=$CORE_PEER_TLS_KEY_FILE \
            -e CORE_PEER_TLS_ROOTCERT_FILE=$CORE_PEER_TLS_ROOTCERT_FILE \
            -e CORE_PEER_MSPCONFIGPATH=$CORE_PEER_MSPCONFIGPATH \
            $FABKIT_CHAINCODE_UTIL_CONTAINER "

    eval $__result="'$__cmd'"
}

__timer() {
    local start_time="$1"
    local end_time="${2}"

    local elapsed_time="$((end_time - start_time))"

    echo -e "\n⏰ $(logsucc $((elapsed_time / 60))m$((elapsed_time % 60))s)"
}

__validate_params() {
    local version_exists=false
    for version in "${FABKIT_FABRIC_AVAILABLE_VERSIONS[@]}"; do
        if [ "$version" = "$FABKIT_FABRIC_VERSION" ]; then
            version_exists=true
        fi
    done
    if [ "$version_exists" = "false" ]; then
        logerr "Fabric version ${FABKIT_FABRIC_VERSION} does not exist. For the complete list of releases visit: https://github.com/hyperledger/fabric/tags"
        exit 1
    fi

    if [[ $FABKIT_ORGS -lt 1 ]]; then
        logerr "-o,--orgs cannot be lower than 1"
        exit 1
    fi
}

__set_lastrun() {
    if [ ! -f "$FABKIT_ROOT" ]; then
        mkdir -p "$FABKIT_ROOT"
    fi

    unset FABKIT_RESET
    unset FABKIT_QUICK_RUN
    (
        set -o posix
        set | grep "FABKIT_"
    ) >"$FABKIT_LASTRUN"

    __load_lastrun
}

__load_lastrun() {
    # shellcheck disable=SC1090
    source "$FABKIT_LASTRUN" &>/dev/null || true
}

__clean_user_path() {
    __delete_path "$FABKIT_LASTRUN"
    __delete_path "$FABKIT_LOGFILE"
}

__catch() {
    if [ "$1" == 0 ]; then
        return
    fi

    __print_to_file "$FABKIT_LOGFILE" "Caught error $1 in:" "[ERROR]"
    frame=0
    line="$(caller $frame 2>&1 | cut -d ' ' -f 1)"
    while [ -n "$line" ]; do
        subroutine="$(caller $frame 2>&1 | cut -d ' ' -f 2)"
        file="$(caller $frame 2>&1 | cut -d ' ' -f 3)"
        __print_to_file "$FABKIT_LOGFILE" "From $file:$line in $subroutine" "[ERROR]"
        __print_to_file "$FABKIT_LOGFILE" "\t$(sed -n "${line}"p "$file")" "[ERROR]"
        ((frame++)) || true
        line="$(caller "$frame" 2>&1 | cut -d ' ' -f 1)"
    done

    exit "$1"
}

__throw() {
    local input

    if [ -n "$1" ]; then
        input="$1"
        __clear_spinner && logerr "$input"
    else
        while read -r input; do
            __clear_spinner && logerr "$input"
        done
    fi
}
