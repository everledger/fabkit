#!/bin/sh

__exec_jobs() {
    local jobs=$1
    local entries=$2

    if [ -z "$jobs" ]; then
        echo "Provide a number of jobs to run in parallel"
        exit 1
    fi
    if [ -z "$entries" ]; then
        echo "Provide a number of entries per job"
        exit 1
    fi

    log "==================" info
    log "Network: benchmark" info
    log "==================" info
    echo

    log "Running in parallel:
    Jobs: $jobs
    Entries: $entries
    " info

    start_time="$(date -u +%s)"
    
    for i in $(seq 1 $jobs); do
        __loader $entries & 
    done

    for job in $(jobs -p); do
        wait $job
    done 

    end_time="$(date -u +%s)"

    elapsed="$(($end_time - $start_time))"
    log "Total of $elapsed seconds elapsed for process" warning

    log "$(( $jobs * $entries )) entries added" success
}

__loader() {
    if [ -z "$1" ]; then
        log "Provide a number of entries for put" error
        exit 1
    fi

    set -e
    export LC_CTYPE=C

    for i in $(seq 1 $1); do 
        key=$(LC_CTYPE=C cat /dev/urandom | tr -cd 'A-Z0-9' | fold -w 14 | head -n 1)
        value="$i"

        invoke mychannel mychaincode 1 0 "{\"Args\":[\"put\",\"${key}\",\"${value}\"]}" &>/dev/null
    done
}