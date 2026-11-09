// Draws preview images of the game from the headless simulation (not real Roblox screenshots).
// Colours, sizes, zones and the HUD layout follow the game code; Roblox lighting and 3D shading are not shown.
//   DUMP_AT=0.5,6,16 node tools/sim-server.js 17 > dumps.txt
//   node tools/render-preview.js dumps.txt out-folder
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const [dumpFile, outDir] = process.argv.slice(2);
const dumps = fs
	.readFileSync(dumpFile, "utf8")
	.split("\n")
	.filter((l) => l.startsWith("DUMP "))
	.map((l) => JSON.parse(l.slice(5)));
const cfg = fs.readFileSync(path.join(__dirname, "..", "src", "shared", "Config.luau"), "utf8");
const num = (re) => Number(cfg.match(re)[1]);
const C = {
	arena: num(/Config\.ArenaRadius = (\d+)/),
	rps: num(/Config\.RadiusPerRootSize = ([\d.]+)/),
	bubble: num(/Config\.SpawnBubbleRadius = (\d+)/),
	camBase: num(/BaseHeight = (\d+)/),
	camPer: num(/PerRadius = (\d+)/),
	zones: [...cfg.matchAll(/Name = "([^"]+)", Outer = (\d+), MinShare = ([\d.]+)/g)].map((m) => ({ name: m[1], outer: +m[2], min: +m[3] })),
	sneeze: num(/SneezeSize = (\d+)/),
};

