#!/bin/sh

set -e
rm -rf deps/build
mkdir deps/build

cd deps/build
    git clone https://github.com/tree-sitter/tree-sitter.git
	cd tree-sitter
		echo "Building tree-sitter..."
		./script/build-lib
		echo "Done building tree-sitter."
	cd ..
	git clone https://github.com/ikatyang/tree-sitter-markdown.git
	git clone https://github.com/tree-sitter/tree-sitter-json.git
cd ../..