#!/usr/bin/env bash

loghead() {
    echo -en "\033[1;35m${1}\033[0m"
}

logerr() {
    echo -en "\033[1;31m${1}\033[0m"
}

logsucc() {
    echo -en "\033[1;32m${1}\033[0m"
}

logwarn() {
    echo -en "\033[1;33m${1}\033[0m"
}

loginfo() {
    echo -en "\033[1;34m${1}\033[0m"
}

logdebu() {
    if [ -z "${FABKIT_DEBUG}" ] || [ "${FABKIT_DEBUG}" == "false" ]; then return; fi
    echo -en "\033[1;36m${1}\033[0m"
}

__check_fabric_version() {
    if [[ ! "${FABKIT_FABRIC_VERSION}" =~ ${1}.* ]]; then
        logerr "This command is not enabled on Fabric v${FABKIT_FABRIC_VERSION}. In order to run, run your network with the flag: -v|--version [version]\n"
        exit 1
    fi
}

__check_deps() {
    if [ "${1}" == "deploy" ]; then
        type docker >/dev/null 2>&1 || {
            logerr >&2 "docker required but it is not installed. Aborting.\n"
            exit 1
        }
        type docker-compose >/dev/null 2>&1 || {
            logerr >&2 "docker-compose required but it is not installed. Aborting.\n"
            exit 1
        }
    elif [ "${1}" == "test" ]; then
        type go >/dev/null 2>&1 || {
            logwarn >&2 "Go binary is missing in your PATH. Running the dockerised version...\n"
            echo $?
        }
    fi
}

__check_docker_daemon() {
    if [ "$(docker info --format '{{json .}}' | grep "Cannot connect" 2>/dev/null)" ]; then
        logerr "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?\n"
        exit 1
    fi
}

# delete path recursively and asks for root permissions if needed
__delete_path() {
    if [ ! -d "$1" ]; then
        logdebu "Directory \"${1}\" does not exist. Skipping delete. All good :)\n"
        return
    fi

    if [ -w "$1" ]; then
        rm -rf "$1"
    else
        logerr "!!!!! ATTENTION !!!!!\n"
        logerr "Directory \"${1}\" requires superuser permissions\n"
        read -rp "Do you wish to continue? [yes/no=default] " yn
        case $yn in
        [Yy]*) sudo rm -rf "$1" ;;
        *) return 0 ;;
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

    logdebu "===========================================\n"
    logdebu "Peer address: ${CORE_PEER_ADDRESS}\n"
    logdebu "Peer cert: ${CORE_PEER_TLS_CERT_FILE}\n"
    logdebu "===========================================\n"
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

__exec_command() {
    logdebu "\nExcecuting command: \n\n"
    local message="$1"
    logdebu "${message}\n\n"
    # TODO: Return error and let the caller to handle it
    eval "$message &>/dev/null"
}

__timer() {
    local start_time="${1}"
    local end_time="${2}"

    local elapsed_time="$((end_time - start_time))"

    echo -e "\n\n⏰ : $(logsucc $((elapsed_time / 60))m$((elapsed_time % 60))s)"
}

__validate_params() {
    local version_exists=false
    for version in "${FABKIT_FABRIC_AVAILABLE_VERSIONS[@]}"; do
        if [ "$version" == "$FABKIT_FABRIC_VERSION" ]; then
            version_exists=true
        fi
    done
    if [ "$version_exists" == "false" ]; then
        logerr "Fabric version ${FABKIT_FABRIC_VERSION} does not exist. For the complete list of releases visit: https://github.com/hyperledger/fabric/tags\n"
        exit 1
    fi

    if [[ $FABKIT_ORGS -lt 1 ]]; then
        logerr "-o,--orgs cannot be lower than 1\n"
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
    ) >"${FABKIT_ROOT}/.lastrun"

    __load_lastrun
}

__load_lastrun() {
    source "${FABKIT_ROOT}/.lastrun" 2>/dev/null
}

__clean_user_path() {
    __delete_path ${FABKIT_ROOT}/.lastrun
}

tostring() {
    echo "$@" | __jq tostring 2>/dev/null ||
        # TODO: fix this
        echo
    echo "${@//\"/\\\"}"
}

tojson() {
    echo "$@" | __jq .
}

cursor_back() {
    echo -en "\033[$1D"
}

keep_me_busy() {
    local LC_CTYPE=C
    local pid=$!
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local charwidth=3

    echo -en "\033[3C→ "
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        tput civis
        local i=$(((i + charwidth) % ${#spin}))
        printf "%s" "${spin:$i:$charwidth}"
        cursor_back 1
        sleep .1
    done

    tput cnorm
    if wait "$pid"; then
        echo " ✅"
    else
        echo " ❌"
        exit 1
    fi

    return $?
}
