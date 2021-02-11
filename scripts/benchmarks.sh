#!/usr/bin/env bash

__exec_jobs() {
    if [[ $# == 1 ]]; then
        __loader $1
        return
    fi

    local jobs=$1
    local entries=$2

    if [ -z "$jobs" ]; then
        logerr "Provide a number of jobs to run in parallel\n"
        exit 1
    fi
    if [ -z "$entries" ]; then
        logerr "Provide a number of entries per job\n"
        exit 1
    fi

    loginfo "==================\n"
    loginfo "Network: benchmark\n"
    loginfo "==================\n"
    echo

    loginfo "Running in parallel:
    Jobs: $jobs
    Entries: $entries
    \n"

    local start_time="$(date -u +%s)"

    for i in $(seq 1 $jobs); do
        __loader $entries &
    done

    for job in $(jobs -p); do
        wait $job
    done

    local end_time="$(date -u +%s)"
    local elapsed="$(($end_time - $start_time))"

    logwarn "Total of $elapsed seconds elapsed for process\n"
    logsucc "$(($jobs * $entries)) entries added\n"
}

__loader() {
    if [ -z "$1" ]; then
        logerr "Provide a number of entries for put\n"
        exit 1
    fi

    set -e

    for i in $(seq 1 $1); do
        local key=$(LC_CTYPE=C tr -cd '[:alnum:]' </dev/urandom | fold -w12 | head -n1)
        local value="$i"

        logdebu "Writing <${key},${value}> pair in the ledger\n"

        invoke $FABKIT_CHANNEL_NAME $FABKIT_CHAINCODE_NAME 1 0 "{\"Args\":[\"put\",\"${key}\",\"${value}\"]}" &>/dev/null
    done
}
