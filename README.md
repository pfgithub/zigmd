## build

setup:

-   install zig version `0.5.0+d89650025`

build:

```
zig build run --verbose-cimport
```

format:

-   install prettier (globally)
-   use prettier and zig fmt to format all files.

## todo

using SDL rendering right now

sdl is a bad choice for a few reasons:

-   no mouse events when the mouse is out of the screen
-   scroll events are useless (1 value on a scroll wheel but goes between 1 and 4 on a trackpad)
-   no smooth resize on mac
