// Runs the client modules (Ui, Renderer, Fx, Hud, Menus) outside Roblox with fake Roblox objects,
// feeding them a dish, germs, snapshots, effects and a profile, and opening every menu tab.
// It catches runtime mistakes (nil fields, wrong calls) that a syntax check can't.
//   node tools/client-smoke.js
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const src = path.join(__dirname, "..", "src");
const read = (p) => fs.readFileSync(path.join(src, p), "utf8");
function toLua(code) {
	code = code.replace(/^(\s*)([\w.\[\]"':]+)\s*(\+|-|\*|\/|\.\.)=\s*(.+?)(\s*--.*)?$/gm, (_, ws, lhs, op, rhs) => `${ws}${lhs} = ${lhs} ${op} (${rhs})`);
	code = code.replace(/^(\s*)continue\b/gm, "$1goto continue");
	code = code.replace(/^(\s*for\b[^\n]*?\bin\s+)(?!pairs\(|ipairs\(|next\b|string\.gmatch)([^\n]+?)\s+do\b/gm, "$1__iter($2) do");
	return code;
}
const prelude = `
local modules, loaded = {}, {}
-- Luau iterates arrays in order; fengari's pairs may not, so loops go through this
function __iter(t)
  local keys, n = {}, #t
  for i = 1, n do keys[i] = i end
  for k in pairs(t) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end end
  local i = 0
  return function() i = i + 1 local k = keys[i] if k ~= nil then return k, t[k] end end
end
function __define(name, fn) modules[name] = fn end
function require(m)
  if type(m) == "table" then m = m.__name end
  if loaded[m] == nil then
    if not modules[m] then error("no module " .. tostring(m)) end
    loaded[m] = modules[m]()
  end
  return loaded[m]
end
script = { Parent = setmetatable({}, { __index = function(_, k) return { __name = k } end }) }
local function noop() end
math.clamp = function(x, a, b) if x < a then return a elseif x > b then return b end return x end
table.clone = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
table.find = function(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
utf8 = utf8
-- values
local V3 = {}
V3.__index = V3
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end
V3.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b) if type(a) == "number" then a, b = b, a end if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end
Vector3 = { new = v3, one = v3(1, 1, 1), zero = v3(0, 0, 0) }
math.atan2 = math.atan2 or math.atan
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
local CF = {}
CF.__index = CF
CF.__mul = function(a, b) return setmetatable({}, CF) end
function CF:PointToObjectSpace(p) return p end
CFrame = { new = function() return setmetatable({}, CF) end, lookAt = function() return setmetatable({}, CF) end, Angles = function() return setmetatable({}, CF) end }
local C3 = {}
C3.__index = C3
function C3.Lerp(a, b, t) return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, C3) end
local function c3(r, g, b) return setmetatable({ R = r, G = g, B = b }, C3) end
Color3 = { new = c3, fromRGB = function(r, g, b) return c3(r / 255, g / 255, b / 255) end }
UDim = { new = function(a, b) return { Scale = a, Offset = b } end }
UDim2 = { new = function(a, b, c, d) return { a or 0, b or 0, c or 0, d or 0 } end, fromScale = function(a, b) return { a, 0, b, 0 } end, fromOffset = function(a, b) return { 0, a, 0, b } end }
-- sequences keep their keypoints (the picture tools draw UIGradients from them)
ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
ColorSequence = { new = function(a, b)
  if type(a) == "table" and a[1] then return { __seq = "color", Keypoints = a } end
  return { __seq = "color", Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b or a } } }
end }
NumberSequence = { new = function(a, b)
  if type(a) == "table" then return { __seq = "number", Keypoints = a } end
  return { __seq = "number", Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = b or a } } }
end }
TweenInfo = { new = function() return {} end }
function typeof(v) if getmetatable(v) == C3 then return "Color3" end return type(v) end
Enum = setmetatable({}, { __index = function(t, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
-- instances
local Signal = {}
Signal.__index = Signal
function Signal:Connect(f) table.insert(self.fns, f) return { Disconnect = noop } end
function Signal:Fire(...) for _, f in ipairs(self.fns) do f(...) end end
local function signal() return setmetatable({ fns = {} }, Signal) end
local EVENTS = { Activated = 1, FocusLost = 1, OnClientEvent = 1, Event = 1 }
local Inst = {}
function Inst.new(class)
  local o = { __class = class, __children = {}, __attrs = {} }
  return setmetatable(o, Inst)
end
Inst.__index = function(self, k)
  local m = rawget(Inst, k)
  if m then return m end
  if EVENTS[k] then local s = signal() rawset(self, k, s) return s end
  if k == "AbsolutePosition" then return { X = 0, Y = 0 } end
  if k == "AbsoluteSize" then return { X = 170, Y = 170 } end
  return nil
end
Inst.__newindex = function(self, k, v)
  if k == "Parent" then
    local old = rawget(self, "__parent")
    if old then for i, c in ipairs(old.__children) do if c == self then table.remove(old.__children, i) break end end end
    rawset(self, "__parent", v)
    if v and type(v) == "table" and rawget(v, "__children") then table.insert(v.__children, self) end
    return
  end
  rawset(self, k, v)
end
function Inst:GetChildren() return table.clone(self.__children) end
function Inst:IsA(c) return self.__class == c or (c == "GuiObject" and self.__class ~= "UIListLayout" and self.__class ~= "UICorner" and self.__class ~= "UIStroke") or (c == "GuiButton" and self.__class == "TextButton") end
function Inst:Destroy() self.Parent = nil end
function Inst:FindFirstChildOfClass(c) for _, x in ipairs(self.__children) do if x.__class == c then return x end end return nil end
function Inst:FindFirstChildWhichIsA(c) return self:FindFirstChildOfClass(c) end
function Inst:FindFirstChild(n) for _, x in ipairs(self.__children) do if x.Name == n then return x end end return nil end
function Inst:WaitForChild(n) return self:FindFirstChild(n) or Inst.new("Folder") end
function Inst:SetAttribute(k, v) self.__attrs[k] = v end
function Inst:GetAttribute(k) return self.__attrs[k] end
function Inst:IsDescendantOf() return true end
function Inst:GetGuiObjectsAtPosition() return {} end
function Inst:Play() end
Instance = { new = Inst.new }
-- remotes
CALLS = {}
local Remotes = Inst.new("Folder")
local remoteMt = { __index = function(t, k)
  local r = { OnClientEvent = signal(), FireServer = noop, InvokeServer = function(self, ...) local a = {} for i, v in ipairs({ ... }) do a[i] = tostring(v) end table.insert(CALLS, k .. " " .. table.concat(a, " ")) if k == "Leaders" then return { { name = "SneezeQueen", value = 412 }, { name = "Laszlo", value = 377 }, { name = "GermLord99", value = 250 }, { name = "Bubbles", value = 198 }, { name = "TinyTerror", value = 120 } } end return true, "ok" end }
  rawset(t, k, r)
  return r
end }
REMOTES = setmetatable({}, remoteMt)
Remotes.WaitForChild = nil
local player = Inst.new("Player")
player.PlayerGui = Inst.new("PlayerGui")
player.WaitForChild = function(self, n) return self.PlayerGui end
player.UserId = 1
local services = {
  Players = { LocalPlayer = player },
  ReplicatedStorage = { Shared = { Config = { __name = "Config" }, Formulas = { __name = "Formulas" }, Flags = { __name = "Flags" }, Names = { __name = "Names" } }, WaitForChild = function() return REMOTES end },
  TweenService = { Create = function() return { Play = noop } end },
  UserInputService = { TouchEnabled = MENU_TOUCH == true, KeyboardEnabled = MENU_TOUCH ~= true, GetFocusedTextBox = function() return nil end },
  SocialService = {},
  Lighting = Inst.new("Lighting"),
}
game = { GetService = function(_, n) return services[n] or Inst.new(n) end }
workspace = Inst.new("Workspace")
workspace.CurrentCamera = Inst.new("Camera")
workspace.CurrentCamera.ViewportSize = { X = 800, Y = 400 }
workspace.CurrentCamera.GetPropertyChangedSignal = function() return signal() end
workspace.BulkMoveTo = function(_, parts, cfs) assert(#parts == #cfs, "bulk mismatch") BULK = #parts end
task = { spawn = function(f, ...) f(...) end, delay = noop, wait = noop }
-- buffer
buffer = {}
function buffer.create(n) return { n = n, v = {} } end
function buffer.len(b) return b.n end
function buffer.writeu32(b, o, x) b.v[o] = x end
function buffer.writef32(b, o, x) b.v[o] = x end
function buffer.writeu8(b, o, x) b.v[o] = x end
buffer.readu32 = function(b, o) return b.v[o] end
buffer.readf32 = buffer.readu32
buffer.readu8 = buffer.readu32
bit32 = { band = function(a, b) local r, bitv = 0, 1 while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + bitv end a, b, bitv = a // 2, b // 2, bitv * 2 end return r end }
os.clock = os.clock or function() return 0 end
`;
const wrap = (name, code) => `__define(${JSON.stringify(name)}, function()\n${toLua(code)}\nend)\n`;
const run = `
local Config = require("Config")
local Ui = require("Ui")
local Renderer = require("Renderer")
local Fx = require("Fx")
local Hud = require("Hud")
local Menus = require("Menus")
local Looks = require("Looks")
if LOOK_SHOTS then
  __LOOK_DUMP__
  return
end
-- every look item in the shop has art
for cat, tbl in pairs({ Pattern = Looks.patterns, Eyes = Looks.eyes, Mouth = Looks.mouths, Hat = Looks.hats }) do
  for _, item in ipairs(Config.Skins[cat]) do
    assert(item.Id == "None" or tbl[item.Id], "no look art for " .. cat .. " " .. item.Id)
  end
end
for _, e in ipairs({ "Cute", "Googly", "Sleepy", "Heart" }) do
  local root = Instance.new("Frame")
  local h = Looks.build(root, { skin = { Eyes = e, Hat = "Propeller", Pattern = "Leopard", Mouth = "Kitty", Color2 = { 1, 2, 3 } }, color = Color3.new(0.5, 0.5, 0.5) })
  Looks.aim(h, 1, 0, 2) Looks.blink(h, true) Looks.blink(h, false)
  assert(h.spin, "propeller spin frame")
end
print("looks ok")
-- flag pictures from the (uploaded) flag sheets; reset after the renderer tests so the picture
-- tools keep drawing emoji
local FlagsMod = require("Flags")
for i in ipairs(FlagsMod.SheetIds) do FlagsMod.SheetIds[i] = "rbxassetid://" .. i end
assert(FlagsMod.picture("HU") and FlagsMod.picture("ZW") and not FlagsMod.picture("XX"), "flag pictures")
local info = { id = 7, kind = "host", host = 2, scale = 10, radius = 500, wall = 500, sneeze = 25000, cx = 2400, cz = 0, name = "Big Barkley", hazard = "x",
  zones = { { name = "Snout", outer = 500 }, { name = "Drool Lake", outer = 360 }, { name = "Stomach", outer = 220 }, { name = "Brain", outer = 100 } }, outside = { 60, 40, 30 }, modifiers = { "Fog" } }
Renderer.setDish(info)
Fx.setDish(info)
Hud = require("Hud")
Hud.mapDish(info)
-- germs with every look
local germs, cells = {}, {}
local id = 100
local function germ(skin, muts, npc, core)
  id = id + 1
  germs[tostring(id)] = { name = "G" .. id, color = Color3.fromRGB(100, 200, 100), muts = muts or {}, skin = skin, npc = npc, core = core or "Blob", vip = true }
  cells[tostring(id + 1000)] = id
end
for _, cat in ipairs({ "Body", "Pattern", "Eyes", "Mouth", "Hat", "Trail" }) do
  for _, item in ipairs(Config.Skins[cat]) do
    local skin = { Body = "Jelly", Pattern = "None", Eyes = "Cute", Mouth = "Smile", Hat = "None", Trail = "None", Flag = "HU", Color2 = { 1, 2, 3 } }
    skin[cat] = item.Id
    germ(skin)
  end
end
for _, id in ipairs(Config.MutationOrder) do germ(nil, { [Config.Mutations[id].Slot] = id }) end
for _, id in ipairs(Config.FusionOrder) do germ(nil, { Front = id, Back = "#" .. id }) end
for _, c in ipairs(Config.CoreOrder) do germ(nil, {}, nil, c) end
for _, n in ipairs({ "whitey", "macrophage", "antibody" }) do germ(nil, {}, n) end
Renderer.applyInfo({ germs = germs, cells = cells })
local count = 0
for _ in pairs(cells) do count = count + 1 end
local buf = buffer.create(8 + count * 17)
buffer.writef32(buf, 0, 1) buffer.writeu32(buf, 4, 7)
local o = 8
for cidKey in pairs(cells) do
  local cid = tonumber(cidKey)
  buffer.writeu32(buf, o, cid) buffer.writef32(buf, o + 4, 2400 + cid % 50) buffer.writef32(buf, o + 8, 3) buffer.writef32(buf, o + 12, 50) buffer.writeu8(buf, o + 16, 127)
  o = o + 17
end
Renderer.snapshot(buf)
Renderer.myGermId = 101
Renderer.update(0.016, 1)
Renderer.update(0.016, 1.1)
print("renderer ok, parts moved:", BULK)
assert(Renderer.germView(101), "germView")
assert(#Renderer.board(6) == 6, "board")
Renderer.foodSync({ 1, 2400, 0, 1.2, 0, 2, 2401, 1, 3, 1 })
Renderer.foodDelta({ 3, 2402, 0, 1, 0 }, { 1 })
Renderer.foodDelta({}, { 2, 3 })
Renderer.removeCells({ 1101, 1103 }, { ["1101"] = 1102 })
for i = 1, 20 do Renderer.update(0.03, 2 + i * 0.03) end
print("eat animations ok")
-- mutation gear: every mutation and fusion draws and animates through every ability
local Gear = require("Gear")
local powers = { "Chomp", "Vacuum", "Pierce", "Ghost", "GravityWell", "Blast" }
local function gearTest(muts, core)
  local root = Instance.new("Frame")
  local h = Gear.build(root, muts, Color3.new(0.5, 0.5, 0.5), core)
  assert(h, "no gear drawn for " .. tostring(next(muts) and muts[next(muts)] or core))
  for _, pw in ipairs(powers) do
    for i = 0, 12 do
      Gear.animate(h, 0.1, i * 0.1, { dx = 0.6, dz = -0.8, fight = i % 2 == 0, dash = i % 3 == 0, power = pw, powerAge = i * 0.1 })
    end
  end
  Gear.animate(h, 0.1, 5, { dx = 1, dz = 0 })
  return h
end
for _, mid in ipairs(Config.MutationOrder) do gearTest({ [Config.Mutations[mid].Slot] = mid }) end
for _, fid in ipairs(Config.FusionOrder) do gearTest({ Front = fid, Back = "#" .. fid }) end
gearTest({}, "Star")
assert(Gear.build(Instance.new("Frame"), {}, Color3.new(1, 1, 1), "Blob") == nil, "no gear for a plain germ")
-- in the renderer: fighting, dashing germs using abilities
o = 8
for cidKey in pairs(cells) do
  local cid = tonumber(cidKey)
  if Renderer.cells[cid] then
    buffer.writeu32(buf, o, cid) buffer.writef32(buf, o + 4, 2400 + cid % 50) buffer.writef32(buf, o + 8, 3 + cid % 7) buffer.writef32(buf, o + 12, 50) buffer.writeu8(buf, o + 16, 12)
    o = o + 17
  end
end
Renderer.snapshot(buf)
for gid in pairs(germs) do Renderer.power(tonumber(gid), powers[tonumber(gid) % #powers + 1]) end
for i = 1, 30 do Renderer.update(0.1, 3 + i * 0.1) end
print("gear ok")
for i in ipairs(FlagsMod.SheetIds) do FlagsMod.SheetIds[i] = "" end
-- effects
for _, e in ipairs({
  { "Ink", { { x = 1, z = 2, r = 3 } } }, { "Warps", { { x = 1, z = 2, r = 3 }, { x = 1, z = 2, r = 3 } } }, { "Spikes", { { x = 1, z = 2, r = 3 } } },
  { "Whiskers", { duration = 5, angle = 1, length = 500 } }, { "Drool", { dx = 1, dz = 0, duration = 5 } }, { "Suction", { duration = 5 } },
  { "FireWarn", { seconds = 3, from = 350 } }, { "Fire", { from = 350, duration = 5 } }, { "HazardEnd", {} }, { "Fever", {} }, { "FeverEnd", {} },
  { "Medicine", { wall = 275, duration = 60 } }, { "MedicineEnd", { wall = 500 } }, { "BossHp", { id = 1, name = "Whitey", hp = 5, max = 10 } },
  { "ArenaTimer", { left = 100, sudden = false } }, { "Mirror", { on = true } }, { "Gulp", { id = 1 } } }) do
  Fx.event(e[1], e[2])
  Fx.update(0.5, 100)
end
print("fx ok")
-- HUD
local state = { germId = 101, alive = true, mode = "host", size = 26000, best = 1, dna = 500, zone = 1, zoneName = "Snout", hostName = "Barkley", host = 2,
  nextGate = { name = "Sneeze", size = 25000 }, sneezeSize = 25000, quarantine = 30, protected = true, dashIn = 1, splitIn = 2,
  actives = { Front = { id = "Chomp", readyIn = 3 } }, crowned = true, kills = 1, gp = 2, tokens = 3, mutant = 1, sneezes = 4, potion = 100, canRevive = true }
Hud.sync(state)
Hud.tick(0.1)
state.mode = "arena" state.nextGate = { name = "Exit", size = 1000 } state.floor = 3
Hud.sync(state)
Hud.notify("hi", "success") Hud.announce("x") Hud.feed("a", "b", true, false) Hud.died("Bob", 2.5, true, nil) Hud.died("Bob", 2.5, false, 10)
Hud.sneeze({ from = "A", to = "B", fx = "Glitter", dna = 100, sneezes = 1, mutant = 1, mutantUp = true, core = "Rod", arenaUnlocked = true })
Hud.board(Renderer.board(6), 101)
Hud.map(2400, 3, Renderer.markers())
Hud.radar({ { x = 2500, z = 10, d = 3, kind = "prey" }, { x = 2300, z = 10, d = 3, kind = "danger" } }, 2400, 3)
Hud.radar(nil, nil, nil)
Hud.setStick(true)
assert(Hud.onStick(85, 85) and not Hud.onStick(400, 85), "stick hit test")
local sx, sz = Hud.stickMove(400, 85)
assert(math.abs(sx - 1) < 1e-6 and math.abs(sz) < 1e-6, "stick clamp")
Hud.stickMove(nil)
print("hud ok")
-- menus with a profile
local profile = { Dna = 99999, Levels = { Jaws = 5, Suction = 5, Spikes = 2 }, Fusions = { BlackHole = true }, Equipped = { Front = "BlackHole", Sides = "Spikes" }, Loadouts = { { Front = "Jaws" } },
  Core = "Blob", MaxHost = 3, Host = 3, Skills = { Hunter = 2 }, GermPoints = 3,
  Skin = { Body = "Jelly", Pattern = "None", Eyes = "Cute", Mouth = "Smile", Hat = "None", Trail = "None", SneezeFx = "Classic", Flag = "HU", Color = { 110, 200, 255 }, Color2 = { 255, 255, 255 } },
  OwnedSkins = { ["Body:Lava"] = true }, Flags = { HU = true }, Outfits = { { Body = "Jelly", Pattern = "None", Hat = "None" } }, Passes = { ExtraLoadout = true }, Potions = 1, PotionUntil = 0,
  Quests = { Day = 1, List = { { Id = "EatGerms", Goal = 5, Progress = 5, Claimed = false }, { Id = "Grow", Goal = 3, Progress = 1, Claimed = false } }, Weekly = 7, WeeklyClaimed = false },
  Streak = { Day = 1, Count = 3 }, Cards = { Whitey = true }, CardSetsClaimed = {}, ArenaBest = 4, ArenaBestEver = 12, ArenaFloor = 10, Tokens = 50, Mutant = 1, Sneezes = 7, Kills = 3, BestSize = 9,
  IsDev = true, Studio = true, Strain = 1, BestRun = 754, RunSeconds = 300, RunValid = true, StrainRuns = 1,
  Strains = { { name = "Strain A", host = 3, hostName = "Big Barkley", core = "Blob", muts = "Jaws, Spikes", levels = 7, runs = 1, active = true }, false, { name = "Strain C", host = 6, hostName = "X", core = "Rod", muts = "", levels = 0, runs = 4, active = false } },
  Season = 1, SeasonLeft = 100000, ArenaUnlocked = true, Rank = "Cough" }
Menus.setProfile(profile)
if MENU_SHOTS then
  state.mode = "host" state.nextGate = { name = "Sneeze", size = 25000 } state.size = 9000 state.quarantine = 0 state.protected = false state.actives = { Front = { id = "Chomp", readyIn = 0 }, Special = { id = "Blast", readyIn = 0 } } state.dashIn = 0 state.splitIn = 0 Hud.sync(state) Hud.tick(0.01) Hud.setStick(MENU_TOUCH == true)
  local marks = { king = { x = 2400 + 230, z = -170 }, bosses = { { x = 2400 - 90, z = 300 } }, golden = { { x = 2400 + 140, z = 200 } } }
  Hud.map(2400 - 160, 140, marks) Hud.map(2400 - 150, 130, marks)
  __MENU_DUMP__
  return
end
for name, p in pairs(Ui.panels) do
  Ui.open(name)
  local tabs = { "Mutations", "Fusions", "Cores", "Skills", "Builds", "Body", "Pattern", "Eyes", "Mouth", "Hat", "Trail", "Sneeze", "Flag", "Colors", "Outfits", "Daily", "Cards", "Runs", "Speedrun" }
  local pressed = 0
  local function press(o)
    for _, c in ipairs(o.__children) do
      if c.__class == "TextButton" and rawget(c, "Activated") then c.Activated:Fire() pressed = pressed + 1 end
      press(c)
    end
  end
  for _, t in ipairs(tabs) do p.tab = t if p.onOpen then p.onOpen() end press(p.list) end
  print("menu " .. name .. " ok, buttons pressed: " .. pressed)
  Ui.close()
end
Menus.setMode("arena")
Ui.open("Arena")
print("calls made: " .. #CALLS)
print("CLIENT SMOKE OK")
`;
let code = (process.env.MENU_TOUCH ? "MENU_TOUCH = true\n" : "") + prelude;
for (const n of ["Config", "Formulas", "Flags", "Names"]) code += wrap(n, read(`shared/${n}.luau`));
for (const n of ["Ui", "Looks", "Gear", "Renderer", "Fx", "Hud", "Menus"]) code += wrap(n, read(`client/${n}.luau`));
const tool = (f) => fs.readFileSync(path.join(__dirname, f), "utf8");
let runCode = run.replace("__MENU_DUMP__", process.env.MENU_DUMP ? tool("gui-json.lua") + tool("menu-dump.lua") : "")
  .replace("__LOOK_DUMP__", process.env.LOOK_DUMP ? tool("gui-json.lua") + tool("look-dump.lua") : "");
if (process.env.MENU_DUMP) runCode = `MENU_SHOTS = ${process.env.MENU_DUMP}\n` + runCode;
// LOOK_DUMP = a JSON file: [{ skin = {...}, color = [r, g, b], flag = bool }]
const luaLit = (v) => Array.isArray(v) ? "{" + v.map(luaLit).join(",") + "}" : v && typeof v === "object" ?
  "{" + Object.entries(v).map(([k, x]) => `[${JSON.stringify(k)}]=${luaLit(x)}`).join(",") + "}" : JSON.stringify(v);
if (process.env.LOOK_DUMP) runCode = `LOOK_SHOTS = ${luaLit(JSON.parse(fs.readFileSync(process.env.LOOK_DUMP, "utf8")))}\n` + runCode;
code += runCode;
if (process.env.SMOKE_CODE) fs.writeFileSync(process.env.SMOKE_CODE, code);
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK) { console.error(lua.lua_tojsstring(L, -1)); process.exit(1); }
lua.lua_getglobal(L, to_luastring("debug")); lua.lua_getfield(L, -1, to_luastring("traceback")); lua.lua_remove(L, -2); lua.lua_insert(L, 1);
if (lua.lua_pcall(L, 0, 0, 1) !== lua.LUA_OK) { console.error(lua.lua_tojsstring(L, -1)); process.exit(1); }
if (process.env.MENU_DUMP || process.env.LOOK_DUMP) { lua.lua_getglobal(L, to_luastring("MENU_JSON")); fs.writeFileSync(process.env.MENU_OUT || process.env.LOOK_OUT, lua.lua_tojsstring(L, -1)); }
