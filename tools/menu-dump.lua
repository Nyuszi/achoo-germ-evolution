-- Appended to the client smoke run when MENU_DUMP is set: opens each menu tab and records
-- the GUI tree as JSON (in the global MENU_JSON) so tools/render-menus.js can draw it.
local function findTabButton(frame, text)
  for _, c in ipairs(frame.__children) do
    if c.__class == "TextButton" and c.Text == text then return c end
    local r = findTabButton(c, text)
    if r then return r end
  end
end
local shots = {}
local function shot(name, tab)
  Ui.close()
  if name == "_hud" then
    for _, c in ipairs(Ui.gui.__children) do
      if (rawget(c, "ZIndex") or 0) >= 20 then c.Visible = false end -- full-screen overlays (sneeze, death)
    end
    table.insert(shots, "{\"name\":\"_hud\",\"tab\":\"\",\"tree\":" .. dump(Ui.gui) .. "}")
    return
  end
  Ui.open(name)
  local p = Ui.panels[name]
  if tab then
    local b = findTabButton(p.frame, tab)
    if b then b.Activated:Fire() end
  end
  table.insert(shots, "{\"name\":" .. esc(name) .. ",\"tab\":" .. esc(tab or "") .. ",\"tree\":" .. dump(p.frame) .. "}")
end
for _, s in ipairs(MENU_SHOTS) do shot(s[1], s[2]) end
Ui.close()
-- the left menu bar
local bar
for _, c in ipairs(Ui.gui.__children) do
  for _, k in ipairs(c.__children) do
    if k.__class == "UISizeConstraint" and k.MaxSize and k.MaxSize.X == 112 then bar = c end
  end
end
MENU_JSON = "{\"bar\":" .. (bar and dump(bar) or "null") .. ",\"shots\":[" .. table.concat(shots, ",") .. "]}"
