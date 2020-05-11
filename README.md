# zigmd

zigmd is a markdown editor `test`

## why zigmd

full control over text rendering. newline characters can get rendered in one line. one character can get rendered as five.

## notes

- font rendering with https://manpages.debian.org/testing/libxft-dev/Xft.3.en.html ?
- move style to imgui and switch font args to style args
- instead of storing text state, how about using the text cache? update it a tiny bit so it supports any length of text, but then there is no need for storing text state
- not sure what to do about button state. how do ids work if the entire ui can change completely in a frame? what if the wrong component gets the id? clearly I don't know how other imgui implementations work
- pass an allocator in the init arg for imgui components to allow for an inline text field component
- performance: don't remeasure as much stuff. remeasure is the main performance issue right now. after that, tree-sitter updating is the second main perf issue, then the issue that the entire file is stored in a contiguous array, making insertions at the beginning difficult
- issue: there is something weird going on with scroll smoothing.
- todo: when resizing the app, keep a specified line in the same position on screen by updating the scroll position.
- idea: select nearest node. takes the cursor position, finds the nearest node above where start is < hl left and end is > hl right, then selects it. pressing repeatedly will go up the node list (becuase a node's left is not < itself nor its right > to itself). basically select word but context aware