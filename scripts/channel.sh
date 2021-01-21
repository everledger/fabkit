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

    __set_certs $org $peer
    __set_peer_exec cmd

    log "Creating channel ${channel_name} using configuration file ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}_tx.pb" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer channel create -o $FABKIT_ORDERER_ADDRESS -c ${channel_name} -f $FABKIT_CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}_tx.pb --outputBlock $FABKIT_CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block"
    else
        cmd+="peer channel create -o $FABKIT_ORDERER_ADDRESS -c ${channel_name} -f $FABKIT_CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}_tx.pb --outputBlock $FABKIT_CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${cmd}"
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

    __set_certs $org $peer
    __set_peer_exec cmd

    log "Joining channel ${channel_name}" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer channel join -b ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}.block"
    else
        cmd+="peer channel join -b ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}.block --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${cmd}"
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

    __set_certs $org $peer
    __set_peer_exec cmd

    log "Updating anchors peers on ${channel_name} using configuration file ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors.tx" info

    if [ -z "$FABKIT_TLS_ENABLED" ] || [ "$FABKIT_TLS_ENABLED" == "false" ]; then
        cmd+="peer channel update -o $FABKIT_ORDERER_ADDRESS -c ${channel_name} -f ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors_tx.pb"
    else
        cmd+="peer channel update -o $FABKIT_ORDERER_ADDRESS -c ${channel_name} -f ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors_tx.pb --tls $FABKIT_TLS_ENABLED --cafile $ORDERER_CA"
    fi

    __exec_command "${cmd}"
}