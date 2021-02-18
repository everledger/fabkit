#!/usr/bin/env bash

__exec_jobs() {
    if [[ $# == 1 ]]; then
        __loader "$1"
        return
    fi

    local jobs=$1
    local entries=$2

    if [ -z "$jobs" ]; then
        logerr "Provide a number of jobs to run in parallel"
        exit 1
    fi
    if [ -z "$entries" ]; then
        logerr "Provide a number of entries per job"
        exit 1
    fi

    loginfo "Benchmarking network"
    lodebu "Running in parallel:\nJobs: $jobs\nEntries: $entries"

    for i in $(seq 1 "$jobs"); do
        __loader "$entries" &
    done

    for job in $(jobs -p); do
        wait "$job"
    done
}

__loader() {
    if [ -z "$1" ]; then
        logerr "Provide a number of entries for put"
        exit 1
    fi

    for i in $(seq 1 "$1"); do
        local key=$(LC_CTYPE=C tr -cd '[:alnum:]' </dev/urandom | fold -w12 | head -n1)
        local value="$i"

        logdebu "Writing <${key},${value}> pair in the ledger"

        invoke "$FABKIT_CHANNEL_NAME" "$FABKIT_CHAINCODE_NAME" 1 0 "{\"Args\":[\"put\",\"${key}\",\"${value}\"]}" &>/dev/null
    done
}
