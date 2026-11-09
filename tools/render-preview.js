// Draws preview images of the game from the headless simulation (not real Roblox screenshots).
// Colours, sizes, zones and the HUD layout follow the game code; Roblox lighting and 3D shading are not shown.
//   PREVIEW=1 node tools/sim-server.js 9.4 > dumps.txt
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
	rps: num(/Config\.RadiusPerRootSize = ([\d.]+)/),
	bubble: num(/Config\.SpawnBubbleRadius = (\d+)/),
	camBase: num(/BaseHeight = (\d+)/),
	camPer: num(/PerRadius = (\d+)/),
	nerve: num(/Config\.NerveRadius = (\d+)/),
};
// the flag emoji from a country code
const flagEmoji = (code) => code && code.length === 2 ? String.fromCodePoint(...[...code].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65)) : "";

const page = (D, view) => `<!doctype html><html><body style="margin:0;background:#000">
<canvas id="c" width="1280" height="720"></canvas>
<script>
const D = ${JSON.stringify(D)}, C = ${JSON.stringify(C)}, VIEW = ${JSON.stringify(view)};
const cv = document.getElementById("c"), g = cv.getContext("2d");
g.lineJoin = "round";
const T = D.theme, rgb = (c, k) => "rgb(" + c.map(v => Math.round(v * (k || 1))).join(",") + ")";
const radius = (s) => C.rps * Math.sqrt(Math.max(s, 0));
let cx = 0, cz = 0, pps;
const mine = D.cells.filter(c => c.g === D.probe);
const myTotal = mine.reduce((a, c) => a + c.s, 0) || 10;
if (VIEW === "player" && mine.length) {
  cx = mine.reduce((a, c) => a + c.x * c.s, 0) / myTotal; cz = mine.reduce((a, c) => a + c.z * c.s, 0) / myTotal;
  const h = Math.min(900, C.camBase + radius(myTotal) * C.camPer);
  pps = 360 / (h * Math.tan(Math.PI / 6));
} else { pps = 700 / (2 * D.radius + 30); }
const X = (x) => 640 + (x - cx) * pps, Y = (z) => 360 + (z - cz) * pps;
function circle(x, z, r, fill, stroke, lw) { g.beginPath(); g.arc(X(x), Y(z), Math.max(r * pps, 0.5), 0, 7); if (fill) { g.fillStyle = fill; g.fill(); } if (stroke) { g.lineWidth = lw || 2; g.strokeStyle = stroke; g.stroke(); } }
g.fillStyle = rgb(T.outside); g.fillRect(0, 0, 1280, 720);
circle(0, 0, D.radius + 6, rgb(T.wall));
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
D.zones.forEach((z, i) => {
  circle(0, 0, z.outer, rgb(T.floors[i] || T.floors[0]));
  const inner = D.zones[i + 1] ? D.zones[i + 1].outer : 0;
  const n = Math.floor((z.outer - inner) * 0.3);
  for (let k = 0; k < n; k++) { const a = rnd() * 7, d = inner + 6 + rnd() * (z.outer - inner - 12), r = 3 + rnd() * 9;
    g.globalAlpha = 0.1; circle(Math.cos(a) * d, Math.sin(a) * d, r, "#000"); g.globalAlpha = 1; }
});
if (D.kind === "arena") { g.strokeStyle = "rgba(120,170,200,0.5)"; g.lineWidth = 1; for (let x = -D.radius; x <= D.radius; x += 20) { g.beginPath(); g.moveTo(X(x), Y(-D.radius)); g.lineTo(X(x), Y(D.radius)); g.stroke(); g.beginPath(); g.moveTo(X(-D.radius), Y(x)); g.lineTo(X(D.radius), Y(x)); g.stroke(); } }
D.zones.forEach((z, i) => { if (i > 0) { const m = rgb(T.membranes[i]); g.shadowColor = m; g.shadowBlur = 12; circle(0, 0, z.outer, null, m, Math.max(2.5 * pps, 2)); g.shadowBlur = 0; } });
g.textAlign = "center"; g.textBaseline = "middle";
if (D.kind === "host") D.zones.forEach((z, i) => { const inner = D.zones[i + 1] ? D.zones[i + 1].outer : 0; const mid = i === D.zones.length - 1 ? z.outer * 0.55 : (z.outer + inner) / 2;
  const w = Math.min(120, (z.outer - inner) * 1.6); g.font = "bold " + Math.round(w / 4 * pps * 0.8) + "px 'Fredoka One', Arial Rounded MT Bold, sans-serif";
  g.fillStyle = "rgba(255,255,255,0.65)"; g.fillText(z.name, X(0), Y(-mid)); });
// burning outer ring (Fire burp)
if (D.burnFrom > 0) { g.globalAlpha = 0.45; g.beginPath(); g.arc(X(0), Y(0), D.radius * pps, 0, 2 * Math.PI); g.moveTo(X(D.burnFrom), Y(0)); g.arc(X(0), Y(0), D.burnFrom * pps, 0, 2 * Math.PI, true); g.fillStyle = "#ff5a14"; g.fill(); g.globalAlpha = 1; }
(D.warps || []).forEach((w, i) => { const col = i < 2 ? "#be5aff" : "#50ffc8"; g.shadowColor = col; g.shadowBlur = 20; circle(w.x, w.z, w.r, col); g.shadowBlur = 0; circle(w.x, w.z, w.r * 0.6, "#0a0514"); });
(D.spikes || []).forEach((s) => circle(s.x, s.z, s.r, "rgba(200,40,50,0.85)"));
(D.bubbles || []).forEach(b => { g.globalAlpha = 0.35; circle(b[0], b[1], C.bubble, "#96dcff", "#cff0ff", 2); g.globalAlpha = 1; });
const nerveCol = D.kind === "arena" ? "#78ffc8" : "#ffe678";
g.shadowColor = nerveCol; g.shadowBlur = 25; circle(0, 0, C.nerve, nerveCol); g.shadowBlur = 0;
const FOOD = ["#fff08c", "#aaffaa", "#96dcff", "#ffb4e6", "#ffc896"];
D.food.forEach((f, i) => { const d = f[3] ? 5 : Math.min(3, 0.8 + Math.sqrt(f[2]) * 0.3); if (f[3]) { g.shadowColor = "#ffc828"; g.shadowBlur = 20; }
  circle(f[0], f[1], d / 2, f[3] ? "#ffc828" : FOOD[i % 5]); g.shadowBlur = 0; });
const fmt = (n) => { const u = [[1e12,"T"],[1e9,"B"],[1e6,"M"],[1e3,"K"]]; for (const [v, s] of u) if (n >= v) { const x = n / v; return (x >= 100 ? Math.floor(x) : x >= 10 ? (Math.floor(x * 10) / 10).toFixed(1) : (Math.floor(x * 100) / 100).toFixed(2)) + s; } return Math.round(n) + ""; };
[...D.cells].sort((a, b) => a.s - b.s).forEach(c => {
  const r = radius(c.s); let col = c.color;
  if (c.npc === "whitey") col = [245, 245, 255]; if (c.npc === "macrophage") col = [190, 120, 230]; if (c.npc === "antibody") col = [120, 180, 255];
  if (c.hidden && c.g !== D.probe) g.globalAlpha = 0.12;
  let fx = -c.x, fz = -c.z; const l = Math.hypot(fx, fz) || 1; fx /= l; fz /= l;
  const rot = (c.g % 7) * 0.4; [fx, fz] = [fx * Math.cos(rot) - fz * Math.sin(rot), fx * Math.sin(rot) + fz * Math.cos(rot)];
  const rx = -fz, rz = fx; const m = c.muts || {}; const has = (slot, id) => (m[slot] || "") === id;
  if (has("Back", "Flagella")) { g.strokeStyle = rgb(col, 0.8); g.lineWidth = r * 0.18 * pps; g.beginPath(); g.moveTo(X(c.x - fx * r), Y(c.z - fz * r));
    g.quadraticCurveTo(X(c.x - fx * r * 1.6 + rx * r * 0.4), Y(c.z - fz * r * 1.6 + rz * r * 0.4), X(c.x - fx * r * 2), Y(c.z - fz * r * 2)); g.stroke(); }
  if (has("Sides", "Spikes")) { g.fillStyle = rgb(col, 0.55); for (let i = 0; i < 8; i++) { const a = i / 8 * 6.283; const dx = Math.cos(a), dz = Math.sin(a);
    g.beginPath(); g.moveTo(X(c.x + dx * r * 1.35), Y(c.z + dz * r * 1.35)); g.lineTo(X(c.x + dx * r * 0.9 - dz * r * 0.15), Y(c.z + dz * r * 0.9 + dx * r * 0.15));
    g.lineTo(X(c.x + dx * r * 0.9 + dz * r * 0.15), Y(c.z + dz * r * 0.9 - dx * r * 0.15)); g.fill(); } }
  if (has("Front", "Jaws")) [-1, 1].forEach(s => circle(c.x + fx * r * 1.0 + s * rx * r * 0.22, c.z + fz * r * 1.0 + s * rz * r * 0.22, r * 0.2, "#f5f5e6"));
  if (c.npc === "antibody") { g.strokeStyle = rgb(col); g.lineWidth = Math.max(2, r * 0.3 * pps); g.beginPath(); g.moveTo(X(c.x), Y(c.z + r)); g.lineTo(X(c.x), Y(c.z)); g.lineTo(X(c.x - r * 0.7), Y(c.z - r * 0.8)); g.moveTo(X(c.x), Y(c.z)); g.lineTo(X(c.x + r * 0.7), Y(c.z - r * 0.8)); g.stroke(); g.globalAlpha = 1; return; }
  circle(c.x, c.z, r, rgb(col), rgb(col, 0.75), Math.max(1, r * 0.06 * pps));
  circle(c.x - fx * r * 0.2, c.z - fz * r * 0.2, r * 0.4, rgb(col, 0.65));
  if (has("Sides", "Shell")) { g.globalAlpha = 0.45; circle(c.x, c.z, r * 1.08, null, "#aaaab9", r * 0.18 * pps); g.globalAlpha = 1; }
  const eyes = c.npc ? "Angry" : c.eyes;
  const sides = eyes === "Cyclops" ? [0] : eyes === "Three" ? [-1.2, 0, 1.2] : [-1, 1];
  sides.forEach(s => { circle(c.x + fx * r * 0.42 + s * rx * r * 0.32, c.z + fz * r * 0.42 + s * rz * r * 0.32, r * (eyes === "Cyclops" ? 0.3 : 0.21), "#fff");
    circle(c.x + fx * r * 0.5 + s * rx * r * 0.32, c.z + fz * r * 0.5 + s * rz * r * 0.32, r * 0.1, "#191923"); });
  if (eyes === "Angry") [-1, 1].forEach(s => { g.strokeStyle = "#191923"; g.lineWidth = Math.max(1, r * 0.07 * pps); g.beginPath(); g.moveTo(X(c.x + fx * r * 0.62 + s * rx * r * 0.5), Y(c.z + fz * r * 0.62 + s * rz * r * 0.5)); g.lineTo(X(c.x + fx * r * 0.52 + s * rx * r * 0.12), Y(c.z + fz * r * 0.52 + s * rz * r * 0.12)); g.stroke(); });
  if (c.hat === "Crown") circle(c.x, c.z, r * 0.3, "#ffcd32"); if (c.hat === "Halo") circle(c.x, c.z, r * 0.5, null, "#fffab4", r * 0.08 * pps);
  if (c.hat === "Party") circle(c.x, c.z, r * 0.18, "#ff5ac8"); if (c.hat === "Horns") [-1, 1].forEach(s => circle(c.x + s * rx * r * 0.35, c.z + s * rz * r * 0.35, r * 0.12, "#c82828"));
  if (c.flag) { g.font = Math.round(r * 0.8 * pps) + "px sans-serif"; g.fillText(FLAGS[c.flag] || "", X(c.x + r * 0.45), Y(c.z + r * 0.45)); }
  if (c.prot) { g.globalAlpha = 0.35; circle(c.x, c.z, r * 1.25, "#96dcff"); g.globalAlpha = 1; }
  if (c.npc !== "antibody") {
    g.font = "bold 15px 'Fredoka One', Arial Rounded MT Bold, sans-serif"; g.lineWidth = 3; g.strokeStyle = "rgba(0,0,0,0.6)"; g.fillStyle = "#fff";
    const name = (c.crown ? "👑 " : "") + c.name; g.strokeText(name, X(c.x), Y(c.z) - 9); g.fillText(name, X(c.x), Y(c.z) - 9);
    g.strokeText(fmt(c.real), X(c.x), Y(c.z) + 9); g.fillText(fmt(c.real), X(c.x), Y(c.z) + 9);
  }
  g.globalAlpha = 1;
});
(D.ink || []).forEach(k => { g.globalAlpha = 0.85; circle(k.x, k.z, k.r, "#140f28"); g.globalAlpha = 1; });
function txt(t, x, y, size, align, color) { g.font = "bold " + size + "px 'Fredoka One', Arial Rounded MT Bold, sans-serif"; g.textAlign = align || "center"; g.lineWidth = 4; g.strokeStyle = "#140a1e"; g.strokeText(t, x, y); g.fillStyle = color || "#fff"; g.fillText(t, x, y); }
function rrect(x, y, w, h, r, fill) { g.beginPath(); g.roundRect(x, y, w, h, r); g.fillStyle = fill; g.fill(); }
const H = D.hud;
if (VIEW === "player") {
  txt("Size " + fmt(H.size), 640, 30, 34);
  txt(H.zoneName + " · inside " + H.hostName, 640, 62, 17);
  const sneezeReal = D.sneeze * (D.kind === "arena" ? 1 : Math.pow(10, D.host - 1));
  let gate = { name: D.kind === "arena" ? "Exit" : "Sneeze", size: sneezeReal };
  if (D.kind === "host") { const next = D.zones.findIndex(z => z.min * sneezeReal > H.size); if (next >= 0) gate = { name: D.zones[next].name, size: D.zones[next].min * sneezeReal }; }
  rrect(450, 76, 380, 24, 12, "rgba(40,25,50,0.8)"); rrect(450, 76, 380 * Math.min(1, H.size / gate.size), 24, 12, "#78e68c");
  txt(gate.name === "Sneeze" ? "Size " + fmt(gate.size) + " to SNEEZE into the next host" : gate.name === "Exit" ? "Floor " + H.floor + ": reach size " + fmt(gate.size) : "Size " + fmt(gate.size) + " to enter the " + gate.name, 640, 94, 15);
  txt("🧬 " + fmt(H.dna) + " DNA", 14, 30, 24, "left");
  if (H.gp > 0) txt("⭐ " + H.gp + " Germ Points", 14, 56, 15, "left", "#dcc8ff");
  const menu = [["🧪 Lab", "#78c878"], ["🎨 Editor", "#e68cc8"], ["🛒 Shop", "#ebaf28"], ["📜 Quests", "#6eaaf0"], ["🏟️ Arena", "#aa6ee6"], ["🏆 Top", "#f0a050"], ["💬 Ideas", "#787896"], ["🛠 Dev", "#50505a"]];
  menu.forEach(([t, c], i) => { rrect(10, 150 + i * 52, 112, 46, 12, c); txt(t, 66, 180 + i * 52, 17); });
  rrect(1060, 6, 210, 170, 12, "rgba(40,25,50,0.65)"); txt("Biggest germs", 1165, 24, 16);
  const totals = {}; D.cells.filter(c => !c.npc).forEach(c => { totals[c.g] = totals[c.g] || { name: c.name, s: 0, g: c.g }; totals[c.g].s += c.real; });
  Object.values(totals).sort((a, b) => b.s - a.s).slice(0, 6).forEach((t, i) => txt((i + 1) + ". " + t.name + "  " + fmt(t.s), 1068, 50 + i * 23, 14, "left", t.g === D.probe ? "#8cffa0" : "#fff"));
  rrect(1010, 584, 120, 52, 12, "#9a5adc"); txt("Q", 1070, 616, 18); rrect(1140, 584, 120, 52, 12, "#dc5096"); txt("R", 1200, 616, 18);
  rrect(1010, 646, 120, 52, 12, "#50aaff"); txt("DASH [Shift]", 1070, 678, 16); rrect(1140, 646, 120, 52, 12, "#ff8c50"); txt("SPLIT [Space]", 1200, 678, 15);
  if (BANNER) txt(BANNER, 640, 200, 26, "center", "#ffe678");
} else {
  txt(T.name + (D.kind === "arena" ? "" : " · whole host from above (overview, not the in-game camera)"), 640, 30, 20);
  if (BANNER) txt(BANNER, 640, 60, 22, "center", "#ffe678");
}
txt("Preview drawn from the game's simulation · not a Roblox screenshot", 640, 712, 12, "center", "rgba(255,255,255,0.7)");
</script></body></html>`;

