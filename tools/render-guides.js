// Controls guides for PC and phones: the real HUD (dumped from the client code like
// tools/render-menus.js) over a drawn dish, with labels pointing at each control.
// Usage: NODE_PATH=$(npm root -g) node tools/render-guides.js <out-dir>
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { chromium } = require("playwright");
const guiDraw = require("./gui-draw");
const germDraw = require("./germ-draw");

const out = path.resolve(process.argv[2] || "guide-previews");
fs.mkdirSync(out, { recursive: true });
function dump(touch) {
  const file = path.join(out, "hud.json");
  execFileSync("node", [path.join(__dirname, "client-smoke.js")], {
    env: { ...process.env, MENU_DUMP: '{{"_hud"}}', MENU_OUT: file, MENU_TOUCH: touch ? "1" : "" }, stdio: "ignore",
  });
  const tree = JSON.parse(fs.readFileSync(file, "utf8")).shots[0].tree;
  fs.unlinkSync(file);
  // leftovers of the smoke test's fake events, and nicer names on the size board
  const names = ["SneezeQueen", "You", "Bubbles", "TinyTerror", "GermLord99", "Gloopy"];
  const clean = (o) => {
    o.children = o.children.filter((c) => !(typeof c.Text === "string" && /^(hi|X|x)$|REVENGE on b|^Bob|Quarantine/.test(c.Text)));
    for (const c of o.children) {
      if (typeof c.Text === "string") c.Text = c.Text.replace(/^(\d)\. G\d+ +500$/, (_, n) => n + ". " + names[n - 1] + " " + [9000, 2600, 900, 600, 480, 300][n - 1].toLocaleString("en"));
      clean(c);
    }
    return o;
  };
  return clean(tree);
}

// screen = size of the game screen in GUI units, scale = how big it is drawn, at = where on the page
const GUIDES = [
  { file: "controls-pc", title: "PC controls", touch: false, page: [1820, 960], at: [270, 110], screen: [1280, 720], scale: 1, hudScale: 1,
    labels: [
      { text: "🖱️ Your germ swims toward the mouse. Farther away = faster. No clicking", target: "cursor", at: [1180, 22] },
      { text: "Shift: DASH (escape or catch)", target: "DASH", at: [1570, 700] },
      { text: "Space: SPLIT (throw half forward)", target: "SPLIT", at: [1570, 800] },
      { text: "Q: Front power (Chomp, Vacuum, Pierce)", target: "Q", at: [1570, 560] },
      { text: "E: Special power (Ghost, Gravity, Blast)", target: "E", at: [1570, 440] },
      { text: "Menus", target: "Lab", at: [40, 470] },
      { text: "Map", target: "map", at: [1570, 300] },
      { text: "How big you must get to sneeze into the next host", target: "gate", at: [560, 22] },
      { text: "⌨️ WASD or the arrow keys also swim (let go = stop)   ·   🖲️ Mouse wheel = zoom", target: "me", at: [270, 880], noLine: true, wide: true },
    ] },
  { file: "controls-phone", title: "Phone controls", touch: true, page: [1560, 860], at: [250, 150], screen: [844, 390], scale: 1.25, hudScale: 390 / 620,
    labels: [
      { text: "👍 Drag the stick to swim. Push a little = slower, let go = stop", target: "Stick", at: [30, 760] },
      { text: "👆 Or hold a finger anywhere on the dish: your germ swims there", target: "finger", at: [700, 40] },
      { text: "DASH", target: "DASH", at: [1380, 720] },
      { text: "SPLIT", target: "SPLIT", at: [1380, 790] },
      { text: "Q power", target: "Q", at: [1380, 560] },
      { text: "E power", target: "E", at: [1380, 630] },
      { text: "Menus", target: "Lab", at: [40, 300] },
      { text: "Map", target: "map", at: [1380, 300] },
      { text: "🤏 Pinch = zoom", target: "me", at: [250, 40], noLine: true },
    ] },
];

