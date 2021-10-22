#!/usr/bin/env bash

dep_install() {
    __check_param_chaincode "$1"
    loginfo "Installing chaincode dependencies"

    local chaincode_relative_path="$1"
    __set_chaincode_absolute_path "$chaincode_relative_path" chaincode_path
    __get_chaincode_language "$chaincode_path" chaincode_language

    if [ "$chaincode_language" = "golang" ]; then
        __check_go_version
        __init_go_mod install "$chaincode_path"
    else
        # TODO: [FND-115] dep_install extended to all languages
        logwarn "We only support Golang for now, sorry 😔"
    fi
}

dep_update() {
    __check_param_chaincode "$1"
    loginfo "Updating chaincode dependencies"

    local chaincode_relative_path="$1"
    __set_chaincode_absolute_path "$chaincode_relative_path" chaincode_path
    __get_chaincode_language "$chaincode_path" chaincode_language

    if [ "$chaincode_language" = "golang" ]; then
        __check_go_version
        __init_go_mod update "$chaincode_path"
    else
        # TODO: [FND-116] dep_update extended to all languages
        logwarn "We only support Golang for now, sorry 😔"
    fi
}

chaincode_test() {
    loginfo "Testing chaincode $1"

    __check_param_chaincode "$1"

    __clear_logdebu
    local chaincode_relative_path="$1"
    __set_chaincode_absolute_path "$chaincode_relative_path" chaincode_path
    local chaincode_name=$(basename "$chaincode_path")
    __get_chaincode_language "$chaincode_path" chaincode_language

    if [ "$chaincode_language" = "golang" ]; then
        __check_go_version
        # avoid "found no test suites" error
        if ! find "$chaincode_path" -type f -name "*_test*" ! -path "**/node_modules/*" ! -path "**/vendor/*" &>/dev/null; then
            logwarn "No test suites found. Skipping tests..."
            return
        fi

        __init_go_mod install "$chaincode_path"

        if ! (__run "$chaincode_path" go test ./... &>/dev/null); then
            logerr "Failed testing chaincode $chaincode_name"
            exit 1
        fi
    elif [ "$chaincode_language" = "node" ]; then
        if ! (__run "$chaincode_path" npm run test &>/dev/null); then
            logerr "Failed testing chaincode $chaincode_name"
            exit 1
        fi
    fi

    cd "$FABKIT_ROOT" || return
}

chaincode_build() {
    loginfo "Building chaincode $1"

    __check_param_chaincode "$1"

    __clear_logdebu
    local chaincode_relative_path="$1"
    __set_chaincode_absolute_path "$chaincode_relative_path" chaincode_path
    local chaincode_name=$(basename "$chaincode_path")
    __get_chaincode_language "$chaincode_path" chaincode_language

    if [ "$chaincode_language" = "golang" ]; then
        __check_go_version
        __init_go_mod install "$chaincode_path"

        if ! (__run "$chaincode_path" go build ./... &>/dev/null && rm -rf "${chaincode_path}/${chaincode_name}" &>/dev/null); then
            logerr "Failed building chaincode $chaincode_name"
            exit 1
        fi
    fi

    cd "$FABKIT_ROOT" || return
}

chaincode_install() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local chaincode_name="$1"
    local chaincode_version="$2"
    local chaincode_relative_path="$3"
    local org="$4"
    local peer="$5"
    shift 5

    loginfo "Installing chaincode ${chaincode_name}@${chaincode_version}"

    __clear_logdebu
    __set_chaincode_options install options "$@"
    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    __set_chaincode_absolute_path "$chaincode_relative_path" chaincode_path
    __get_chaincode_language "$chaincode_path" chaincode_language

    __rename_chaincode_path_to_name "$chaincode_path" "$chaincode_name" result
    chaincode_path=$result

    if [ "$chaincode_language" = "golang" ]; then
        __init_go_mod install "$chaincode_path"
    fi

    __chaincode_module_pack "$chaincode_path"

    __set_chaincode_remote_path "$chaincode_path" "$chaincode_language" chaincode_remote_path

    cmd+="peer chaincode install -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p $chaincode_remote_path -l $chaincode_language $options"

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        if [ "$chaincode_language" = "golang" ]; then
            __chaincode_module_restore "$chaincode_path"
        fi
        logerr "Error executing chaincode install"
        exit 1
    fi

    if [ "$chaincode_language" = "golang" ]; then
        __chaincode_module_restore "$chaincode_path"
    fi
}

