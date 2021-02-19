#!/usr/bin/env bash

register_user() {
    loginfo "Registering user"

    __ca_setup register

    docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${FABKIT_CRYPTOS_PATH}:/crypto-config" \
        --network="${FABKIT_DOCKER_NETWORK}" \
        hyperledger/fabric-ca:"$FABKIT_FABRIC_CA_VERSION" \
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

    logwarn "!! IMPORTANT: Note down these lines containing the information of the registered user"
}

enroll_user() {
    loginfo "Enrolling user"

    __ca_setup enroll

    docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${FABKIT_CRYPTOS_PATH}:/crypto-config" \
        --network="${FABKIT_DOCKER_NETWORK}" \
        hyperledger/fabric-ca:"$FABKIT_FABRIC_CA_VERSION" \
        sh -c " \
        fabric-ca-client enroll -d \
            --home /crypto-config \
            --mspdir ${org}/users/${username} \
            --url ${ca_protocol}${username}:'${password}'@${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --enrollment.attrs $user_attributes
        "

    # IMPORTANT: the CA requires this folder in case of the user is an admin
    cp -r "${FABKIT_CRYPTOS_PATH}/${org}/users/${username}/signcerts" "${FABKIT_CRYPTOS_PATH}/${org}/users/${username}/admincerts"
}

reenroll_user() {
    loginfo "Reenrolling user"

    __ca_setup enroll

    docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${FABKIT_CRYPTOS_PATH}:/crypto-config" \
        --network="${FABKIT_DOCKER_NETWORK}" \
        hyperledger/fabric-ca:"$FABKIT_FABRIC_CA_VERSION" \
        sh -c " \
        fabric-ca-client reenroll -d \
            --home /crypto-config \
            --mspdir ${org}/users/${username} \
            --url ${ca_protocol}${username}:'${password}'@${ca_url} \
            --tls.certfiles ${org}/${ca_cert} \
            --enrollment.attrs $user_attributes
        "

    # IMPORTANT: the CA requires this folder in case of the user is an admin
    cp -r "${FABKIT_CRYPTOS_PATH}/${org}/users/${username}/signcerts" "${FABKIT_CRYPTOS_PATH}/${org}/users/${username}/admincerts"
}

revoke_user() {
    loginfo "Revoking user"

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
        loginfo "Select one of the reason for the revoke from this list: "
        loginfo "${reason_list}"
        read -rp "Select a number from the list above: [1] " reason
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
        *) logwarn "Please select any of the reason from the list by typying in the corresponding number" ;;
        esac
    done
    logsucc ${reason}
    echo

    docker run --rm -v /var/run/docker.sock:/host/var/run/docker.sock \
        -v "${FABKIT_CRYPTOS_PATH}:/crypto-config" \
        --network="${FABKIT_DOCKER_NETWORK}" \
        hyperledger/fabric-ca:"$FABKIT_FABRIC_CA_VERSION" \
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
    logdebu "Creating docker network ${FABKIT_DOCKER_NETWORK}"
    docker network create "${FABKIT_DOCKER_NETWORK}" &>/dev/null || true

    loginfo "Insert the organization name of the user to register/enroll"
    while [ -z "$org" ]; do
        read -rp "Organization: [] " org
    done
    export org
    logsucc "$org"
    echo

    users_dir="${FABKIT_CRYPTOS_PATH}/${org}/users"

    # workaround to avoid emtpy or existing directories
    admin_msp="a/s/d/f/g"
    if [ "$1" = "register" ]; then
        # set admin msp path
        while [ ! -d "${admin_msp}" ]; do
            loginfo "Set the root Admin MSP path containing admincert, signcert, etc. directories"
            loginfo "You can drag&drop in the terminal the top admin directory - e.g. if the certs are in ./admin/msp, simply drag in the ./admin folder "
            admin_path_default=$(find "$FABKIT_NETWORK_PATH" -path "*/peerOrganizations/*/Admin*org1*" | head -n 1)
            read -rp "Admin name/path: [${admin_path_default}] " admin_path
            admin_path=${admin_path:-${admin_path_default}}
            logsucc "admin path: $admin_path"
            export admin=$(basename "${admin_path}")
            logsucc "admin: $admin"
            admin_msp=$(dirname "$(find "${admin_path}" -type d -name 'signcert*' 2>/dev/null)" 2>/dev/null)
            logsucc "admin msp: $admin_msp"

            if [ ! -d "${admin_msp}" ]; then
                logwarn "Admin MSP signcerts directory not found in: ${admin_path}. Please be sure the selected Admin MSP directory exists."
            fi
        done

        # avoid to copy the admin directory if it is already in place
        if [ "${users_dir}/${admin}" != "${admin_msp}" ]; then
            # copy the Admin msp to the main cryptos directory
            mkdir -p "${users_dir}/${admin}" && cp -r "$admin_msp/**" "${users_dir}/${admin}"
            # TODO: check whether this renaming is still necessary
            # mv ${users_dir}/${admin}/signcert*/* ${users_dir}/${admin}/signcert*/cert.pem
            cp -r "${users_dir}/${admin}/signcert*/" "${users_dir}/${admin}/admincerts/"
        else
            logwarn "Admin MSP directory is already in place under ${users_dir}/${admin}. Be sure the certificate are up to date or remove that directory and restart this process."
        fi
    fi

    loginfo "Insert the correct Hyperledger Fabric CA version to use (read Troubleshooting section)"
    loginfo "This should be the same used by your CA server (i.e. at the time of writing, IBPv1 is using 1.1.0)"
    read -rp "CA Version: [${FABKIT_FABRIC_VERSION}] " fabric_version
    export fabric_version=${fabric_version:-${FABKIT_FABRIC_VERSION}}
    logsucc "$fabric_version"
    echo

    loginfo "Insert the username of the user to register/enroll"
    username_default="user_"$(
        LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 5
        echo
    )
    read -rp "Username: [${username_default}] " username
    export username=${username:-${username_default}}
    mkdir -p "${users_dir}/${username}"
    logsucc "$username"
    echo

    loginfo "Insert password of the user. It will be used by the CA as secret to generate the user certificate and key"
    password_default=$(
        LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
        echo
    )
    read -rp "Password: [${password_default}] " password
    export password=${password:-${password_default}}
    logsucc "$password"
    logwarn "!! IMPORTANT: Take note of this password before continuing. If you loose this password you will not be able to manage the credentials of this user any longer."
    echo

    loginfo "CA secure connection (https)"
    read -rp "Using TLS secure connection? (if your CA address starts with https)? [yes/no=default] " yn
    case $yn in
    [Yy]*)
        export ca_protocol="https://"
        logsucc "Secure TLS connection: enabled"
        ;;
    *)
        export ca_protocol="http://"
        logsucc "Secure TLS connection: disabled"
        ;;
    esac
    echo

    loginfo "Set CA TLS certificate path"
    ca_cert_default=$(find "$FABKIT_NETWORK_PATH" -name "tlsca*.pem" | head -n 1)
    read -rp "CA cert: [${ca_cert_default}] " ca_cert
    ca_cert=${ca_cert:-${ca_cert_default}}
    logsucc "$ca_cert"
    # copy the CA certificate to the main cryptos directory
    mkdir -p "${FABKIT_CRYPTOS_PATH}/${org}"
    cp "$ca_cert" "${FABKIT_CRYPTOS_PATH}/${org}/cert.pem"
    export ca_cert=$(basename "${FABKIT_CRYPTOS_PATH}/${org}/cert.pem")
    echo

    loginfo "Insert CA hostname and port only (e.g. ca.example.com:7054)"
    ca_url_default="ca.example.com:7054"
    read -rp "CA hostname and port: [${ca_url_default}] " ca_url
    export ca_url=${ca_url:-${ca_url_default}}
    logsucc "$ca_url"
    echo

    if [ "$1" = "register" ] || [ "$1" = "enroll" ]; then
        loginfo "Insert user attributes (e.g. admin=false:ecert)"
        loginfo "Wiki: https://hyperledger-fabric-ca.readthedocs.io/en/latest/users-guide.html#registering-a-new-identity"
        echo
        loginfo "A few examples:"
        logwarn "If enrolling an admin: 'hf.Registrar.Roles,hf.Registrar.Attributes,hf.AffiliationMgr'"
        logwarn "If registering a user: 'admin=false:ecert,email=app@example.org:ecert,application=app'"
        logwarn "If enrolling a user: 'admin:opt,email:opt,application:opt'"
        read -rp "User attributes: [admin=false:ecert] " user_attributes
        export user_attributes=${user_attributes:-"admin=false:ecert"}
        logsucc "$user_attributes"
        echo
    fi

    # registering a user requires additional information
    if [ "$1" = "register" ]; then
        loginfo "Insert user type (e.g. client, peer, orderer)"
        read -rp "User type: [client] " user_type
        export user_type=${user_type:-client}
        logsucc "$user_type"
        echo

        loginfo "Insert user affiliation (default value is usually enough)"
        read -rp "User affiliation: [${org}] " user_affiliation
        export user_affiliation=${user_affiliation:-${org}}
        logsucc "$user_affiliation"
        echo
    fi
}
