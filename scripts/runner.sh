#!/usr/bin/env bash

source $(pwd)/scripts/utils.sh

ALIASES=("fabkit" "fk")

__add_aliases() {
    local shell="${1}"
    local cmd="\n# Fabkit aliases to run commands with ease\n"
    local to_add=false

    for alias in "${ALIASES[@]}"; do
        if [[ ! $(cat ~/.${shell}rc | grep "alias ${alias}") ]]; then
            cmd+="alias ${alias}=./fabkit\n"
            to_add=true
        fi
    done

    if [ "${to_add}" == "true" ]; then
        echo -e ${cmd} >>~/.${shell}rc
        source ~/.${shell}rc 2>/dev/null
    fi
}

init() {
    case $SHELL in
    *bash)
        __add_aliases bash
        ;;
    *zsh)
        __add_aliases zsh
        ;;
    esac

    log "Fabkit aliases added to your default shell. Try now to use any of: $(for alias in ${ALIASES[@]}; do printf "$alias "; done)" success
}

if [ "$1" == "init" ]; then
    init
fi