chaincode_instantiate() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local chaincode_name="$1"
    local chaincode_version="$2"
    local channel_name="$3"
    local org="$4"
    local peer="$5"
    shift 5

    loginfo "Instantiating chaincode ${chaincode_name}@${chaincode_version} on channel $channel_name"

    __clear_logdebu
    __set_chaincode_options instantiate options "$@"
    __get_chaincode_language "${FABKIT_CHAINCODE_PATH}/${chaincode_name}" chaincode_language

    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer chaincode instantiate -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -C $channel_name -l $chaincode_language $options"
    else
        cmd+="peer chaincode instantiate -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -C $channel_name -l $chaincode_language $options --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error instatiating chaincode $chaincode_name"
        exit 1
    fi
}

chaincode_upgrade() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local chaincode_name="$1"
    local chaincode_version="$2"
    local channel_name="$3"
    local org="$4"
    local peer="$5"
    shift 5

    loginfo "Upgrading chaincode $chaincode_name to version $chaincode_version on channel ${channel_name}"

    __clear_logdebu
    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    __set_chaincode_options upgrade options "$@"
    __get_chaincode_language "${FABKIT_CHAINCODE_PATH}/${chaincode_name}" chaincode_language

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C $channel_name -l $chaincode_language $options"
    else
        cmd+="peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C $channel_name -l $chaincode_language $options --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error upgrading chaincode $chaincode_name"
        exit 1
    fi
}

chaincode_zip() {
    type zip >/dev/null 2>&1 || {
        logerr >&2 "zip required but it is not installed. Aborting."
        exit 1
    }
    type rsync >/dev/null 2>&1 || {
        logerr >&2 "rsync required but it is not installed. Aborting."
        exit 1
    }

    __check_param_chaincode "$1"

    loginfo "Zipping chaincode $1"

    __clear_logdebu
    local chaincode_relative_path="$1"
    __set_chaincode_absolute_path "$chaincode_relative_path" chaincode_path
    __get_chaincode_language "$chaincode_path" chaincode_language

    if [ "$chaincode_language" = "golang" ]; then
        __delete_path "${chaincode_path}/vendor" &>/dev/null
        __init_go_mod install "$chaincode_path"
        __chaincode_module_pack "$chaincode_path"
    fi

    local chaincode_name=$(basename "$chaincode_path")
    local timestamp=$(date +%Y-%m-%d-%H-%M-%S)
    local filename="${chaincode_name}_${timestamp}.zip"

    if [ ! -d "${FABKIT_DIST_PATH}" ]; then
        mkdir -p "$FABKIT_DIST_PATH"
    fi

    cd "$chaincode_path" && zip -rq "${FABKIT_DIST_PATH}/${filename}" . || {
        logerr "Error creating chaincode archive"
        if [[ "$chaincode_language" = "golang" && -d ${FABKIT_ROOT}/.${chaincode_name}.bak ]]; then
            __chaincode_module_restore "$chaincode_path"
        fi
        exit 1
    }

    if [[ "$chaincode_language" = "golang" && -d ${FABKIT_ROOT}/.${chaincode_name}.bak ]]; then
        __chaincode_module_restore "$chaincode_path"
    fi

    echo "Chaincode archive created in: $(logsucc "${FABKIT_DIST_PATH}/${filename}")"
}

