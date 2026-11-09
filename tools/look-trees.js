// Builds germ looks with the real client code (src/client/Looks.luau, run in tools/client-smoke.js)
// and returns their GUI trees for tools/gui-draw.js. looks = [{ skin, color: [r, g, b], flag, aim: [dx, dz], muts, core,
// gear: Gear.animate state { t, dx, dz, fight, dash, power, powerAge } }]
const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");
module.exports = function lookTrees(looks) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "looks-"));
  const inFile = path.join(dir, "in.json"), outFile = path.join(dir, "out.json");
  fs.writeFileSync(inFile, JSON.stringify(looks.map((l) => ({ skin: l.skin || {}, color: l.color, flag: !!l.flag, aim: l.aim, blink: l.blink, muts: l.muts, core: l.core, gear: l.gear }))));
  execFileSync("node", [path.join(__dirname, "client-smoke.js")], { env: { ...process.env, LOOK_DUMP: inFile, LOOK_OUT: outFile }, stdio: ["ignore", "ignore", "inherit"] });
  const trees = JSON.parse(fs.readFileSync(outFile, "utf8"));
  fs.rmSync(dir, { recursive: true });
  return trees;
};
