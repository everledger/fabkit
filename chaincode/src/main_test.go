package main

import (
	"encoding/json"
	"testing"
	"fmt"
	"github.com/hyperledger/fabric/core/chaincode/shim"
	"github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/suite"
)

type ChaincodeTS struct {
    suite.Suite
	stub *shim.MockStub
}

// setup will be run for all tests in the suite
func (suite *ChaincodeTS) SetupTest() {
	suite.stub = shim.NewMockStub("mockStub", new(Chaincode))
	assert.NotNil(suite.T(), suite.stub, "MockStub creation failed")
	// call the constructor
	result := suite.stub.MockInit("1",[][]byte{
		[]byte("init"),
		[]byte{}})
	assert.EqualValues(suite.T(), result.Status, shim.OK, "Init is not successful")
}

func (suite *ChaincodeTS) TestInit() { 

}

func (suite *ChaincodeTS) TestPut() {

	testKey := "key1"
	testValue := "value1"
	// call put
	result := suite.stub.MockInvoke("1", [][]byte{
		[]byte("put"),
		[]byte(testKey),
		[]byte(testValue) })

	assert.EqualValues(suite.T(), shim.OK, result.Status, "Put failed")
		
		// get the underlying state value to verify
	val, _ := suite.stub.GetState(testKey)
	assert.Equal(suite.T(), testValue, string(val), "Value is not correctly put")

}


// to run just this test 
// go test -v -run TestProcurementSuite/TestBulkPut
func (suite *ChaincodeTS) TestBulkPut() {

	kvList := make([]KV,0)
	kvList = append(kvList, KV{Key: "key1",  Value: "value1"})
	kvList = append(kvList, KV{Key: "key2",  Value: "value2"})
	kvList = append(kvList, KV{Key: "key3",  Value: "value3"})

	kvListJson, _  := json.Marshal(&kvList)
	fmt.Println("json list of KV ", string(kvListJson))
	// call bulkPut
	result := suite.stub.MockInvoke("1", [][]byte{
		[]byte("bulkPut"),
		[]byte(kvListJson) })

	assert.EqualValues(suite.T(), shim.OK, result.Status, "Bulk Put failed")
		
	// get the underlying state value to verify
	for _, kv := range kvList {
		val, _ := suite.stub.GetState(kv.Key)
		assert.Equal(suite.T(), kv.Value, string(val), "Value is not correctly put")
	}
}

func (suite *ChaincodeTS) TestBulkCreateCompositeKey() {
	compositeKeyList  := make ([]CompositeKey, 0)
	compositeKeyList  = append (compositeKeyList, CompositeKey{ObjectType:"UniqueVersionID~QuestionID~AnswerKey", Attributes: []string{"U", "Q1", "AnswerKey1"} })
	compositeKeyList  = append (compositeKeyList, CompositeKey{ObjectType:"UniqueVersionID~QuestionID~AnswerKey", Attributes: []string{"U", "Q2", "AnswerKey2"} })
	compositeKeyList  = append (compositeKeyList, CompositeKey{ObjectType:"UniqueVersionID~QuestionID~AnswerKey", Attributes: []string{"U", "Q3", "AnswerKey3"} })

	compositeKeyListJson, _  := json.Marshal(&compositeKeyList)
	fmt.Println("json list of compositeKeys ", string(compositeKeyListJson))

	result := suite.stub.MockInvoke("1", [][]byte{
		[]byte("bulkCreateCompositeKey"),
		[]byte(compositeKeyListJson) })

	assert.EqualValues(suite.T(), shim.OK, result.Status, "bulkCreateCompositeKey  failed")
	
	
	// put somevalue for AnswerKey2 befpre scanning
	suite.stub.MockTransactionStart("1")
	suite.stub.PutState("AnswerKey2", []byte("Answer2Value"))
	suite.stub.MockTransactionStart("1")

	
	// move to scan part
	valuesListJson, _  := json.Marshal([]string{"U", "Q2"})
	result = suite.stub.MockInvoke("1", [][]byte{
		[]byte("scanByPartialCompositeKey"),
		[]byte("UniqueVersionID~QuestionID~AnswerKey"),
		[]byte(valuesListJson)})
	assert.EqualValues(suite.T(), shim.OK, result.Status, "scanByPartialCompositeKey failed")
	fmt.Println("scanByPartialCompositeKey results ", string(result.Payload))

	expectedResult := "[{\"Key\":\"AnswerKey2\",\"Value\":\"Answer2Value\"}]\n"
	assert.EqualValues(suite.T(), expectedResult,
		string(result.Payload), "")

	// scan for attribute
	result = suite.stub.MockInvoke("1", [][]byte{
		[]byte("scanByPartialCompositeKeyForAttributes"),
		[]byte("UniqueVersionID~QuestionID~AnswerKey"),
		[]byte(valuesListJson)})
	expectedResult = "[[\"U\",\"Q2\",\"AnswerKey2\"]]\n"
		assert.EqualValues(suite.T(), expectedResult,
			string(result.Payload), "")	
	fmt.Println("scanByPartialCompositeKeyForAttributes results ", string(result.Payload))
}

