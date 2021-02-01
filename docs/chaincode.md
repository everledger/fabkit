# Working with chaincodes

Fabkit currently supports _golang_, _node_ and _java_ chaincodes. To deploy a chaincode from your own directory, you must set the following env variables before starting the network:

- `FABKIT_CHAINCODE_PATH`: Absolute path to the directory to be mounted
- `FABKIT_CHAINCODE_REMOTE_PATH`: Mount path inside the cli container. _Golang chaincodes must be mounted inside `GOPATH` ( `/opt/gopath/src` )_

To deploy chaincode using Fabkit's commands refer below.

_Note: `options` is an optional parameter. For more information about all the available options check the following documentations:_

- [v1.x Chaincode Commands](https://hyperledger-fabric.readthedocs.io/en/latest/commands/peerchaincode.html)
- [v2.x Chaincode Commands](https://hyperledger-fabric.readthedocs.io/en/latest/commands/peerlifecycle.html)

While inserting the `chaincode_path` in any of these commands, Fabkit allows the user to simply type in the basename of the directory when this path is under `$FABKIT_CHAINCODE_PATH`. For example, if you want to use the `mynodecc` chaincode, which is under `${FABKIT_CHAINCODE_PATH}/node/mynodecc`, then simply type `mynodecc`, Fabkit will do the rest!

## v1.x

Run the following commands in order to install and instantiate a new chaincode:

```bash
fabkit chaincode install [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no] [options]
fabkit chaincode instantiate [chaincode_name] [chaincode_version] [channel_name] [org_no] [peer_no] [options]
# e.g.
fabkit chaincode install mynodecc 1.0 mynodecc 1 0
fabkit chaincode instantiate mynodecc 1.0 mychannel 1 0 '{"Args":["init","a","100","b","200"]}'
```

Run the following commands in order to install and instantiate a newer version of an existing chaincode:

```bash
fabkit chaincode install [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no] [options]
fabkit chaincode upgrade [chaincode_name] [chaincode_version] [channel_name] [org_no] [peer_no] [options]
# e.g.
fabkit chaincode install mynodecc 1.1 mynodecc 1 0
fabkit chaincode upgrade mynodecc 1.1 mychannel 1 0 '{"Args":["init","a","100","b","200"]}'
```

Be sure the `chaincode_version` is unique and never used before (otherwise an error will be prompted).

## v2.x

The new chaincode lifecycle flow implemented in v2.x decentralizes much more the way in which a chaincode gets deployed into the network, enforcing security and empowering governance. However, this choice comes with an increase in complexity at the full expense of user experience.

Fabkit offers a simplified all-in-one command to perform this process.

The commands below will install, approve, commit and initialize a newer version of an existing chaincode.

```bash
fabkit chaincode lifecycle deploy [chaincode_name] [chaincode_version] [chaincode_path] [channel_name] [sequence_no] [org_no] [peer_no] [options]

# e.g. considering previous chaincode_version was 1.0 and sequence_no was 1 (using default peer)
fabkit chaincode lifecycle deploy mnynodeccv2 1.1 mynodeccv2 mychannel 2 1 0 '{"Args":["init","a","100","b","200"]}'
```

However, if you want more control over the single command execution, you can reproduce the exact same results as above by splitting that into the following steps:

```bash
fabkit chaincode lifecycle package [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no] [options]
# tip: run the install only if you are upgrading the chaincode binaries, otherwise no new container will be built (but also no errors will be thrown)
fabkit chaincode lifecycle install [chaincode_name] [chaincode_version] [org_no] [peer_no] [options]
fabkit chaincode lifecycle approve [chaincode_name] [chaincode_version] [channel_name] [sequence_no] [org_no] [peer_no] [options]
fabkit chaincode lifecycle commit [chaincode_name] [chaincode_version] [channel_name] [sequence_no] [org_no] [peer_no] [options]

# e.g. considering previous chaincode_version was 1.0 and sequence_no was 1 (using default peer)
fabkit chaincode lifecycle package mnynodeccv2 1.1 mnynodeccv2 1 0
fabkit chaincode lifecycle install mnynodeccv2 1.1 1 0
fabkit chaincode lifecycle approve mnynodeccv2 1.1 mychannel 2 1 0
fabkit chaincode lifecycle commit mnynodeccv2 1.1 mychannel 2 1 0 '{"Args":["init","a","100","b","200"]}'
```

> If you are upgrading the chaincode binaries, you need to update the chaincode version and the package ID in the chaincode definition. You can also update your chaincode endorsement policy without having to repackage your chaincode binaries. Channel members simply need to approve a definition with the new policy. The new definition needs to increment the sequence variable in the definition by one.

Be sure the `chaincode_version` is unique and never used before (otherwise an error will be prompted) and the `sequence_no` has an incremental value.

More details here: [Chaincode Lifecycle - Upgrade](https://hyperledger-fabric.readthedocs.io/en/release-2.0/chaincode4noah.html#upgrade-a-chaincode)

## Archive chaincode for deployment

Run the following command in order to create an archive for the selected chaincode including all the required dependencies:

```bash
fabkit chaincode zip [chaincode_name]
```

Follow the output message in console to see where the archive has been created.

## Package and sign chaincode for deployment

Some platforms, like IBPv2, do not accept `.zip` or archives which are not packaged and signed using the `peer chaincode package` Fabric functionality. In these specific cases you can use the following command:

```bash
fabkit chaincode package [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no]
```

Follow the output message in console to see where the package has been created.

## Private Data Collections

To know more about private data collections, see the [Private Data Collections](pdc.md) section.
