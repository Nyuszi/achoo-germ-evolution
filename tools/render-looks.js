// Pictures of every skin, bundle and flag, drawn from above like the game camera sees them.
// The face, pattern and hat are the game's own 2D art (src/client/Looks.luau, built through
// tools/look-trees.js); the 3D body imitates src/client/Renderer.luau (materials only roughly).
// Usage: NODE_PATH=$(npm root -g) node tools/render-looks.js <out-dir>
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");
const germDraw = require("./germ-draw");
const guiDraw = require("./gui-draw");
const lookTrees = require("./look-trees");

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
// a few looking around and blinking, to show the eyes follow the swim direction
const COLS = [[120, 220, 120], [110, 200, 255], [255, 150, 200], [255, 210, 90], [190, 140, 255], [255, 140, 100]];
sheets.unshift({ file: "skins-0-closeups", title: "Germ looks up close", big: true, sections: [
  section("Faces (pupils follow where you swim, and they blink)", [
    cell("Big Cute, looking left", Object.assign(look({ Eyes: "Cute" }, COLS[1]), { aim: [-1, 0] }), ""),
    cell("Angry + Fangs", Object.assign(look({ Eyes: "Angry", Mouth: "Fangs" }, COLS[5]), { aim: [0, 1] }), ""),
    cell("Cat Eyes + Kitty", look({ Eyes: "Cat", Mouth: "Kitty", Hat: "CatEars" }, COLS[3]), ""),
    cell("Blinking", Object.assign(look({ Eyes: "Cute", Mouth: "Tongue" }, COLS[2]), { blink: true }), ""),
    cell("Heart Eyes", look({ Eyes: "Heart", Mouth: "Smile", Hat: "Bow" }, COLS[2]), ""),
    cell("Googly + Braces", look({ Eyes: "Googly", Mouth: "Braces", Pattern: "Checkers", Color2: [255, 255, 255] }, COLS[4]), ""),
    cell("Sleepy + Mustache", look({ Eyes: "Sleepy", Mouth: "Mustache", Hat: "TopHat" }, COLS[0]), ""),
    cell("Wink + Crown", look({ Eyes: "Wink", Mouth: "Tongue", Hat: "Crown", Pattern: "Hearts", Color2: [255, 90, 150] }, COLS[3]), ""),
  ]),
] });
sheets.push({ file: "skins-3-bundles-colours", title: "Bundles and colours", sections: [
  section("Bundles (whole outfits)", bundles.map((b) => cell(b.name, look(b.items, b.id === "DragonGerm" ? [200, 60, 40] : b.id === "SpaceGerm" ? [110, 70, 220] : [255, 150, 200]), b.price + " R$"))),
  section("Colours are free: any colour, plus a 2nd colour for patterns", [[120, 220, 120], [110, 200, 255], [255, 150, 200], [255, 210, 90], [190, 140, 255], [255, 140, 100], [60, 60, 70], [255, 255, 255]].map((c, i) =>
    cell(["Mint", "Sky", "Pink", "Sun", "Lilac", "Peach", "Ink", "Snow"][i], look({ Pattern: "Spots", Color2: i === 7 ? [80, 80, 90] : [255, 255, 255] }, c), "Free"))),
] });
// Lab mutations: the real Gear art (src/client/Gear.luau), resting and in action. Swimming up.
const UP = { dx: 0, dz: -1, t: 0.3 };
const act = (o) => Object.assign({}, UP, o);
const MUTS = [
  ["Jaws", "Front", "Jaws", "chews", act({ power: "Chomp", powerAge: 0.01 }), "Chomp: wide snap"],
  ["Suction", "Front", "Suction Mouth", "food drifts in", act({ power: "Vacuum", powerAge: 0.5 }), "Vacuum: big vortex"],
  ["Drill", "Front", "Drill Nose", "spins", act({ power: "Pierce", powerAge: 0.5 }), "Pierce: red hot"],
  ["Flagella", "Back", "Flagella Tail", "whips", act({ dash: true, t: 0.41 }), "dashing: fast whip"],
  ["Jet", "Back", "Jet Sac", "small flames", act({ dash: true }), "dashing: long flames"],
  ["Slime", "Back", "Slime Trail", "drips goo", act({ t: 0.75 }), "leaves puddles"],
  ["Spikes", "Sides", "Spikes", "turn slowly", act({ fight: true }), "in a fight: red tips"],
  ["Toxin", "Sides", "Toxin Glands", "leak bubbles", act({ fight: true, t: 0.5 }), "in a fight: throbbing"],
  ["Shell", "Sides", "Shell Plates", "riveted steel", act({ fight: true, t: 0.157 }), "hit: plates flash"],
  ["Camo", "Special", "Camo Skin", "leafy blotches", act({ power: "Ghost", powerAge: 0.5 }), "Ghost hides you"],
  ["Magnet", "Special", "Magnet Core", "ripples pull food", act({ power: "GravityWell", powerAge: 0.3 }), "Gravity well"],
  ["Sneezer", "Special", "Mini Sneeze", "twitchy nose", act({ power: "Blast", powerAge: 0.22 }), "Blast: shock rings"],
];
const labLook = (muts, gear, color, core) => ({ color: color || [110, 200, 255], skin: Object.assign({}, base), muts, gear, core });
sheets.push({ file: "lab-1-mutations", title: "Lab mutations on your germ (swimming up)", gear: true, sections: [
  section("Front, Back, Sides and Special: resting, then in action", MUTS.flatMap(([id, slot, name, idle, a, action]) => [
    cell(name, labLook({ [slot]: id }, UP), idle), cell(name, labLook({ [slot]: id }, a), action)])),
] });
const FUS = [["Buzzsaw", act({ dash: true }), "spins hard when dashing"], ["PlagueTrail", act({ t: 0.75 }), "purple poison goo"], ["BlackHole", act({ power: "Vacuum", powerAge: 0.5 }), "one dark vortex mouth"],
  ["Ninja", act({ dash: true }), "camo + jets"], ["Fortress", act({ fight: true, t: 0.157 }), "shell + spikes"], ["Driller", act({ dash: true }), "dash: drill glows"],
  ["Venom", act({ power: "Chomp", powerAge: 0.01 }), "green venom teeth"], ["Storm", act({ power: "Blast", powerAge: 0.22 }), "blast + gravity well"]];
