package main

import (
	"bytes"
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric/core/chaincode/shim"
	pb "github.com/hyperledger/fabric/protos/peer"
)

type Chaincode struct {
}

// for scan or query results
type KV struct {
	Key   string
	Value string
}

type CompositeKey struct {
	ObjectType string
	Attributes []string
}

func (c *Chaincode) Init(stub shim.ChaincodeStubInterface) pb.Response {
	fmt.Println("Chaincode Init")
	return shim.Success(nil)
}

func (c *Chaincode) Invoke(stub shim.ChaincodeStubInterface) pb.Response {
	function, args := stub.GetFunctionAndParameters()
	fmt.Printf("Chaincode Invoke; function='%s'\n", function)

	if function == "put" {
		return c.put(stub, args)
	} else if function == "bulkPut" {
		return c.bulkPut(stub, args)
	} else if function == "bulkCreateCompositeKey" {
		return c.bulkCreateCompositeKey(stub, args)
	} else if function == "get" {
		return c.get(stub, args)
	} else if function == "scan" {
		return c.scan(stub, args)
	} else if function == "scanByPartialCompositeKey" {
		return c.scanByPartialCompositeKey(stub, args)
	} else if function == "scanByPartialCompositeKeyForAttributes" { // return list of attributes instead of KV
		return c.scanByPartialCompositeKeyForAttributes(stub, args)
	} else if function == "query" {
		return c.query(stub, args)
	} else if function == "delete" {
		return c.delete(stub, args)
	}

	return shim.Error("Invalid invoke function name. Expecting \"put\" \"get\" \"scan\" \"query\"")
}

func (c *Chaincode) delete(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	key := args[0]
	fmt.Printf("Deleting key='%s'\n", key)

	err := stub.DelState(key)
	if err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(nil)
}

func (c *Chaincode) put(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	key := args[0]
	value := args[1]

	fmt.Printf("Putting key='%s'\n", key)
	err := stub.PutState(key, []byte(value))
	if err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(nil)
}

func (c *Chaincode) bulkPut(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	kvListJsonString := args[0] // a json string of a list

	kvList := make([]KV, 0)

	err := json.Unmarshal([]byte(kvListJsonString), &kvList)
	if err != nil {
		fmt.Println("Error unmarshalling the kv list")
		return shim.Error(err.Error())
	}
	isError := false
	for _, kv := range kvList {
		fmt.Printf("Putting key='%s'\n", kv.Key)
		err := stub.PutState(kv.Key, []byte(kv.Value))
		if err != nil {
			fmt.Printf("Error Putting key='%s'\n", kv.Key)
			isError = true
			continue
		}
	}
	if isError {
		return shim.Error("There was one or more errors occurred when putting keys")
	}
	return shim.Success(nil)
}

func (c *Chaincode) bulkCreateCompositeKey(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	compositeKeyListJsonString := args[0] // a json string of a list

	compositeKeyList := make([]CompositeKey, 0)

	err := json.Unmarshal([]byte(compositeKeyListJsonString), &compositeKeyList)
	if err != nil {
		fmt.Println("Error unmarshalling the compositekey list")
		return shim.Error(err.Error())
	}
	isError := false
	for _, cKey := range compositeKeyList {

		indexKey, err := stub.CreateCompositeKey(cKey.ObjectType,
			cKey.Attributes)
		if err != nil {
			fmt.Println("Error Creating composite for objectType ", cKey.ObjectType)
			isError = true
			continue
		}
		fmt.Printf("Putting composite key='%s'\n", indexKey)
		// save the index entry on blockchain
		err = stub.PutState(indexKey, []byte{0x00})

		if err != nil {
			fmt.Printf("Error Putting composite key='%s'\n", indexKey)
			isError = true
			continue
		}
	}
	if isError {
		return shim.Error("There was one or more errors occurred when creating composite keys")
	}
	return shim.Success(nil)
}

func (c *Chaincode) get(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	key := args[0]

	fmt.Printf("Getting key='%s'\n", key)

	payload, err := stub.GetState(key)
	if err != nil {
		return shim.Error(err.Error())
	}

	return shim.Success(payload)
}

func (c *Chaincode) scan(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	startKey := args[0]
	endKey := args[1]

	fmt.Printf("scan starKey='%s' endKey='%s'\n", startKey, endKey)
	resultsIterator, err := stub.GetStateByRange(startKey, endKey)
	if err != nil {
		fmt.Println("Error with GetStateByRange")
		return shim.Error(err.Error())
	}
	defer resultsIterator.Close()

	arr := make([]KV, 0)
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return shim.Error(err.Error())
		}
		arr = append(arr, KV{
			Key:   queryResponse.Key,
			Value: string(queryResponse.Value),
		})
	}

	buffer := new(bytes.Buffer)
	encoder := json.NewEncoder(buffer)
	err = encoder.Encode(arr)
	if err != nil {
		fmt.Println("Error encoding the data")
		return shim.Error(err.Error())
	}

	return shim.Success(buffer.Bytes())

}

