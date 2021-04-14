# Troubleshooting

## Issue scenario

While registering a new user the fabric ca returns the following error

```bash
Error: Response from server: Error Code: 20 - Authorization failure
```

## Possible solutions

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

## Issue scenario

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

## Possible solutions

- If you are trying to enroll a registered user on Oracle this cannot be done by CLI. Please read the Oracle-related paragraph above.

## Issue scenario

While registering a user with an affiliation attribute the following error occurs

```bash
statusCode=500 (500 Internal Server Error)
Error: Response from server: Error Code: 0 - Registration of 'user_bdp1Z' failed in affiliation validation: Failed getting affiliation 'org1.example.com': : scode: 404, code: 63, msg: Failed to get Affiliation: sql: no rows in result set
```

## Possible solutions

- Be sure you are using an existing affiliation attribute (e.g. for sample setup with `org1.example.com` the affiliation attributes to use are `org1.department1` and `org1.department2`)

## Issue scenario

While installing a chaincode the following (or similar) error occurs

```bash
Error: error getting chaincode code pdc: error getting chaincode package bytes: Error writing src/github.com/hyperledger/fabric/peer/chaincode/pdc/vendor/golang.org/x/net/http/httpguts/guts.go to tar: Error copy (path: /opt/gopath/src/github.com/hyperledger/fabric/peer/chaincode/pdc/vendor/golang.org/x/net/http/httpguts/guts.go, oldname:guts.go,newname:src/github.com/hyperledger/fabric/peer/chaincode/pdc/vendor/golang.org/x/net/http/httpguts/guts.go,sz:1425) : archive/tar: write too long
```

## Possible solutions

It is a common error in environments running under low resources (or not-Linux machines).

If your docker is running on less than half of your available CPU and RAM, try to reallocate more resources.

It could also be related to mismatched references between packages in `vendor` and the ones written in `go.sum`. **Try to delete the ./chaincode/[chaincode]/go.sum** file.

Keep refiring the same command.

## Issue scenario

While enrolling a user via Fabric CA CLI towards a network running on Oracle Blockchain Platform, the following error occurs:

```bash
Error: Response from server: Error Code: 0 - The following required attributes are missing: [hf.Registrar.Attributes hf.AffiliationMgr]
# or
Error: Invalid option in attribute request specification at 'admin=false:ecert'; the value after the colon must be 'opt'
```

## Possible solutions

When asked to provide enrollment attributes be sure you are either using a correct list of attributes (check existing attributes querying the CA) or you can simply pass an empty string `""`

## Issue scenario

- You running Docker on a Mac

- Your version of Docker is > 2.3.x

While running the app with `fabkit network start` or trying to instantiate a chaincode, the following error occurs:

```bash
Error: could not assemble transaction, err proposal response was not successful, error code 500, msg error starting container: error starting container: Post http://unix.sock/containers/create?name=dev-peer0.org1.example.com-mygocc-1.0: dial unix /host/var/run/docker.sock: connect: no such file or directory
```

## Possible solutions

- Uncheck “Use gRPC FUSE for file sharing” option in the Docker "Preferences > Experimental Features" and restart your daemon

## Issue scenario

When running the network start command, the following error message is shown:

```bash
   → Generating cryptos ⡿
       [ERROR] Failed to generate crypto material
       [ERROR] panic: runtime error: invalid memory address or nil pointer dereference
       [ERROR] 2021-04-14 12:56:30.685 UTC [bccsp_sw] storePrivateKey -> ERRO 001 Failed storing private key [e77c33598a67d7c08d2be1e920c80a602ef0b56343d9a3ccb62e7bacb5cc6a2e]: [open /crypto-config/peerOrganizations/org1.example.com/ca/e77c33598a67d7c08d2be1e920c80a602ef0b56343d9a3ccb62e7bacb5cc6a2e_sk: stale NFS file handle]
```

## Possible solutions

It is a volume synchronization error that happens with docker every so often. Try to run the same command again.
