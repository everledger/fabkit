# Hyperledger Fabric Chaincode Boilerplate 

A basic and simple boilerplate which contains utilities for efficiently writing chaincode and test it in a running network.

#### Note: If this is a fork, follow the special paragraph contained in this README

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
./run.sh network install
```

## Run the blockchain network

The following command will spin a Hyperledger Fabric network up, generating _channel_ and _crypto_ config at runtime:

```bash
./run.sh network start
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
- Instantiate the chaincode on the default peer

Afterwards, the network will be ready to accept `invoke` and `query` functions.

Run `./run.sh help` for the complete list of functionalities.

## Restart a previously running network

The following command will restart a Hyperledgre Fabric network only if a _data_ directory is found:

```bash
./run.sh network restart
```

## Upgrade chaincode

Run the following command in order to install and instantiate a new version of the chaincode:

```bash
./run.sh chaincode upgrade [chaincode_name] [chaincode_version] [channel_name]
```

Be sure the `chaincode_version` is unique and never used before (otherwise an error will be prompted).

## Invoke and query

It is possible to use the CLI to run and test functionalities.

**Note:** The function appearing as a string in the first place of the array `Args` needs to be defined in the chaincode and the `request` should be provided as a JSON wrapped into single quotes `'`.

### Invoke

```bash
./run.sh chaincode invoke [channel_name] [chaincode_name] [request]

# e.g.
./run.sh chaincode invoke mychannel mychaincode '{"Args":["put","key1","10"]}'
```

### Query

```bash
./run.sh chaincode query [channel_name] [chaincode_name] [request]

# e.g.
./run.sh chaincode query mychannel mychaincode '{"Args":["get","key1"]}'
```

## Explore

This code is provided with a graphical blockchain explorer powered by [Hyperledger Explorer](https://github.com/hyperledger/blockchain-explorer) and other useful tools, such as [Grafana](https://grafana.com/) and [Prometheus](https://prometheus.io/), in order to have full control over the data stored in your ledger.

**Note: Before running the following command be sure the connection profile contains the right information related to your running network. Pay particularly attention to the private key of the admin user that should reflect the one in your crypto path.**

```json
organizations": {
		"Org1MSP": {
			"mspid": "Org1MSP",
			"fullpath": true,
			"adminPrivateKey": {
				"path": "/tmp/crypto/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/keystore/0dff7b7853afac8b81bcc97d52ce165930288878e041b8def8af80e981d81502_sk"
			},
```

Once the configuration is ready, you can run the explorer (and all the connected tools) with a simple command:

```bash
./run.sh network explore
```

### Blockchain Explorer

- Username: `admin` | Password: `adminpw`

- Host: `http://localhost:8090`

### Grafana

- Username: `admin` | Password: `admin`

- Host: `http://localhost:3000`

## Register and enroll users

todo

## Cleanup the environment

### Tear blockchain network down

It will stop and remove all the blockchain network containers including the `dev-peer*` tagged chaincode ones.

```bash
./run.sh network stop
```

## Benchmarks

The repository provides also a simple implementation of a bulk load function in order to benchmark the general speed of the network in terms of tps (transactions-per-second).

```bash
./run.sh benchmark [jobs] [entries]

# e.g.
./run.sh benchmark 5 1000
```

The example above will do a bulk load of 1000 entries times 5 parallel jobs, for a total of 5000 entries. At the completion of all the jobs it will be prompted on screen the elapsed time of the total task.

**Note: Maintain the number of jobs not superior to your CPU cores in order to obtain the best results. This implementation does not provides a complete parallelisation.**

To achieve the optimal result it is recommended to install [Gnu Parallel](https://www.gnu.org/software/parallel/) and use as it follows:

```bash
time (parallel ./benchmarks.sh {} ::: [entries])

# e.g.
time (parallel ./benchmarks.sh {} ::: 20)
# 8.613 total against 29.893 total
# ~4 times lower than running jobs with "&"
```

## Forks

There are a few changes to make to your new forked repository in order to make it work properly.

- Replace all the occurrences of `bitbucket.org/everledger/fabric-chaincode-boilerplate` with your current go package

- Create a new directory under the `./chaincode` path. It has to match with the name of your final binary install.

- Run `./run.sh dep install [chaincode_path]` from your main project directory

In `.env`:

- Replace `CHAINCODE_REMOTE_PATH` with the correct package `GOPATH` and chaincode directory

```bash
# e.g.
CHAINCODE_REMOTE_PATH="bitbucket.org/everledger/evl-prov-pfm-cc-wine/chaincode"
```

- Replace `CHAINCODE_NAME` with the correct directory name path of the chaincode you want to install

```bash
# e.g.
CHAINCODE_NAME=wine
```

In the main `go.mod`:

- Add the reference to the new chaincode path as follows

```go
// before
require (
    bitbucket.org/everledger/evl-prov-pfm-cc-wine/chaincode/mychaincode v0.0.0
)

replace (
    bitbucket.org/everledger/evl-prov-pfm-cc-wine/chaincode/mychaincode v0.0.0 => ./chaincode/mychaincode
)
```

```go
// after
require (
    bitbucket.org/everledger/evl-prov-pfm-cc-wine/chaincode/mychaincode v0.0.0
    bitbucket.org/everledger/evl-prov-pfm-cc-wine/chaincode/wine v0.0.0
)

replace (
    bitbucket.org/everledger/evl-prov-pfm-cc-wine/chaincode/mychaincode v0.0.0 => ./chaincode/mychaincode
    bitbucket.org/everledger/evl-prov-pfm-cc-wine/chaincode/wine v0.0.0 => ./chaincode/wine
)
```

In `bitbucket-pipelines.yml`

- Replace `mychaincode` with the chaincode name you have in `.env` at the right of `CHAINCODE_NAME`

- If you want, you can add a link to this repository in your `README`, like:

```markdown
Forked from [fabric-chaincode-boilerplate](https://bitbucket.org/everledger/fabric-chaincode-boilerplate
```

Et voila'!

## Sync up

In order to sync your repository with the new changes coming from the `main` one, you can do the following:

- Add the `main` repository to the list of your remotes with `git remote add main git@bitbucket.org:everledger/fabric-chaincode-boilerplate.git`

- Check the repository has been added with `git remote -v`

- Pull all the upcoming changes from `main` with `git pull main`

- Merge (or rebase) these new changes into your current branch

```bash
git merge main/master
```

Merge will result with **a single commit**.

or

```bash
git rebase main/master
# after fixing the conflicts, keep on using the next 2 commands to register the changes and continue with the next commit to attach
git add .
git rebase --continue
# use the following only when there are no changes to apply
git rebase --skip
# use the following only if you want to abort the rebasing
git rebase --abort
```

Rebase will result with **the list of all the previous commits** applied.
