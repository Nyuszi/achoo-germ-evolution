// Draws every left-side menu as a picture, from the real menu code.
// Runs the client smoke test in dump mode (tools/menu-dump.lua), lays the GUI tree out like
// Roblox would on a 1280x720 screen, and screenshots it with Playwright.
// Usage: NODE_PATH=$(npm root -g) node tools/render-menus.js <out-dir>
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { chromium } = require("playwright");

const out = path.resolve(process.argv[2] || "menu-previews");
fs.mkdirSync(out, { recursive: true });
const SHOTS = [
  ["Lab", "Mutations"], ["Lab", "Skills"], ["Editor", "Body"], ["Editor", "Flag"], ["Shop"], ["Quests", "Daily"],
  ["Quests", "Cards"], ["Arena"], ["Leaders"], ["Feedback"], ["Dev"], ["_hud"],
];
const BAR_NAME = { Lab: "Lab", Editor: "Editor", Shop: "Shop", Quests: "Quests", Arena: "Arena", Leaders: "Top", Feedback: "Ideas", Dev: "Dev" };
const json = path.join(out, "menus.json");
const luaList = "{" + SHOTS.map((s) => "{" + s.map((x) => JSON.stringify(x)).join(",") + "}").join(",") + "}";
execFileSync("node", [path.join(__dirname, "client-smoke.js")], { env: { ...process.env, MENU_DUMP: luaList, MENU_OUT: json }, stdio: "ignore" });
const data = JSON.parse(fs.readFileSync(json, "utf8"));
fs.unlinkSync(json);

