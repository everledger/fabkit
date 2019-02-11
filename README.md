# Hyperledger Fabric Chaincode Boilerplate 
A basic and simple boilerplate which contains utilities for efficiently writing chaincode and test it in a running network.

# Purpose
The codebase of this repository is meant to serve the following scopes:

- as a starting point for any new project which will use a Hyperledger Fabric native chaincode
- as an open project shared across all the development teams which are asked to participate and contribute following the common issue tracking system and merge request procedure
- as a space where to define coding standards and best practices through a process of peer reviewing and features proposing (working as a discussion forum)

## Prerequisites
- [Go](https://golang.org/dl/)
- [Docker](https://www.docker.com/get-started)
- [Docker-compose](https://www.docker.com/get-started)

## Install
Install all the docker images needed:
```bash
./run.sh install
```

## Run the blockchain network
The following command will spin a Hyperledger Fabric network up, generating _channel_ and _crypto_ config at runtime:
```bash
./run.sh start_network
```
Implicitly it will execute the following functions:
```bash
test_chaincode
build_chaincode
generate_cryptos
create_channel
join_channel
update_channel
install_chaincode
instantiate_chaincode
```

Run `./run.sh help` for the complete list of functionalities.

## Upgrade chaincode
Run the following command in order to install and instantiate a new version of the chaincode:
```bash
./run.sh upgrade_chaincode <chaincode_name> <chaincode_version> <channel_name>
```
Be sure the `chaincode_version` is unique and never used before (otherwise an error will be prompted).

## Invoke and query
It is possible to use the CLI to run and test functionalities.

**Note:** The function appearing as a string in the first place of the array `Args` needs to be defined in the chaincode and the `request` should be provided as a JSON wrapped into single quotes `'`.

### Invoke
```bash
./run.sh invoke <channel_name> <chaincode_name> <request>

# e.g.
./run.sh invoke mychannel mychaincode '{"Args":["put","key1","10"]}'
```

### Query
```bash
./run.sh query <channel_name> <chaincode_name> <request>

# e.g.
./run.sh query mychannel mychaincode '{"Args":["get","key1"]}'
```


## Register and enroll users
todo

## Cleanup the environment
### Tear blockchain network down
It will stop and remove all the blockchain network containers including the `dev-` tagged chaincode ones.
```bash
./run.sh stop_network
```