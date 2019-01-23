package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"

	// "github.com/gorilla/handlers"
	_ "github.com/go-sql-driver/mysql"
	"github.com/gorilla/mux"
)

type App struct {
	Router *mux.Router
	DB     *sql.DB
}

func (a *App) Initialize(node, password, dbname string) {
	connectionString := fmt.Sprintf("%s:%s@/%s", node, password, dbname)

	var err error
	a.DB, err = sql.Open("mysql", connectionString)
	if err != nil {
		log.Fatal(err)
	}

	a.Router = mux.NewRouter()
	a.initializeRoutes()
}
func enableCors(w *http.ResponseWriter) {
	(*w).Header().Set("Access-Control-Allow-Origin", "*")
}
func (a *App) Run(addr string) {
	// headersOk := handlers.AllowedHeaders([]string{"X-Requested-With"})
	// originsOk := handlers.AllowedOrigins([]string{"http://127.0.0.1:8080"})
	// methodsOk := handlers.AllowedMethods([]string{"GET", "HEAD", "POST", "PUT", "OPTIONS"})

		// Handle all preflight request
	a.Router.Methods("OPTIONS").HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// fmt.Printf("OPTIONS")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
		w.Header().Set("Access-Control-Allow-Headers", "Accept, Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, Access-Control-Request-Headers, Access-Control-Request-Method, Connection, Host, Origin, User-Agent, Referer, Cache-Control, X-header")
		w.WriteHeader(http.StatusNoContent)
		return
	})
	// with error handling
	http.ListenAndServe(addr, a.Router)
	// log.Fatal(http.ListenAndServe(addr, a.Router))
	// http.ListenAndServe(addr, a.Router)
}
func (a *App) initializeRoutes() {
	a.Router.HandleFunc("/nodes", a.getTree).Methods("GET")
	a.Router.HandleFunc("/nodes/parents/{id:[0-9]+}", a.getParents).Methods("GET")
	a.Router.HandleFunc("/nodes/direct/{id:[0-9]+}", a.getDirectChildren).Methods("GET")
	a.Router.HandleFunc("/nodes/children/{id:[0-9]+}", a.getChildren).Methods("GET")
	a.Router.HandleFunc("/nodes/neighbours/{id:[0-9]+}", a.getNeighbours).Methods("GET")
	a.Router.HandleFunc("/nodes", a.getTree).Methods("GET")
	a.Router.HandleFunc("/node", a.createNode).Methods("POST")
	a.Router.HandleFunc("/node/rebuild", a.postRebuild).Methods("POST")
	a.Router.HandleFunc("/node/{id:[0-9]+}", a.getNode).Methods("GET")
	a.Router.HandleFunc("/node/{id:[0-9]+}", a.updateNode).Methods("PUT")
	a.Router.HandleFunc("/node/{id:[0-9]+}", a.deleteNode).Methods("DELETE")
}

func (a *App) getTree(w http.ResponseWriter, r *http.Request) {
	enableCors(&w)
	products, err := getTree(a.DB)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondWithJSON(w, http.StatusOK, products)
}


func (a *App) postRebuild(w http.ResponseWriter, r *http.Request) {

	enableCors(&w)
	err := rebuild(a.DB)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondWithJSON(w, http.StatusOK, map[string]string{"result": "success"})
}

func (a *App) getParents(w http.ResponseWriter, r *http.Request) {

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid node ID")
		return
	}

	u := node{ID: id}

	u.getNode(a.DB)

	products, err := u.getParents(a.DB)

	if err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondWithJSON(w, http.StatusOK, products)
}

func (a *App) getChildren(w http.ResponseWriter, r *http.Request) {

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid node ID")
		return
	}

	u := node{ID: id}


	u.getNode(a.DB)

	products, err := u.getChildren(a.DB)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondWithJSON(w, http.StatusOK, products)
}

func (a *App) getDirectChildren(w http.ResponseWriter, r *http.Request) {

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid node ID")
		return
	}

	u := node{ID: id}

	u.getNode(a.DB)


	products, err := u.getDirectChildren(a.DB)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondWithJSON(w, http.StatusOK, products)
}

func (a *App) getNeighbours(w http.ResponseWriter, r *http.Request) {

	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid node ID")
		return
	}


	u := node{ID: id}

	u.getNode(a.DB)

	products, err := u.getNeighbours(a.DB)
	if err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondWithJSON(w, http.StatusOK, products)
}

func ToNullInt64(s string) sql.NullInt64 {
   i, err := strconv.Atoi(s)
   return sql.NullInt64{Int64 : int64(i), Valid : err == nil}
}
func (a *App) createNode(w http.ResponseWriter, r *http.Request) {
	var u node
	r.ParseForm()

	u.Name = r.FormValue("name")
	var ParentId string = r.FormValue("parent_id")

	var LeftKeyString string
	var TreeString string
	LeftKeyString = r.FormValue("left_key")
	TreeString  = r.FormValue("tree")

	if u.Name == "" {
		respondWithError(w, http.StatusBadRequest, "Invalid request payload")
	}

	if LeftKeyString == "" {
		LeftKeyString = "null"
	}

	if TreeString == "" {
		TreeString = "0"
	}

	u.ParentId = ToNullInt64(ParentId)

	if err := u.createNode(a.DB, LeftKeyString, TreeString); err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}

	u.getNode(a.DB)

	respondWithJSON(w, http.StatusCreated, u)
}

func (a *App) getNode(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid node ID")
		return
	}

	u := node{ID: id}
	if err := u.getNode(a.DB); err != nil {
		switch err {
		case sql.ErrNoRows:
			respondWithError(w, http.StatusNotFound, "Node not found")
		default:
			respondWithError(w, http.StatusInternalServerError, err.Error())
		}
		return
	}

	respondWithJSON(w, http.StatusOK, u)
}

func (a *App) updateNode(w http.ResponseWriter, r *http.Request) {

	enableCors(&w)
	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid node ID")
		return
	}

	var u node

	r.ParseForm()

	var LeftKey string
	var ParentId string = r.FormValue("parent_id")
	LeftKey = r.FormValue("left_key")

	u.ParentId = ToNullInt64(ParentId)


	if LeftKey == "" {
		LeftKey = "null"
	}


	u.ID = id

	if err := u.updateNode(a.DB, LeftKey); err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}

	u.getNode(a.DB)

	respondWithJSON(w, http.StatusOK, u)
}

func (a *App) deleteNode(w http.ResponseWriter, r *http.Request) {
	enableCors(&w)
	vars := mux.Vars(r)
	id, err := strconv.Atoi(vars["id"])
	if err != nil {
		respondWithError(w, http.StatusBadRequest, "Invalid Node ID")
		return
	}

	u := node{ID: id}
	if err := u.deleteNode(a.DB); err != nil {
		respondWithError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondWithJSON(w, http.StatusOK, map[string]string{"result": "success"})
}

func respondWithError(w http.ResponseWriter, code int, message string) {
	respondWithJSON(w, code, map[string]string{"error": message})
}

func respondWithJSON(w http.ResponseWriter, code int, payload interface{}) {
	response, _ := json.Marshal(payload)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	w.Write(response)
}
