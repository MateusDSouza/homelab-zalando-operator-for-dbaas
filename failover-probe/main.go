package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/jackc/pgx/v5" // This is the postgres driver used!
)

// here is where the program starts - this is a script and letting this being from package main with the func main is the entry point of the application
// This simple go application is writing data to the database and returning if it works or not with the following row id. My ideia with this simple script is to show a minimum amount of go practice and knowledge.
func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		fmt.Fprintln(os.Stderr, "DATABASE_URL is not set")
		os.Exit(1)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second) // This is important because the database call will give up if lasts more than 2seconds, so there is no hanging during a fallover.
	defer cancel() // the defer block will be executed once main finishes the execution to guarantee that all connections were closed.

	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		fmt.Fprintln(os.Stderr, "connect failed:", err)
		os.Exit(1)
	} // every condition in golang needs to return something - thats the way golang treat the exceptions -> it returns it as a normal value from the function.
	defer conn.Close(context.Background()) // the defer block will be executed once main finishes the execution to guarantee that all connections were closed.

	var id int64
	err = conn.QueryRow(ctx, "INSERT INTO ticks DEFAULT VALUES RETURNING id").Scan(&id) // Here the database is returning the row id so we know exactly which written row was acknowledge!
	if err != nil {
		fmt.Fprintln(os.Stderr, "insert failed:", err)
		os.Exit(1)
	} // every condition in golang needs to return something - thats the way golang treat the exceptions -> it returns it as a normal value from the function.
	fmt.Println("inserted row", id)
}