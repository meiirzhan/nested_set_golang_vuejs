package main

import (
  "fmt"
	"bytes"
	"encoding/json"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"testing"
)

var a App

func TestMain(m *testing.M) {
	a = App{}
	a.Initialize("root", "", "nested_set_db")

	code := m.Run()

	clearTable()

	os.Exit(code)
}

func clearTable() {
	a.DB.Exec("DELETE FROM _ns_tree")
	a.DB.Exec("ALTER TABLE _ns_tree AUTO_INCREMENT = 1")
}

const tableCreationQuery = `
CREATE TABLE IF NOT EXISTS nodes
(
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    age INT NOT NULL
)`

func TestEmptyTable(t *testing.T) {
	clearTable()

	req, _ := http.NewRequest("GET", "/nodes", nil)
	response := executeRequest(req)

	checkResponseCode(t, http.StatusOK, response.Code)

	if body := response.Body.String(); body != "[]" {
		t.Errorf("Expected an empty array. Got %s", body)
	}
}

func executeRequest(req *http.Request) *httptest.ResponseRecorder {
	rr := httptest.NewRecorder()
	a.Router.ServeHTTP(rr, req)

	return rr
}

func checkResponseCode(t *testing.T, expected, actual int) {
	if expected != actual {
		t.Errorf("Expected response code %d. Got %d\n", expected, actual)
	}
}

func TestGetNonExistentnode(t *testing.T) {
	clearTable()

	req, _ := http.NewRequest("GET", "/node/45", nil)
	response := executeRequest(req)

	checkResponseCode(t, http.StatusNotFound, response.Code)

	var m map[string]string
	json.Unmarshal(response.Body.Bytes(), &m)
	if m["error"] != "node not found" {
		t.Errorf("Expected the 'error' key of the response to be set to 'node not found'. Got '%s'", m["error"])
	}
}

func TestCreatenode(t *testing.T) {
	clearTable()

	payload := []byte(`{"name":"node1"}`)

	req, _ := http.NewRequest("POST", "/node", bytes.NewBuffer(payload))
	response := executeRequest(req)

	checkResponseCode(t, http.StatusCreated, response.Code)

	var m map[string]interface{}
	json.Unmarshal(response.Body.Bytes(), &m)

	if m["name"] != "node1" {
		t.Errorf("Expected node to be 'node1'. Got '%v'", m["name"])
	}

	// the id is compared to 1.0 because JSON unmarshaling converts numbers to
	// floats, when the target is a map[string]interface{}
	if m["id"] != 1.0 {
		t.Errorf("Expected node ID to be '1'. Got '%v'", m["id"])
	}
}

func addNodes(count int) {
	if count < 1 {
		count = 1
	}

	for i := 0; i < count; i++ {
    statement := fmt.Sprintf("call create_node(NULL, '%s', NULL, NULL)", ("node " + strconv.Itoa(i+1)))
		a.DB.Exec(statement)
	}
}

func TestGetnode(t *testing.T) {
	clearTable()
	addNodes(1)

	req, _ := http.NewRequest("GET", "/node/1", nil)
	response := executeRequest(req)

	checkResponseCode(t, http.StatusOK, response.Code)
}

func TestUpdatenode(t *testing.T) {
	clearTable()
	addNodes(1)

	req, _ := http.NewRequest("GET", "/node/1", nil)
	response := executeRequest(req)
	var originalnode map[string]interface{}
	json.Unmarshal(response.Body.Bytes(), &originalnode)

	payload := []byte(`{"name":"node - updated name"}`)

	req, _ = http.NewRequest("PUT", "/node/1", bytes.NewBuffer(payload))
	response = executeRequest(req)

	checkResponseCode(t, http.StatusOK, response.Code)

	var m map[string]interface{}
	json.Unmarshal(response.Body.Bytes(), &m)

	if m["id"] != originalnode["id"] {
		t.Errorf("Expected the id to remain the same (%v). Got %v", originalnode["id"], m["id"])
	}

	if m["name"] == originalnode["name"] {
		t.Errorf("Expected the name to change from '%v' to '%v'. Got '%v'", originalnode["name"], m["name"], m["name"])
	}

}

func TestDeletenode(t *testing.T) {
	clearTable()
	addNodes(1)

	req, _ := http.NewRequest("GET", "/node/1", nil)
	response := executeRequest(req)
	checkResponseCode(t, http.StatusOK, response.Code)

	req, _ = http.NewRequest("DELETE", "/node/1", nil)
	response = executeRequest(req)

	checkResponseCode(t, http.StatusOK, response.Code)

	req, _ = http.NewRequest("GET", "/node/1", nil)
	response = executeRequest(req)
	checkResponseCode(t, http.StatusNotFound, response.Code)
}
