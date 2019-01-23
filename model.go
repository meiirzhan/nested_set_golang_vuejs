
package main

import (
  "fmt"
	"database/sql"
)

type node struct {
	ID   		int    `json:"id"`
	Name 		string `json:"name"`
	Level  		int    `json:"level"`
	ParentId  	sql.NullInt64    `json:"parent_id"`
	LeftKey  	int    `json:"left_key"`
	RightKey  	int    `json:"right_key"`
	Tree 		int    `json:"tree"`
}

func (u *node) getNode(db *sql.DB) error {
	statement := fmt.Sprintf("SELECT name, level, parent_id, left_key, right_key, tree FROM _ns_tree WHERE id=%d", u.ID)
	return db.QueryRow(statement).Scan(&u.Name, &u.Level, &u.ParentId.Int64, &u.LeftKey, &u.RightKey, &u.Tree)
}



func (u *node) updateNode(db *sql.DB, leftKey string) error {
	statement := fmt.Sprintf("CALL update_node(%d, %d, %s)", u.ID, u.ParentId.Int64, leftKey)
	fmt.Printf("CALL update_node(%d, %d, %s)", u.ID, u.ParentId.Int64, leftKey)
	_, err := db.Exec(statement)
	return err
}

func (u *node) deleteNode(db *sql.DB) error {
	statement := fmt.Sprintf("CALL drop_node(%d)", u.ID)
	_, err := db.Exec(statement)
	return err
}

func rebuild(db *sql.DB) error {
	statement := fmt.Sprintf("CALL rebuild_nested_set_tree()")
	_, err := db.Exec(statement)
	return err
}

func (u *node) createNode(db *sql.DB, leftKey string, tree string) error {
	statement := fmt.Sprintf("CALL create_node(%d, '%s', %s, %s)", u.ParentId.Int64, u.Name, tree, leftKey)
	fmt.Printf("CALL create_node(%d, '%s', %s, %s)", u.ParentId.Int64, u.Name, tree, leftKey)
	_, err := db.Exec(statement)

	if err != nil {
		return err
	}

	err = db.QueryRow("SELECT LAST_INSERT_ID()").Scan(&u.ID)

	if err != nil {
		return err
	}

	return nil
}

func (u *node) getParents(db *sql.DB) ([]node, error) {
	statement := fmt.Sprintf("SELECT id, name, level, right_key, left_key, parent_id, tree FROM _ns_tree WHERE left_key < %d AND right_key > %d AND tree = %d ORDER BY left_key", u.LeftKey, u.RightKey, u.Tree)
	rows, err := db.Query(statement)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	tree := []node{}

	for rows.Next() {
		var u node
		if err := rows.Scan(&u.ID, &u.Name, &u.Level, &u.RightKey, &u.LeftKey, &u.ParentId, &u.Tree); err != nil {
			return nil, err
		}
		tree = append(tree, u)
	}

	return tree, nil
}


func (u *node) getDirectChildren(db *sql.DB) ([]node, error) {
	statement := fmt.Sprintf("SELECT id, name, level, right_key, left_key, parent_id, tree FROM _ns_tree WHERE parent_id = %d ORDER BY left_key", u.ID)
	rows, err := db.Query(statement)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	tree := []node{}

	for rows.Next() {
		var u node
		if err := rows.Scan(&u.ID, &u.Name, &u.Level, &u.RightKey, &u.LeftKey, &u.ParentId, &u.Tree); err != nil {
			return nil, err
		}
		tree = append(tree, u)
	}

	return tree, nil
}


func (u *node) getChildren(db *sql.DB) ([]node, error) {
	statement := fmt.Sprintf("SELECT id, name, level, right_key, left_key, parent_id, tree FROM _ns_tree WHERE left_key > %d AND right_key < %d AND tree = %d ORDER BY left_key", u.LeftKey, u.RightKey, u.Tree)
	rows, err := db.Query(statement)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	tree := []node{}

	for rows.Next() {
		var u node
		if err := rows.Scan(&u.ID, &u.Name, &u.Level, &u.RightKey, &u.LeftKey, &u.ParentId, &u.Tree); err != nil {
			return nil, err
		}
		tree = append(tree, u)
	}

	return tree, nil
}

func getTree(db *sql.DB) ([]node, error) {
	statement := fmt.Sprintf("SELECT id, name, level, right_key, left_key, parent_id, tree FROM _ns_tree ORDER BY left_key")
	rows, err := db.Query(statement)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	tree := []node{}

	for rows.Next() {
		var u node
		if err := rows.Scan(&u.ID, &u.Name, &u.Level, &u.RightKey, &u.LeftKey, &u.ParentId, &u.Tree); err != nil {
			return nil, err
		}
		tree = append(tree, u)
	}

	return tree, nil
}

func (u *node) getNeighbours(db *sql.DB) ([]node, error) {
	statement := fmt.Sprintf("SELECT id, name, level, right_key, left_key, parent_id, tree FROM _ns_tree WHERE parent_id = %d AND level = %d AND tree = %d AND id <> %d ORDER BY left_key", u.ParentId.Int64, u.Level, u.Tree, u.ID)
	rows, err := db.Query(statement)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	tree := []node{}

	for rows.Next() {
		var u node
		if err := rows.Scan(&u.ID, &u.Name, &u.Level, &u.RightKey, &u.LeftKey, &u.ParentId, &u.Tree); err != nil {
			return nil, err
		}
		tree = append(tree, u)
	}

	return tree, nil
}
