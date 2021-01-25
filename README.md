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
./scripts/runner.sh init
```

Note: **this command needs to be executed only once (however, there will be no harm if accidentally you run it again 😉 )**

## Install

Before starting the network, let's first install all the required dependencies:

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

To run the network in multi-org setup, you can use the `-o|--orgs <org_no>` flag, where `org_no` is a numeric integer:

```bash
fabkit network start --orgs <org_no>
```

Note: **The maximum number of organizations supported at the time of writing is 3.**

Or you might want to run a multi-org setup, in debug mode and on a specific version of Fabric:

```bash
fabkit network start -o 3 -d -v 1.4.9
```

For the full list of params, check the helper by typing `fabkit network`.

**Note: Fabkit will save the options of the last deployed network. To redeploy using the same configurations, simply run `fabkit network start`. To start afresh add the `-r` option to the command.**

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

## Invoke and query

It is possible to use the CLI to run and test functionalities via invoke and query.

**Note:** The function appearing as a string in the first place of the array `Args` needs to be defined in the chaincode and the `request` should be provided as a JSON wrapped into single quotes `'`.

### Invoke

```bash
fabkit chaincode invoke [channel_name] [chaincode_name] [org_no] [peer_no] [request]

# e.g.
fabkit chaincode invoke mychannel mygocc 1 0 '{"Args":["put","key1","10"]}'
```

### Query

```bash
fabkit chaincode query [channel_name] [chaincode_name] [org_no] [peer_no] [request]

# e.g.
fabkit chaincode query mychannel mygocc 1 0 '{"Args":["get","key1"]}'
```

## Chaincodes

To deep dive in all chaincode operations check out the [Working with chaincode](./docs/chaincode.md) section.

## Blockchain Explorer

![Hyperledger Explorer: Dashboard](./docs/images/explorer1.jpg)

![Hyperledger Explorer: Transaction Details](./docs/images/explorer2.jpg)

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

Note: If you are using _docker-machine_ replace `localhost` with the docker-machine IP address. You can find this out by running `docker-machine ip`.

## Register and enroll users

Fabkit offers full support to interact with a Fabric CA. To have a complete overview of the all available commands visit the [Fabric CA and user certificates management](./docs/ca.md) page.

## On Ordering service

The consensus mechanism for the Ordering Service so far fully supported by this repo is `SOLO`, however, there is a 1-org configuration made available for `Raft` as well and it can be used by replacing the following variable in the `.env` file:

```bash
FABKIT_CONFIGTX_PROFILE_NETWORK=OneOrgOrdererEtcdRaft
```

Then simply run the network with a single organization:

```bash
fabkit network start
```

All network available configurations can be found under `network/config`. Users can extend them on their own need.

## Benchmarks

Looking for benchmarking your network? Have a look [here](./docs/benchmarks.md).

## Troubleshooting

If you are experiencing any issue, before opening a ticket, please search among the existing ones or refer to the [troubleshooting](./docs/troubleshooting.md) page.
