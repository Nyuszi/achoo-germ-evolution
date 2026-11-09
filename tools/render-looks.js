// Pictures of every skin, bundle and flag, drawn from above like the game camera sees them
// (same parts as src/client/Renderer.luau; Roblox materials are only imitated).
// Usage: NODE_PATH=$(npm root -g) node tools/render-looks.js <out-dir>
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");
const germDraw = require("./germ-draw");

const out = path.resolve(process.argv[2] || "look-previews");
fs.mkdirSync(out, { recursive: true });
const src = (p) => fs.readFileSync(path.join(__dirname, "..", "src", "shared", p), "utf8");
const cfg = src("Config.luau");

// Config.Skins entries: { Id = "X", Name = "Y", Price = 49, Dna = 100, Free = true, Arena = true }
function skins(cat) {
  const block = cfg.match(new RegExp("\\n\\t" + cat + " = \\{\\n([\\s\\S]*?)\\n\\t\\},"))[1];
  return block.split("\n").filter((l) => l.includes("Id =")).map((l) => ({
    id: l.match(/Id = "(\w+)"/)[1], name: l.match(/Name = "([^"]+)"/)[1],
    price: +(l.match(/Price = (\d+)/) || [])[1] || 0, dna: +(l.match(/Dna = (\d+)/) || [])[1] || 0,
    free: /Free = true/.test(l), arena: /Arena = true/.test(l),
  }));
}
const bundles = [...cfg.matchAll(/\{ Id = "(\w+)", Name = "([^"]+)", Price = (\d+), Items = \{ ([^}]+) \} \}/g)].map((m) => ({
  id: m[1], name: m[2], price: +m[3], items: Object.fromEntries([...m[4].matchAll(/(\w+) = "(\w+)"/g)].map((x) => [x[1], x[2]])),
}));
const flagList = [...src("Flags.luau").matchAll(/^([A-Z]{2}) ([^;]+);(\w+)$/gm)].map((m) => ({ code: m[1], name: m[2], cont: m[3] }));
const emoji = (code) => String.fromCodePoint(...[...code].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65));
const priceText = (s) => s.free ? "Free" : s.arena ? "Arena tokens" : [s.price ? s.price + " R$" : "", s.dna ? s.dna + " DNA" : ""].filter(Boolean).join(" or ");

const GREEN = [120, 220, 120];
const base = { Body: "Jelly", Pattern: "None", Eyes: "Cute", Mouth: "Smile", Hat: "None", Trail: "None", Color2: [255, 255, 255] };
const sheets = [];
const cell = (title, look, price) => ({ title, look, price });
const section = (name, items) => ({ name, items });
const look = (over, color, flag) => ({ color: color || GREEN, skin: Object.assign({}, base, over), flag });
sheets.push({ file: "skins-1-body-pattern-eyes", title: "Germ Editor: bodies, patterns, eyes", sections: [
  section("Body", skins("Body").map((s) => cell(s.name, look({ Body: s.id }), priceText(s)))),
  section("Pattern (in your 2nd colour)", skins("Pattern").map((s) => cell(s.name, look({ Pattern: s.id, Color2: [255, 240, 120] }), priceText(s)))),
  section("Eyes", skins("Eyes").map((s) => cell(s.name, look({ Eyes: s.id }), priceText(s)))),
] });
sheets.push({ file: "skins-2-mouth-hat-trail", title: "Germ Editor: mouths, hats, trails", sections: [
  section("Mouth", skins("Mouth").map((s) => cell(s.name, look({ Mouth: s.id }), priceText(s)))),
  section("Hat", skins("Hat").map((s) => cell(s.name, look({ Hat: s.id }), priceText(s)))),
  section("Trail", skins("Trail").filter((s) => s.id !== "None").map((s) => cell(s.name, look({ Trail: s.id }), priceText(s)))),
] });
sheets.push({ file: "skins-3-bundles-colours", title: "Bundles and colours", sections: [
  section("Bundles (whole outfits)", bundles.map((b) => cell(b.name, look(b.items, b.id === "DragonGerm" ? [200, 60, 40] : b.id === "SpaceGerm" ? [110, 70, 220] : [255, 150, 200]), b.price + " R$"))),
  section("Colours are free: any colour, plus a 2nd colour for patterns", [[120, 220, 120], [110, 200, 255], [255, 150, 200], [255, 210, 90], [190, 140, 255], [255, 140, 100], [60, 60, 70], [255, 255, 255]].map((c, i) =>
    cell(["Mint", "Sky", "Pink", "Sun", "Lilac", "Peach", "Ink", "Snow"][i], look({ Pattern: "Spots", Color2: i === 7 ? [80, 80, 90] : [255, 255, 255] }, c), "Free"))),
] });
const popular = ["HU", "US", "GB", "DE", "FR", "BR", "JP", "KR", "MX", "CA", "IN", "IT", "ES", "PH", "ID", "AU", "PL", "TR", "UA", "NL", "SE", "AR", "NG", "EG"];
sheets.push({ file: "flags-1-popular", title: "Flag skins: the flag becomes the whole body (49 R$ each)", sections: [
  section("Popular flags", popular.map((c) => cell(flagList.find((f) => f.code === c).name, look({}, GREEN, emoji(c)), "49 R$"))),
  section("Flags mix with every other look. Packs: a continent 199 R$, the World Pack (all 195) 499 R$", [cell("With a hat", look({ Hat: "Crown" }, GREEN, emoji("HU")), "flag + hat"), cell("With Fangs", look({ Mouth: "Fangs", Eyes: "Angry" }, GREEN, emoji("BR")), "flag + face"),
    cell("With a trail", look({ Trail: "Sparkles" }, GREEN, emoji("JP")), "flag + trail"), cell("No flag", look({}), "Free")]),
] });
const conts = { Africa: "Africa", Asia: "Asia", Europe: "Europe", NorthAmerica: "North & Central America", SouthAmerica: "South America", Oceania: "Oceania" };
sheets.push({ file: "flags-2-all-195", title: "All " + flagList.length + " flags", compact: true, sections: Object.keys(conts).map((k) =>
  section(conts[k], flagList.filter((f) => f.cont === k).map((f) => cell(f.name, look({ Eyes: "Cute", Mouth: "None" }, GREEN, emoji(f.code)), "")))) });