sheets.push({ file: "lab-2-fusions-and-mix", title: "Fusions, and a fully kitted germ", gear: true, sections: [
  section("Fusions (in action)", FUS.map(([id, a, txt]) => cell(id, labLook({ Front: id, Back: "#" + id }, a, [255, 150, 200]), txt))),
  section("All four slots", [
    cell("Jaws, Jet, Spikes, Magnet", labLook({ Front: "Jaws", Back: "Jet", Sides: "Spikes", Special: "Magnet" }, act({ dx: 0.8, dz: -0.6 }), [255, 210, 90]), "swimming up-right"),
    cell("Drill, Flagella, Toxin, Sneezer", labLook({ Front: "Drill", Back: "Flagella", Sides: "Toxin", Special: "Sneezer" }, act({ dx: -1, dz: 0 }), [190, 140, 255]), "swimming left"),
    cell("Suction, Slime, Shell, Camo", labLook({ Front: "Suction", Back: "Slime", Sides: "Shell", Special: "Camo" }, act({ dx: 0, dz: 1 }), [120, 220, 120]), "swimming down"),
    cell("Star core", labLook({}, UP, [255, 140, 100], "Star"), "built-in spikes"),
  ]),
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

const html = (sheet, trees) => `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600&display=block" rel="stylesheet">
<style>body{margin:0;background:#2a1838;font-family:Fredoka,sans-serif;color:#fff;width:1400px}
h1{margin:0;padding:22px 30px 6px;font-size:34px} .note{padding:0 30px;color:#d9c8ef;font-size:16px}
h2{margin:18px 30px 8px;font-size:22px;color:#ffd978} .grid{display:flex;flex-wrap:wrap;gap:12px;padding:0 30px}
.c{width:${sheet.compact ? 82 : sheet.big ? 300 : 150}px;background:#3e2a4e;border-radius:14px;padding:${sheet.compact ? 4 : 8}px;text-align:center}
.c canvas{display:block} .st{position:relative;margin:0 auto} .c>.n{font-size:${sheet.compact ? 11 : 16}px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.p{font-size:13px;color:#ffd978;min-height:16px}</style></head><body>
<h1>${sheet.title}</h1><div class="note">Drawn from above like the game camera. The face, pattern and hat are the game's own art; Roblox lighting and body materials look a bit different in the real game.</div>
<div id="root"></div><script>${germDraw}
${guiDraw}
const S = ${JSON.stringify(sheet)}, TREES = ${JSON.stringify(trees)};
const root = document.getElementById("root");
for (const sec of S.sections) {
  const h = document.createElement("h2"); h.textContent = sec.name; root.appendChild(h);
  const grid = document.createElement("div"); grid.className = "grid"; root.appendChild(grid);
  for (const it of sec.items) {
    const d = document.createElement("div"); d.className = "c";
    const size = S.compact ? 74 : S.big ? 284 : 134;
    const st = document.createElement("div"); st.className = "st"; st.style.width = size + "px"; st.style.height = size + "px";
    const cv = document.createElement("canvas"); cv.width = size * 2; cv.height = size * 2; cv.style.width = size + "px"; cv.style.height = size + "px";
    const g = cv.getContext("2d"); g.scale(2, 2);
    const hasTrail = it.look.skin.Trail && it.look.skin.Trail !== "None";
    const hatted = it.look.skin.Hat && it.look.skin.Hat !== "None";
    const cx = size / 2, cy = S.gear ? size / 2 : hasTrail ? size * 0.36 : size / 2 + (hatted ? size * 0.08 : 0), r = size * (S.gear ? 0.27 : S.compact ? 0.38 : hatted ? 0.28 : 0.31);
    drawGerm(g, cx, cy, r, it.look, 0.3);
    st.appendChild(cv);
    lookOverlay(st, cx, cy, r, TREES[it.tree]);
    d.appendChild(st);
    const n = document.createElement("div"); n.className = "n"; n.textContent = it.title; d.appendChild(n);
    if (!S.compact) { const p = document.createElement("div"); p.className = "p"; p.textContent = it.price; d.appendChild(p); }
    grid.appendChild(d);
  }
}
</script></body></html>`;

(async () => {
  const browser = await chromium.launch();
  for (const sheet of sheets.filter((s) => !process.env.ONLY || s.file.startsWith(process.env.ONLY))) {
    // a fresh page each time: the drawing code declares top-level constants
    const tab = await browser.newPage({ viewport: { width: 1400, height: 800 }, deviceScaleFactor: 2 });
    tab.on("pageerror", (e) => console.error("page error:", e.message));
    const items = sheet.sections.flatMap((sec) => sec.items);
    const trees = lookTrees(items.map((it) => it.look));
    items.forEach((it, i) => (it.tree = i));
    await tab.setContent(html(sheet, trees), { waitUntil: "networkidle" }).catch(() => {});
    await tab.evaluate(() => document.fonts.ready);
    const file = path.join(out, sheet.file + ".png");
    await tab.screenshot({ path: file, fullPage: true });
    console.log(file);
    await tab.close();
  }
  await browser.close();
})();
