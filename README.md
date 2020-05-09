# zigmd

zigmd is a markdown editor `test`

## why zigmd

full control over text rendering. newline characters can get rendered in one line. one character can get rendered as five.

## notes

- font rendering with https://manpages.debian.org/testing/libxft-dev/Xft.3.en.html ?
- rename imgui to gui?
- move style to imgui and switch font args to style args
- instead of storing text state, how about using the text cache? update it a tiny bit so it supports any length of text, but then there is no need for storing text state
- not sure what to do about button state. how do ids work if the entire ui can change completely in a frame? what if the wrong component gets the id? clearly I don't know how other imgui implementations work
- pass an allocator in the init arg for imgui components to allow for an inline text field component