const html = (sheet) => `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600&display=block" rel="stylesheet">
<style>body{margin:0;background:#2a1838;font-family:Fredoka,sans-serif;color:#fff;width:1400px}
h1{margin:0;padding:22px 30px 6px;font-size:34px} .note{padding:0 30px;color:#d9c8ef;font-size:16px}
h2{margin:18px 30px 8px;font-size:22px;color:#ffd978} .grid{display:flex;flex-wrap:wrap;gap:12px;padding:0 30px}
.c{width:${sheet.compact ? 82 : 150}px;background:#3e2a4e;border-radius:14px;padding:${sheet.compact ? 4 : 8}px;text-align:center}
.c canvas{display:block;margin:0 auto} .n{font-size:${sheet.compact ? 11 : 16}px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.p{font-size:13px;color:#ffd978;min-height:16px}</style></head><body>
<h1>${sheet.title}</h1><div class="note">Drawn from above like the game camera, with the same parts as the game code. Roblox lighting and materials look a bit different in the real game.</div>
<div id="root"></div><script>${germDraw}
const S = ${JSON.stringify(sheet)};
const root = document.getElementById("root");
for (const sec of S.sections) {
  const h = document.createElement("h2"); h.textContent = sec.name; root.appendChild(h);
  const grid = document.createElement("div"); grid.className = "grid"; root.appendChild(grid);
  for (const it of sec.items) {
    const d = document.createElement("div"); d.className = "c";
    const size = S.compact ? 74 : 134;
    const cv = document.createElement("canvas"); cv.width = size * 2; cv.height = size * 2; cv.style.width = size + "px"; cv.style.height = size + "px";
    const g = cv.getContext("2d"); g.scale(2, 2);
    const hasTrail = it.look.skin.Trail && it.look.skin.Trail !== "None";
    drawGerm(g, size / 2, hasTrail ? size * 0.36 : size / 2 + (it.look.skin.Hat !== "None" ? 4 : 0), size * (S.compact ? 0.38 : 0.31), it.look, 0.3);
    d.appendChild(cv);
    const n = document.createElement("div"); n.className = "n"; n.textContent = it.title; d.appendChild(n);
    if (!S.compact) { const p = document.createElement("div"); p.className = "p"; p.textContent = it.price; d.appendChild(p); }
    grid.appendChild(d);
  }
}
</script></body></html>`;

(async () => {
  const browser = await chromium.launch();
  for (const sheet of sheets) {
    // a fresh page each time: the drawing code declares top-level constants
    const tab = await browser.newPage({ viewport: { width: 1400, height: 800 }, deviceScaleFactor: 2 });
    tab.on("pageerror", (e) => console.error("page error:", e.message));
    await tab.setContent(html(sheet), { waitUntil: "networkidle" }).catch(() => {});
    await tab.evaluate(() => document.fonts.ready);
    const file = path.join(out, sheet.file + ".png");
    await tab.screenshot({ path: file, fullPage: true });
    console.log(file);
    await tab.close();
  }
  await browser.close();
})();
