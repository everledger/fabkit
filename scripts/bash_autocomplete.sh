#!/usr/bin/env bash


function AutoComplete {
    local cmd="${1##*/}"
    local word=${COMP_WORDS[1]}
    local line=${COMP_LINE}
    # echo "word is ${word}"

    # COMPLETE_BASH_SUMMARY_ALIGN=right

    # echo "cmd is $cmd"
    # echo "word is $word"
    # echo "line is $line"
    COMPREPLY=($(compgen -W "help dep channel network explorer ca generate chaincode benchmark utils" "${word}"))
    # echo "COMPAREPLY is ${COMPREPLY}"

    if [ "${word}" == "ca" ]; then
        # echo "word is ${word}"
        COMPREPLY=($(compgen -W "register enroll reenroll revok" "${word}"))
        # echo "COMPAREPLY is ${COMPREPLY}" 
    fi
}   

complete -F AutoComplete ./fabkit

# complete -W "help dep ca network explorer channel generate chaincode benchmark utils" ./fabkit