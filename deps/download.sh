#!/bin/sh

set -e

rm -rf deps/build
mkdir deps/build

cd deps/build
    git clone https://github.com/tree-sitter/tree-sitter.git
	git clone https://github.com/ikatyang/tree-sitter-markdown.git
	git clone https://github.com/tree-sitter/tree-sitter-json.git
    cd tree-sitter-markdown/src
		echo "Building markdown scanner..."
        zig c++ scanner.cc -I ../../tree-sitter/lib/include -c -o scanner.o
		echo "Done building markdown scanner."
    cd ../..
    cd tree-sitter/lib
        echo "Building tree-sitter with allowed undefined behaviour"
        gcc -O3 -c -o src/lib.o -I src -I include src/lib.c
        echo "Done building tree-sitter"
    cd ..
cd ../..