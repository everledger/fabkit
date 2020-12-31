#!/usr/bin/env bash

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

case $SHELL in
*bash)
    __add_aliases bash
    ;;
*zsh)
    __add_aliases zsh
    ;;
esac

source ${ROOT}/scripts/autocomplete.sh