const page = `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@600&display=block" rel="stylesheet">
<style>
body{margin:0;background:#000;font-family:'Fredoka','Arial Rounded MT Bold',sans-serif;font-weight:600}
#screen{position:relative;width:1280px;height:720px;overflow:hidden;
 background:radial-gradient(circle at 60% 55%,#f6b3c4 0,#e48aa6 35%,#b85a7d 70%,#5a2340 100%)}
.n{position:absolute;box-sizing:border-box;overflow:hidden}
.t{display:flex;align-items:center;white-space:nowrap;color:#fff}
.hl{outline:4px solid #fff;outline-offset:2px;box-shadow:0 0 18px 6px #fff8}
.cap{position:absolute;left:140px;bottom:14px;color:#fff;font-size:20px;text-shadow:0 2px 4px #000}
</style></head><body><div id="screen"></div><script>
const DATA = ${JSON.stringify(data)};
const rgb = (c) => c ? "rgb(" + c.map((x) => Math.round(x * 255)).join(",") + ")" : null;
const kid = (o, cls) => o.children.find((c) => c.class === cls);
const GUI = ["Frame", "TextLabel", "TextButton", "TextBox", "ScrollingFrame", "ImageLabel", "ImageButton"];
function draw(o, parentEl, pw, ph, pos) {
  if (o.Visible === false || !GUI.includes(o.class)) return null;
  const s = o.Size || [0, 100, 0, 100];
  let w = s[0] * pw + s[1], h = s[2] * ph + s[3];
  const lim = kid(o, "UISizeConstraint");
  if (lim) { w = Math.min(w, lim.MaxSize.x); h = Math.min(h, lim.MaxSize.y); }
  let x, y;
  if (pos) { x = pos[0]; y = pos[1]; } else {
    const p = o.Position || [0, 0, 0, 0], a = o.AnchorPoint || { x: 0, y: 0 };
    x = p[0] * pw + p[1] - a.x * w; y = p[2] * ph + p[3] - a.y * h;
  }
  const el = document.createElement("div");
  el.className = "n";
  Object.assign(el.style, { left: x + "px", top: y + "px", width: w + "px", height: h + "px" });
  const transparent = o.BackgroundTransparency === 1 || (o.class === "ScrollingFrame" && o.BackgroundTransparency === undefined);
  if (!transparent) {
    el.style.background = rgb(o.BackgroundColor3) || "rgb(163,162,165)";
    if (o.BackgroundTransparency) el.style.background = el.style.background.replace("rgb", "rgba").replace(")", "," + (1 - o.BackgroundTransparency) + ")");
  }
  const corner = kid(o, "UICorner");
  if (corner) { const r = corner.CornerRadius || { s: 0, o: 8 }; el.style.borderRadius = (r.s * Math.min(w, h) + r.o) + "px"; }
  const isText = o.class === "TextLabel" || o.class === "TextButton" || o.class === "TextBox";
  if (kid(o, "UIStroke") && !isText) el.style.border = "3px solid rgb(20,10,30)";
  if (o.Name) el.dataset.name = o.Name;
  parentEl.appendChild(el);
  if (isText) {
    let txt = o.Text || "";
    let color = rgb(o.TextColor3) || "#fff";
    if (!txt && o.PlaceholderText) { txt = o.PlaceholderText; color = "rgba(40,25,50,.5)"; }
    const t = document.createElement("div");
    t.className = "t";
    const span = document.createElement("span");
    span.textContent = txt;
    t.appendChild(span);
    const al = o.TextXAlignment || "";
    t.style.justifyContent = al.endsWith("Left") ? "flex-start" : al.endsWith("Right") ? "flex-end" : "center";
    t.style.width = "100%"; t.style.height = "100%"; t.style.color = color;
    if (kid(o, "UIStroke")) t.style.textShadow = "-1.5px -1.5px 0 #140a1e,1.5px -1.5px 0 #140a1e,-1.5px 1.5px 0 #140a1e,1.5px 1.5px 0 #140a1e";
    el.appendChild(t);
    const max = (kid(o, "UITextSizeConstraint") || {}).MaxTextSize || 100;
    let fs = Math.min(h * 0.82, max);
    t.style.fontSize = fs + "px";
    while (fs > 6 && span.offsetWidth > w - 6) { fs -= 0.5; t.style.fontSize = fs + "px"; }
  }
  // children
  const list = kid(o, "UIListLayout"), grid = kid(o, "UIGridLayout");
  const kids = o.children.filter((c) => GUI.includes(c.class) && c.Visible !== false);
  if (list || grid) {
    const order = kids.map((c, i) => [c, i]).sort((a, b) => (a[0].LayoutOrder || 0) - (b[0].LayoutOrder || 0) || a[1] - b[1]).map((a) => a[0]);
    if (grid) {
      const cs = grid.CellSize, cp = grid.CellPadding;
      let cx = 0, cy = 0;
      for (const c of order) {
        if (cx + cs[1] > w) { cx = 0; cy += cs[3] + cp[3]; }
        draw({ ...c, Size: [0, cs[1], 0, cs[3]] }, el, w, h, [cx, cy]);
        cx += cs[1] + cp[1];
      }
    } else {
      const pad = list.Padding ? list.Padding.o + list.Padding.s * h : 0;
      const horiz = (list.FillDirection || "").endsWith("Horizontal");
      let at = 0;
      for (const c of order) {
        const cs = c.Size || [0, 0, 0, 0];
        const e = draw(c, el, w, h, horiz ? [at, 0] : [0, at]);
        if (!e) continue;
        at += (horiz ? parseFloat(e.style.width) : parseFloat(e.style.height)) + pad;
      }
    }
  } else for (const c of kids) draw(c, el, w, h);
  return el;
}
function render(i) {
  const screen = document.getElementById("screen");
  screen.innerHTML = "";
  const shot = DATA.shots[i];
  if (shot.name === "_hud") {
    // a phone screen (844x390): the UI root is 1342x620 scaled down by 0.629
    const root = draw({ ...shot.tree, Size: [0, 1342, 0, 620] }, screen, 1342, 620);
    root.style.transform = "scale(" + 390 / 620 + ")"; root.style.transformOrigin = "0 0";
    screen.style.width = "844px"; screen.style.height = "390px";
    return;
  }
  screen.style.width = "1280px"; screen.style.height = "720px";
  const bar = draw(DATA.bar, screen, 1280, 720);
  for (const b of bar.querySelectorAll(".t")) if (b.textContent.endsWith(" " + shot.bar)) b.parentElement.classList.add("hl");
  draw(shot.tree, screen, 1280, 720);
}
</script></body></html>`;

(async () => {
  const browser = await chromium.launch();
  const tab = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 2 });
  await tab.setContent(page, { waitUntil: "networkidle" }).catch(() => {});
  await tab.evaluate(() => document.fonts.ready);
  for (let i = 0; i < data.shots.length; i++) {
    const s = data.shots[i];
    await tab.evaluate(([i, bar]) => { DATA.shots[i].bar = bar; render(i); }, [i, BAR_NAME[s.name]]);
    const file = path.join(out, `${String(i + 1).padStart(2, "0")}-${s.name === "_hud" ? "Phone-HUD" : s.name}${s.tab ? "-" + s.tab : ""}.png`);
    await tab.screenshot({ path: file, clip: s.name === "_hud" ? { x: 0, y: 0, width: 844, height: 390 } : undefined });
    console.log(file);
  }
  await browser.close();
})();
