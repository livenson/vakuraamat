// Compile every sites/<site>/narrative/*.ink into <name>.ink.json next to it.
// Usage: cd tools/ink && npm install && npm run compile [-- <site> [<sitesRoot>]]
const { execFileSync } = require("child_process");
const fs = require("fs"), path = require("path");
const only = process.argv[2];
const root = process.argv[3] ? path.resolve(process.argv[3]) : path.resolve(__dirname, "../../sites");
const bin = path.resolve(__dirname, "node_modules/.bin/inkjs-compiler");
for (const site of fs.readdirSync(root).filter(s => !only || s === only)) {
  const dir = path.join(root, site, "narrative");
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith(".ink"))) {
    const src = path.join(dir, f), out = src.replace(/\.ink$/, ".ink.json");
    execFileSync(bin, [src, "-o", out], { stdio: "inherit" });
    console.log(site, "compiled", f, "->", path.basename(out), fs.statSync(out).size, "bytes");
  }
}