chaincode_pack() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    type rsync >/dev/null 2>&1 || {
        logerr >&2 "rsync required but it is not installed. Aborting."
        exit 1
    }

    __check_param_chaincode "$1"

    loginfo "Packing chaincode $1"

    __clear_logdebu
    local chaincode_name="$1"
    local chaincode_version="$2"
    local chaincode_relative_path="$3"
    local org="$4"
    local peer="$5"
    shift 5

    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    __set_chaincode_absolute_path "$chaincode_relative_path" chaincode_path
    __get_chaincode_language "$chaincode_path" chaincode_language
    __set_chaincode_remote_path "$chaincode_path" "$chaincode_language" chaincode_remote_path

    if [ "$chaincode_language" = "golang" ]; then
        __delete_path "${chaincode_path}/vendor" &>/dev/null
        __init_go_mod install "$chaincode_path"
        __chaincode_module_pack "$chaincode_path"
    fi

    local chaincode_name=$(basename "$chaincode_path")
    local timestamp=$(date +%Y-%m-%d-%H-%M-%S)
    local filename="${chaincode_name}@${chaincode_version}_${timestamp}.cc"

    if [ ! -d "$FABKIT_DIST_PATH" ]; then
        mkdir -p "$FABKIT_DIST_PATH"
    fi

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer chaincode package dist/${filename} -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p $chaincode_remote_path -l $chaincode_language --cc-package --sign"
    else
        cmd+="peer chaincode package dist/${filename} -o $FABKIT_ORDERER_ADDRESS -n $chaincode_name -v $chaincode_version -p $chaincode_remote_path -l $chaincode_language --cc-package --sign --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error executing chaincode pack"
        if [[ "$chaincode_language" = "golang" && -d ${FABKIT_ROOT}/.${chaincode_name}.bak ]]; then
            __chaincode_module_restore "$chaincode_path"
        fi
        exit 1
    fi

    if [[ "$chaincode_language" = "golang" && -d ${FABKIT_ROOT}/.${chaincode_name}.bak ]]; then
        __chaincode_module_restore "$chaincode_path"
    fi

    echo "Chaincode package created in: $(logsucc "${FABKIT_DIST_PATH}/${filename}")"
}

chaincode_invoke() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local channel_name="$1"
    local chaincode_name="$2"
    local org="$3"
    local peer="$4"
    shift 4

    loginfo "Invoking chaincode $chaincode_name on channel ${channel_name} as org${org} and peer${peer} with the following params: $* "

    __clear_logdebu
    __set_chaincode_options invoke options "$@"
    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer chaincode invoke -o $FABKIT_ORDERER_ADDRESS -C $channel_name -n $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --waitForEvent $options"
    else
        cmd+="peer chaincode invoke -o $FABKIT_ORDERER_ADDRESS -C $channel_name -n $chaincode_name --waitForEvent $options --peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error invoking chaincode $chaincode_name"
        exit 1
    fi
}

chaincode_query() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local channel_name="$1"
    local chaincode_name="$2"
    local org="$3"
    local peer="$4"
    local request="$5"
    shift 5

    __clear_logdebu
    __set_chaincode_options query options "$@"
    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    loginfo "Querying chaincode $chaincode_name on channel ${channel_name} as org${org} and peer${peer} with the following params '${request} $*'"

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer chaincode query -o $FABKIT_ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c '$request' $options"
    else
        cmd+="peer chaincode query -o $FABKIT_ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c '$request' $options --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    local query=$(eval "$cmd" 2>&1)
    if echo "$query" | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error invoking chaincode $chaincode_name"
        exit 1
    else
        if [ -n "$query" ]; then
            echo -en "\n\n"
            tojson "$query"
            echo
        else
            echo -e "\nNo results"
        fi
    fi
}

lifecycle_chaincode_package_id() {
    local chaincode_name="$1"
    local chaincode_version="$2"
    local org="$3"
    local peer="$4"
    shift 4

    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    logdebu "Retrieving package id"

    local chaincode_label="\"${chaincode_name}_${chaincode_version}\""
    logdebu "Chaincode label: $chaincode_label"

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer lifecycle chaincode queryinstalled --output json"
    else
        cmd+="peer lifecycle chaincode queryinstalled --tls --cafile $ORDERER_CA --output json"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    export PACKAGE_ID=$(eval "$cmd" | __run "$FABKIT_ROOT" jq -r "'.installed_chaincodes[] | select(.label == ${chaincode_label})'" | __run "$FABKIT_ROOT" jq -r '.package_id')
    if echo "$PACKAGE_ID" | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error retrieving package id for chaincode $chaincode_name"
        exit 1
    fi

    logdebu "Package ID: $PACKAGE_ID"
}

