#!/bin/bash

NC=$'\e[0m'
RED=$'\e[0;31m'
GREEN=$'\e[0;32m'

function infoln() {
  echo "${GREEN}${1}${NC}"
}

function errorln() {
  echo "${RED}${1}${NC}"
}

function ifFailExit() {
  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    errorln "Failed"
    exit 1
  else
    infoln "Successful"
  fi
}

function pullBinaries() {
  ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')")

  VERSION=2.2.0

  URL="https://github.com/hyperledger/fabric/releases/download/v${VERSION}/hyperledger-fabric-${ARCH}-${VERSION}.tar.gz"
  infoln "Download Fabric ${VERSION} Binaries"
  infoln "${URL}"
  curl -L "${URL}" | tar xz
  ifFailExit

  CA_VERSION=1.4.8

  URL="https://github.com/hyperledger/fabric-ca/releases/download/v${CA_VERSION}/hyperledger-fabric-ca-${ARCH}-${CA_VERSION}.tar.gz"
  infoln "Download Fabric CA ${CA_VERSION} Binaries"
  infoln "${URL}"
  curl -L "${URL}" | tar xz
  ifFailExit
}

# Scenario

#pullBinaries

infoln "Cleaning"
rm -rf "${PWD}/channel-artifacts"
rm -rf "${PWD}/organizations"
rm -rf "${PWD}/system-genesis-block"
rm -f "${PWD}/basic.tar.gz"
docker-compose -f docker/docker-compose.yaml stop ca_org1
docker-compose -f docker/docker-compose.yaml stop ca_org2
docker-compose -f docker/docker-compose.yaml stop ca_orderer
docker-compose -f docker/docker-compose.yaml stop orderer.example.com
docker-compose -f docker/docker-compose.yaml stop peer0.org1.example.com
docker-compose -f docker/docker-compose.yaml stop peer0.org2.example.com

infoln "Starting CA Servers"
docker-compose -f docker/docker-compose.yaml up -d ca_org1
docker-compose -f docker/docker-compose.yaml up -d ca_org2
docker-compose -f docker/docker-compose.yaml up -d ca_orderer
DELAY=5
infoln "Waiting ${DELAY} Seconds"
sleep ${DELAY}

export PATH=${PWD}/bin:${PATH}

export FABRIC_CA_CLIENT_HOME=${PWD}/organizations/peerOrganizations/org1.example.com/
export FABRIC_CA_CLIENT_CANAME=ca-org1
export FABRIC_CA_CLIENT_TLS_CERTFILES=${PWD}/organizations/fabric-ca/org1/tls-cert.pem

infoln "Enroll Org1 CA admin"
fabric-ca-client enroll -u https://admin:adminpw@localhost:7054

echo 'NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/localhost-7054-ca-org1.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/localhost-7054-ca-org1.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/localhost-7054-ca-org1.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/localhost-7054-ca-org1.pem
    OrganizationalUnitIdentifier: orderer
' > "${PWD}/organizations/peerOrganizations/org1.example.com/msp/config.yaml"

infoln "Register Org1 peer0"
fabric-ca-client register --id.name peer0 --id.secret peer0pw --id.type peer

infoln "Register Org1 user1"
fabric-ca-client register --id.name user1 --id.secret user1pw --id.type client

infoln "Register Org1 org1admin"
fabric-ca-client register --id.name org1admin --id.secret org1adminpw --id.type admin

mkdir -p "${PWD}/organizations/peerOrganizations/org1.example.com/peers"
mkdir -p "${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com"

infoln "Generate Org1 peer0 msp"
fabric-ca-client enroll --url https://peer0:peer0pw@localhost:7054 --mspdir "${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/msp" --csr.hosts peer0.org1.example.com
ifFailExit

cp "${PWD}/organizations/peerOrganizations/org1.example.com/msp/config.yaml" "${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/msp/config.yaml"

infoln "Generate Org1 peer0 tls certificates"
fabric-ca-client enroll --url https://peer0:peer0pw@localhost:7054 --mspdir "${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls" --enrollment.profile tls --csr.hosts peer0.org1.example.com --csr.hosts localhost
ifFailExit

