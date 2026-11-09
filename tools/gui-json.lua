-- Turns a fake GUI tree (from tools/client-smoke.js) into JSON for tools/gui-draw.js.
local BS = string.char(92)
local function esc(s)
  s = string.gsub(s, BS, BS .. BS)
  s = string.gsub(s, '"', BS .. '"')
  s = string.gsub(s, "\n", BS .. "n")
  return '"' .. s .. '"'
end
local KEYS = { "Name", "Size", "Position", "AnchorPoint", "Text", "PlaceholderText", "BackgroundColor3", "BackgroundTransparency", "TextColor3",
  "Visible", "LayoutOrder", "TextXAlignment", "FillDirection", "Padding", "CornerRadius", "MaxSize", "MaxTextSize", "CellSize", "CellPadding", "TextWrapped", "TextScaled",
  "Rotation", "ZIndex", "ClipsDescendants", "Color", "Transparency", "Thickness", "TextTransparency" }
local function val(v)
  local t = type(v)
  if t == "string" then return esc(v) end
  if t == "number" then return tostring(v) end
  if t == "boolean" then return tostring(v) end
  if t == "table" then
    if v.__seq then
      local kp = {}
      for i, k in ipairs(v.Keypoints) do
        local x = k.Value
        kp[i] = "[" .. k.Time .. "," .. (type(x) == "table" and (x.R .. "," .. x.G .. "," .. x.B) or tostring(x)) .. "]"
      end
      return "{\"seq\":\"" .. v.__seq .. "\",\"kp\":[" .. table.concat(kp, ",") .. "]}"
    end
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
