#!/usr/bin/env bash

__check_fabric_version() {
    if [[ ! "${FABRIC_VERSION}" =~ ${1}.* ]]; then
        log "This command is not enabled on Fabric v${FABRIC_VERSION}. In order to run, update the FABRIC_VERSION value in .env file" error
        exit 1
    fi
}

__check_deps() {
    if [ "${1}" == "deploy" ]; then
        type docker >/dev/null 2>&1 || {
            log >&2 "docker required but it is not installed. Aborting." error
            exit 1
        }
        type docker-compose >/dev/null 2>&1 || {
            log >&2 "docker-compose required but it is not installed. Aborting." error
            exit 1
        }
    elif [ "${1}" == "test" ]; then
        type go >/dev/null 2>&1 || {
            log >&2 "Go binary is missing in your PATH. Running the dockerised version..." warning
            echo $?
        }
    fi
}

__check_docker_daemon() {
    if [ "$(docker info --format '{{json .}}' | grep "Cannot connect" 2>/dev/null)" ]; then
        log "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" error
        exit 1
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
        [Yy]*) sudo rm -rf ${1} ;;
        *) return 0 ;;
        esac
    fi
}

set_certs() {
    CORE_PEER_ADDRESS=peer${2}.org${1}.example.com:$((6 + ${1}))051
    CORE_PEER_LOCALMSPID=Org${1}MSP
    CORE_PEER_TLS_ENABLED=false
    CORE_PEER_TLS_CERT_FILE=${PEER_REMOTE_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/peers/peer${2}.org${1}.example.com/tls/server.crt
    CORE_PEER_TLS_KEY_FILE=${PEER_REMOTE_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/peers/peer${2}.org${1}.example.com/tls/server.key
    CORE_PEER_TLS_ROOTCERT_FILE=${PEER_REMOTE_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/peers/peer${2}.org${1}.example.com/tls/ca.crt
    CORE_PEER_MSPCONFIGPATH=${PEER_REMOTE_BASEPATH}/crypto/peerOrganizations/org${1}.example.com/users/Admin@org${1}.example.com/msp
    ORDERER_CA=${PEER_REMOTE_BASEPATH}/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

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
    local message=$1
    log "$message" debug
    echo

    eval "$message || exit 1"
}

__timer() {
    local start_time="${1}"
    local end_time="${2}"

    local elapsed_time="$(($end_time - $start_time))"
    
    log "\nTotal elapsed time: $(($elapsed_time / 60))m$(($elapsed_time % 60))s" debug
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
    header) colour_code="\033[1;35m" ;;
    error) colour_code="\033[1;31m" ;;
    success) colour_code="\033[1;32m" ;;
    warning) colour_code="\033[1;33m" ;;
    info) colour_code="\033[1;34m" ;;
    debug)
        if [ -z "${DEBUG}" ] || [ "${DEBUG}" == "false" ]; then return; fi
        colour_code="\033[1;36m"
        ;;
    *) colour_code=${default_colour} ;;
    esac

    # Print out the message and reset
    echo -e "${colour_code}${message}${default_colour}"
}

tostring() {
    echo "$@" | __jq tostring 2>/dev/null || echo ${@//\"/\\\"}
}

tojson() {
    echo "$@" | __jq .
}
