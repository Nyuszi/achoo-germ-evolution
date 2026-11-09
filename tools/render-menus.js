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
  ["Lab", "Mutations"], ["Lab", "Fusions"], ["Lab", "Runs"], ["Editor", "Body"], ["Editor", "Eyes"], ["Editor", "Hat"], ["Editor", "Flag"], ["Shop"], ["Quests", "Daily"],
  ["Quests", "Cards"], ["Arena"], ["Leaders", "Speedrun"], ["Feedback"], ["Dev"], ["_hud"],
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
${require("./gui-draw")}
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
  bar.style.overflow = "visible"; // the game doesn't clip the bar; only this drawing did
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
