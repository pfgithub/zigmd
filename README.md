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
-   no smooth resize on mac.

here is some text: fkdjsafnkjdsnfksdfnkdsnackdsjlacndsklacndskacnlkdskcdaslkjladsjknalcdkjnslajkncdsjnkljknsdcljnkadsckjnlsdcljknacdsljkncdsjnkldsclnjkdcsjknkncjdskjnlcadsnjkcdnsjkankcjldsnjklcnkjdsacjnkdsajnckasdnkjajkndscndkjsacjnkadsjkdsnjkcdsnalcnadjklsbfjkdsncdlskjahfkjdsfndskalcnadjkslnfjdnskanfkaldsncljkdnskacnkjdsnkjkkjdjdjdjdsjdsjlkadfjnlkdsacnjlkdcsanjklajdlscnkadcskjnlcdasnjkladscljnkdacsljnkdascjnkladsckljnadcskljncadskljncdsajnlkcdasjknlcdsaknjldknjlcasknjldnjcasnljkadscknjldsacnjlkadscnjadcslnjldcaskjnkcdnjkdacsjnkdacsjdcsjnlkdcasnjlkadcsjnkldjacnsljankcsldcdjknasjckdasndcjksanldcjkasnldaskcjlncjdaklsnkcjandlsajckdsnlajkcdsnlcdasjknlcjkdanslckjdsnalcdsjkanladscjklncdasjklnjdsckanljkdnscljkdsnclajkdlscnajkndlscajknldsacjknldscajknlsdcajknlsdcajknlsdcajknldscajnklcdsajknlacsdjknlsdcajknlcdsajknlsdcajnklcdsajknlcdsajkndsclajkcndslajkncdslajnkcdslajnkscdaljnkacsdljksadncljksdncaljnkcdljnkdcsajnkdscajnkcdsafadshjbafsdhbjkdskfhjbjhkbdcsajhbjchbdsahjbcskajhcdsjkabcjkhbdcshjbkcadshjkcdshbjkcdshjkbacdshbjkacdshjbkacdshbjcdshjbacsdhbjacdsbhjkkacdbhsjscdkajhbcdsahjbkdacshbjkadcshjbkacdshbjkcdashbjadcshbjdcashjbkdsckhjbdcsbhjkcdshbjkadcsjhbdcshjbkadcsbhjkadcshbjkcdshjbkdcshbjdcsbhjcdsabhjdcasbhjadcshbjdcsahbjkadscjhbcdashjbkadcshbjkadschbjkcdasbhjkasdcbhjacdsbhjk

note: before examples:

Measuring took 13025891.
Click handling took 205.
Rendering took 579939.
Handling took 829.
Measuring took 12689688.
Click handling took 173.
Rendering took 559786.
Handling took 942.
Measuring took 12223180.
Click handling took 190.
Rendering took 557192.
Handling took 1201.
Measuring took 12195064.
Click handling took 119.
Rendering took 544001.
Handling took 910.
Measuring took 12230158.
Click handling took 126.
Rendering took 544657.
Handling took 983.
Measuring took 12196659.
Click handling took 98.
Rendering took 550273.
Handling took 709.
Measuring took 12273336.
Click handling took 88.
Rendering took 571200.
Handling took 1112.
Measuring took 12954940.
Click handling took 397.
Rendering took 598580.
Handling took 1058.
Measuring took 12989292.
Click handling took 134.
Rendering took 584199.
Handling took 1122.
Measuring took 13052382.
Click handling took 179.
Rendering took 585353.
Handling took 1261.
