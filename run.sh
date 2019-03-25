#!/bin/sh

set -o errexit
export GO111MODULE=on

readonly ROOT=$PWD
readonly CONFIG_PATH=${ROOT}/network
readonly CHAINCODE_PATH=${ROOT}/chaincode
readonly CHAINCODE_UTIL_CONTAINER=channel-chaincode-util
readonly CHANNELS_CONFIG_PATH=/etc/hyperledger/channels
readonly ORDERER_ADDRESS=orderer.example.com:7050

readonly GOLANG_DOCKER_IMAGE=golang
readonly GOLANG_DOCKER_TAG=1.11.4-alpine3.8
# if version not passed in, default to latest released version
export FABRIC_VERSION=1.4
# current version of thirdparty images (couchdb, kafka and zookeeper) released
export FABRIC_THIRDPARTY_IMAGE_VERSION=0.4.14

help() {
  echo "Usage: run.sh [command]"
  echo 
  echo "commands:"
  echo 
  echo "help                                                                        : this help"
  echo "start_network                                                               : start the blockchain network and initialize it"
  echo "stop_network                                                                : stop the blockchain network and remove all the docker containers"
  echo "install_chaincode [chaincode_name] [chaincode_version] [chaincode_path]     : install chaincode on a peer"
  echo "instantiate_chaincode [chaincode_name] [chaincode_version] [channel_name]   : instantiate chaincode on a peer for an assigned channel"
  echo "upgrade_chaincode [channel_name] [chaincode_name] [chaincode_version]       : upgrade chaincode with a new version"
  echo "query [channel_name] [chaincode_name] [data_in_json]                        : run query in the format '{\"Args\":\"queryFunction\",\"key\"]}'"
  echo "invoke [channel_name] [chaincode_name] [data_in_json]                       : run invoke in the format '{\"Args\":[\"invokeFunction\",\"key\",\"value\"]}'"
  echo "test_chaincode                                                              : run unit tests"
  echo "build_chaincode                                                             : run build and test against the binary file"
  echo "generate_cryptos                                                            : generate all the crypto keys and certificates for the network"
  echo "create_channel [channel_name]                                               : generate channel configuration file"
  echo "update_channel [channel_name] [org]                                         : update channel with anchor peers"
  echo "join_channel [channel_name]                                                 : run by a peer to join a channel"
}

install() {
	echo "Installing dependencies"

	echo "Pulling Go docker image"
	docker pull ${GOLANG_DOCKER_IMAGE}:${GOLANG_DOCKER_TAG}

	__docker_fabric_pull
	__docker_third_party_images_pull
}

__docker_fabric_pull() {
  local FABRIC_TAG=$FABRIC_VERSION
  for IMAGES in peer orderer ca ccenv javaenv tools; do
      echo "==> FABRIC IMAGE: $IMAGES"
      echo
      docker pull hyperledger/fabric-$IMAGES:$FABRIC_TAG
      docker tag hyperledger/fabric-$IMAGES:$FABRIC_TAG hyperledger/fabric-$IMAGES
  done
}

__docker_third_party_images_pull() {
  local THIRDPARTY_TAG=$FABRIC_THIRDPARTY_IMAGE_VERSION
  for IMAGES in couchdb kafka zookeeper; do
      echo "==> THIRDPARTY DOCKER IMAGE: $IMAGES"
      echo
      docker pull hyperledger/fabric-$IMAGES:$THIRDPARTY_TAG
      docker tag hyperledger/fabric-$IMAGES:$THIRDPARTY_TAG hyperledger/fabric-$IMAGES
  done
}

start_network() {
	build_chaincode
	test_chaincode
	echo "Starting Fabric network"
	generate_cryptos
	docker-compose up -d
	sleep 5
	initialize_network
}

initialize_network() {
	echo "Initializing Fabric network"
	create_channel mychannel
	join_channel mychannel
	update_channel mychannel Org1MSP
	install_chaincode mychaincode 1.0 mychaincode
	instantiate_chaincode mychaincode 1.0 mychannel
}

