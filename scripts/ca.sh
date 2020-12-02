#!/usr/bin/env bash

register_user() {
    log "=================" info
    log "CA User: register" info
    log "=================" info
    echo

    __ca_setup register

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${FABRIC_CA_VERSION} \
        sh -c " \
        fabric-ca-client register -d \
            --home /crypto-config \
            --mspdir ${org}/users/${admin} \
            --url ${ca_protocol}${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --id.name $username \
            --id.secret '$password'  \
            --id.affiliation $user_affiliation \
            --id.attrs $user_attributes \
            --id.type $user_type
         "

    log "!! IMPORTANT: Note down these lines containing the information of the registered user" success
}

enroll_user() {
    log "===============" info
    log "CA User: enroll" info
    log "===============" info
    echo

    __ca_setup enroll

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${FABRIC_CA_VERSION} \
        sh -c " \
        fabric-ca-client enroll -d \
            --home /crypto-config \
            --mspdir ${org}/users/${username} \
            --url ${ca_protocol}${username}:'${password}'@${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --enrollment.attrs $user_attributes
        "

    # IMPORTANT: the CA requires this folder in case of the user is an admin
    cp -r ${CRYPTOS_PATH}/${org}/users/${username}/signcerts ${CRYPTOS_PATH}/${org}/users/${username}/admincerts
}

reenroll_user() {
    log "=================" info
    log "CA User: reenroll" info
    log "=================" info
    echo

    __ca_setup enroll

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${FABRIC_CA_VERSION} \
        sh -c " \
        fabric-ca-client reenroll -d \
            --home /crypto-config \
            --mspdir ${org}/users/${username} \
            --url ${ca_protocol}${username}:'${password}'@${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --enrollment.attrs $user_attributes
        "

    # IMPORTANT: the CA requires this folder in case of the user is an admin
    cp -r ${CRYPTOS_PATH}/${org}/users/${username}/signcerts ${CRYPTOS_PATH}/${org}/users/${username}/admincerts
}

revoke_user() {
    log "===============" info
    log "CA User: revoke" info
    log "===============" info
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
        log "Select one of the reason for the revoke from this list: " info
        log "${reason_list}" info
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
            *) log "Please select any of the reason from the list by typying in the corresponding number" warning;;
        esac
    done
    log ${reason} success
    echo

    docker run --rm \
        -v ${CRYPTOS_PATH}:/crypto-config \
        --network="${DOCKER_NETWORK}" \
        hyperledger/fabric-ca:${FABRIC_CA_VERSION} \
        sh -c " \
        fabric-ca-client revoke -d \
            --home /crypto-config \
            --mspdir ${org}/users/${admin} \
            --url ${ca_protocol}${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --revoke.name $username \
            --revoke.reason $reason
        "
}

