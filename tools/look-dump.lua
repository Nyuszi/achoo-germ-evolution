-- Appended to the client smoke run when LOOK_DUMP is set: builds each look (see Looks.build) on a
-- fresh disc Frame and records the trees as JSON (in the global MENU_JSON) for the picture tools.
local Gear = require("Gear")
local trees = {}
for i, l in ipairs(LOOK_SHOTS) do
  local root = Instance.new("Frame")
  root.Size = UDim2.fromScale(1, 1)
  root.BackgroundTransparency = 1
  local c = l.color or { 120, 220, 120 }
  local h = Looks.build(root, { skin = l.skin or {}, color = Color3.fromRGB(c[1], c[2], c[3]), flag = l.flag })
  if l.aim then Looks.aim(h, l.aim[1], l.aim[2], 0) end
  if l.blink then Looks.blink(h, true) end
  local gear = Gear.build(root, l.muts or {}, Color3.fromRGB(c[1], c[2], c[3]), l.core)
  if gear then
    local st = l.gear or {}
    Gear.animate(gear, 0.05, st.t or 0.3, { dx = st.dx or 0, dz = st.dz or -1, fight = st.fight, dash = st.dash, power = st.power, powerAge = st.powerAge })
  end
  trees[i] = dump(root)
end
MENU_JSON = "[" .. table.concat(trees, ",") .. "]"
