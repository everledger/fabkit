#!/usr/bin/env bash


function _autocomplete {
    COMPREPLY=()
    
    local FIRST=("help" "dep" "channel" "network" "explorer" "ca" "generate" "chaincode" "benchmark" "utils" )
    
    declare -A ACTIONS
    ACTIONS[ca]="register enroll reenroll revoke"
    ACTIONS[network]="install start restart stop"
    ACTIONS[explorer]="start stop"
    ACTIONS[channel]="create update join"
    ACTIONS[generate]="genensis cryptos channeltx"
    ACTIONS[chaincode]="test build zip package install instantiate upgrade query invoke lifecycle"
    ACTIONS[benchmark]="load"
    ACTIONS[utils]="tojson tostring"
    
    local cur=${COMP_WORDS[COMP_CWORD]}
    
    if [ ${ACTIONS[$3]+1} ] ; then
        COMPREPLY=( `compgen -W "${ACTIONS[$3]}" -- $cur` )
        elif [[ "${ACTIONS[*]}" == *"$3"* ]] ; then
        COMPREPLY=( `compgen -W "${OPTIONS[*]}" -- $cur` )
    else
        COMPREPLY=( `compgen -W "${FIRST[*]}" -- $cur` )
    fi
}

complete -F _autocomplete fabkit