func (suite *ChaincodeTS) TestGet() {
	testKey := "key1"
	testValue := "value1"

	// put something for the underlying state 
	suite.stub.MockTransactionStart("1")
	suite.stub.PutState(testKey, []byte(testValue))
	suite.stub.MockTransactionStart("1")

	// call get
	result := suite.stub.MockInvoke("1", [][]byte{
		[]byte("get"),
		[]byte(testKey)})

	assert.EqualValues(suite.T(), shim.OK, result.Status, "Get failed")
	assert.EqualValues(suite.T(), testValue, string(result.Payload), "Get payload not the same as expected")


	// NOTE: this test does not pass; MockStub does not return error when the key does not exist
	// test for  a key which does not exist
	// result = suite.stub.MockInvoke("1", [][]byte{
	// 	[]byte("get"),
	// 	[]byte("some_non_existent_key")})
	// assert.EqualValues(suite.T(), shim.ERROR, result.Status, "Get failed")
	

	//  call put
	testKey = "key2"
	testValue = "value2"
	result = suite.stub.MockInvoke("1", [][]byte{
		[]byte("put"),
		[]byte(testKey),
		[]byte(testValue) })

	result = suite.stub.MockInvoke("1", [][]byte{
		[]byte("get"),
		[]byte(testKey)})

	assert.EqualValues(suite.T(), shim.OK, result.Status, "Get failed")
	assert.EqualValues(suite.T(), testValue, string(result.Payload), "Get payload not the same as expected")
}

func (suite *ChaincodeTS) TestScan() {

	// put a range of key and values
	for i:=1; i < 20; i++ {
		key := fmt.Sprintf("key%02d", i)	
		value := fmt.Sprintf("value%02d", i)
		result := suite.stub.MockInvoke("1", [][]byte{
			[]byte("put"),
			[]byte(key),
			[]byte(value) })
		assert.EqualValues(suite.T(), shim.OK, result.Status, "Put failed")
	}

	
	startKey := "key07"
	endKey := "key14"
	result := suite.stub.MockInvoke("1", [][]byte{
		[]byte("scan"),
		[]byte(startKey),
		[]byte(endKey) })
	assert.EqualValues(suite.T(), shim.OK, result.Status, "Scan failed")

	expectedPayload :="[{\"Key\":\"key07\",\"Value\":\"value07\"},{\"Key\":\"key08\",\"Value\":\"value08\"},{\"Key\":\"key09\",\"Value\":\"value09\"},{\"Key\":\"key10\",\"Value\":\"value10\"},{\"Key\":\"key11\",\"Value\":\"value11\"},{\"Key\":\"key12\",\"Value\":\"value12\"},{\"Key\":\"key13\",\"Value\":\"value13\"}]\n"
	assert.EqualValues(suite.T(), expectedPayload, string(result.Payload), "Scan payload is incorrect")
}

func (suite *ChaincodeTS) TestQuery() {
	// put some key 
	// and value will be json structure
	valueJSON := `{"docID":"%d", "title":"content-%d}`
	for i:=1; i < 10; i++ {
		key := fmt.Sprintf("key%02d", i)	
		value := fmt.Sprintf(valueJSON, i, i)
		fmt.Printf("key='%s' value='%s'\n", key, value)
		result := suite.stub.MockInvoke("1", [][]byte{
			[]byte("put"),
			[]byte(key),
			[]byte(value) })
		assert.EqualValues(suite.T(), shim.OK, result.Status, "Put failed")
	}

	// call query
	queryString := "{\"selector\":{\"docID\":\"3\"}}"
	result := suite.stub.MockInvoke("1", [][]byte{
		[]byte("query"),
		[]byte(queryString) })
	_ = result 
	// NOTE: those mocks for unit tests do no implement these queries;
	// Need to test with actual fabric setup
	//
	//assert.EqualValues(suite.T(), shim.OK, result.Status, "Query failed")
	

}


func TestSuite(t *testing.T) {
    suite.Run(t, new(ChaincodeTS))
}
