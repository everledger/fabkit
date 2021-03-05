# Private Data Collections

Starting from v1.2, Fabric offers the ability to create [private data collections](https://hyperledger-fabric.readthedocs.io/en/release-1.4/private-data/private-data.html), which allow a defined subset of organizations on a channel the ability to endorse, commit, or query private data without having to create a separate channel.

This repository proposes a sample chaincode, `pdc`, to allow the user to experiment and get more familiar with the concept of private data collection.

This chaincode is a repackaged code from [fabric-samples - marbles02_private](https://github.com/hyperledger/fabric-samples/tree/v1.4.8/chaincode/marbles02_private) with the Fabkit's way to run commands which have been added to the `main.go` file itself, as commented lines above the corresponding fabric-samples' command.

Any chaincode which interacts with private data collections need to have a JSON file containing the configurations of those and this file needs to be passed in input during the instantiation step (see below).

The `collections_config.json` file resides in the same directory of the main code and defines collections with the following configuration:

- `collectionMarbles`: Org1MSP, Org2MSP
- `collectionMarblePrivateDetails`: Org1MSP

In order to provide with a basic demonstration of how private data collections work, it is recommended to run the network with the **3-orgs setup** (2-orgs will also work).

```bash
# start the network with 3-orgs setup
fabkit network start --orgs 3
```

The network will be initialized with the following components:

- orderer
- ca.org1
- peer0.org1 (mygocc installed)
- couchdb.peer0.org1
- ca.org2
- peer0.org2
- couchdb.peer0.org2
- ca.org3
- peer0.org3
- couchdb.peer0.org3
- cli

Install and instantiate the `pdc` chaincode:

## v1.x

```bash
# install the pdc chaincode on all the organizations' peer0
fabkit chaincode install pdc 1.0 pdc 1 0
fabkit chaincode install pdc 1.0 pdc 2 0
fabkit chaincode install pdc 1.0 pdc 3 0

# instantiate pdc chaincode on mychannel using org1 peer0
fabkit chaincode instantiate pdc 1.0 mychannel 1 0 --collections-config ${FABKIT_CHAINCODE_REMOTE_PATH}/pdc/collections_config.json -P 'OR("Org1MSP.member","Org2MSP.member","Org3MSP.member")'
```

## v2.x

```bash
fabkit chaincode lifecycle deploy pdc 1.0 pdc mychannel 1 1 0 --collections-config ${FABKIT_CHAINCODE_REMOTE_PATH}/pdc/collections_config.json
```

**Note: if you are deploying your own chaincode, remember that your remote basename path should match the chaincode name. e.g. if the chaincode name is `mycc`, then the full remote path should look like `${FABKIT_CHAINCODE_REMOTE_PATH}/mycc` .**

Execute some actions:

```bash
# create a new marble as org1 peer0
export MARBLE=$(echo -n "{\"name\":\"marble1\",\"color\":\"blue\",\"size\":35,\"owner\":\"tom\",\"price\":99}" | base64 | tr -d \\n)
fabkit chaincode invoke mychannel pdc 1 0 '{"Args":["initMarble"]}' --transient '{"marble":"$MARBLE"}'

# query marble as org2 peer0 (successful)
fabkit chaincode query mychannel pdc 2 0 '{"Args":["readMarble","marble1"]}'

# query marble as org3 peer0 (fail, as org3 is not part of this collection)
fabkit chaincode query mychannel pdc 3 0 '{"Args":["readMarble","marble1"]}'
```

You can access the CouchDB UI for each organization's peer to inspect the data which gets effectively stored and its format.

For each private collection your StateDB will create 2 databases, one public to the channel and one private. e.g.:

- `mychannel_pdc$$hcollection$marbles`: it refers to `collectionMarbles` where the `h` in front stands for `hash`. This will contain only the hash of the data and it is shared publicly across the channel.
- `mychannel_pdc$$pcollection$marbles`: it refers to `collectionMarbles` where the `p` in front stands for `private`. This will contain the data in clear.

A few more examples of commands are available in the main chaincode file `./chaincode/pdc/main.go` commented out in the header.

For a full overview about collections properties and definitions check the official documentation at [this page](https://hyperledger-fabric.readthedocs.io/en/release-1.4/private-data-arch.html).

## Additional commands

### Init marbles

```bash
export MARBLE=$(echo -n "{\"name\":\"marble1\",\"color\":\"blue\",\"size\":35,\"owner\":\"tom\",\"price\":99}" | base64 | tr -d \\n)
fabkit chaincode invoke mychannel pdc 1 0 '{"Args":["initMarble"]}' --transient '{"marble":"$MARBLE"}'

export MARBLE=$(echo -n "{\"name\":\"marble2\",\"color\":\"red\",\"size\":50,\"owner\":\"tom\",\"price\":102}" | base64 | tr -d \\n)
fabkit chaincode invoke mychannel pdc 1 0 '{"Args":["initMarble"]}' --transient '{"marble":"$MARBLE"}'

export MARBLE=$(echo -n "{\"name\":\"marble3\",\"color\":\"blue\",\"size\":70,\"owner\":\"tom\",\"price\":103}" | base64 | tr -d \\n)
fabkit chaincode invoke mychannel pdc 1 0 '{"Args":["initMarble"]}' --transient '{"marble":"$MARBLE"}'
```

### Transfer a marble

```bash
export MARBLE_OWNER=$(echo -n "{\"name\":\"marble2\",\"owner\":\"jerry\"}" | base64 | tr -d \\n)
fabkit chaincode invoke mychannel pdc 1 0 '{"Args":["transferMarble"]}' --transient '{"marble_owner":"$MARBLE_OWNER"}'
```

### Delete a marble

```bash
export MARBLE_DELETE=$(echo -n "{\"name\":\"marble1\"}" | base64 | tr -d \\n)
fabkit chaincode invoke mychannel pdc 1 0 '{"Args":["delete"]}' --transient '{"marble_delete":"$MARBLE_DELETE"}'
```

### Query marbles

#### Standard queries (via peer query)

```bash
fabkit chaincode query mychannel pdc 1 0 '{"Args":["readMarble","marble1"]}'
fabkit chaincode query mychannel pdc 1 0 '{"Args":["readMarblePrivateDetails","marble1"]}'
fabkit chaincode query mychannel pdc 1 0 '{"Args":["getMarblesByRange","marble1","marble4"]}'
```

### Rich queries (via CouchDB syntax)

```bash
fabkit chaincode query mychannel pdc 1 0 '{"Args":["queryMarblesByOwner","tom"]}'
fabkit chaincode query mychannel pdc 1 0 '{"Args":["queryMarbles","{\"selector\":{\"owner\":\"tom\"}}"]}'
fabkit chaincode query mychannel pdc 1 0 '{"Args":["queryMarbles","{\"selector\":{\"docType\":\"marble\",\"owner\":\"tom\"}, \"use_index\":[\"_design/indexOwnerDoc\", \"indexOwner\"]}"]}'
fabkit chaincode query mychannel pdc 1 0 '{"Args":["queryMarbles","{\"selector\":{\"docType\":{\"$eq\":\"marble\"},\"owner\":{\"$eq\":\"tom\"},\"size\":{\"$gt\":0}},\"fields\":[\"docType\",\"owner\",\"size\"],\"sort\":[{\"size\":\"desc\"}],\"use_index\":\"_design/indexSizeSortDoc\"}"]}'
```
