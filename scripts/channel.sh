#!/usr/bin/env bash

create_channel() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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
        PEER_EXEC+="peer channel create -o $ORDERER_ADDRESS -c ${channel_name} -f $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}_tx.pb --outputBlock $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block"
    else
        PEER_EXEC+="peer channel create -o $ORDERER_ADDRESS -c ${channel_name} -f $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}_tx.pb --outputBlock $CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block --tls $TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${PEER_EXEC}"
}

join_channel() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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
        PEER_EXEC+="peer channel join -b ${CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}.block"
    else
        PEER_EXEC+="peer channel join -b ${CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}.block --tls $TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${PEER_EXEC}"
}

update_channel() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        log "Incorrect usage of $FUNCNAME. Please consult the help: fabkit help" error
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
        PEER_EXEC+="peer channel update -o $ORDERER_ADDRESS -c ${channel_name} -f ${CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors_tx.pb"
    else
        PEER_EXEC+="peer channel update -o $ORDERER_ADDRESS -c ${channel_name} -f ${CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors_tx.pb --tls $TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${PEER_EXEC}"
}
