#!/bin/sh

set -e
export LC_CTYPE=C

ENTRIES=$1
if [ -z "$ENTRIES" ]; then
    echo "Provide a number of entries for put"
    exit 1
fi

for i in $(seq 1 $ENTRIES); do 
    key=$(cat /dev/urandom | tr -cd 'A-Z0-9' | fold -w 14 | head -n 1)
    value="$i"
    sh run.sh chaincode invoke mychannel mychaincode 1 0 "{\"Args\":[\"put\",\"${key}\",\"${value}\"]}" &>/dev/null
done