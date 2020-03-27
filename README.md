## build

**bold test** _italic test_ **_bold italic test_**

setup:

-   install zig version `0.5.0+d89650025`
-   download and build dependencies (`./deps/download.sh`)

build:

```
zig build run --verbose-cimport
```

format:

-   install prettier (globally)
-   use prettier and zig fmt to format all files.

## generate docs

good luck

## todo list

### completed

-   fontconfig

### todo

-   text rendering that does not use sdl_ttf
-   less text measurement
-   null character support (should be pretty simple)
-   tree-sitter instead of a custom parser, initially just reparse the entire code every update
-   use tree-sitter to its full potential
-   https://en.wikipedia.org/wiki/Rope_(data_structure)

using SDL rendering right now

sdl is a bad choice for a few reasons:

-   no mouse events when the mouse is out of the screen
-   scroll events are useless (1 value on a scroll wheel but goes between 1 and 4 on a trackpad)
-   no smooth resize on mac.
