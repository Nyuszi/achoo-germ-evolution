// Runs the real server simulation (World + BotService) outside Roblox, with bots only,
// to catch errors and check pacing.  node tools/sim-server.js [minutes]
// It rewrites the few Luau-only bits (+=, continue, `for x in t do`) into plain Lua and
// fakes the Roblox services the code touches.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const minutes = Number(process.argv[2] || 10);
// DUMP_AT=1,5,12 prints the full world state (JSON after "DUMP ") at those minutes (tools/render-preview.js draws it)
const dumpAt = process.env.DUMP_AT || "";
const src = path.join(__dirname, "..", "src");
const read = (p) => fs.readFileSync(path.join(src, p), "utf8");

function toLua(code) {
	code = code.replace(/^(\s*)([\w.\[\]"':]+)\s*(\+|-|\*|\/|\.\.)=\s*(.+?)(\s*--.*)?$/gm, (_, ws, lhs, op, rhs) => `${ws}${lhs} = ${lhs} ${op} (${rhs})`);
	code = code.replace(/^(\s*)continue\b/gm, "$1goto continue");
	code = code.replace(/^(\s*for\b[^\n]*?\bin\s+)(?!pairs\(|ipairs\(|next\b|string\.gmatch)([^\n]+?)\s+do\b/gm, "$1pairs($2) do");
	return code;
}

const prelude = `
local modules, loaded = {}, {}
function __define(name, fn) modules[name] = fn end
local function lookup(_, k) return { __name = k } end
script = { Parent = setmetatable({ Parent = setmetatable({}, { __index = lookup }) }, { __index = lookup }) }
function require(m)
  if type(m) == "table" then m = m.__name end
  if loaded[m] == nil then
    if not modules[m] then error("no module " .. tostring(m)) end
    loaded[m] = modules[m]()
  end
  return loaded[m]
end
local function noop() end
local Signal = { Connect = function(self, f) table.insert(self, f) return { Disconnect = noop } end }
Signal.__index = Signal
local function signal() return setmetatable({}, Signal) end
local function color(r, g, b) return { r, g, b, R = r / 255, G = g / 255, B = b / 255, Lerp = function(self) return self end } end
Color3 = { fromRGB = color, new = function(r, g, b) return color(r * 255, g * 255, b * 255) end }
Enum = setmetatable({}, { __index = function(t, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
math.clamp = function(x, a, b) if x < a then return a elseif x > b then return b end return x end
math.sign = function(x) if x > 0 then return 1 elseif x < 0 then return -1 end return 0 end
table.clone = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
table.find = function(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
Random = { new = function(seed) local s = seed or 1 return { NextInteger = function(_, a, b) s = (s * 1103515245 + 12345) % 2147483648 return a + s % (b - a + 1) end } end }
warn = function(...) print("WARN", ...) end
-- fake Instances (anything can be set, children found by Name)
local Inst = {}
Inst.__index = function(self, k)
  if Inst[k] then return Inst[k] end
  return nil
end
function Inst.FindFirstChild(self, name) for _, c in ipairs(rawget(self, "__children")) do if c.Name == name then return c end end return nil end
function Inst.SetAttribute(self, k, v) rawget(self, "__attrs")[k] = v end
function Inst.GetAttribute(self, k) return rawget(self, "__attrs")[k] end
function Inst.Destroy() end
Instance = { new = function(class)
  local o = setmetatable({ __children = {}, __attrs = {}, ClassName = class }, Inst)
  return o
end }
local mt = getmetatable(Instance.new("x"))
mt.__newindex = function(self, k, v)
  if k == "Parent" and type(v) == "table" and rawget(v, "__children") then table.insert(rawget(v, "__children"), self) end
  rawset(self, k, v)
end
-- fake remotes: one table per name so the sim can call OnServerInvoke
local remotes = {}
local Net = setmetatable({ notify = function(p, text) if p.log then p.log(text) end end }, { __index = function(t, k)
  local r = { FireAllClients = noop, FireClient = function(self, player, ...) if player and player.onRemote then player.onRemote(k, ...) end end, OnServerEvent = signal() }
  rawset(t, k, r)
  return r
end })
NET = Net
modules.Net = function() return Net end
modules.MapBuilder = function() return { setup = noop, buildDish = function() return { Destroy = noop } end } end
-- fake buffer
buffer = { create = function(n) return { n = n } end, writef32 = noop, writeu32 = noop, writeu8 = noop }
-- scheduler
SIMTIME = 0
local sleeping = {}
local heartbeats = {}
task = {}
function task.spawn(f, ...)
  local co = coroutine.create(f)
  local ok, err = coroutine.resume(co, ...)
  if not ok then error(debug.traceback(co, err)) end
  return co
end
function task.wait(s)
  local co = coroutine.running()
  table.insert(sleeping, { co = co, at = SIMTIME + (s or 0) })
  coroutine.yield()
  return s
end
function task.delay(s, f, ...)
  local args = { ... }
  task.spawn(function() task.wait(s) f(table.unpack(args)) end)
end
function __resume()
  local due = {}
  for i = #sleeping, 1, -1 do
    if sleeping[i].at <= SIMTIME then table.insert(due, table.remove(sleeping, i)) end
  end
  for _, s in ipairs(due) do
    local ok, err = coroutine.resume(s.co)
    if not ok then error(debug.traceback(s.co, err)) end
  end
end
function __heartbeat(dt) for _, f in ipairs(heartbeats) do f(dt) end end
PLAYERS = {}
local playerAdded = signal()
local services = {
  RunService = { Heartbeat = { Connect = function(_, f) table.insert(heartbeats, f) end }, IsStudio = function() return true end },
  Players = { GetPlayers = function() return PLAYERS end, PlayerAdded = playerAdded, PlayerRemoving = signal(),
    GetPlayerByUserId = function(_, id) for _, p in ipairs(PLAYERS) do if p.UserId == id then return p end end end },
  MarketplaceService = { PromptGamePassPurchaseFinished = signal() },
  Lighting = {},
}
game = { GetService = function(_, n) return services[n] or {} end, BindToClose = noop, CreatorType = "User", CreatorId = 1 }
os.time = function() return 1793577600 + math.floor(SIMTIME) end
workspace = Instance.new("Workspace")
function ADDPLAYER(name, id)
  local p = Instance.new("Player")
  p.Name, p.DisplayName, p.UserId, p.Parent = name, name, id, true
  p.GetJoinData = function() return {} end
  table.insert(PLAYERS, p)
  for _, f in ipairs(playerAdded) do task.spawn(f, p) end
  return p
end
ReplicatedStorage = { Shared = { Config = { __name = "Config" }, Formulas = { __name = "Formulas" }, Names = { __name = "Names" }, Stats = { __name = "Stats" }, Flags = { __name = "Flags" } } }
services.ReplicatedStorage = ReplicatedStorage
`;

const wrap = (name, code) => `__define(${JSON.stringify(name)}, function()\n${toLua(code)}\nend)\n`;

const run = `
DUMP_AT = ${JSON.stringify(dumpAt)}
local Config = require("Config")
local Formulas = require("Formulas")
local World = require("World")
local BotService = require("BotService")
local PlayerService = require("PlayerService")
local DataService = require("DataService")
require("Main")

-- one fake player, steered by the bot brain (grazes, runs from bigger germs, hunts a bit)
local log = {}
local sneezes = {}
local p = ADDPLAYER("PROBE", 1)
p.log = function(text) table.insert(log, string.format("%5.1f min  %s", SIMTIME / 60, text)) end
p.onRemote = function(name, a, b)
  if name == "Sneeze" then table.insert(sneezes, string.format("%5.1f min  sneeze %s -> %s", SIMTIME / 60, a.from, a.to)) end
  if name == "Announce" or name == "Died" then table.insert(log, string.format("%5.1f min  [%s] %s", SIMTIME / 60, name, tostring(a))) end
end
local brain = { behaviour = "Hunter", nextThink = 0, huntStart = 0, restUntil = 0, wanderAt = 0 }
local function call(remote, ...)
  local ok, msg = NET[remote].OnServerInvoke(p, ...)
  table.insert(log, string.format("%5.1f min  %s %s -> %s %s", SIMTIME / 60, remote, table.concat({ ... }, " "), tostring(ok), tostring(msg)))
  return ok
end

-- tiny JSON writer for the preview dumps
local function json(v)
  local t = type(v)
  if t == "number" then if v ~= v or v == math.huge or v == -math.huge then return "0" end return string.format("%.3f", v)
  elseif t == "string" then return '"' .. v:gsub('[%c"' .. string.char(92) .. ']', function(c) return string.format(string.char(92) .. "u%04x", c:byte()) end) .. '"'
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" then
    if #v > 0 or next(v) == nil then local o = {} for i = 1, #v do o[i] = json(v[i]) end return "[" .. table.concat(o, ",") .. "]" end
    local o = {} for k, x in pairs(v) do if type(x) ~= "function" then table.insert(o, json(tostring(k)) .. ":" .. json(x)) end end return "{" .. table.concat(o, ",") .. "}"
  end
  return "null"
end
local function rgbOf(c) return { c[1] or 0, c[2] or 0, c[3] or 0 } end
function DUMP(name)
  local germ = PlayerService.germ(p)
  local dish = germ.dish
  local data = DataService.get(p)
  local sc = dish.scale
  local out = { name = name, kind = dish.kind, host = dish.host, floor = dish.floor, radius = dish.layout.radius, wall = dish.wall, probe = germ.id,
    zones = {}, cells = {}, food = {}, bubbles = {}, ink = dish.ink, warps = {}, spikes = dish.spikes, burnFrom = dish.effects.burnFrom or 0, sneeze = dish.layout.sneeze / sc,
    modifiers = dish.modifiers or {} }
  for i, z in ipairs(dish.layout.zones) do
    out.zones[i] = { name = dish.kind == "host" and Config.Hosts[dish.host].Zones[i] or "Petri Floor", outer = z.Outer, min = z.MinShare }
  end
  if dish.kind == "host" then
    local h = Config.Hosts[dish.host]
    out.theme = { floors = h.Floors, membranes = h.Membranes, wall = h.Wall, outside = h.Outside, name = h.Name }
  else
    out.theme = { floors = { { 205, 230, 240 } }, membranes = { { 160, 200, 220 } }, wall = { 200, 240, 255 }, outside = { 15, 20, 35 }, name = "The Infinite Petri" }
  end
  for _, w in ipairs(dish.warps) do table.insert(out.warps, { x = w.x, z = w.z, r = w.r }) end
  for _, b in ipairs(dish.bubbles) do table.insert(out.bubbles, { b.x, b.z }) end
  for _, cell in pairs(dish.cells) do
    local g = cell.germ
    local muts = {}
    for slot, id in pairs(g.equipped or {}) do muts[slot] = id end
    table.insert(out.cells, { g = g.id, x = cell.x, z = cell.z, s = cell.size / sc, real = cell.size, name = g.name, color = rgbOf(g.color), muts = muts,
      crown = dish.crowned == g, prot = World.isProtected(g), npc = g.npc and g.npc.kind or "", flag = g.skin and g.skin.Flag or "",
      hidden = dish.hidden[g] == true, hat = g.skin and g.skin.Hat or "None", eyes = g.skin and g.skin.Eyes or "Cute" })
  end
  for _, f in pairs(dish.food) do table.insert(out.food, { f.x, f.z, f.v / sc, f.golden and 1 or 0 }) end
  local size = World.germSize(germ)
  local cx, cz = World.germCentre(germ)
  local zone = Formulas.zoneAt(math.sqrt(cx * cx + cz * cz), dish.layout)
  out.hud = { size = size, dna = data.Dna, gp = data.GermPoints, zoneName = out.zones[zone].name, hostName = out.theme.name, floor = germ.arenaFloor or 0 }
  print("DUMP " .. json(out))
end

local step = 1 / Config.TickRate
local total = ${minutes} * 60
local nextReport = 60
local thinkAt = 0
local labAt = 30
while SIMTIME < total do
  SIMTIME = SIMTIME + step
  __heartbeat(step)
  __resume()
  local germ = PlayerService.germ(p)
  if germ and germ.alive and SIMTIME >= thinkAt then
    thinkAt = SIMTIME + 0.25
    BotService.think(germ, brain)
    -- at sneeze size: swim to the nerve
    if World.germSize(germ) >= germ.dish.layout.sneeze then germ.target = { x = 0, z = 0 } end
    if math.random() < 0.02 then NET.Action.OnServerEvent[1](p, "Dash") end
  end
  -- spend DNA in the Lab now and then like a player would
  if SIMTIME >= labAt then
    labAt = SIMTIME + 30
    local data = DataService.get(p)
    for _, id in ipairs({ "Flagella", "Jaws", "Shell", "Suction", "Magnet" }) do
      if data.Dna >= Formulas.mutationCost(id, (data.Levels[id] or 0) + 1) and (data.Levels[id] or 0) < 5 then call("Lab", "Upgrade", id) break end
    end
    if data.GermPoints > 0 then call("Lab", "Skill", "Glutton") end
    for qi = 1, 3 do local q = data.Quests.List[qi] if q and not q.Claimed and q.Progress >= q.Goal then call("Quests", "Claim", qi) end end
  end
  if SIMTIME >= nextReport then
    nextReport = nextReport + 60
    local data = DataService.get(p)
    local nd, ng = 0, 0
    for _, d in pairs(World.dishes()) do nd = nd + 1 end
    for _, g in pairs(World.allGerms()) do if g.alive then ng = ng + 1 end end
    if germ and germ.dish and germ.dish.modifiers and #germ.dish.modifiers > 0 then print("  modifiers: " .. table.concat(germ.dish.modifiers, ", ") .. " wall=" .. math.floor(germ.dish.wall) .. " poison=" .. tostring(World.hasEffect(germ, "Poison")) .. " rate=" .. tostring(germ.poisonRate)) end
    print(string.format("t=%3dmin dishes=%d germs=%d host=%d size=%s dna=%d kills=%d deaths=%d mode=%s floor=%s", math.floor(SIMTIME / 60 + 0.5), nd, ng, data.Host,
      Formulas.formatNumber(germ and germ.alive and World.germSize(germ) or 0), data.Dna, data.Kills, data.Deaths, tostring(germ and germ.mode), tostring(germ and germ.arenaFloor)))
  end
  -- EXERCISE=1: press every Dev, Shop, Editor, Lab, Quests and Arena action once, 3 s apart
  if EXERCISE and SIMTIME >= 20 and SIMTIME >= (nextExercise or 0) then
    nextExercise = SIMTIME + 3
    exerciseI = (exerciseI or 0) + 1
    local list = {
      { "Dev", "Dna" }, { "Dev", "MaxLab" }, { "Lab", "Fuse", "BlackHole" }, { "Lab", "Fuse", "Fortress" }, { "Lab", "Equip", "Fortress" }, { "Lab", "Equip", "Drill" },
      { "Lab", "SaveLoadout", 1 }, { "Lab", "LoadLoadout", 1 }, { "Lab", "Core", "Rod" }, { "Dev", "GermPoints" }, { "Lab", "Skill", "Starter" },
      { "Shop", "BuyPass", "DoubleDna" }, { "Shop", "BuyPass", "VIP" }, { "Shop", "BuyProduct", "GrowthPotion" }, { "Shop", "UsePotion" }, { "Shop", "BuyProduct", "DnaLarge" },
      { "Shop", "BuyProduct", "ServerFever" }, { "Shop", "BuyProduct", "ImmuneStrike" }, { "Shop", "BuyItem", { kind = "Skin", cat = "Body", id = "Lava" } },
      { "Shop", "BuyItem", { kind = "Skin", cat = "Pattern", id = "Spots", dna = true } }, { "Shop", "BuyItem", { kind = "Flag", id = "HU" } },
      { "Shop", "BuyItem", { kind = "Continent", id = "Europe" } }, { "Shop", "BuyItem", { kind = "World" } }, { "Shop", "BuyItem", { kind = "Bundle", id = "DragonGerm" } },
      { "Editor", "Equip", "Flag", "JP" }, { "Editor", "Color", "Color", { 255, 0, 10 } }, { "Editor", "SaveOutfit", 3 }, { "Editor", "LoadOutfit", 3 },
      { "Dev", "Hazard" }, { "Dev", "Whitey" }, { "Dev", "Macrophage" }, { "Dev", "Fever" }, { "Dev", "Medicine" }, { "Dev", "Golden" }, { "Dev", "EndQuarantine" },
      { "Dev", "CompleteQuests" }, { "Quests", "Claim", 1 }, { "Quests", "Redeem", "achoo" }, { "Quests", "ClaimWeekly" }, { "Quests", "ClaimSet", "Hosts" },
      { "Dev", "Grow" }, { "Dev", "SneezeSize" }, { "Dev", "NextHost" }, { "Dev", "Host", 4 }, { "Dev", "Hazard" }, { "Dev", "Host", 5 }, { "Dev", "Hazard" },
      { "Dev", "Host", 6 }, { "Dev", "Hazard" }, { "Dev", "Host", 3 }, { "Dev", "Hazard" }, { "Dev", "Host", 2 }, { "Dev", "Hazard" },
      { "Arena", "Enter" }, { "Dev", "Mutant" }, { "Arena", "Enter" }, { "Dev", "SneezeSize" }, { "Dev", "Tokens" }, { "Arena", "Buy", 1 }, { "Dev", "ArenaFloor" },
      { "Dev", "ArenaFloor" }, { "Dev", "ArenaFloor" }, { "Dev", "SneezeSize" }, { "Arena", "Leave" }, { "Dev", "Reset" },
    }
    local c = list[exerciseI]
    if c then
      local args = {}
      for i = 2, #c do args[i - 1] = type(c[i]) == "table" and "{...}" or tostring(c[i]) end
      local ok, msg = NET[c[1]].OnServerInvoke(p, table.unpack(c, 2))
      print(string.format("%5.1fs  %s %s -> %s %s", SIMTIME, c[1], table.concat(args, " "), tostring(ok), tostring(msg)))
    end
  end
  -- PREVIEW=1: visit hosts and the Arena and print DUMP lines for tools/render-preview.js
  if PREVIEW then
    previewStep = previewStep or 1
    local plan = {
      { 30, "dump", "host1-new" },
      { 360, "dump", "host1-growing" },
      { 362, "Host", 2 }, { 392, "Hazard" }, { 394, "dump", "host2-drool" },
      { 396, "Host", 4 }, { 430, "Hazard" }, { 434.5, "dump", "host4-fire" },
      { 436, "Host", 5 }, { 470, "Grow" }, { 471, "dump", "host5-ink" },
      { 473, "Host", 6 }, { 505, "Grow" }, { 506, "dump", "host6-warps" },
      { 508, "Mutant" }, { 509, "Arena" }, { 560, "dump", "arena" },
    }
    local step = plan[previewStep]
    if step and SIMTIME >= step[1] then
      previewStep = previewStep + 1
      if step[2] == "dump" then DUMP(step[3])
      elseif step[2] == "Arena" then NET.Arena.OnServerInvoke(p, "Enter")
      else NET.Dev.OnServerInvoke(p, step[2], step[3]) end
    end
  end
  if TESTARENA and SIMTIME >= TESTARENA and not ARENADONE then
    ARENADONE = true
    call("Dev", "Mutant")
    call("Arena", "Enter")
  end
end
for _, line in ipairs(sneezes) do print(line) end
print("--- log (last 40) ---")
for i = math.max(1, #log - 40), #log do print(log[i]) end
`;

const services = ["Net", "Bus", "DataService", "World", "MapBuilder", "DishService", "HazardService", "ImmuneService", "BotService", "PlayerService", "LabService", "ShopService", "ArenaService", "QuestService", "DevService", "FeedbackService"];
let code = prelude + `PREVIEW = ${process.env.PREVIEW ? 'true' : 'false'}\nEXERCISE = ${process.env.EXERCISE ? 'true' : 'false'}\nTESTARENA = ${process.env.ARENA_AT ? Number(process.env.ARENA_AT) * 60 : "nil"}\n`;
for (const n of ["Config", "Formulas", "Names", "Stats", "Flags"]) code += wrap(n, read(`shared/${n}.luau`));
for (const n of services) if (n !== "Net" && n !== "MapBuilder") code += wrap(n, read(`server/Services/${n}.luau`));
code += wrap("Main", read("server/Main.server.luau").replace(/script\.Parent\.Services/g, "script.Parent"));
code += run;

if (process.env.SIM_CODE) fs.writeFileSync(process.env.SIM_CODE, code);
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
	console.error(lua.lua_tojsstring(L, -1));
	process.exit(1);
}