lifecycle_chaincode_package() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local chaincode_name="$1"
    local chaincode_version="$2"
    local chaincode_relative_path="$3"
    local org="$4"
    local peer="$5"
    shift 5

    loginfo "Packaging chaincode ${chaincode_name}@${chaincode_version}"

    __clear_logdebu
    __set_chaincode_options package options "$@"
    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    __set_chaincode_absolute_path "$chaincode_relative_path" chaincode_path
    __get_chaincode_language "$chaincode_path" chaincode_language

    __rename_chaincode_path_to_name "$chaincode_path" "$chaincode_name" result
    chaincode_path=$result

    if [ "$chaincode_language" = "golang" ]; then
        __init_go_mod install "$chaincode_path"
    fi

    __chaincode_module_pack "$chaincode_path"

    __set_chaincode_remote_path "$chaincode_path" "$chaincode_language" chaincode_remote_path

    cmd+="peer lifecycle chaincode package ${chaincode_name}_${chaincode_version}.tar.gz --path $chaincode_remote_path --label ${chaincode_name}_${chaincode_version} --lang $chaincode_language $options"

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error executing chaincode package"
        if [[ "$chaincode_language" = "golang" && -d ${FABKIT_ROOT}/.${chaincode_name}.bak ]]; then
            __chaincode_module_restore "$chaincode_path"
        fi
        exit 1
    fi

    if [[ "$chaincode_language" = "golang" && -d ${FABKIT_ROOT}/.${chaincode_name}.bak ]]; then
        __chaincode_module_restore "$chaincode_path"
    fi
}

lifecycle_chaincode_install() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local chaincode_name="$1"
    local chaincode_version="$2"
    local org="$3"
    local peer="$4"
    shift 4

    loginfo "Installing chaincode ${chaincode_name}@${chaincode_version}"

    __clear_logdebu
    __set_chaincode_options install options "$@"
    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer lifecycle chaincode install ${chaincode_name}_${chaincode_version}.tar.gz $options"
    else
        cmd+="peer lifecycle chaincode install ${chaincode_name}_${chaincode_version}.tar.gz $options --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error installing chaincode $chaincode_name"
        exit 1
    fi
}

lifecycle_chaincode_approve() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local chaincode_name="$1"
    local chaincode_version="$2"
    local channel_name="$3"
    local sequence_no="$4"
    local org="$5"
    local peer="$6"
    shift 6

    loginfo "Approve chaincode ${chaincode_name}@${chaincode_version} on channel $channel_name for org${org}"

    __clear_logdebu
    __set_chaincode_options approve options "$@"
    # TODO: Accept as input or build dynamically
    local signature_policy='OR("Org1MSP.member","Org2MSP.member","Org3MSP.member")'

    logdebu "Querying chaincode package ID"
    lifecycle_chaincode_package_id "$chaincode_name" "$chaincode_version" "$org" "$peer"
    if [ -z "$PACKAGE_ID" ]; then
        logdebu "Package ID is not defined"
        return
    fi

    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer lifecycle chaincode approveformyorg --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --package-id $PACKAGE_ID --sequence $sequence_no --waitForEvent --signature-policy '${signature_policy}' $options"
    else
        cmd+="peer lifecycle chaincode approveformyorg --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --package-id $PACKAGE_ID --sequence $sequence_no --waitForEvent --signature-policy '${signature_policy}' $options --tls --cafile $ORDERER_CA"
    fi

    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error approving chaincode $chaincode_name"
        exit 1
    fi
}