(async () => {
	fs.mkdirSync(outDir, { recursive: true });
	const browser = await chromium.launch();
	const by = Object.fromEntries(dumps.map((d) => [d.name, d]));
	const shots = [
		["host1-new", "player", "1-host1-new-germ.png", "🦠 Inside Nibbles the Hamster!"],
		["host1-growing", "player", "2-host1-growing.png", ""],
		["host2-drool", "player", "3-host2-drool-wave.png", "💧 DROOL WAVE! Everything slides one way"],
		["host4-fire", "overview", "4-host4-fire-burp.png", "🔥 The outer ring is BURNING!"],
		["host5-ink", "player", "5-host5-ink-clouds.png", "Ink clouds! Germs inside a cloud are hidden"],
		["host6-warps", "overview", "6-host6-warp-holes.png", "Warp holes: jump in to teleport"],
		["arena", "player", "7-arena-floor.png", "🏟️ The Infinite Petri"],
	];
	for (const [key, view, name, banner] of shots) {
		const dump = by[key];
		if (!dump) continue;
		const p = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2 });
		p.on("pageerror", (e) => console.log("page error in", name, e.message));
		const flags = {};
		dump.cells.forEach((c) => { if (c.flag) flags[c.flag] = flagEmoji(c.flag); });
		await p.setContent(page(dump, view).replace("<script>", "<script>const BANNER = " + JSON.stringify(banner) + ", FLAGS = " + JSON.stringify(flags) + ";"));
		await p.screenshot({ path: path.join(outDir, name) });
		await p.close();
		console.log("wrote", name);
	}
	await browser.close();
})();