const page = (dump, view) => `<!doctype html><html><body style="margin:0;background:#000">
<canvas id="c" width="1280" height="720"></canvas>
<script>
const D = ${JSON.stringify(dump)}, C = ${JSON.stringify(C)}, VIEW = ${JSON.stringify(view)};
const cv = document.getElementById("c"), g = cv.getContext("2d");
g.lineJoin = "round";
const ZONE = [["#ffc4c4","#ff7896"],["#ffdcb4","#ffaa5a"],["#fac88c","#e6783c"],["#dc5a64","#ff3c50"]];
const radius = (s) => C.rps * Math.sqrt(s);
let cx = 0, cz = 0, pps;
const mine = D.cells.filter(c => c.g === D.probe);
const myTotal = mine.reduce((a, c) => a + c.s, 0);
if (VIEW === "player") {
  cx = mine.reduce((a, c) => a + c.x * c.s, 0) / myTotal; cz = mine.reduce((a, c) => a + c.z * c.s, 0) / myTotal;
  const h = C.camBase + radius(myTotal) * C.camPer;
  pps = 360 / (h * Math.tan(Math.PI / 6)); // 60 degree field of view, half the screen height
} else { pps = 700 / (2 * C.arena + 30); }
const X = (x) => 640 + (x - cx) * pps, Y = (z) => 360 + (z - cz) * pps;
function circle(x, z, r, fill, stroke, lw) { g.beginPath(); g.arc(X(x), Y(z), Math.max(r * pps, 0.5), 0, 7); if (fill) { g.fillStyle = fill; g.fill(); } if (stroke) { g.lineWidth = lw || 2; g.strokeStyle = stroke; g.stroke(); } }
// outside + zones
g.fillStyle = "#3c141e"; g.fillRect(0, 0, 1280, 720);
circle(0, 0, C.arena + 6, "#c86e78");
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
C.zones.forEach((z, i) => {
  circle(0, 0, z.outer, ZONE[i][0]);
  const inner = C.zones[i + 1] ? C.zones[i + 1].outer : 0;
  const n = Math.floor((z.outer - inner) * 0.35);
  for (let k = 0; k < n; k++) { const a = rnd() * 7, d = inner + 6 + rnd() * (z.outer - inner - 12), r = 3 + rnd() * 9;
    g.globalAlpha = 0.1; circle(Math.cos(a) * d, Math.sin(a) * d, r, "#000"); g.globalAlpha = 1; }
});
C.zones.forEach((z, i) => { if (i > 0) { g.shadowColor = ZONE[i][1]; g.shadowBlur = 12; circle(0, 0, z.outer, null, ZONE[i][1], Math.max(2.5 * pps, 2)); g.shadowBlur = 0; } });
// zone names on the floor
g.textAlign = "center"; g.textBaseline = "middle";
C.zones.forEach((z, i) => { const inner = C.zones[i + 1] ? C.zones[i + 1].outer : 0; const mid = i === C.zones.length - 1 ? z.outer * 0.55 : (z.outer + inner) / 2;
  const w = Math.min(120, (z.outer - inner) * 1.6); g.font = "bold " + Math.round(w / 4 * pps * 0.8) + "px 'Fredoka One', Arial Rounded MT Bold, sans-serif";
  g.fillStyle = "rgba(255,255,255,0.65)"; g.fillText(z.name, X(0), Y(-mid)); });
// bubbles + sneeze nerve
D.bubbles.forEach(b => { g.globalAlpha = 0.35; circle(b[0], b[1], C.bubble, "#96dcff", "#cff0ff", 2); g.globalAlpha = 1; });
g.shadowColor = "#ffe678"; g.shadowBlur = 25; circle(0, 0, 13, "#ffe678"); g.shadowBlur = 0;
// food
const FOOD = ["#fff08c", "#aaffaa", "#96dcff", "#ffb4e6", "#ffc896"];
D.food.forEach((f, i) => { const d = f[3] ? 5 : Math.min(3, 0.8 + Math.sqrt(f[2]) * 0.3); if (f[3]) { g.shadowColor = "#ffc828"; g.shadowBlur = 20; }
  circle(f[0], f[1], d / 2, f[3] ? "#ffc828" : FOOD[i % 5]); g.shadowBlur = 0; });
// germs, small ones first
const rgb = (c, k) => "rgb(" + c.map(v => Math.round(v * (k || 1))).join(",") + ")";
[...D.cells].sort((a, b) => a.s - b.s).forEach(c => {
  const r = radius(c.s), col = c.color;
  // facing: toward the middle of the dish, slightly rotated per germ
  let fx = -c.x, fz = -c.z; const l = Math.hypot(fx, fz) || 1; fx /= l; fz /= l;
  const rot = (c.g % 7) * 0.4; [fx, fz] = [fx * Math.cos(rot) - fz * Math.sin(rot), fx * Math.sin(rot) + fz * Math.cos(rot)];
  const rx = -fz, rz = fx;
  if (c.muts.Back === "Flagella") { g.strokeStyle = rgb(col, 0.8); g.lineWidth = r * 0.18 * pps; g.beginPath(); g.moveTo(X(c.x - fx * r), Y(c.z - fz * r));
    g.quadraticCurveTo(X(c.x - fx * r * 1.6 + rx * r * 0.4), Y(c.z - fz * r * 1.6 + rz * r * 0.4), X(c.x - fx * r * 2), Y(c.z - fz * r * 2)); g.stroke(); }
  if (c.muts.Sides === "Spikes") { g.fillStyle = rgb(col, 0.55); for (let i = 0; i < 8; i++) { const a = i / 8 * 6.283; const dx = Math.cos(a), dz = Math.sin(a);
    g.beginPath(); g.moveTo(X(c.x + dx * r * 1.35), Y(c.z + dz * r * 1.35)); g.lineTo(X(c.x + dx * r * 0.9 - dz * r * 0.15), Y(c.z + dz * r * 0.9 + dx * r * 0.15));
    g.lineTo(X(c.x + dx * r * 0.9 + dz * r * 0.15), Y(c.z + dz * r * 0.9 - dx * r * 0.15)); g.fill(); } }
  if (c.muts.Front === "Jaws") { g.fillStyle = "#f5f5e6"; [-1, 1].forEach(s => { circle(c.x + fx * r * 1.0 + s * rx * r * 0.22, c.z + fz * r * 1.0 + s * rz * r * 0.22, r * 0.2, "#f5f5e6"); }); }
  circle(c.x, c.z, r, rgb(col), rgb(col, 0.75), Math.max(1, r * 0.06 * pps));
  circle(c.x - fx * r * 0.2, c.z - fz * r * 0.2, r * 0.4, rgb(col, 0.65));
  if (c.muts.Sides === "Shell") { g.globalAlpha = 0.45; circle(c.x, c.z, r * 1.08, null, "#aaaab9", r * 0.18 * pps); g.globalAlpha = 1; }
  [-1, 1].forEach(s => { circle(c.x + fx * r * 0.42 + s * rx * r * 0.32, c.z + fz * r * 0.42 + s * rz * r * 0.32, r * 0.21, "#fff");
    circle(c.x + fx * r * 0.5 + s * rx * r * 0.32, c.z + fz * r * 0.5 + s * rz * r * 0.32, r * 0.1, "#191923"); });
  if (c.prot) { g.globalAlpha = 0.35; circle(c.x, c.z, r * 1.25, "#96dcff"); g.globalAlpha = 1; }
  // name tag (fixed pixel size, like the BillboardGui)
  const fmt = (n) => n >= 1000 ? (n / 1000).toFixed(n >= 10000 ? 1 : 2) + "K" : Math.round(n) + "";
  g.font = "bold 15px 'Fredoka One', Arial Rounded MT Bold, sans-serif"; g.lineWidth = 3; g.strokeStyle = "rgba(0,0,0,0.6)"; g.fillStyle = "#fff";
  const name = (c.crown ? "👑 " : "") + c.name; g.strokeText(name, X(c.x), Y(c.z) - 9); g.fillText(name, X(c.x), Y(c.z) - 9);
  g.strokeText(fmt(c.s), X(c.x), Y(c.z) + 9); g.fillText(fmt(c.s), X(c.x), Y(c.z) + 9);
});
// HUD (same layout as Hud.luau)
function txt(t, x, y, size, align, color) { g.font = "bold " + size + "px 'Fredoka One', Arial Rounded MT Bold, sans-serif"; g.textAlign = align || "center"; g.lineWidth = 4; g.strokeStyle = "#140a1e"; g.strokeText(t, x, y); g.fillStyle = color || "#fff"; g.fillText(t, x, y); }
function rrect(x, y, w, h, r, fill) { g.beginPath(); g.roundRect(x, y, w, h, r); g.fillStyle = fill; g.fill(); }
if (VIEW === "player") {
  const fmt = (n) => n >= 1000 ? (n / 1000).toFixed(2) + "K" : Math.round(n) + "";
  const d = Math.hypot(cx, cz); let zi = 0; C.zones.forEach((z, i) => { if (d <= z.outer) zi = i; });
  txt("Size " + fmt(myTotal), 640, 30, 34);
  txt(C.zones[zi].name + " · inside Nibbles the Hamster", 640, 62, 17);
  let next = C.zones.findIndex(z => z.min * C.sneeze > myTotal); const gate = next < 0 ? { name: "Sneeze", size: C.sneeze } : { name: C.zones[next].name, size: C.zones[next].min * C.sneeze };
  rrect(460, 76, 360, 22, 11, "rgba(40,25,50,0.8)"); rrect(460, 76, 360 * Math.min(1, myTotal / gate.size), 22, 11, "#78e68c");
  txt(gate.name === "Sneeze" ? "Size 2.50K to SNEEZE (next update!)" : "Size " + fmt(gate.size) + " to enter the " + gate.name, 640, 93, 15);
  txt("🧬 DNA", 14, 84, 22, "left");
  rrect(12, 100, 120, 44, 14, "#aa6ee6"); txt("🧪 Lab", 72, 130, 20);
  rrect(12, 150, 120, 34, 14, "#786e82"); txt("🐞 Bugs & Ideas", 72, 173, 13);
  rrect(1080, 60, 190, 190, 12, "rgba(40,25,50,0.65)"); txt("Biggest germs", 1175, 82, 16);
  const totals = {}; D.cells.forEach(c => { totals[c.g] = totals[c.g] || { name: c.name, s: 0, g: c.g }; totals[c.g].s += c.s; });
  Object.values(totals).sort((a, b) => b.s - a.s).slice(0, 6).forEach((t, i) => txt((i + 1) + ". " + t.name + "  " + fmt(t.s), 1090, 110 + i * 26, 14, "left", t.g === D.probe ? "#8cffa0" : "#fff"));
  rrect(1150, 470, 110, 110, 14, "#5aaaff"); txt("DASH", 1205, 520, 22); txt("[Shift]", 1205, 546, 16);
  rrect(1040, 570, 90, 90, 14, "#ff965a"); txt("SPLIT", 1085, 612, 20); txt("[Space]", 1085, 636, 14);
} else {
  txt("Whole host from above (overview, not the in-game camera)", 640, 30, 20);
}
txt("Preview drawn from the game's simulation · not a Roblox screenshot", 640, 712, 12, "center", "rgba(255,255,255,0.7)");
</script></body></html>`;

(async () => {
	fs.mkdirSync(outDir, { recursive: true });
	const browser = await chromium.launch();
	const shots = [
		[dumps[0], "player", "1-new-germ.png"],
		[dumps[1], "player", "2-growing.png"],
		[dumps[2], "player", "3-big-germ.png"],
		[dumps[2], "overview", "4-whole-host.png"],
	];
	for (const [dump, view, name] of shots) {
		if (!dump) continue;
		const p = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2 });
		p.on("pageerror", (e) => console.log("page error in", name, e.message));
		await p.setContent(page(dump, view));
		await p.screenshot({ path: path.join(outDir, name) });
		await p.close();
		console.log("wrote", name);
	}
	await browser.close();
})();
