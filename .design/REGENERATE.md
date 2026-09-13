# Keeping the dark artboard in sync

`MenuDark.dc.html` is a generated copy of `Main.dc.html` with the `theme`
tweak defaulting to `Dark`. After editing `Main.dc.html`, regenerate it:

    node -e 'const fs=require("fs");let s=fs.readFileSync("Main.dc.html","utf8");
    s=s.replace(String.raw`"default":"Light"`, String.raw`"default":"Dark"`);
    fs.writeFileSync("MenuDark.dc.html", s);'

Then re-seed the canvas with all five artboards plus canvas.json.
The shared palette lives in `theme-snippet.txt`, inlined into each
screen's `<helmet>` block under the `.app` / `.app.dark` selectors.
