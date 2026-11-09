// Draws the 195 flag skins into image sheets for Roblox (emoji flags are tiny bitmaps and look
// blurry on a big germ). Square flags from the MIT-licensed flag-icons package (1x1 SVGs), 16 per
// 1024x1024 sheet (4x4 cells of 256 px), in the order of src/shared/Flags.luau.
// Usage: npm pack flag-icons && tar xzf flag-icons-*.tgz
//        NODE_PATH=$(npm root -g) node tools/flag-atlas.js <flag-icons package dir> [out dir]
// Then upload the sheets and put their asset ids in src/shared/FlagSheets.luau.
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const pkg = process.argv[2];
const out = path.resolve(process.argv[3] || path.join(__dirname, "..", "assets", "flags"));
fs.mkdirSync(out, { recursive: true });
const src = fs.readFileSync(path.join(__dirname, "..", "src", "shared", "Flags.luau"), "utf8");
const codes = [...src.matchAll(/^([A-Z]{2}) ([^;]+);(\w+)$/gm)].map((m) => m[1]);
const CELL = 256, PER_ROW = 4, PER_SHEET = PER_ROW * PER_ROW;

(async () => {
  const browser = await chromium.launch();
  const tab = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  for (let sheet = 0; sheet * PER_SHEET < codes.length; sheet++) {
    const cells = codes.slice(sheet * PER_SHEET, (sheet + 1) * PER_SHEET).map((c) => {
      const svg = fs.readFileSync(path.join(pkg, "flags", "1x1", c.toLowerCase() + ".svg"), "utf8");
      return `<div style="width:${CELL}px;height:${CELL}px">${svg.replace("<svg", `<svg width="${CELL}" height="${CELL}" preserveAspectRatio="xMidYMid slice"`)}</div>`;
    });
    await tab.setContent(`<!doctype html><html><body style="margin:0;background:transparent;display:flex;flex-wrap:wrap;width:1024px;height:1024px">${cells.join("")}</body></html>`);
    const file = path.join(out, `flags-${String(sheet + 1).padStart(2, "0")}.png`);
    await tab.screenshot({ path: file, omitBackground: true, clip: { x: 0, y: 0, width: 1024, height: 1024 } });
    console.log(file);
  }
  await browser.close();
})();