cp "${PWD}"/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/tlscacerts/* "${PWD}"/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
cp "${PWD}"/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/signcerts/* "${PWD}"/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/server.crt
cp "${PWD}"/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/keystore/* "${PWD}"/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/server.key

mkdir -p "${PWD}"/organizations/peerOrganizations/org1.example.com/msp/tlscacerts
cp "${PWD}"/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/tlscacerts/* "${PWD}"/organizations/peerOrganizations/org1.example.com/msp/tlscacerts/ca.crt

mkdir -p "${PWD}"/organizations/peerOrganizations/org1.example.com/tlsca
cp "${PWD}"/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/tlscacerts/* "${PWD}"/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem

mkdir -p "${PWD}"/organizations/peerOrganizations/org1.example.com/ca
cp "${PWD}"/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/msp/cacerts/* "${PWD}"/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem

mkdir -p organizations/peerOrganizations/org1.example.com/users
mkdir -p organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com

infoln "Generate Org1 user1 msp"
fabric-ca-client enroll --url https://user1:user1pw@localhost:7054 --mspdir "${PWD}/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp"
ifFailExit

cp "${PWD}"/organizations/peerOrganizations/org1.example.com/msp/config.yaml "${PWD}"/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/config.yaml

mkdir -p organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com

infoln "Generate Org1 org1admin msp"
fabric-ca-client enroll --url https://org1admin:org1adminpw@localhost:7054 --mspdir "${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
ifFailExit

cp "${PWD}"/organizations/peerOrganizations/org1.example.com/msp/config.yaml "${PWD}"/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp/config.yaml

mkdir -p organizations/peerOrganizations/org2.example.com/
export FABRIC_CA_CLIENT_HOME=${PWD}/organizations/peerOrganizations/org2.example.com/
export FABRIC_CA_CLIENT_CANAME=ca-org2
export FABRIC_CA_CLIENT_TLS_CERTFILES=${PWD}/organizations/fabric-ca/org2/tls-cert.pem

infoln "Enroll Org2 CA admin"
fabric-ca-client enroll -u https://admin:adminpw@localhost:8054

echo 'NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/localhost-8054-ca-org2.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/localhost-8054-ca-org2.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/localhost-8054-ca-org2.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/localhost-8054-ca-org2.pem
    OrganizationalUnitIdentifier: orderer
' > "${PWD}/organizations/peerOrganizations/org2.example.com/msp/config.yaml"

infoln "Register Org2 peer0"
fabric-ca-client register --id.name peer0 --id.secret peer0pw --id.type peer

infoln "Register Org2 user1"
fabric-ca-client register --id.name user1 --id.secret user1pw --id.type client

infoln "Register Org2 org2admin"
fabric-ca-client register --id.name org2admin --id.secret org2adminpw --id.type admin

mkdir -p organizations/peerOrganizations/org2.example.com/peers
mkdir -p organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com

infoln "Generate Org2 peer0 msp"
fabric-ca-client enroll --url https://peer0:peer0pw@localhost:8054 --mspdir "${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/msp" --csr.hosts peer0.org2.example.com
ifFailExit

cp "${PWD}"/organizations/peerOrganizations/org2.example.com/msp/config.yaml "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/msp/config.yaml

infoln "Generate Org2 peer0 tls certificates"
fabric-ca-client enroll --url https://peer0:peer0pw@localhost:8054 --mspdir "${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls" --enrollment.profile tls --csr.hosts peer0.org2.example.com --csr.hosts localhost
ifFailExit

cp "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/tlscacerts/* "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
cp "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/signcerts/* "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/server.crt
cp "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/keystore/* "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/server.key

mkdir -p "${PWD}"/organizations/peerOrganizations/org2.example.com/msp/tlscacerts
cp "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/tlscacerts/* "${PWD}"/organizations/peerOrganizations/org2.example.com/msp/tlscacerts/ca.crt

mkdir -p "${PWD}"/organizations/peerOrganizations/org2.example.com/tlsca
cp "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/tlscacerts/* "${PWD}"/organizations/peerOrganizations/org2.example.com/tlsca/tlsca.org2.example.com-cert.pem

mkdir -p "${PWD}"/organizations/peerOrganizations/org2.example.com/ca
cp "${PWD}"/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/msp/cacerts/* "${PWD}"/organizations/peerOrganizations/org2.example.com/ca/ca.org2.example.com-cert.pem

mkdir -p organizations/peerOrganizations/org2.example.com/users
mkdir -p organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com

infoln "Generate Org2 user1 msp"
fabric-ca-client enroll --url https://user1:user1pw@localhost:8054 --mspdir "${PWD}/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp"
ifFailExit

cp "${PWD}"/organizations/peerOrganizations/org2.example.com/msp/config.yaml "${PWD}"/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/config.yaml

mkdir -p organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com

infoln "Generate Org2 org2admin msp"
fabric-ca-client enroll --url https://org2admin:org2adminpw@localhost:8054 --mspdir "${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"
ifFailExit

cp "${PWD}"/organizations/peerOrganizations/org2.example.com/msp/config.yaml "${PWD}"/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp/config.yaml

mkdir -p organizations/ordererOrganizations/example.com
export FABRIC_CA_CLIENT_HOME=${PWD}/organizations/ordererOrganizations/example.com
export FABRIC_CA_CLIENT_CANAME=ca-orderer
export FABRIC_CA_CLIENT_TLS_CERTFILES=${PWD}/organizations/fabric-ca/ordererOrg/tls-cert.pem

infoln "Enroll Orderer CA admin"
fabric-ca-client enroll -u https://admin:adminpw@localhost:9054

echo 'NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/localhost-9054-ca-orderer.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/localhost-9054-ca-orderer.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/localhost-9054-ca-orderer.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/localhost-9054-ca-orderer.pem
    OrganizationalUnitIdentifier: orderer
' > "${PWD}/organizations/ordererOrganizations/example.com/msp/config.yaml"

infoln "Register Orderer orderer"
fabric-ca-client register --id.name orderer --id.secret ordererpw --id.type orderer

infoln "Register Orderer ordererAdmin"
fabric-ca-client register --id.name ordererAdmin --id.secret ordererAdminpw --id.type admin

mkdir -p organizations/ordererOrganizations/example.com/orderers
mkdir -p organizations/ordererOrganizations/example.com/orderers/example.com

mkdir -p organizations/ordererOrganizations/example.com/orderers/orderer.example.com

infoln "Generate Orderer msp"
fabric-ca-client enroll --url https://orderer:ordererpw@localhost:9054 --mspdir "${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp" --csr.hosts orderer.example.com
ifFailExit

cp "${PWD}"/organizations/ordererOrganizations/example.com/msp/config.yaml "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/config.yaml


infoln "Generate Orderer tls certificates"
fabric-ca-client enroll --url https://orderer:ordererpw@localhost:9054 --mspdir "${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls" --enrollment.profile tls --csr.hosts orderer.example.com --csr.hosts localhost
ifFailExit

cp "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/tlscacerts/* "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt
cp "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/signcerts/* "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt
cp "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/keystore/* "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key

mkdir -p "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts
cp "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/tlscacerts/* "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

mkdir -p "${PWD}"/organizations/ordererOrganizations/example.com/msp/tlscacerts
cp "${PWD}"/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/tls/tlscacerts/* "${PWD}"/organizations/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem

mkdir -p organizations/ordererOrganizations/example.com/users
mkdir -p organizations/ordererOrganizations/example.com/users/Admin@example.com

infoln "Generate Orderer admin msp"
fabric-ca-client enroll --url https://ordererAdmin:ordererAdminpw@localhost:9054 --mspdir "${PWD}/organizations/ordererOrganizations/example.com/users/Admin@example.com/msp"
ifFailExit

cp "${PWD}"/organizations/ordererOrganizations/example.com/msp/config.yaml "${PWD}"/organizations/ordererOrganizations/example.com/users/Admin@example.com/msp/config.yaml


infoln "Generating Orderer Genesis block"
export FABRIC_CFG_PATH=$PWD/configtx
mkdir -p "$PWD/system-genesis-block"
configtxgen -profile TwoOrgsOrdererGenesis -channelID system-channel -outputBlock ./system-genesis-block/genesis.block
ifFailExit

docker-compose -f docker/docker-compose.yaml up -d orderer.example.com
docker-compose -f docker/docker-compose.yaml up -d peer0.org1.example.com
docker-compose -f docker/docker-compose.yaml up -d peer0.org2.example.com
DELAY=5
infoln "Waiting ${DELAY} Seconds"
sleep ${DELAY}

infoln "Generate Channel Configuration transaction"
export FABRIC_CFG_PATH=$PWD/configtx
mkdir -p "$PWD/channel-artifacts"
configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/mychannel.tx -channelID mychannel
ifFailExit

for ORGMSP in Org1MSP Org2MSP; do
	infoln "Generating anchor peer update transaction for ${ORGMSP}"
	configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/${ORGMSP}anchors.tx -channelID mychannel -asOrg ${ORGMSP}
	ifFailExit
done

infoln "Creating channel"
export FABRIC_CFG_PATH=${PWD}/config/
export ORDERER_CA=${PWD}/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG1_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
peer channel create -o localhost:7050 -c mychannel --ordererTLSHostnameOverride orderer.example.com -f ./channel-artifacts/mychannel.tx --outputBlock ./channel-artifacts/mychannel.block --tls --cafile $ORDERER_CA
ifFailExit

infoln "Join Org1 peers to the channel"
peer channel join -b ./channel-artifacts/mychannel.block
ifFailExit

infoln "Join Org2 peers to the channel"
export PEER0_ORG2_CA=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org2MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG2_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:9051
peer channel join -b ./channel-artifacts/mychannel.block
ifFailExit

infoln "Updating anchor peers for org1"
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG1_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
peer channel update -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com -c mychannel -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls --cafile $ORDERER_CA
ifFailExit

infoln "Updating anchor peers for org2"
export PEER0_ORG2_CA=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org2MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG2_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:9051
peer channel update -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com -c mychannel -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls --cafile $ORDERER_CA
ifFailExit

infoln "Package Chaincode"
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG1_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
peer lifecycle chaincode package basic.tar.gz --path "${PWD}/chaincode" --lang golang --label basic_1.0
ifFailExit

infoln "Installing chaincode on peer0.org1"
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG1_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
peer lifecycle chaincode install basic.tar.gz
ifFailExit

infoln "Installing chaincode on peer0.org2"
export PEER0_ORG2_CA=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org2MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG2_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:9051
peer lifecycle chaincode install basic.tar.gz
ifFailExit

infoln "Check installed on peer0.org1"
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG1_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
PACKAGE_ID=$(peer lifecycle chaincode queryinstalled | sed -n "/basic_1.0/{s/^Package ID: //; s/, Label:.*$//; p;}")
ifFailExit

infoln "Approve chaincode definition on peer0.org1 on 'mychannel'"
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG1_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "${ORDERER_CA}" --channelID mychannel --name basic --version 1.0 --package-id "${PACKAGE_ID}" --sequence 1
ifFailExit

infoln "Check installed on peer0.org2"
export PEER0_ORG2_CA=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org2MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG2_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:9051
PACKAGE_ID=$(peer lifecycle chaincode queryinstalled | sed -n "/basic_1.0/{s/^Package ID: //; s/, Label:.*$//; p;}")
ifFailExit

infoln "Approve chaincode definition on peer0.org2 on 'mychannel'"
export PEER0_ORG2_CA=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org2MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG2_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:9051
peer lifecycle chaincode approveformyorg -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "${ORDERER_CA}" --channelID mychannel --name basic --version 1.0 --package-id "${PACKAGE_ID}" --sequence 1
ifFailExit

infoln "Check commit readiness on peer0.org1 on 'mychannel'"
export PEER0_ORG1_CA=${PWD}/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG1_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp
export CORE_PEER_ADDRESS=localhost:7051
peer lifecycle chaincode checkcommitreadiness --channelID mychannel --name basic --version 1.0 --sequence 1 --output json
ifFailExit

infoln "Check commit readiness on peer0.org2 on 'mychannel'"
export PEER0_ORG2_CA=${PWD}/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
export CORE_PEER_LOCALMSPID="Org2MSP"
export CORE_PEER_TLS_ROOTCERT_FILE=${PEER0_ORG2_CA}
export CORE_PEER_MSPCONFIGPATH=${PWD}/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
export CORE_PEER_ADDRESS=localhost:9051
peer lifecycle chaincode checkcommitreadiness --channelID mychannel --name basic --version 1.0 --sequence 1 --output json
ifFailExit

#infoln "Commit Chaincode Definition"
#peer lifecycle chaincode commit -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile "$ORDERER_CA" --channelID mychannel --name basic "${PEER_CONN_PARMS}" --version "${CC_VERSION}" --sequence ${CC_SEQUENCE} ${INIT_REQUIRED} ${CC_END_POLICY} ${CC_COLL_CONFIG}