# Fabric CA and user certificates management

The Hyperledger Fabric CA is a Certificate Authority (CA) for Hyperledger Fabric.

It provides features such as:

- registration of identities, or connects to LDAP as the user registry

- issuance of Enrollment Certificates (ECerts)

- certificate renewal and revocation

Hyperledger Fabric CA consists of both a server and a client component.

This section is meant to discuss the basic interactions a client can perform with either local or remote server which may sit on-prem or on a BaaS, such as Oracle Blockchain Platform (OBP) or IBM Blockchain Platform (IBP).

## Base Prerequisites

To perform any of the below procedures you need to have satisfied the following prerequisites:

- Downloaded locally the CA root certificate (for IBP, that is usually available directly in the connection profile, but it needs to be converted from string to file without \n and other escape characters)

- Downloaded the connection profile if available or be sure you have on your hands the following information

  - Admin username (commonly `admin`) and password. This user needs to have the right permissions in order to perform any of the operations below.

  - Organization name

  - CA hostname and port

## Register and enroll a new user

### Prerequisites

- Fulfilled all the base prerequisites

- Username and password of the new user to register and enroll

- User attributes, affiliation and type (see [Fabric CA documentation](https://hyperledger-fabric-ca.readthedocs.io/en/latest/users-guide.html))

### Steps

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

## Renew an expired certificate

Hyperledger Fabric certificates do not last forever and they usually have an expiration date which is set by default to **1 year**.
That means, after such period, any operation made by a blockchain identity with an expired certificate will not work, causing possible disruptions on the system.

The procedure to renew a certificate follows a few steps but it is not that banal, so please read these lines below very carefully and be sure you are running these commands on a machine you trust and you have access to the output log (in console should be sufficient).

### Prerequisites

- Same as for enrollment

## Steps

- Enroll the `admin` user to retrieve its certificate (if you do not have it yet)

```bash
fabkit ca enroll
```

- Re-enroll the user with the expired certificate

```bash
fabkit ca reenroll
```

## Revoke a certificate

An identity or a certificate can be revoked. Revoking an identity will revoke all the certificates owned by the identity and will also prevent the identity from getting any new certificates. Revoking a certificate will invalidate a single certificate.

In order to revoke a certificate or an identity, the calling identity must have the `hf.Revoker` and `hf.Registrar.Roles` attribute. The revoking identity can only revoke a certificate or an identity that has an affiliation that is equal to or prefixed by the revoking identity’s affiliation. Furthermore, the revoker can only revoke identities with types that are listed in the revoker’s hf.Registrar.Roles attribute.

For example, a revoker with affiliation `orgs.org1` and `hf.Registrar.Roles=peer,client` attribute can revoke either a peer or client type identity affiliated with `orgs.org1` or `orgs.org1.department1` but can’t revoke an identity affiliated with `orgs.org2` or of any other type.

### Prerequisites

- Fulfilled all the base prerequisites

- Username and password of the user whom we want to revoke the certificate

## Steps

```bash
fabkit ca revoke
```

## Registering and enrolling users on PaaS

### Oracle Blockchain Platform

We have two way of registering and enrolling users in OBP:

1. using Oracle Identity Cloud service, which, however, locks the user key and certificate to be used internally by any of the restproxy service. **Pick this option if you think you will only operate via Oracle restproxy service and you do not need to have these certificates at your hand** (not recommended)

   - In order to register new user on OBP, please refer to the official Oracle documentation - [Set users and application roles](https://docs.oracle.com/en/cloud/paas/blockchain-cloud/administer/set-users-and-application-roles.html)

   - In order to enroll a registered user on OBP via Identity Management, please refer to this section on the documentation - [Add enrollments to the REST Proxy](https://docs.oracle.com/en/cloud/paas/blockchain-cloud/user/manage-rest-proxy-nodes.html#GUID-D24E018A-58B0-43FE-AFE1-B297A791D4EB)

2. via normal Fabric CA CLI interaction. See section below. **Note that during enrollment you will need to insert the correct list of attributes attached to the user during the registration step, otherwise, a workaround is to pass an empty string `""` (but only if you do want to set any attributes)**

The OBP configuration and cryptos can be downloaded from `Developer Tools > Application Development > OBP`.

### IBM Blockchain Platform

At the time of writing, IBM provides two version of their BaaS. In both cases, we are able to register and enroll users directly via UI, but we will not be able to download those certificates from there.

If we want to use a specific user certificate and key, we need first to download the connection profile and cryptos from the platform dashboard and then perform the steps listed in this section in order to retrieve those credentials.