test_chaincode() {
	echo "Running unit testing on chaincode"
	(cd $CHAINCODE_PATH; go test ./src/... -v)
	# docker run --rm -v "$CHAINCODE_PATH":/usr/src/myapp -w /usr/src/myapp everledgerio/golang sh -c "go clean -modcache; rm go.sum; go test"
}

build_chaincode() {
	echo "Building chaincode"
	cd $CHAINCODE_PATH
	CGO_ENABLED=0 go build -a -installsuffix nocgo -o binary ./src/...
	# docker run -v "$CHAINCODE_PATH":/usr/src/myapp -w /usr/src/myapp -e CGO_ENABLED=0 everledgerio/golang sh -c "go clean -modcache; rm go.sum; go build -a -installsuffix nocgo -o binary ./..."
	echo "Testing built chaincode"
	go test -c -o binary_test ./...
	# docker run -v "$CHAINCODE_PATH":/usr/src/myapp -w /usr/src/myapp -e CGO_ENABLED=0 everledgerio/golang sh -c "go clean -modcache; rm go.sum; go test -c -o binary_test ./..."
	rm -rf binary binary_test
	cd $ROOT
}

stop_network() {
	echo "Tearing Fabric network down"
	docker rm -f -v $(docker ps -aq) 2>/dev/null; docker rmi $(docker images -qf "dangling=true") 2>/dev/null; docker rmi $(docker images | grep "dev-" | awk "{print $1}") 2>/dev/null; docker rmi $(docker images | grep "^<none>" | awk "{print $3}") 2>/dev/null;
}

generate_cryptos() {
	if [ -d "network/crypto-config" ]; then
		echo "crypto-config already exists"
		read -p "Do you wish to re-generate crypto-config? [yes/no] " yn
		case $yn in
			[YyEeSs]* ) ;;
			* ) return 0
    	esac
	fi 
	echo "Generating crypto-config"

	local channel_name=mychannel
    local org=Org1MSP

	# remove previous crypto material and config transactions
	rm -fr ${CONFIG_PATH}/config ${CONFIG_PATH}/crypto-config
	mkdir ${CONFIG_PATH}/config ${CONFIG_PATH}/crypto-config

	# generate crypto material
	docker run --rm -v ${CONFIG_PATH}/crypto-config.yaml:/crypto-config.yaml -v ${CONFIG_PATH}/crypto-config:/crypto-config hyperledger/fabric-tools:$FABRIC_VERSION cryptogen generate --config=/crypto-config.yaml --output=/crypto-config
	if [ "$?" -ne 0 ]; then
		echo "Failed to generate crypto material..."
		exit 1
	fi

	# generate genesis block for orderer
	docker run --rm -v ${CONFIG_PATH}/configtx.yaml:/configtx.yaml -v ${CONFIG_PATH}/config:/config -v ${CONFIG_PATH}/crypto-config:/crypto-config -e FABRIC_CFG_PATH=/ hyperledger/fabric-tools:$FABRIC_VERSION configtxgen -profile OneOrgOrdererGenesis -outputBlock /config/genesis.block /configtx.yaml
	if [ "$?" -ne 0 ]; then
		echo "Failed to generate orderer genesis block..."
		exit 1
	fi

	# generate channel configuration transaction
	docker run --rm -v ${CONFIG_PATH}/configtx.yaml:/configtx.yaml -v ${CONFIG_PATH}/config:/config -v ${CONFIG_PATH}/crypto-config:/crypto-config -e FABRIC_CFG_PATH=/ hyperledger/fabric-tools:$FABRIC_VERSION configtxgen -profile OneOrgChannel -outputCreateChannelTx /config/${channel_name}.tx -channelID $channel_name /configtx.yaml
	if [ "$?" -ne 0 ]; then
		echo "Failed to generate channel configuration transaction..."
		exit 1
	fi

	# generate anchor peer transaction
	docker run --rm -v ${CONFIG_PATH}/configtx.yaml:/configtx.yaml -v ${CONFIG_PATH}/config:/config -v ${CONFIG_PATH}/crypto-config:/crypto-config -e FABRIC_CFG_PATH=/ hyperledger/fabric-tools:$FABRIC_VERSION configtxgen -profile OneOrgChannel -outputAnchorPeersUpdate /config/${org}_anchors.tx -channelID $channel_name -asOrg ${org} /configtx.yaml
	if [ "$?" -ne 0 ]; then
		echo "Failed to generate anchor peer update for Org1MSP..."
		exit 1
	fi
}

