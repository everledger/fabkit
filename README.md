# Fabkit

## Prerequisites

- [Go](https://golang.org/dl/) [>= 1.12]
- [Docker](https://www.docker.com/get-started) [>= 18.05]
- [Docker-compose](https://www.docker.com/get-started) [>= 1.24]

## Pre-install

In order to run commands with ease, we recommend to add `fabkit` as an alias in your default shell profile.

You can perform this step manually, as follows:

```bash
# for bash users
echo "alias fabkit=./fabkit" >> ~/.bashrc
source ~/.bashrc

# for zsh users
echo "alias fabkit=./fabkit" >> ~/.zshrc
source ~/.bashrc
```

or, if you do not know what shell you are using, you can let this script doing it for you:

```bash
./scripts/runner.sh
```

Note: **this command needs to be executed only once (however, there will be no harm if accidentally you run it again 😉 )**

## Install

Before starting our network, let's first install all the required dependencies:

```bash
fabkit network install
```

## Run the blockchain network

The following command will spin a Hyperledger Fabric network up, generating _channel_ and _crypto_ config at runtime:

```bash
fabkit network start
# or
fabkit network start --orgs 1
```

It will execute the following functions:

- Build and test the chaincode
- Run unit tests
- Generate crypto materials
- Generate genesis block
- Generate default channel configuration files
- Add default peer to join the channel
- Update the channel with anchor peers
- Install the default chaincode into the default peer
- (v1.x) Instantiate the chaincode on the default peer
- (v2.x) Approve, commit and init the chaincode on the default peer and organization

Afterwards, the network will be ready to accept `invoke` and `query` functions.

Run `fabkit help` for the complete list of functionalities.

### Run the network with different configurations

You may want to run the network with multiple organizations or by using customized network and channel profiles.

To run the network in multi-org setup, you can use the `-o|--orgs <number>` flag, where `number` is a numeric integer:

```bash
fabkit network start --orgs <number>
```

Note: **The maximum number of organizations supported at the time of writing is 3.**

Or you might want to run a multi-org setup, in debug mode and on a specific version of Fabric:

```bash
fabkit networks start -o 3 -d -v 1.4.9
```

For the full list of params, check the helper by typing `fabkit network`.

### On ordering service

The consensus mechanism for the Ordering Service so far fully supported by this repo is `SOLO`, however, there is a 1-org configuration made available for `Raft` as well and it can be used by replacing the following variable in the `.env` file:

```bash
CONFIGTX_PROFILE_NETWORK=OneOrgOrdererEtcdRaft
```

Then simply run the network with a single organization:

```bash
fabkit network start
```

All network available configurations can be found under `network/config`. Users can extend them on their own need.

## Stop a running network

The following command will stop all the components of your running network while preserving all the stored data into the _data_ directory by default:

```bash
fabkit network stop
```

## Restart a previously running network

The following command will restart a network with the configuration of your last run only if a _data_ directory is found:

```bash
fabkit network restart
```

## Chaincodes

Fabkit currently supports _golang_, _node_ and _java_ chaincodes. To deploy a chaincode from your own directory, you must set the following env variables before starting the network:

- `CHAINCODE_PATH`: Absolute path to the directory to be mounted
- `CHAINCODE_REMOTE_PATH`: Mount path inside the cli container. _Golang chaincodes must be mounted inside `GOPATH` ( `/opt/gopath/src` )_

To deploy chaincode using Fabkit's commands refer below.

_Note `options` is an optional parameter. For more information about all the available options check the following documentations:_

- [v1.x Chaincode Commands](https://hyperledger-fabric.readthedocs.io/en/latest/commands/peerchaincode.html)
- [v2.x Chaincode Commands](https://hyperledger-fabric.readthedocs.io/en/latest/commands/peerlifecycle.html)

### v1.x

Run the following commands in order to install and instantiate a new chaincode:

```bash
fabkit chaincode install [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no] [options]
fabkit chaincode instantiate [chaincode_name] [chaincode_version] [chaincode_path] [channel_name] [org_no] [peer_no] [options]
# e.g.
fabkit chaincode install mynodecc 1.0 node/mychaincode 1 0
fabkit chaincode instantiate mynodecc 1.0 node/mychaincode mychannel 1 0 '{"Args":["init","a","100","b","200"]}'
```

Run the following commands in order to install and instantiate a newer version of an existing chaincode:

```bash
fabkit chaincode install [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no] [options]
fabkit chaincode upgrade [chaincode_name] [chaincode_version] [chaincode_path] [channel_name] [org_no] [peer_no] [options]
# e.g.
fabkit chaincode install mynodecc 1.1 node/mychaincode 1 0
fabkit chaincode upgrade mynodecc 1.1 node/mychaincode mychannel 1 0 '{"Args":["init","a","100","b","200"]}'
```

Be sure the `chaincode_version` is unique and never used before (otherwise an error will be prompted).

### v2.x

The new chaincode lifecycle flow implemented in v2.x decentralizes much more the way in which a chaincode gets deployed into the network, enforcing security and empowering governance. However, this choice comes with an increase in complexity at the full expense of user experience.

Fabkit offers a simplified all-in-one command to perform this process.

The commands below will install, approve, commit and initialize a newer version of an existing chaincode.

```bash
fabkit chaincode lifecycle deploy [chaincode_name] [chaincode_version] [chaincode_path] [channel_name] [sequence_no] [org_no] [peer_no] [options]

# e.g. considering previous chaincode_version was 1.0 and sequence_no was 1 (using default peer)
fabkit chaincode lifecycle deploy abstore 1.1 node/abstore mychannel 2 1 0 '{"Args":["init","a","100","b","200"]}'
```

However, if you want more control over the single command execution, you can reproduce the exact same results as above by splitting that into the following steps:

```bash
fabkit chaincode lifecycle package [chaincode_name] [chaincode_version] [chaincode_path] [org_no] [peer_no] [options]
# tip: run the install only if you are upgrading the chaincode binaries, otherwise no new container will be built (but also no errors will be thrown)
fabkit chaincode lifecycle install [chaincode_name] [chaincode_version] [org_no] [peer_no] [options]
fabkit chaincode lifecycle approve [chaincode_name] [chaincode_version] [channel_name] [sequence_no] [org_no] [peer_no] [options]
fabkit chaincode lifecycle commit [chaincode_name] [chaincode_version] [channel_name] [sequence_no] [org_no] [peer_no] [options]

# e.g. considering previous chaincode_version was 1.0 and sequence_no was 1 (using default peer)
fabkit chaincode lifecycle package abstore 1.1 node/abstore 1 0
fabkit chaincode lifecycle install abstore 1.1 1 0
fabkit chaincode lifecycle approve abstore 1.1 mychannel 2 1 0
fabkit chaincode lifecycle commit abstore 1.1 mychannel 2 1 0 '{"Args":["init","a","100","b","200"]}'
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

## Invoke and query

It is possible to use the CLI to run and test functionalities via invoke and query.

**Note:** The function appearing as a string in the first place of the array `Args` needs to be defined in the chaincode and the `request` should be provided as a JSON wrapped into single quotes `'`.

### Invoke

```bash
fabkit chaincode invoke [channel_name] [chaincode_name] [org_no] [peer_no] [request]

# e.g.
fabkit chaincode invoke mychannel mychaincode 1 0 '{"Args":["put","key1","10"]}'
```

### Query

```bash
fabkit chaincode query [channel_name] [chaincode_name] [org_no] [peer_no] [request]

# e.g.
fabkit chaincode query mychannel mychaincode 1 0 '{"Args":["get","key1"]}'
```

## Private Data Collections

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
- peer0.org1 (mychaincode installed)
- couchdb.peer0.org1
- ca.org2
- peer0.org2
- couchdb.peer0.org2
- ca.org3
- peer0.org3
- couchdb.peer0.org3
- cli

Install and instantiate the `pdc` chaincode:

### v1.x

```bash
# install the pdc chaincode on all the organizations' peer0
fabkit chaincode install pdc 1.0 golang/pdc 1 0
fabkit chaincode install pdc 1.0 golang/pdc 2 0
fabkit chaincode install pdc 1.0 golang/pdc 3 0

# instantiate pdc chaincode on mychannel using org1 peer0
fabkit chaincode instantiate pdc 1.0 golang/pdc mychannel 1 0 --collections-config ${CHAINCODE_REMOTE_PATH}/golang/pdc/collections_config.json -P 'OR("Org1MSP.member","Org2MSP.member","Org3MSP.member")'
```

### v2.x

```bash
fabkit chaincode lifecycle deploy pdc 1.0 golang/pdc mychannel 1 1 0 --collections-config ${CHAINCODE_REMOTE_PATH}/golang/pdc/collections_config.json
```

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

## Blockchain Explorer

![Hyperledger Explorer: Dashboard](./_imgs/explorer1.jpg)

![Hyperledger Explorer: Transaction Details](./_imgs/explorer2.jpg)

This code is provided with a graphical blockchain explorer powered by [Hyperledger Explorer](https://github.com/hyperledger/blockchain-explorer) and other useful tools, such as [Grafana](https://grafana.com/) and [Prometheus](https://prometheus.io/), in order to have full control over the data stored in your ledger.

Once the configuration is ready, you can run the explorer (and all the connected tools) with a simple command:

```bash
fabkit explorer start
```

To stop and remove all the running Explorer processes:

```bash
fabkit explorer stop
```

### UI Explorer

- Username: `admin` | Password: `adminpw`

- Host: [http://localhost:8090](http://localhost:8090)

### Grafana

- Username: `admin` | Password: `admin`

- Host: [http://localhost:3000](http://localhost:3000)

## Fabric CA and user certificates management

The Hyperledger Fabric CA is a Certificate Authority (CA) for Hyperledger Fabric.

It provides features such as:

- registration of identities, or connects to LDAP as the user registry

- issuance of Enrollment Certificates (ECerts)

- certificate renewal and revocation

Hyperledger Fabric CA consists of both a server and a client component.

This section is meant to discuss the basic interactions a client can perform with either local or remote server which may sit on-prem or on a BaaS, such as Oracle Blockchain Platform (OBP) or IBM Blockchain Platform (IBP).

### Base Prerequisites

To perform any of the below procedures you need to have satisfied the following prerequisites:

- Downloaded locally the CA root certificate (for IBP, that is usually available directly in the connection profile, but it needs to be converted from string to file without \n and other escape characters)

- Downloaded the connection profile if available or be sure you have on your hands the following information

  - Admin username (commonly `admin`) and password. This user needs to have the right permissions in order to perform any of the operations below.

  - Organization name

  - CA hostname and port

### Register and enroll a new user

#### Prerequisites

- Fulfilled all the base prerequisites

- Username and password of the new user to register and enroll

- User attributes, affiliation and type (see [Fabric CA documentation](https://hyperledger-fabric-ca.readthedocs.io/en/latest/users-guide.html))

#### Steps

- Enroll the `admin` user to retrieve its certificate (if you do not have it yet)

```bash
fabkit ca enroll
```

- Register the new user

```bash
fabkit ca register
```

- Enroll the new user (using same username and password used previously for registering it)

```bash
fabkit ca enroll
```

This final command will generate a new certificate for the user under `network/cryptos/<org_name>/<username>` directory.

### Renew an expired certificate

Hyperledger Fabric certificates do not last forever and they usually have an expiration date which is set by default to **1 year**.
That means, after such period, any operation made by a blockchain identity with an expired certificate will not work, causing possible disruptions on the system.

The procedure to renew a certificate follows a few steps but it is not that banal, so please read these lines below very carefully and be sure you are running these commands on a machine you trust and you have access to the output log (in console should be sufficient).

#### Prerequisites

- Same as for enrollment

### Steps

- Enroll the `admin` user to retrieve its certificate (if you do not have it yet)

```bash
fabkit ca enroll
```

- Re-enroll the user with the expired certificate

```bash
fabkit ca reenroll
```

### Revoke a certificate

An identity or a certificate can be revoked. Revoking an identity will revoke all the certificates owned by the identity and will also prevent the identity from getting any new certificates. Revoking a certificate will invalidate a single certificate.

In order to revoke a certificate or an identity, the calling identity must have the `hf.Revoker` and `hf.Registrar.Roles` attribute. The revoking identity can only revoke a certificate or an identity that has an affiliation that is equal to or prefixed by the revoking identity’s affiliation. Furthermore, the revoker can only revoke identities with types that are listed in the revoker’s hf.Registrar.Roles attribute.

For example, a revoker with affiliation `orgs.org1` and `hf.Registrar.Roles=peer,client` attribute can revoke either a peer or client type identity affiliated with `orgs.org1` or `orgs.org1.department1` but can’t revoke an identity affiliated with `orgs.org2` or of any other type.

#### Prerequisites

- Fulfilled all the base prerequisites

- Username and password of the user whom we want to revoke the certificate

### Steps

```bash
fabkit ca revoke
```

### Registering and enrolling users on PaaS

#### Oracle Blockchain Platform

We have two way of registering and enrolling users in OBP:

1. using Oracle Identity Cloud service, which, however, locks the user key and certificate to be used internally by any of the restproxy service. **Pick this option if you think you will only operate via Oracle restproxy service and you do not need to have these certificates at your hand** (not recommended)

   - In order to register new user on OBP, please refer to the official Oracle documentation - [Set users and application roles](https://docs.oracle.com/en/cloud/paas/blockchain-cloud/administer/set-users-and-application-roles.html)

   - In order to enroll a registered user on OBP via Identity Management, please refer to this section on the documentation - [Add enrollments to the REST Proxy](https://docs.oracle.com/en/cloud/paas/blockchain-cloud/user/manage-rest-proxy-nodes.html#GUID-D24E018A-58B0-43FE-AFE1-B297A791D4EB)

2. via normal Fabric CA CLI interaction. See section below. **Note that during enrollment you will need to insert the correct list of attributes attached to the user during the registration step, otherwise, a workaround is to pass an empty string `""` (but only if you do want to set any attributes)**

The OBP configuration and cryptos can be downloaded from `Developer Tools > Application Development > OBP`.

#### IBM Blockchain Platform

At the time of writing, IBM provides two version of their BaaS. In both cases, we are able to register and enroll users directly via UI, but we will not be able to download those certificates from there.

If we want to use a specific user certificate and key, we need first to download the connection profile and cryptos from the platform dashboard and then perform the steps listed in this section in order to retrieve those credentials.

## Benchmarks

The repository provides also a simple implementation of a bulk load function in order to benchmark the general speed of the network in terms of tps (transactions-per-second).

```bash
fabkit benchmark load [jobs] [entries]

# e.g.
fabkit benchmark load 5 1000
```

The example above will do a bulk load of 1000 entries times 5 parallel jobs, for a total of 5000 entries. At the completion of all the jobs it will be prompted on screen the elapsed time of the total task.

**Note: Maintain the number of jobs not superior to your CPU cores in order to obtain the best results. This implementation does not provides a complete parallelization.**

To achieve the optimal result it is recommended to install [Gnu Parallel](https://www.gnu.org/software/parallel/) and use as it follows:

```bash
time (parallel ./benchmarks.sh {} ::: [entries])

# e.g.
time (parallel ./benchmarks.sh {} ::: 20)
# 8.613 total against 29.893 total
# ~4 times lower than running jobs with "&"
```

### Troubleshooting

#### Issue scenario

While registering a new user the fabric ca returns the following error

```bash
Error: Response from server: Error Code: 20 - Authorization failure
```

#### Possible solutions

- Be sure the CA certificate and the admin credentials you are using are valid and retrievable from the script

- You may need to enroll again the admin using username and password (try it with `fabkit enroll`)

- **Be sure you are using the same versions of fabric-ca both in your server and client. Note that IBP, at the time of writing, is using v1.1.0, so be sure your fabric-ca-client is the exact same.**

```bash
fabric-ca-client version

fabric-ca-client:
 Version: 1.1.0
 Go version: go1.9.2
 OS/Arch: darwin/amd64
```

#### Issue scenario

While enrolling a user with username and password the following error occurs

```bash
statusCode=401 (401 Unauthorized)
Error: Failed to parse response: <html>
<head><title>401 Authorization Required</title></head>
<body bgcolor="white">
<center><h1>401 Authorization Required</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

#### Possible solutions

- If you are trying to enroll a registered user on Oracle this cannot be done by CLI. Please read the Oracle-related paragraph above.

#### Issue scenario

While registering a user with an affiliation attribute the following error occurs

```bash
statusCode=500 (500 Internal Server Error)
Error: Response from server: Error Code: 0 - Registration of 'user_bdp1Z' failed in affiliation validation: Failed getting affiliation 'org1.example.com': : scode: 404, code: 63, msg: Failed to get Affiliation: sql: no rows in result set
```

#### Possible solutions

- Be sure you are using an existing affiliation attribute (e.g. for sample setup with `org1.example.com` the affiliation attributes to use are `org1.department1` and `org1.department2`)

#### Issue scenario

While installing a chaincode the following (or similar) error occurs

```bash
Error: error getting chaincode code pdc: error getting chaincode package bytes: Error writing src/github.com/hyperledger/fabric/peer/chaincode/pdc/vendor/golang.org/x/net/http/httpguts/guts.go to tar: Error copy (path: /opt/gopath/src/github.com/hyperledger/fabric/peer/chaincode/pdc/vendor/golang.org/x/net/http/httpguts/guts.go, oldname:guts.go,newname:src/github.com/hyperledger/fabric/peer/chaincode/pdc/vendor/golang.org/x/net/http/httpguts/guts.go,sz:1425) : archive/tar: write too long
```

#### Possible solutions

It is a common error in environments running under low resources (or not-Linux machines).

If your docker is running on less than half of your available CPU and RAM, try to reallocate more resources.

It could also be related to mismatched references between packages in `vendor` and the ones written in `go.sum`. **Try to delete the ./chaincode/[chaincode]/go.sum** file.

Keep refiring the same command.

#### Issue scenario

While enrolling a user via Fabric CA CLI towards a network running on Oracle Blockchain Platform, the following error occurs:

```bash
Error: Response from server: Error Code: 0 - The following required attributes are missing: [hf.Registrar.Attributes hf.AffiliationMgr]
# or
Error: Invalid option in attribute request specification at 'admin=false:ecert'; the value after the colon must be 'opt'
```

#### Possible solutions

When asked to provide enrollment attributes be sure you are either using a correct list of attributes (check existing attributes querying the CA) or you can simply pass an empty string `""`

#### Issue scenario

- You running Docker on a Mac

- Your version of Docker is > 2.3.x

While running the app with `fabkit network start` or trying to instantiate a chaincode, the following error occurs:

```bash
Error: could not assemble transaction, err proposal response was not successful, error code 500, msg error starting container: error starting container: Post http://unix.sock/containers/create?name=dev-peer0.org1.example.com-mychaincode-1.0: dial unix /host/var/run/docker.sock: connect: no such file or directory
```

#### Possible solutions

- Uncheck “Use gRPC FUSE for file sharing” option in the Docker "Preferences > Experimental Features" and restart your daemon
