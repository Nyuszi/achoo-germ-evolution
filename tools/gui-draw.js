// Lays out a dumped Roblox GUI tree (from tools/menu-dump.lua) as HTML, like Roblox would:
// UDim2 sizes/positions, AnchorPoint, UIListLayout, UIGridLayout, UICorner, UIStroke, TextScaled.
// Exports browser JS defining draw(o, parentEl, parentW, parentH, pos).
module.exports = String.raw`
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
`;
