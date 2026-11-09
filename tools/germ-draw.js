// Draws a germ's 3D body from above in a <canvas>, using the same parts, sizes and offsets as
// src/client/Renderer.luau (buildVisual). Shared by the picture tools. Roblox materials
// (Glass, Neon, Lava...) are only imitated with simple paint. The face, pattern and hat are the
// real 2D art from src/client/Looks.luau (see tools/look-trees.js), laid on top with lookOverlay.
// Exports a string of browser JS defining drawGerm(g, x, y, r, look, t) and
// lookOverlay(parentEl, x, y, r, tree) (needs tools/gui-draw.js on the page too).
module.exports = String.raw`
const WHITE = [255,255,255], BLACK = [25,25,35];
const lerp = (a, b, k) => a.map((v, i) => v + (b[i] - v) * k);
const css = (c, a) => "rgba(" + c.map(Math.round).join(",") + "," + (a == null ? 1 : a) + ")";
const TRAILS = { Bubbles: [[180,230,255],[255,255,255]], Sparkles: [[255,240,150],[255,255,255]], SlimeTrail: [[120,230,90],[60,160,40]],
  Hearts: [[255,120,170],[255,200,220]], Fire: [[255,200,40],[255,60,20]], ArenaFlame: [[120,255,220],[40,120,255]], ArenaLightning: [[255,255,120],[160,120,255]] };
const BODY = { Jelly: ["SmoothPlastic", 0.12], Fuzzy: ["Fabric", 0], Slime: ["Glass", 0.25], Crystal: ["Glass", 0.35], Lava: ["CrackedLava", 0],
  Galaxy: ["Neon", 0.1], Candy: ["Plastic", 0], Robot: ["DiamondPlate", 0], Champion: ["Foil", 0] };
// 3D extras on the body: none any more, mutations are 2D art (src/client/Gear.luau) in the look overlay
function parts() {
  return [];
}
function paintBody(g, x, y, r, look) {
  const skin = look.skin || {}, color = look.color;
  const [mat, tr] = BODY[skin.Body || "Jelly"] || BODY.Jelly;
  g.save(); g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.closePath();
  if (look.flag) {
    g.fillStyle = css(color); g.fill(); g.clip();
    g.font = Math.round(r * 2.6) + "px 'Noto Color Emoji', sans-serif"; g.textAlign = "center"; g.textBaseline = "middle";
    g.fillText(look.flag, x, y + r * 0.08);
  } else {
    const grad = g.createRadialGradient(x - r * 0.35, y - r * 0.35, r * 0.1, x, y, r);
    let base = color;
    if (mat === "Neon") { grad.addColorStop(0, css(lerp(color, WHITE, 0.5))); grad.addColorStop(1, css(lerp(color, [90,40,160], 0.5))); }
    else if (mat === "Foil") { grad.addColorStop(0, css([255,245,180])); grad.addColorStop(0.5, css([230,180,60])); grad.addColorStop(1, css([150,100,30])); }
    else { grad.addColorStop(0, css(lerp(base, WHITE, mat === "Glass" ? 0.55 : 0.3), 1 - tr)); grad.addColorStop(1, css(lerp(base, BLACK, mat === "Fabric" ? 0.25 : 0.15), 1 - tr * 0.6)); }
    g.fillStyle = grad; g.fill(); g.clip();
    // material texture
    let seed = 7; const rnd = () => (seed = (seed * 9301 + 49297) % 233280) / 233280;
    if (mat === "Fabric") { for (let i = 0; i < 260; i++) { g.fillStyle = css(lerp(color, i % 2 ? WHITE : BLACK, 0.25), 0.35); g.fillRect(x - r + rnd() * 2 * r, y - r + rnd() * 2 * r, r * 0.04, r * 0.04); } }
    if (mat === "CrackedLava") { g.strokeStyle = css([255,120,30]); g.lineWidth = r * 0.05; for (let i = 0; i < 9; i++) { g.beginPath(); let px = x - r + rnd() * 2 * r, py = y - r + rnd() * 2 * r; g.moveTo(px, py); for (let k = 0; k < 4; k++) { px += (rnd() - 0.5) * r * 0.6; py += (rnd() - 0.5) * r * 0.6; g.lineTo(px, py); } g.stroke(); } }
    if (mat === "Neon") { for (let i = 0; i < 40; i++) { g.fillStyle = "rgba(255,255,255," + (0.4 + rnd() * 0.6) + ")"; const s = r * (0.015 + rnd() * 0.03); g.fillRect(x - r + rnd() * 2 * r, y - r + rnd() * 2 * r, s, s); } }
    if (mat === "DiamondPlate") { g.strokeStyle = "rgba(255,255,255,0.35)"; g.lineWidth = r * 0.03; for (let i = -6; i <= 6; i++) for (let k = -6; k <= 6; k++) { const px = x + i * r * 0.18, py = y + k * r * 0.18 + (i % 2) * r * 0.09; g.beginPath(); g.moveTo(px - r * 0.04, py - r * 0.04); g.lineTo(px + r * 0.04, py + r * 0.04); g.stroke(); } }
    if (skin.Body === "Crystal") { g.strokeStyle = "rgba(255,255,255,0.6)"; g.lineWidth = r * 0.03; for (let i = 0; i < 6; i++) { const a = i / 6 * Math.PI * 2; g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r); g.stroke(); } }
    if (skin.Body === "Candy") { g.strokeStyle = "rgba(255,255,255,0.55)"; g.lineWidth = r * 0.14; for (let i = -4; i <= 4; i++) { g.beginPath(); g.moveTo(x + i * r * 0.45 - r, y - r); g.lineTo(x + i * r * 0.45 + r, y + r); g.stroke(); } }
  }
  g.restore();
  g.lineWidth = Math.max(1.5, r * 0.04); g.strokeStyle = css(lerp(color, BLACK, 0.45), 0.8); g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.stroke();
  if (!look.flag) { g.fillStyle = css(lerp(color, BLACK, 0.35), 0.35); g.beginPath(); g.arc(x, y + r * 0.2, r * 0.4, 0, Math.PI * 2); g.fill(); }
}
// (x, y) = centre on the canvas, r = radius in px, facing up the screen
function drawGerm(g, x, y, r, look, t) {
  t = t || 0;
  const skin = look.skin || {};
  const trail = TRAILS[skin.Trail];
  if (trail) {
    const len = r * 3.2, grad = g.createLinearGradient(x, y + r * 0.2, x, y + r + len);
    grad.addColorStop(0, css(trail[0], 0.8)); grad.addColorStop(1, css(trail[1], 0));
    g.fillStyle = grad; g.beginPath(); g.moveTo(x - r * 0.8, y); g.lineTo(x + r * 0.8, y); g.lineTo(x + r * 0.15, y + r + len); g.lineTo(x - r * 0.15, y + r + len); g.closePath(); g.fill();
    const icon = { Bubbles: "○", Sparkles: "✦", Hearts: "♥", Fire: "▲", SlimeTrail: "●", ArenaFlame: "▲", ArenaLightning: "ϟ" }[skin.Trail];
    g.fillStyle = css(trail[0]); g.textAlign = "center"; g.textBaseline = "middle";
    for (let i = 0; i < 6; i++) { g.font = Math.round(r * (0.45 - i * 0.05)) + "px sans-serif"; g.fillText(icon, x + Math.sin(i * 2.1) * r * 0.45, y + r * 1.3 + i * r * 0.45); }
  }
  const P = parts(look);
  const lift = look.flag ? 0.8 : 0;
  // lower parts first (things under the body: tail, jaws, spikes...)
  const under = P.filter(p => p.up < 0.2 && !(p.up > 0)).filter(p => Math.hypot(p.fwd, p.right) > 0.7);
  const over = P.filter(p => !under.includes(p)).sort((a, b) => a.up - b.up);
  const at = (p) => [x + p.right * r, y - p.fwd * r];
  const drawPart = (p) => {
    const [px, py] = at(p);
    const c = p.c, a = p.alpha || 1;
    g.save(); g.translate(px, py);
    if (p.neon) { g.shadowColor = css(c); g.shadowBlur = r * 0.25; }
    g.fillStyle = css(c, a); g.strokeStyle = css(lerp(c, BLACK, 0.5), 0.7); g.lineWidth = Math.max(1, r * 0.025);
    const sx = p.size[0] * r, sz = p.size[2] * r, sy = p.size[1] * r;
    if (p.shape === "ball") { g.beginPath(); g.arc(0, 0, sx / 2, 0, Math.PI * 2); g.fill(); g.stroke();
      if (c === WHITE || (c[0] > 240 && c[1] > 240)) { g.fillStyle = "rgba(255,255,255,0.9)"; } }
    else if (p.shape === "block") { g.rotate(p.rot ? Math.PI / 2 - p.rot : (p.tilt || 0)); if (p.wavy) { g.lineWidth = sx; g.strokeStyle = css(c); g.lineCap = "round"; g.beginPath(); for (let k = 0; k <= 10; k++) { const yy = -sz / 2 + sz * k / 10; const xx = Math.sin(k * 0.9 + t * 12) * r * 0.12; k ? g.lineTo(xx, yy) : g.moveTo(xx, yy); } g.stroke(); }
      else { g.beginPath(); g.roundRect(-sx / 2, -sz / 2, sx, sz, Math.min(sx, sz) * 0.25); g.fill(); g.stroke(); } }
    else if (p.shape === "disc") { g.beginPath(); g.ellipse(0, 0, sy / 2, sx / 2 + sy * 0.15, 0, 0, Math.PI * 2); g.fill(); g.stroke(); g.fillStyle = css(lerp(c, BLACK, 0.4)); g.beginPath(); g.arc(0, 0, sy * 0.2, 0, Math.PI * 2); g.fill(); }
    else if (p.shape === "tri") { g.beginPath(); g.moveTo(0, -sz / 2 - r * 0.15); g.lineTo(sx / 2, sz / 2); g.lineTo(-sx / 2, sz / 2); g.closePath(); g.fill(); g.stroke(); }
    else if (p.shape === "crown") { g.beginPath(); const n = 5, R = sy / 2; for (let i = 0; i < n * 2; i++) { const ang = i / (n * 2) * Math.PI * 2 - Math.PI / 2, rr = i % 2 ? R * 0.6 : R; g.lineTo(Math.cos(ang) * rr, Math.sin(ang) * rr); } g.closePath(); g.fill(); g.stroke(); }
    else if (p.shape === "cone") { const R = sx / 2 * (p.big || 1); g.beginPath(); g.arc(0, 0, R * 1.3, 0, Math.PI * 2); g.fill(); g.stroke(); g.fillStyle = css(lerp(c, WHITE, 0.4)); g.beginPath(); g.arc(0, 0, R * 0.45, 0, Math.PI * 2); g.fill(); }
    else if (p.shape === "ring") { g.lineWidth = Math.max(2, sx * (p.leaves ? 1.6 : 1.2)); g.strokeStyle = css(c, 0.9); g.beginPath(); g.arc(0, 0, sy / 2, 0, Math.PI * 2); g.stroke();
      if (p.leaves) { g.fillStyle = css(lerp(c, BLACK, 0.2)); for (let i = 0; i < 14; i++) { const ang = i / 14 * Math.PI * 2; g.beginPath(); g.ellipse(Math.cos(ang) * sy / 2, Math.sin(ang) * sy / 2, r * 0.09, r * 0.04, ang + 0.8, 0, Math.PI * 2); g.fill(); } } }
    g.restore();
  };
  under.forEach(drawPart);
  paintBody(g, x, y, r, look);
  over.forEach(drawPart);
}
function lookOverlay(parentEl, x, y, r, tree) {
  if (!document.getElementById("look-css")) {
    const st = document.createElement("style"); st.id = "look-css";
    st.textContent = ".look{position:absolute}.look .n{position:absolute;box-sizing:border-box;overflow:visible!important}.look .t{display:flex;align-items:center;white-space:nowrap;font-family:Fredoka,sans-serif}";
    document.head.appendChild(st);
  }
  const d = document.createElement("div"); d.className = "look";
  Object.assign(d.style, { left: (x - r) + "px", top: (y - r) + "px", width: 2 * r + "px", height: 2 * r + "px" });
  parentEl.appendChild(d);
  draw(tree, d, 2 * r, 2 * r);
  return d;
}
`;