lifecycle_chaincode_commit() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
        exit 1
    fi

    local chaincode_name="$1"
    local chaincode_version="$2"
    local channel_name="$3"
    local sequence_no="$4"
    local org="$5"
    local peer="$6"
    shift 6

    loginfo "Commit the chaincode definition ${chaincode_name}:${chaincode_version} to channel $channel_name"

    __clear_logdebu
    __set_chaincode_options commit options "$@"

    # TODO: Accept as input or build dynamically
    local signature_policy='OR("Org1MSP.member","Org2MSP.member","Org3MSP.member")'

    if [ -z "$PACKAGE_ID" ]; then
        logdebu "Package ID is not defined"
        logdebu "Querying chaincode package ID"
        lifecycle_chaincode_package_id "$chaincode_name" "$chaincode_version" "$org" "$peer"

        if [ -z "$PACKAGE_ID" ]; then
            logwarn "Chaincode not installed on peer"
        fi
    fi

    __set_certs "$org" "$peer"
    __set_peer_exec cmd

    logdebu "Check whether the chaincode definition is ready to be committed"
    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer lifecycle chaincode checkcommitreadiness --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --sequence $sequence_no --output json --signature-policy '${signature_policy}' $options"
    else
        cmd+="peer lifecycle chaincode checkcommitreadiness --channelID $channel_name --name $chaincode_name --version $chaincode_version --init-required --sequence $sequence_no --output json --signature-policy '${signature_policy}' $options --tls --cafile $ORDERER_CA"
    fi
    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error checking commit readiness for chaincode $chaincode_name"
        exit 1
    fi

    __set_peer_exec cmd
    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer lifecycle chaincode commit --channelID $channel_name --name $chaincode_name --version $chaincode_version --sequence $sequence_no --init-required --peerAddresses $CORE_PEER_ADDRESS --signature-policy '${signature_policy}' $options"
    else
        cmd+="peer lifecycle chaincode commit --channelID $channel_name --name $chaincode_name --version $chaincode_version --sequence $sequence_no --init-required  --signature-policy '${signature_policy}' $options --tls --cafile $ORDERER_CA"
        forall=${cmd}
        for o in $(seq 1 "$FABKIT_ORGS"); do
            #TODO: Create from endorsement policy and make endorsement policy dynamic
            lifecycle_chaincode_package_id "$chaincode_name" "$chaincode_version" "$o" "$peer"
            if [ -n "$PACKAGE_ID" ]; then
                __set_certs "$o" "$peer"
                forall+=" --peerAddresses $CORE_PEER_ADDRESS --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE "
            fi
        done
    fi
    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "${forall}") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error committing chaincode $chaincode_name"
        exit 1
    fi

    logdebu "Query the chaincode definitions that have been committed to the channel"
    __set_certs "$org" "$peer"
    __set_peer_exec cmd
    if [ "${FABKIT_TLS_ENABLED:-}" = "false" ]; then
        cmd+="peer lifecycle chaincode querycommitted --channelID $channel_name --name $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --output json"
    else
        cmd+="peer lifecycle chaincode querycommitted --channelID $channel_name --name $chaincode_name --peerAddresses $CORE_PEER_ADDRESS --output json --tls --cafile $ORDERER_CA --tlsRootCertFiles $CORE_PEER_TLS_ROOTCERT_FILE"
    fi
    __clear_logdebu
    logdebu "Excecuting command: ${cmd}"
    if (eval "$cmd") 2>&1 >/dev/null | grep -iE "erro|pani|fail|fatal" > >(__throw >&2); then
        logerr "Error querying committed chaincode $chaincode_name"
        exit 1
    fi

    logdebu "Init the chaincode"
    __clear_spinner
    echo -en "\n\033[6C→ "
    chaincode_invoke "$channel_name" "$chaincode_name" "$org" "$peer" "$@" --isInit
}

# TODO: Enable fabric options for chaincode deploy
lifecycle_chaincode_deploy() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ] || [ -z "$7" ]; then
        logerr "Incorrect usage of ${FUNCNAME[0]}. Please consult the help: fabkit help"
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

    (lifecycle_chaincode_package "$chaincode_name" "$chaincode_version" "$chaincode_relative_path" "$org" "$peer" "$@") &
    __spinner
    for o in $(seq 1 "$FABKIT_ORGS"); do
        (lifecycle_chaincode_install "$chaincode_name" "$chaincode_version" "$o" "$peer" "$@") &
        __spinner
        (lifecycle_chaincode_approve "$chaincode_name" "$chaincode_version" "$channel_name" "$sequence_no" "$o" "$peer" "$@") &
        __spinner
    done
    (lifecycle_chaincode_commit "$chaincode_name" "$chaincode_version" "$channel_name" "$sequence_no" "$org" "$peer" "$@") &
    __spinner
}

__check_param_chaincode() {
    if [ -z "$1" ]; then
        logerr "Chaincode name missing"
        exit 1
    fi
}

__chaincode_module_restore() {
    local chaincode_path=$1
    local chaincode_name="$(basename "$chaincode_path")"

    if [ -d "${FABKIT_ROOT}/.${chaincode_name}.bak" ]; then
        rm -r "$chaincode_path"
        mv "${FABKIT_ROOT}/.${chaincode_name}.bak" "$chaincode_path"
    fi
}