create_channel() {
	if [ -z "$1" ]; then
		echo "Missing channel_name"
		exit 1
	fi

	local channel_name="$1"

	echo "Creating channel $channel_name using configuration file $CHANNELS_CONFIG_PATH/$channel_name/$channel_name.tx"
	docker exec $CHAINCODE_UTIL_CONTAINER peer channel create -o $ORDERER_ADDRESS -c $channel_name -f $CHANNELS_CONFIG_PATH/$channel_name/$channel_name.tx --outputBlock $CHANNELS_CONFIG_PATH/$channel_name/$channel_name.block
}

join_channel() {
 	if [ -z "$1" ]; then
		echo "Missing channel_name"
		exit 1
	fi

	local channel_name="$1"

	echo "Joining channel $channel_name"
    docker exec $CHAINCODE_UTIL_CONTAINER peer channel join -b $CHANNELS_CONFIG_PATH/$channel_name/$channel_name.block
}

update_channel() {
	if [ -z "$1" ] || [ -z "$2" ]; then
		echo "The command should be in the format: ./run.sh update_channel [channel_name] [org]"
		exit 1
	fi

	local channel_name="$1"
    local org="$2"

	echo "Updating anchors peers $channel_name using configuration file $CHANNELS_CONFIG_PATH/$channel_name/${org}_anchors.tx"
	docker exec $CHAINCODE_UTIL_CONTAINER peer channel update -o $ORDERER_ADDRESS -c $channel_name -f $CHANNELS_CONFIG_PATH/$channel_name/${org}_anchors.tx
}

install_chaincode() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echo "The command should be in the format: ./run.sh install_chaincode chaincode_name 1.0 chaincode_path"
		exit 1
	fi

	local chaincode_name="$1"
	local chaincode_version="$2"
	local chaincode_path="$3"

    docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode install -n $chaincode_name -v $chaincode_version -p $chaincode_path
}

instantiate_chaincode() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echo "The command should be in the format: ./run.sh instantiate_chaincode chaincode_name 1.0 channel_name"
		exit 1
	fi

	local chaincode_name="$1"
	local chaincode_version="$2"
	local channel_name="$3"

	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode instantiate -n $chaincode_name -v $chaincode_version -C $channel_name -c '{"Args":[]}'
}

upgrade_chaincode() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echo "The command should be in the format: ./run.sh upgrade_chaincode mychaincode 1.0 mychannel"
		exit 1
	fi

	local chaincode_name="$1"
	local chaincode_version="$2"
	local channel_name="$3"

	build_chaincode
	test_chaincode
	install_chaincode $chaincode_name $chaincode_version $channel_name
	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode upgrade -n $chaincode_name -v $chaincode_version -C $channel_name -c '{"Args":[]}'
}

invoke() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echo 'The command should be in the format: ./run.sh invoke channel_name chaincode_name '{"Args":["put","key1","10"]}''
		exit 1
	fi

	local channel_name="$1"
	local chaincode_name="$2"
	local request="$3"

	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode invoke -o $ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c $request
}

query() {
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		echo 'The command should be in the format: ./run.sh query channel_name chaincode_name '{"Args":"get","key1"]}''
		exit 1
	fi

	local channel_name="$1"
	local chaincode_name="$2"
	local request="$3"

	docker exec $CHAINCODE_UTIL_CONTAINER peer chaincode query -o $ORDERER_ADDRESS -C $channel_name -n $chaincode_name -c $request	
}

"$@"

