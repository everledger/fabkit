#!/usr/bin/env bash

init_and_create_channel() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local channel_name="$1"
    local org="$2"
    local peer="$3"

    __set_network_env

    msp_id=Org${org}MSP

    generate_channeltx "$channel_name" "$FABKIT_NETWORK_PATH" "$FABKIT_CONFIG_PATH" "$FABKIT_CRYPTOS_PATH" "$FABKIT_CONFIGTX_PROFILE_NETWORK" "$FABKIT_CONFIGTX_PROFILE_CHANNEL" "$msp_id"

    __spinner_formatter
    create_channel $@
}

create_channel() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local channel_name="$1"
    local org="$2"
    local peer="$3"

    loginfo "Creating channel ${channel_name} with org${org} peer${peer}"

    __clear_logdebu
    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer channel create -o $FABKIT_ORDERER_ADDRESS -c ${channel_name} -f $FABKIT_CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}_tx.pb --outputBlock $FABKIT_CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block"
    else
        cmd+="peer channel create -o $FABKIT_ORDERER_ADDRESS -c ${channel_name} -f $FABKIT_CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}_tx.pb --outputBlock $FABKIT_CHANNELS_CONFIG_PATH/${channel_name}/${channel_name}.block --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error creating channel $channel_name"
        exit 1
    fi
}

join_channel() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local channel_name="$1"
    local org="$2"
    local peer="$3"

    loginfo "Joining channel ${channel_name} with org${org} peer${peer}"

    __clear_logdebu
    __set_certs $org $peer
    __set_peer_exec cmd

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer channel join -b ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}.block"
    else
        cmd+="peer channel join -b ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${channel_name}.block --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error joining channel $channel_name"
        exit 1
    fi
}

update_channel() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local channel_name="$1"
    local org_msp="$2"
    local org="$3"
    local peer="$4"

    loginfo "Updating anchors on ${channel_name} with org${org} peer${peer}"

    __clear_logdebu
    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer channel update -o $FABKIT_ORDERER_ADDRESS -c ${channel_name} -f ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors_tx.pb"
    else
        cmd+="peer channel update -o $FABKIT_ORDERER_ADDRESS -c ${channel_name} -f ${FABKIT_CHANNELS_CONFIG_PATH}/${channel_name}/${org_msp}_anchors_tx.pb --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error updating channel $channel_name"
        exit 1
    fi
}
