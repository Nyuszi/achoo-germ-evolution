// Lays out a dumped Roblox GUI tree (from tools/menu-dump.lua) as HTML, like Roblox would:
// UDim2 sizes/positions, AnchorPoint, Rotation, ZIndex (sibling order), UIListLayout, UIGridLayout,
// UICorner, UIStroke, UIGradient (colour and transparency keypoints), TextScaled.
// Exports browser JS defining draw(o, parentEl, parentW, parentH, pos).
module.exports = String.raw`
const rgb = (c) => c ? "rgb(" + c.map((x) => Math.round(x * 255)).join(",") + ")" : null;
const kid = (o, cls) => o.children.find((c) => c.class === cls);
// a sequence ({ seq, kp: [[t, ...value]] }) at time t
function seqAt(q, t) {
  const kp = q.kp;
  if (t <= kp[0][0]) return kp[0].slice(1);
  for (let i = 1; i < kp.length; i++) if (t <= kp[i][0]) {
    const a = kp[i - 1], b = kp[i], k = (t - a[0]) / Math.max(1e-9, b[0] - a[0]);
    return a.slice(1).map((v, j) => v + (b[j + 1] - v) * k);
  }
  return kp[kp.length - 1].slice(1);
}
// CSS background for a UIGradient on a frame of colour c (0..1) and transparency bt
function gradient(g, c, bt) {
  const times = new Set([0, 1]);
  if (g.Color && g.Color.kp) g.Color.kp.forEach((k) => times.add(k[0]));
  if (g.Transparency && g.Transparency.kp) g.Transparency.kp.forEach((k) => times.add(k[0]));
  const stops = [...times].sort((a, b) => a - b).map((t) => {
    const m = g.Color && g.Color.kp ? seqAt(g.Color, t) : [1, 1, 1];
    const tr = g.Transparency && g.Transparency.kp ? seqAt(g.Transparency, t)[0] : 0;
    const a = (1 - bt) * (1 - tr);
    return "rgba(" + c.map((x, i) => Math.round(x * m[i] * 255)).join(",") + "," + a.toFixed(3) + ") " + (t * 100).toFixed(2) + "%";
  });
  return "linear-gradient(" + (90 + (g.Rotation || 0)) + "deg," + stops.join(",") + ")";
}
const GUI = ["Frame", "CanvasGroup", "TextLabel", "TextButton", "TextBox", "ScrollingFrame", "ImageLabel", "ImageButton"];
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
  const grad = kid(o, "UIGradient");
  if (!transparent && grad) el.style.background = gradient(grad, o.BackgroundColor3 || [0.64, 0.64, 0.65], o.BackgroundTransparency || 0);
  else if (!transparent) {
    el.style.background = rgb(o.BackgroundColor3) || "rgb(163,162,165)";
    if (o.BackgroundTransparency) el.style.background = el.style.background.replace("rgb", "rgba").replace(")", "," + (1 - o.BackgroundTransparency) + ")");
  }
  // like Roblox, only scrolling frames, canvas groups and ClipsDescendants clip their children
  el.style.overflow = o.class === "ScrollingFrame" || o.class === "CanvasGroup" || o.ClipsDescendants ? "hidden" : "visible";
  if (o.Rotation) el.style.transform = "rotate(" + o.Rotation + "deg)";
  el.style.zIndex = o.ZIndex == null ? 1 : o.ZIndex;
  const corner = kid(o, "UICorner");
  if (corner) { const r = corner.CornerRadius || { s: 0, o: 8 }; el.style.borderRadius = (r.s * Math.min(w, h) + r.o) + "px"; }
  const isText = o.class === "TextLabel" || o.class === "TextButton" || o.class === "TextBox";
  const stroke = kid(o, "UIStroke");
  if (stroke && !isText) {
    // Roblox draws a frame's stroke outside its edge
    const sc = stroke.Color && !stroke.Color.seq ? stroke.Color : [0, 0, 0];
    el.style.boxShadow = "0 0 0 " + (stroke.Thickness || 1) + "px rgba(" + sc.map((x) => Math.round(x * 255)).join(",") + "," + (1 - (stroke.Transparency || 0)) + ")";
  }
  if (o.Name) el.dataset.name = o.Name;
  parentEl.appendChild(el);
  if (isText) {
    let txt = o.Text || "";
    let color = rgb(o.TextColor3) || "#fff";
    if (o.TextTransparency) color = color.replace("rgb", "rgba").replace(")", "," + (1 - o.TextTransparency) + ")");
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
`;
