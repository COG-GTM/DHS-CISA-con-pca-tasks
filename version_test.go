package main

import (
	"flag"
	"os"
	"testing"
)

func TestVersion_FlagNotSet(t *testing.T) {
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	os.Args = []string{"cmd"}
	
	flag.CommandLine = flag.NewFlagSet(os.Args[0], flag.ContinueOnError)
	
	version()
}