__ca_setup() {
    log "Creating docker network..." info
    docker network create ${DOCKER_NETWORK} 2>/dev/null 

    log "Insert the organization name of the user to register/enroll" info
    while [ -z "$org" ]; do
        read -p "Organization: [] " org
    done
    export org
    log $org success
    echo

    users_dir="${CRYPTOS_PATH}/${org}/users"

    # workaround to avoid emtpy or existing directories
    admin_msp="a/s/d/f/g"
    if [ "$1" == "register" ]; then
        # set admin msp path
        while [ ! -d "${admin_msp}" ]; do
            log "Set the root Admin MSP path containing admincert, signcert, etc. directories" info
            log "You can drag&drop in the terminal the top admin directory - e.g. if the certs are in ./admin/msp, simply drag in the ./admin folder " info
            admin_path_default=$(find $NETWORK_PATH -path "*/peerOrganizations/*/Admin*org1*" | head -n 1)
            read -p "Admin name/path: [${admin_path_default}] " admin_path
            admin_path=${admin_path:-${admin_path_default}}
            log "admin path: $admin_path" success
            export admin=$(basename ${admin_path})
            log "admin: $admin" success
            admin_msp=$(dirname $(find ${admin_path} -type d -name signcert* 2>/dev/null) 2>/dev/null)
            log "admin msp: $admin_msp" success

            if [ ! -d "${admin_msp}" ]; then
                log "Admin MSP signcerts directory not found in: ${admin_path}. Please be sure the selected Admin MSP directory exists." warning
            fi
        done

        # avoid to copy the admin directory if it is already in place
        if [ "${users_dir}/${admin}" != "${admin_msp}" ]; then
            # copy the Admin msp to the main cryptos directory
            mkdir -p ${users_dir}/${admin} && cp -r $admin_msp/** ${users_dir}/${admin}
            # TODO: check whether this renaming is still necessary
            # mv ${users_dir}/${admin}/signcert*/* ${users_dir}/${admin}/signcert*/cert.pem
            cp -r ${users_dir}/${admin}/signcert*/ ${users_dir}/${admin}/admincerts/
        else
            log "Admin MSP directory is already in place under ${users_dir}/${admin}. Be sure the certificate are up to date or remove that directory and restart this process." warning
        fi
    fi

    log "Insert the correct Hyperledger Fabric CA version to use (read Troubleshooting section)" info
    log "This should be the same used by your CA server (i.e. at the time of writing, IBPv1 is using 1.1.0)" info
    read -p "CA Version: [${FABRIC_VERSION}] " fabric_version
    export fabric_version=${fabric_version:-${FABRIC_VERSION}}
    log $fabric_version success
    echo

    log "Insert the username of the user to register/enroll" info
    username_default="user_"$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 5; echo)
    read -p "Username: [${username_default}] " username
    export username=${username:-${username_default}}
    mkdir -p ${users_dir}/${username}
    log $username success
    echo

    log "Insert password of the user. It will be used by the CA as secret to generate the user certificate and key" info
    password_default=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20; echo)
    read -p "Password: [${password_default}] " password
    export password=${password:-${password_default}}
    log $password success
    log "!! IMPORTANT: Take note of this password before continuing. If you loose this password you will not be able to manage the credentials of this user any longer." warning
    echo

    log "CA secure connection (https)" info
    read -p "Using TLS secure connection? (if your CA address starts with https)? [yes/no=default] " yn
    case $yn in
        [Yy]* ) 
            export ca_protocol="https://"
            log "Secure TLS connection: enabled" success
            ;;
        * ) 
            export ca_protocol="http://" 
            log "Secure TLS connection: disabled" success
            ;;
    esac
    echo

    log "Set CA TLS certificate path" info
    ca_cert_default=$(find $NETWORK_PATH -name "tlsca*.pem" | head -n 1)
    read -p "CA cert: [${ca_cert_default}] " ca_cert
    ca_cert=${ca_cert:-${ca_cert_default}}
    log $ca_cert success
    # copy the CA certificate to the main cryptos directory
    mkdir -p ${CRYPTOS_PATH}/${org}
    cp $ca_cert ${CRYPTOS_PATH}/${org}/cert.pem
    export ca_cert=$(basename ${CRYPTOS_PATH}/${org}/cert.pem)
    echo

    log "Insert CA hostname and port only (e.g. ca.example.com:7054)" info
    ca_url_default="ca.example.com:7054"
    read -p "CA hostname and port: [${ca_url_default}] " ca_url
    export ca_url=${ca_url:-${ca_url_default}}
    log ${ca_url} success
    echo

    if [ "$1" == "register" ] || [ "$1" == "enroll" ]; then
        log "Insert user attributes (e.g. admin=false:ecert)" info
        log "Wiki: https://hyperledger-fabric-ca.readthedocs.io/en/latest/users-guide.html#registering-a-new-identity" info
        echo
        log "A few examples:" info
        log "If enrolling an admin: 'hf.Registrar.Roles,hf.Registrar.Attributes,hf.AffiliationMgr'" warning
        log "If registering a user: 'admin=false:ecert,email=provapi@everledger.io:ecert,application=provapi'" warning
        log "If enrolling a user: 'admin:opt,email:opt,application:opt'" warning
        read -p "User attributes: [admin=false:ecert] " user_attributes
        export user_attributes=${user_attributes:-"admin=false:ecert"}
        log $user_attributes success
        echo
    fi

    # registering a user requires additional information
    if [ "$1" == "register" ]; then
        log "Insert user type (e.g. client, peer, orderer)" info
        read -p "User type: [client] " user_type
        export user_type=${user_type:-client}
        log $user_type success
        echo

        log "Insert user affiliation (default value is usually enough)" info
        read -p "User affiliation: [${org}] " user_affiliation
        export user_affiliation=${user_affiliation:-${org}}
        log $user_affiliation success
        echo
    fi
}