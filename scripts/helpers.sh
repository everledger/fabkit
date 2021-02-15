#!/usr/bin/env bash

title() {
    loghead "
        ╔═╗┌─┐┌┐ ┬┌─ ┬┌┬┐
        ╠╣ ├─┤├┴┐├┴┐ │ │ 
        ╚  ┴ ┴└─┘┴ ┴ ┴ ┴ 
             ■-■-■               \n\n"
}

help_header() {
    loginfo "
        Usage: $* [command]
        
        Commands:
    "
}

help() {
    help_header fabkit
    loginfo "
        help                                                                                            : this help
    
        dep install [chaincode_name]                                                                    : install all go modules as vendor and init go.mod if does not exist yet
        dep update [chaincode_name]                                                                     : update all go modules and rerun install
            
        ca register                                                                                     : register a new user
        ca enroll                                                                                       : enroll a previously registered user    
        ca reenroll                                                                                     : reenroll a user if its certificate expired
        ca revoke                                                                                       : revoke a user's key/certificate providing a reason
            
        network install                                                                                 : install all the dependencies and docker images
        network start                                                                                   : start the blockchain network and initialize it
        network restart                                                                                 : restart a previously running the blockchain network
        network stop                                                                                    : stop the blockchain network and remove all the docker containers
            
        explorer start                                                                                  : run the blockchain explorer user-interface and analytics
        explorer stop                                                                                   : stop the blockchain explorer user-interface and analytics
    
        channel create [channel_name] [org_no] [peer_no]                                                : generate channel configuration file
        channel update [channel_name] [org_msp] [org_no] [peer_no]                                      : update channel with anchor peers
        channel join [channel_name] [org_no] [peer_no]                                                  : run by a peer to join a channel
    
        generate cryptos [config_path] [cryptos_path]                                                   : generate all the crypto keys and certificates for the network
        generate genesis [base_path] [config_path]                                                      : generate the genesis block for the ordering service
        generate channeltx [channel_name] [base_path] [config_path] [cryptos_path]                      : generate channel configuration files
                           [network_profile] [channel_profile] [org_msp]                
    
        chaincode test [chaincode_path]                                                                 : run unit tests
        chaincode build [chaincode_path]                                                                : run build and test against the binary file
        chaincode zip [chaincode_path]                                                                  : create a zip archive ready for deployment containing chaincode and vendors
        chaincode package [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no]      : package, sign and create deployment spec for chaincode 
        chaincode install [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no]      : install chaincode on a peer
        chaincode instantiate [chaincode_name] [chaincode_version] [channel_name] [org_no] [peer_no]    : instantiate chaincode on a peer for an assigned channel
        chaincode upgrade [chaincode_name] [chaincode_version] [channel_name] [org_no] [peer_no]        : upgrade chaincode with a new version
        chaincode query [channel_name] [chaincode_name] [org_no] [peer_no] [data_in_json]               : run query in the format '{\"Args\":[\"queryFunction\",\"key\"]}'
        chaincode invoke [channel_name] [chaincode_name] [org_no] [peer_no] [data_in_json]              : run invoke in the format '{\"Args\":[\"invokeFunction\",\"key\",\"value\"]}'

        chaincode lifecycle package [chaincode_name] [chaincode_version] [chaincode_path]               : package, sign and create deployment spec for chaincode 
                                    [org_no] [peer_no]
        chaincode lifecycle install [chaincode_name] [chaincode_version] [org_no] [peer_no]             : install chaincode on a peer
        chaincode lifecycle approve [chaincode_name] [chaincode_version] [chaincode_path]               : approve chaincode definition
                                    [channel_name] [sequence_no] [org_no] [peer_no]
        chaincode lifecycle commit [chaincode_name] [chaincode_version] [chaincode_path]                : commit and init chaincode on channel
                                   [channel_name] [sequence_no] [org_no] [peer_no]
        chaincode lifecycle deploy [chaincode_name] [chaincode_version] [chaincode_path]                : run in sequence package, install, approve and commit
                                   [channel_name] [sequence_no] [org_no] [peer_no]

        benchmark load [jobs] [entries]                                                                 : run benchmark bulk loading of [entries] per parallel [jobs] against a running network
       
        utils tojson                                                                                    : transform a string format with escaped characters to a valid JSON format
        utils tostring                                                                                  : transform a valid JSON format to a string with escaped characters
    "
}

