#!/bin/sh

set -e

rm -rf deps/build
mkdir deps/build

cd deps/build
    git clone https://github.com/tree-sitter/tree-sitter.git
    cd tree-sitter
        # before breaking change
        git reset --hard c393591e1db759c0f16f877165a6370d06b22472
    cd ..
	git clone https://github.com/pfgithub/tree-sitter-markdown.git
	git clone https://github.com/tree-sitter/tree-sitter-json.git
    cd tree-sitter-markdown/src
		echo "Building markdown scanner..."
        zig c++ scanner.cc -I ../../tree-sitter/lib/include -c -o scanner.o
		echo "Done building markdown scanner."
    cd ../..
cd ../..