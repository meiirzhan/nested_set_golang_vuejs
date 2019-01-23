// main.go

package main

func main() {
	a := App{}
	a.Initialize("root", "root", "nested_set_db")

	a.Run(":8082")
}