help_dep() {
    help_header "fabkit dep"
    loginfo "
        install [chaincode_name]                                                                    : install all go modules as vendor and init go.mod if does not exist yet
        update [chaincode_name]                                                                     : update all go modules and rerun install
    "
}

help_ca() {
    help_header "fabkit ca"
    loginfo "
        register                                                                                     : register a new user
        enroll                                                                                       : enroll a previously registered user    
        reenroll                                                                                     : reenroll a user if its certificate expired
        revoke                                                                                       : revoke a user's key/certificate providing a reason
    "
}

help_network() {
    help_header "fabkit network"
    loginfo "
        install                                                                                 : install all the dependencies and docker images
        start [options]                                                                         : start the blockchain network and initialize it
            -q, --quick-run                                                                         : skip boring chaincode build&test
            -d, --debug                                                                             : run in debug mode verbose logging
            -o, --orgs [orgs_no]                                                                    : use a specific number of organizations (default: 1)
            -r, --reset                                                                             : reset all previous configuration and run in fresh start
            -v, --version [version]                                                                 : use a specific fabric version (default: latest)
        restart                                                                                 : restart a previously running the blockchain network
        stop                                                                                    : stop the blockchain network and remove all the docker containers
    "
}

help_explorer() {
    help_header "fabkit explorer"
    loginfo "
        start                                                                                  : run the blockchain explorer user-interface and analytics
        stop                                                                                   : stop the blockchain explorer user-interface and analytics
    "
}

help_channel() {
    help_header "fabkit channel"
    loginfo "
        create [channel_name] [org_no] [peer_no]                                                : generate channel configuration file
        update [channel_name] [org_msp] [org_no] [peer_no]                                      : update channel with anchor peers
        join [channel_name] [org_no] [peer_no]                                                  : run by a peer to join a channel
    "
}

help_generate() {
    help_header "fabkit generate"
    loginfo "
        cryptos [config_path] [cryptos_path]                                                   : generate all the crypto keys and certificates for the network
        genesis [base_path] [config_path]                                                      : generate the genesis block for the ordering service
        channeltx [channel_name] [base_path] [config_path] [cryptos_path]                      : generate channel configuration files
                           [network_profile] [channel_profile] [org_msp]                
    "
}

help_chaincode() {
    help_header "fabkit chaincode"
    loginfo "
        test [chaincode_path]                                                                 : run unit tests
        build [chaincode_path]                                                                : run build and test against the binary file
        zip [chaincode_path]                                                                  : create a zip archive ready for deployment containing chaincode and vendors
        package [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no]      : package, sign and create deployment spec for chaincode 
        install [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no]      : install chaincode on a peer
        instantiate [chaincode_name] [chaincode_version] [channel_name] [org_no] [peer_no]    : instantiate chaincode on a peer for an assigned channel
        upgrade [chaincode_name] [chaincode_version] [channel_name] [org_no] [peer_no]        : upgrade chaincode with a new version
        query [channel_name] [chaincode_name] [org_no] [peer_no] [data_in_json]               : run query in the format '{\"Args\":[\"queryFunction\",\"key\"]}'
        invoke [channel_name] [chaincode_name] [org_no] [peer_no] [data_in_json]              : run invoke in the format '{\"Args\":[\"invokeFunction\",\"key\",\"value\"]}'

        lifecycle package [chaincode_name] [chaincode_version] [chaincode_path]               : package, sign and create deployment spec for chaincode 
                                    [org_no] [peer_no]
        lifecycle install [chaincode_name] [chaincode_version] [org_no] [peer_no]             : install chaincode on a peer
        lifecycle approve [chaincode_name] [chaincode_version] [chaincode_path]               : approve chaincode definition
                                    [channel_name] [sequence_no] [org_no] [peer_no]
        lifecycle commit [chaincode_name] [chaincode_version] [chaincode_path]                : commit and init chaincode on channel
                                   [channel_name] [sequence_no] [org_no] [peer_no]
        lifecycle deploy [chaincode_name] [chaincode_version] [chaincode_path]                : run in sequence package, install, approve and commit
                                   [channel_name] [sequence_no] [org_no] [peer_no]
    "
}

help_benchmark() {
    help_header "fabkit benchmark"
    loginfo "
        load [jobs] [entries]                                                                 : run benchmark bulk loading of [entries] per parallel [jobs] against a running network        
    "
}

help_utils() {
    help_header "fabkit utils"
    loginfo "
        tojson                                                                                    : transform a string format with escaped characters to a valid JSON format
        tostring                                                                                  : transform a valid JSON format to
    "
}
