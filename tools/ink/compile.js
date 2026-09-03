// Compile every assets/narrative/*.ink into <name>.ink.json next to it.
// Usage: cd tools/ink && npm install && npm run compile
const { execFileSync } = require("child_process");
const fs = require("fs"), path = require("path");
const dir = path.resolve(__dirname, "../../assets/narrative");
const bin = path.resolve(__dirname, "node_modules/.bin/inkjs-compiler");
for (const f of fs.readdirSync(dir).filter(f => f.endsWith(".ink"))) {
  const src = path.join(dir, f), out = src.replace(/\.ink$/, ".ink.json");
  execFileSync(bin, [src, "-o", out], { stdio: "inherit" });
  console.log("compiled", f, "->", path.basename(out), fs.statSync(out).size, "bytes");
}