__set_chaincode_module_main() {
    local __chaincode_path=$1
    local __result=$2

    __init_go_mod install "$__chaincode_path"
    # Golang: workaround for chaincode written as modules
    # make the install to work when main files are not in the main directory but in cmd
    if [[ ! $(find "$__chaincode_path" -type f -name 'main.go' -maxdepth 1 2>/dev/null) && -d "${__chaincode_path}/cmd" ]]; then
        __chaincode_path+="/cmd"
    fi

    # shellcheck disable=SC2086
    eval $__result="'$__chaincode_path'"
}

__init_go_mod() {
    local operation=$1
    local chaincode_relative_path=$2

    cd "${chaincode_relative_path}" >/dev/null 2> >(__throw >&2) || exit 1

    if [ ! -f "./go.mod" ]; then
        if ! __run "${chaincode_relative_path}" go mod init &>/dev/null; then
            logerr "Error initializing go mod"
            exit 1
        fi
    fi

    if [ "${operation}" = "install" ]; then
        if ! __run "${chaincode_relative_path}" go get ./... &>/dev/null; then
            logerr "Error installing go modules"
            exit 1
        fi
    elif [ "${operation}" = "update" ]; then
        if ! __run "${chaincode_relative_path}" go get -u=patch ./... &>/dev/null; then
            logerr "Error updating go modules"
            exit 1
        fi
    fi

    if ! __run "${chaincode_relative_path}" go mod tidy &>/dev/null; then
        logerr "Error running go mod tidy"
        exit 1
    fi
    if ! __run "${chaincode_relative_path}" go mod vendor &>/dev/null; then
        logerr "Error downloading go vendor"
        exit 1
    fi

    cd "$FABKIT_ROOT" || return
}

__get_chaincode_language() {
    if [ -z "$1" ]; then
        logerr "Missing chaincode relative path in argument"
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
        logerr "Error cannot determine chaincode language"
        exit 1
    fi

    logdebu "Chaincode language: $__chaincode_language"

    eval $__result="'$__chaincode_language'"
}

__copy_user_chaincode() {
    local chaincode_absolute_path=$1
    local chaincode_internal_path="$(find "$FABKIT_CHAINCODE_PATH" -type d -maxdepth 1 -iname "$(basename "$chaincode_absolute_path")")"

    if ! [[ -d $chaincode_absolute_path || -d $chaincode_internal_path ]]; then
        logerr "Path does not exist: ${chaincode_absolute_path}"
        exit 1
    fi

    if [[ ! -d ${FABKIT_CHAINCODE_PATH} ]]; then
        mkdir -p "$FABKIT_CHAINCODE_PATH"
    fi

    if [[ ! "$chaincode_absolute_path" =~ ^/ && -d $chaincode_internal_path ]]; then
        chaincode_absolute_path=$chaincode_internal_path
    fi

    rsync -aur --exclude='vendor' --exclude='node_modules' "$chaincode_absolute_path" "$FABKIT_CHAINCODE_PATH" || exit 1
}

__set_chaincode_absolute_path() {
    local __chaincode_relative_path=$1
    local __result=$2

    __copy_user_chaincode "$__chaincode_relative_path"

    local __chaincode_path="${FABKIT_CHAINCODE_PATH}/$(basename "${__chaincode_relative_path}")"

    logdebu "Chaincode absolute path: ${__chaincode_path}"

    eval $__result="'$__chaincode_path'"
}

