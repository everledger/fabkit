#!/usr/bin/env bash

loghead() {
    echo -e "\033[1;35m${1}\033[0m"
}

logerr() {
    echo -e "\t\b[ERROR]\t\b\033[1;31m${1}\033[0m"
    __print_to_file "$FABKIT_LOGFILE" "$1" "[ERROR]"
}

logsucc() {
    echo -e "\033[1;32m${1}\033[0m"
}

logwarn() {
    echo -e "\t\b[WARN]\t\b\033[1;33m${1}\033[0m"
}

loginfo() {
    echo -en "\033[1;34m${1}\033[0m"
}

loginfoln() {
    echo -e "\033[1;34m${1}\033[0m"
}

logdebu() {
    if [ "${FABKIT_DEBUG:-}" = "false" ]; then return; fi
    __clear_spinner && echo -e "\t\b[DEBUG]\t\b\033[1;36m${1}\033[0m"
    __print_to_file "$FABKIT_LOGFILE" "$1" "[DEBUG]"
}

tostring() {
    echo "$*" | __jq tostring 2>/dev/null || echo "${*//\"/\\\"}"
}

tojson() {
    echo "$*" | __jq . 2>/dev/null || echo "${*//\\\"/\"}"
}

__spinner() {
    local LC_CTYPE=C
    local pid=$!
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local charwidth=3

    echo -en "\033[3C→ "
    local i=0
    tput cuf1
    while kill -0 "$pid" 2>/dev/null; do
        tput civis
        local i=$(((i + charwidth) % ${#spin}))
        printf "%s" "${spin:$i:$charwidth}"
        tput cub1
        sleep 0.05
    done

    tput el
    tput cnorm
    if wait "$pid"; then
        echo -e "✅ "
    else
        echo -e "❌ "
        return 1
    fi
}

__clear_spinner() {
    tput cub1 && tput el
}

__print_to_file() {
    local file="$1"
    local message="$2"
    local tag="$3"
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

    echo -e "$tag $timestamp $message" >>"$file"
}

# remove dangling spinner when running in debug mode
__clear_logdebu() {
    if [ "${FABKIT_DEBUG:-}" = "false" ]; then return; fi
    __clear_spinner && echo
}

__throw() {
    local input

    if [ -n "$1" ]; then
        input="$1"
        __clear_spinner && logerr "$input"
    else
        local count=0
        while read -r input; do
            if [ $count -eq 0 ]; then ((count++)) || true; echo; fi
            __clear_spinner && logerr "$input"
        done
    fi
}
