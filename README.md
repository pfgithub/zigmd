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

## generate docs

```
zig test src/main.zig -lc -I/usr/include/SDL2 -femit-docs -fno-emit-bin --output-dir junk && node -e "(() => {const fs = require(\"fs\");const datain = fs.readFileSync(__dirname + \"/junk/docs/data.js\", \"utf-8\");const json = JSON.parse(datain.substring(12, datain.length - 1));let truemain = json.packages[0];let extra = json.packages[truemain.table.root];extra.main = truemain.main;fs.writeFileSync(__dirname + \"/junk/docs/data.js\", \"zigAnalysis=\"+JSON.stringify(json)+\";\", \"utf-8\");console.log(\"done\");})()" # workaround documentation generation bug #4646
```

## short term todo

- proper text rendering that uses system fonts (fontconfig) and possibly harfbuzz
- null character support. right now, a file with a null character will do some strange things in rendering because c strings exist.

using SDL rendering right now

sdl is a bad choice for a few reasons:

-   no mouse events when the mouse is out of the screen
-   scroll events are useless (1 value on a scroll wheel but goes between 1 and 4 on a trackpad)
-   no smooth resize on mac