__set_chaincode_remote_path() {
    local __chaincode_relative_path=$1
    local __chaincode_language=$2
    local __result=$3

    local __chaincode_name=$(basename "$__chaincode_relative_path")

    if [ "$__chaincode_language" = "golang" ]; then
        # Fabric versions prior 2.x require a relative path to be set in order to correctly deploy chaincodes
        if [[ "${FABKIT_FABRIC_VERSION}" =~ ^1.* ]]; then
            case $FABKIT_CHAINCODE_REMOTE_PATH/ in
            /opt/gopath/src/*)
                local __chaincode_remote_path="${FABKIT_CHAINCODE_REMOTE_PATH#/opt/gopath/src/}/${__chaincode_name}"
                ;;
            *)
                logerr "Chaincode not mounted in gopath"
                exit 1
                ;;
            esac
        else
            local __chaincode_remote_path="${FABKIT_CHAINCODE_REMOTE_PATH}/${__chaincode_name}"
        fi

        if [[ ! $(find "$__chaincode_relative_path" -type f -name '*.go' -maxdepth 1 2>/dev/null) && -d "${__chaincode_relative_path}/cmd" ]]; then
            __chaincode_remote_path+="/cmd"
        fi
    # TODO: complete for each supported chaincode language
    else
        local __chaincode_remote_path="${FABKIT_CHAINCODE_REMOTE_PATH}/${__chaincode_name}"
    fi

    logdebu "Chaincode remote path: ${__chaincode_remote_path}"

    eval $__result="'$__chaincode_remote_path'"
}

__rename_chaincode_path_to_name() {
    local __chaincode_path=$1
    local __chaincode_name=$2
    local __result=$3
    local __output_path="${__chaincode_path%/chaincodes/*}/chaincodes/${__chaincode_name}"

    if [[ "$__chaincode_path" != "$__output_path" ]]; then
        rm -rf "$__output_path" &>/dev/null
        mv "$__chaincode_path" "$__output_path" &>/dev/null
    fi

    eval $__result="'$__output_path'"
}

__set_chaincode_options() {
    local operation=$1
    local __result=$2
    local __options=""
    local is_args_set=false
    shift 2

    in="$*"
    logdebu "Chaincode params: $in"

    # TODO: Offer support for multiple options
    while [[ $# -gt 0 ]]; do
        param=$1

        case $param in
        *"{\"Args\":"*)
            if [[ "$operation" =~ ^(invoke|instantiate|upgrade)$ ]]; then
                __options=" -c $(tostring "$param")"
                is_args_set=true
            fi
            shift
            ;;
        -c | --ctor)
            if [[ "$operation" =~ ^(invoke|instantiate|upgrade)$ ]]; then
                __options+=" $param $(tostring "$2")"
                is_args_set=true
            fi
            shift 2
            ;;
        -C | --collections-config | --channelID | --connectionProfile)
            if [[ "$operation" =~ ^(instantiate|upgrade|commit|approve)$ ]]; then
                __options+=" $param $(tostring "$2")"
            fi
            shift 2
            ;;
        -P | --policy)
            if [[ "$operation" =~ ^(instantiate|upgrade)$ ]]; then
                __options+=" $param \"$(tostring "$2")\""
            fi
            shift 2
            ;;
        *)
            __options+=" $(tostring "$param")"
            shift
            ;;
        esac
    done

    if [[ "$operation" =~ ^(invoke|instantiate|upgrade)$ ]] && [ "${is_args_set}" = "false" ]; then
        __options+=' -c "{\"Args\":[]}"'
    fi

    logdebu "Chaincode options: $__options"

    eval $__result="'$__options'"
}

__chaincode_module_pack() {
    local chaincode_path=$1
    trap '__chaincode_module_restore "$chaincode_path"' SIGINT SIGTERM SIGHUP EXIT QUIT

    if [[ ! $(find "$chaincode_path" -type f -name 'main.go' -maxdepth 1 2>/dev/null) && -d "${chaincode_path}/cmd" ]]; then
        # trick to allow chaincode packed as modules to work when deployed against remote environments
        logdebu "Copying chaincode files into vendor..."
        chaincode_name=$(basename "$chaincode_path")
        rsync -ar "${chaincode_path}/" "${FABKIT_ROOT}/.${chaincode_name}.bak"
        rsync -r --ignore-existing --exclude='vendor' --exclude='*.mod' --exclude='*.sum' "${chaincode_path}/cmd/" "$chaincode_path"
        rm -rf "${chaincode_path}/cmd"
        __module=$(awk <"${chaincode_path}/go.mod" '($1 ~ /module/) {print $2}')
        mkdir -p "${chaincode_path}/vendor/${__module}"
        rsync -ar --exclude='vendor' --exclude='META-INF' "${chaincode_path}/" "${chaincode_path}/vendor/${__module}"
    fi
}