const html = (guide, tree) => `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600&display=block" rel="stylesheet">
<style>body{margin:0;width:${guide.page[0]}px;height:${guide.page[1]}px;background:#1f1229;font-family:Fredoka,sans-serif;font-weight:600;position:relative;overflow:hidden}
#stage{position:absolute;left:${guide.at[0]}px;top:${guide.at[1]}px;width:${guide.screen[0]}px;height:${guide.screen[1]}px;transform:scale(${guide.scale});transform-origin:0 0;overflow:hidden;border-radius:${guide.touch ? 26 : 8}px;outline:${guide.touch ? "10px solid #0c0810" : "4px solid #0c0810"}}
#world{position:absolute;left:0;top:0}
.n{position:absolute;box-sizing:border-box;overflow:hidden}.t{display:flex;align-items:center;white-space:nowrap;color:#fff}
.lab{position:absolute;background:#fff;color:#2a1838;border-radius:12px;padding:8px 12px;font-size:19px;box-shadow:0 3px 10px #0008;max-width:360px;line-height:1.2}
h1{position:absolute;left:24px;top:8px;margin:0;color:#fff;font-size:30px}
svg{position:absolute;left:0;top:0;pointer-events:none}</style></head><body>
<h1>${guide.title}</h1>
<div id="stage"><canvas id="world"></canvas></div>
<svg id="lines" width="${guide.page[0]}" height="${guide.page[1]}"></svg>
<script>${germDraw}
${guiDraw}
const G = ${JSON.stringify(guide)}, TREE = ${JSON.stringify(tree)};
const W = G.screen[0], H = G.screen[1];
const cv = document.getElementById("world"); cv.width = W * 2; cv.height = H * 2; cv.style.width = W + "px"; cv.style.height = H + "px";
const g = cv.getContext("2d"); g.scale(2, 2);
// the dish
const bg = g.createRadialGradient(W * 0.55, H * 0.5, 10, W * 0.5, H * 0.5, W * 0.8);
bg.addColorStop(0, "#f7c1cf"); bg.addColorStop(0.6, "#e795ad"); bg.addColorStop(1, "#b8607f");
g.fillStyle = bg; g.fillRect(0, 0, W, H);
let seed = 3; const rnd = () => (seed = (seed * 9301 + 49297) % 233280) / 233280;
for (let i = 0; i < (G.touch ? 70 : 110); i++) { const c = ["#ffe066","#8ce99a","#74c0fc","#ffa8a8","#d0bfff"][i % 5]; g.fillStyle = c; g.beginPath(); g.arc(rnd() * W, rnd() * H, 3 + rnd() * 3, 0, 7); g.fill(); }
const u = G.touch ? 0.55 : 1;
const me = { color: [110, 200, 255], skin: { Body: "Jelly", Pattern: "Spots", Eyes: "Cute", Mouth: "Smile", Hat: "Crown", Trail: "Sparkles", Color2: [255,255,255] }, muts: { Front: "Jaws", Back: "Flagella" } };
const others = [
  [0.22, 0.3, 30, { color: [255,150,90], skin: { Eyes: "Angry", Mouth: "Fangs" }, muts: { Sides: "Spikes" } }, "SneezeQueen 4.1K", "danger"],
  [0.78, 0.68, 16, { color: [190,140,255], skin: { Eyes: "Googly", Pattern: "Stripes", Color2: [255,255,255] } }, "🌱 Bubbles 900", ""],
  [0.68, 0.24, 12, { color: [120,220,120], skin: { Eyes: "Sleepy" } }, "TinyTerror 600", ""],
];
const label = (x, y, txt, s) => { g.font = "600 " + s + "px Fredoka"; g.textAlign = "center"; g.lineWidth = 3; g.strokeStyle = "#140a1e"; g.strokeText(txt, x, y); g.fillStyle = "#fff"; g.fillText(txt, x, y); };
for (const [fx, fy, r, look, name] of others) { drawGerm(g, fx * W, fy * H, r * u * 1.4, look, 0.2); label(fx * W, fy * H + 5, name, 13 * (G.touch ? 0.8 : 1)); }
const ME = [W * 0.5, H * 0.56], meR = 34 * u * 1.4;
drawGerm(g, ME[0], ME[1], meR, me, 0.2);
label(ME[0], ME[1] + meR * 0.25, "You 2.6K", 15 * (G.touch ? 0.8 : 1));
// where you steer
const aim = G.touch ? [W * 0.72, H * 0.33] : [W * 0.66, H * 0.22];
g.setLineDash([8, 6]); g.strokeStyle = "rgba(255,255,255,0.9)"; g.lineWidth = 3; g.beginPath(); g.moveTo(ME[0], ME[1] - meR); g.lineTo(aim[0], aim[1]); g.stroke(); g.setLineDash([]);
g.font = (G.touch ? 34 : 30) + "px 'Noto Color Emoji'"; g.textAlign = "center"; g.textBaseline = "middle"; g.fillText(G.touch ? "👆" : "🖱️", aim[0] + 4, aim[1] + 12);
// the HUD
const stage = document.getElementById("stage");
const root = draw({ ...TREE, Size: [0, W / G.hudScale, 0, H / G.hudScale] }, stage, W / G.hudScale, H / G.hudScale);
root.style.transform = "scale(" + G.hudScale + ")"; root.style.transformOrigin = "0 0";
// a thumb on the stick
const stick = [...stage.querySelectorAll("[data-name=Stick]")][0];
if (stick) { const k = stick.firstElementChild; if (k) { k.style.left = "68%"; k.style.top = "28%"; } const f = document.createElement("div"); f.textContent = "👍"; f.style.cssText = "position:absolute;left:52%;top:5%;font-size:58px;transform:rotate(-20deg);font-family:'Noto Color Emoji'"; stick.appendChild(f); stick.style.overflow = "visible"; }
// targets (page coordinates)
const pr = (el) => { const b = el.getBoundingClientRect(); return [b.left + b.width / 2, b.top + b.height / 2, b]; };
const st = stage.getBoundingClientRect();
const inWorld = (p) => [st.left + p[0] * G.scale, st.top + p[1] * G.scale];
const byText = (re) => [...stage.querySelectorAll(".t")].find((t) => re.test(t.textContent));
function target(name) {
  if (name === "cursor" || name === "finger") return inWorld(aim);
  if (name === "me") return inWorld(ME);
  if (name === "Stick") return pr(stick);
  if (name === "map") { const t = [...stage.querySelectorAll(".n")].filter(e => Math.abs(e.getBoundingClientRect().width - e.getBoundingClientRect().height) < 2 && e.getBoundingClientRect().width > 80 * G.hudScale && e.getBoundingClientRect().left > st.left + st.width * 0.7 && e.getBoundingClientRect().top < st.top + st.height * 0.6); return t.length ? pr(t[0]) : inWorld([W - 60, 120]); }
  if (name === "gate") { const t = byText(/SNEEZE/); return t ? pr(t.parentElement) : inWorld([W / 2, 40]); }
  if (name === "Lab") { const t = byText(/Lab$/); return pr(t.parentElement.parentElement); }
  const t = byText(new RegExp("^" + name + "\\\\b")) || byText(new RegExp("^(Chomp|Vacuum|Pierce)")) ;
  if (name === "E") { const e = byText(/^E\\b/) || byText(/^(Ghost|Gravity|Blast)/); if (e) return pr(e.parentElement); }
  if (name === "Q") { const q = byText(/^(Q|Chomp|Vacuum|Pierce)\\b/); if (q) return pr(q.parentElement); }
  return t ? pr(t.parentElement) : inWorld([W / 2, H / 2]);
}
const svg = document.getElementById("lines");
for (const l of G.labels) {
  const d = document.createElement("div"); d.className = "lab"; d.textContent = l.text; if (l.wide) d.style.maxWidth = "none"; document.body.appendChild(d);
  d.style.left = l.at[0] + "px"; d.style.top = l.at[1] + "px";
  const b = d.getBoundingClientRect();
  if (b.right > G.page[0] - 6) d.style.left = (G.page[0] - 6 - b.width) + "px";
  if (b.bottom > G.page[1] - 6) d.style.top = (G.page[1] - 6 - b.height) + "px";
  if (l.noLine) continue;
  const bb = d.getBoundingClientRect();
  const [tx, ty] = target(l.target);
  const sx = Math.max(bb.left, Math.min(tx, bb.right)), sy = Math.max(bb.top, Math.min(ty, bb.bottom));
  svg.insertAdjacentHTML("beforeend", '<line x1="' + sx + '" y1="' + sy + '" x2="' + tx + '" y2="' + ty + '" stroke="#fff" stroke-width="3"/><circle cx="' + tx + '" cy="' + ty + '" r="7" fill="#ffd43b" stroke="#2a1838" stroke-width="2"/>');
}
</script></body></html>`;

(async () => {
  const browser = await chromium.launch();
  for (const guide of GUIDES) {
    const tree = dump(guide.touch);
    const tab = await browser.newPage({ viewport: { width: guide.page[0], height: guide.page[1] }, deviceScaleFactor: 2 });
    tab.on("pageerror", (e) => console.error("page error:", e.message));
    await tab.setContent(html(guide, tree), { waitUntil: "networkidle" }).catch(() => {});
    await tab.evaluate(() => document.fonts.ready);
    const file = path.join(out, guide.file + ".png");
    await tab.screenshot({ path: file });
    console.log(file);
    await tab.close();
  }
  await browser.close();
})();
