#!/usr/bin/env bash

source ${PWD}/.env

__autocomplete() {
    COMPREPLY=()

    local functions=("help" "dep" "channel" "network" "explorer" "ca" "generate" "chaincode" "benchmark" "utils")

    declare -A actions
    actions[ca]="register enroll reenroll revoke"
    actions[network]="install start restart stop"
    actions[explorer]="start stop"
    actions[channel]="create update join"
    actions[generate]="genesis cryptos channeltx"
    actions[chaincode]="test build zip package install instantiate upgrade query invoke lifecycle"
    actions[benchmark]="load"
    actions[utils]="tojson tostring"
    actions[lifecycle]="package install approve commit deploy"

    local cur=${COMP_WORDS[COMP_CWORD]}

    if [ ${actions[$3]+1} ]; then
        COMPREPLY=($(compgen -W "${actions[$3]}" -- $cur))
    elif [[ "${actions[*]}" == *"$3"* ]]; then
        COMPREPLY=($(compgen -W "${options[*]}" -- $cur))
    else
        COMPREPLY=($(compgen -W "${functions[*]}" -- $cur))
    fi
}

complete -F __autocomplete fabkit fk