func (c *Chaincode) scanByPartialCompositeKey(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	objectType := args[0]
	valuesListJson := args[1]

	values := make([]string, 0)
	err := json.Unmarshal([]byte(valuesListJson), &values)
	if err != nil {
		fmt.Println("Unable to unmarshal the list of keys")
		return shim.Error("Unable to unmarshal the list of keys")
	}
	fmt.Println("start GetStateByPartialCompositeKey ", objectType, values)

	resultsIterator, err := stub.GetStateByPartialCompositeKey(objectType, values)
	if err != nil {
		fmt.Println("Error with GetStateByPartialCompositeKey")
		return shim.Error(err.Error())
	}

	defer resultsIterator.Close()

	arr := make([]KV, 0)
	for resultsIterator.HasNext() {
		responseRange, err := resultsIterator.Next()
		if err != nil {
			return shim.Error(err.Error())
		}
		_, compositeKeyParts, err := stub.SplitCompositeKey(responseRange.Key)
		if err != nil {
			fmt.Println("Error with SplitCompositeKey ", err.Error())
			continue
		}

		if len(compositeKeyParts) == 0 {
			fmt.Println("empty composite key parts")
			continue
		}
		fmt.Println("compositeKeyParts= ", compositeKeyParts)
		actualKey := compositeKeyParts[len(compositeKeyParts)-1] // assuming the last one is the state key
		valueJsonBytes, err := stub.GetState(actualKey)

		arr = append(arr, KV{
			Key:   actualKey,
			Value: string(valueJsonBytes),
		})
	}

	buffer := new(bytes.Buffer)
	encoder := json.NewEncoder(buffer)
	err = encoder.Encode(arr)
	if err != nil {
		fmt.Println("Error encoding the data")
		return shim.Error(err.Error())
	}

	return shim.Success(buffer.Bytes())

}

func (c *Chaincode) scanByPartialCompositeKeyForAttributes(stub shim.ChaincodeStubInterface, args []string) pb.Response {
	objectType := args[0]
	valuesListJson := args[1]

	values := make([]string, 0)
	err := json.Unmarshal([]byte(valuesListJson), &values)
	if err != nil {
		fmt.Println("Unable to unmarshal the list of keys")
		return shim.Error("Unable to unmarshal the list of keys")
	}
	fmt.Println("start GetStateByPartialCompositeKey ", objectType, values)

	resultsIterator, err := stub.GetStateByPartialCompositeKey(objectType, values)
	if err != nil {
		fmt.Println("Error with GetStateByPartialCompositeKey")
		return shim.Error(err.Error())
	}

	defer resultsIterator.Close()

	arr := make([][]string, 0)
	for resultsIterator.HasNext() {
		responseRange, err := resultsIterator.Next()
		if err != nil {
			return shim.Error(err.Error())
		}
		_, compositeKeyParts, err := stub.SplitCompositeKey(responseRange.Key)
		if err != nil {
			fmt.Println("Error with SplitCompositeKey ", err.Error())
			continue
		}

		if len(compositeKeyParts) == 0 {
			fmt.Println("empty composite key parts")
			continue
		}
		fmt.Println("compositeKeyParts= ", compositeKeyParts)

		arr = append(arr, compositeKeyParts)
	}

	fmt.Println("arr=", arr)
	buffer := new(bytes.Buffer)
	encoder := json.NewEncoder(buffer)
	err = encoder.Encode(arr)
	if err != nil {
		fmt.Println("Error encoding the data")
		return shim.Error(err.Error())
	}

	return shim.Success(buffer.Bytes())

}

func (c *Chaincode) query(stub shim.ChaincodeStubInterface, args []string) pb.Response {

	queryString := args[0]

	queryResults, err := getQueryResultForQueryString(stub, queryString)
	if err != nil {
		return shim.Error(err.Error())
	}
	return shim.Success(queryResults)
}

func getQueryResultForQueryString(stub shim.ChaincodeStubInterface, queryString string) ([]byte, error) {

	fmt.Printf("getQueryResultForQueryString queryString:\n%s\n", queryString)

	resultsIterator, err := stub.GetQueryResult(queryString)
	if err != nil {
		fmt.Println("Error with GetQueryResult :", err)
		return nil, err
	}
	defer resultsIterator.Close()

	arr := make([]KV, 0)
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}
		arr = append(arr, KV{
			Key:   queryResponse.Key,
			Value: string(queryResponse.Value),
		})
	}

	buffer := new(bytes.Buffer)
	encoder := json.NewEncoder(buffer)
	err = encoder.Encode(arr)
	if err != nil {
		fmt.Println("Error encoding the data")
		return nil, err
	}

	return buffer.Bytes(), nil
}

func main() {
	err := shim.Start(new(Chaincode))
	if err != nil {
		fmt.Printf("Error starting Procurement chaincode: %s", err)
	}
}
