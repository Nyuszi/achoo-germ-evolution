-- Appended to the client smoke run when MENU_DUMP is set: opens each menu tab and records
-- the GUI tree as JSON (in the global MENU_JSON) so tools/render-menus.js can draw it.
local BS = string.char(92)
local function esc(s)
  s = string.gsub(s, BS, BS .. BS)
  s = string.gsub(s, '"', BS .. '"')
  s = string.gsub(s, "\n", BS .. "n")
  return '"' .. s .. '"'
end
local KEYS = { "Name", "Size", "Position", "AnchorPoint", "Text", "PlaceholderText", "BackgroundColor3", "BackgroundTransparency", "TextColor3",
  "Visible", "LayoutOrder", "TextXAlignment", "FillDirection", "Padding", "CornerRadius", "MaxSize", "MaxTextSize", "CellSize", "CellPadding", "TextWrapped", "TextScaled" }
local function val(v)
  local t = type(v)
  if t == "string" then return esc(v) end
  if t == "number" then return tostring(v) end
  if t == "boolean" then return tostring(v) end
  if t == "table" then
    if v.R then return "[" .. v.R .. "," .. v.G .. "," .. v.B .. "]" end
    if v.Scale then return "{\"s\":" .. v.Scale .. ",\"o\":" .. v.Offset .. "}" end
    if v.X and type(v.X) == "number" then return "{\"x\":" .. v.X .. ",\"y\":" .. v.Y .. "}" end
    local parts = {}
    for i, x in ipairs(v) do parts[i] = tostring(x) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  return "null"
end
local function dump(o)
  local out = { '"class":' .. esc(o.__class) }
  for _, k in ipairs(KEYS) do
    local v = rawget(o, k)
    if v ~= nil then table.insert(out, esc(k) .. ":" .. val(v)) end
  end
  local kids = {}
  for _, c in ipairs(o.__children) do table.insert(kids, dump(c)) end
  table.insert(out, '"children":[' .. table.concat(kids, ",") .. "]")
  return "{" .. table.concat(out, ",") .. "}"
end
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
