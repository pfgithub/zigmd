#!/bin/sh

set -e

rm -rf deps/build
mkdir deps/build

cd deps/build
    git clone https://github.com/tree-sitter/tree-sitter.git
	git clone https://github.com/ikatyang/tree-sitter-markdown.git
	git clone https://github.com/tree-sitter/tree-sitter-json.git
cd ../..