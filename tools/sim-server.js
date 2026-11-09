// Runs the real server simulation (World + BotService) outside Roblox, with bots only,
// to catch errors and check pacing.  node tools/sim-server.js [minutes]
// It rewrites the few Luau-only bits (+=, continue, `for x in t do`) into plain Lua and
// fakes the Roblox services the code touches.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const minutes = Number(process.argv[2] || 10);
const src = path.join(__dirname, "..", "src");
const read = (p) => fs.readFileSync(path.join(src, p), "utf8");

function toLua(code) {
	code = code.replace(/^(\s*)([\w.\[\]"':]+)\s*(\+|-|\*|\/|\.\.)=\s*(.+?)(\s*--.*)?$/gm, (_, ws, lhs, op, rhs) => `${ws}${lhs} = ${lhs} ${op} (${rhs})`);
	code = code.replace(/\bcontinue\b/g, "goto continue");
	code = code.replace(/\bin\s+(?!pairs\(|ipairs\(|next\b)(.+?)\s+do\b/g, "in pairs($1) do");
	return code;
}

const prelude = `
local modules, loaded = {}, {}
function __define(name, fn) modules[name] = fn end
local function lookup(_, k) return k end
script = { Parent = setmetatable({ Parent = setmetatable({}, { __index = lookup }) }, { __index = lookup }) }
function require(m)
  if type(m) == "table" then m = m.__name end
  if loaded[m] == nil then loaded[m] = modules[m]() end
  return loaded[m]
end
Color3 = { fromRGB = function(r, g, b) return { r, g, b } end, new = function(r, g, b) return { r, g, b } end }
Enum = setmetatable({}, { __index = function(t, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
math.clamp = function(x, a, b) if x < a then return a elseif x > b then return b end return x end
table.clone = function(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
local function noop() end
local fireAll = setmetatable({}, { __index = function() return noop end })
-- fake remotes
local Net = setmetatable({ notify = noop }, { __index = function() return { FireAllClients = noop, FireClient = noop, OnServerEvent = { Connect = noop } } end })
modules.Net = function() return Net end
-- fake buffer
buffer = {
  create = function(n) return { n = n } end,
  writef32 = noop, writeu32 = noop, writeu8 = noop,
}
-- scheduler
SIMTIME = 0
local sleeping = {}
local heartbeats = {}
task = {}
function task.spawn(f, ...)
  local co = coroutine.create(f)
  local ok, err = coroutine.resume(co, ...)
  if not ok then error(err) end
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
    if not ok then error(err) end
  end
end
function __heartbeat(dt) for _, f in ipairs(heartbeats) do f(dt) end end
local services = {
  RunService = { Heartbeat = { Connect = function(_, f) table.insert(heartbeats, f) end } },
  Players = { GetPlayers = function() return {} end },
}
game = { GetService = function(_, n) return services[n] end }
ReplicatedStorage = { Shared = { Config = { __name = "Config" }, Formulas = { __name = "Formulas" }, Names = { __name = "Names" } } }
services.ReplicatedStorage = ReplicatedStorage
script.Parent.Net = { __name = "Net" }
script.Parent.World = { __name = "World" }
script.Parent.Config = { __name = "Config" }
`;

const wrap = (name, code) => `__define(${JSON.stringify(name)}, function()\n${toLua(code)}\nend)\n`;

const run = `
local Config = require("Config")
local Formulas = require("Formulas")
local World = require("World")
local BotService = require("BotService")
World.hooks.germDied = function(victim, eater) if victim.bot then BotService.onBotDied(victim) end end
local kills = 0
World.hooks.ateGerm = function() kills = kills + 1 end
World.start()
BotService.start()

-- a "test germ": a fresh size-10 grazer driven by the Wanderer brain, respawned when eaten
local probe
local reached = {}
local deaths = 0
local function spawnProbe()
  probe = World.newGerm({ name = "PROBE", color = Config.GermColors[1], equipped = {} })
  probe.bot = { uncapped = true, behaviour = "Wanderer", nextThink = 0, huntStart = 0, restUntil = 0, wanderAt = 0 }
  World.spawnGerm(probe, Config.StartSize)
end
spawnProbe()
local oldDied = World.hooks.germDied
World.hooks.germDied = function(victim, eater)
  if victim == probe then deaths = deaths + 1; World.spawnGerm(probe, Formulas.respawnSize(victim.sizeAtDeath or 0)) return end
  oldDied(victim, eater)
end

local step = 1 / Config.TickRate
local total = ${minutes} * 60
local nextReport = 60
local thinkAt = 0
local bubbleRule = 0
while SIMTIME < total do
  SIMTIME = SIMTIME + step
  __heartbeat(step)
  __resume()
  -- drive the probe like a bot
  if SIMTIME >= thinkAt then
    thinkAt = SIMTIME + 0.25
    BotService.think(probe, probe.bot) -- grazes and runs from bigger germs, like a careful player
  end
  local size = World.germSize(probe)
  for _, gate in ipairs({ 250, 750, 1500, 2500 }) do
    if not reached[gate] and size >= gate then reached[gate] = SIMTIME end
  end
  if SIMTIME >= nextReport then
    nextReport = nextReport + 60
    local n, biggest = 0, 0
    for _, g in pairs(World.allGerms()) do
      if g.alive then n = n + 1; biggest = math.max(biggest, World.germSize(g)) end
    end
    print(string.format("t=%3dmin  germs=%d  biggest=%6.0f  probe=%6.0f  kills=%d  probe deaths=%d", math.floor(SIMTIME / 60 + 0.5), n, biggest, size, kills, deaths))
  end
end
for _, gate in ipairs({ 250, 750, 1500, 2500 }) do
  print(string.format("probe reached %4d after %s", gate, reached[gate] and string.format("%.1f min", reached[gate] / 60) or "never"))
end
`;

const code =
	prelude +
	wrap("Config", read("shared/Config.luau")) +
	wrap("Formulas", read("shared/Formulas.luau")) +
	wrap("Names", read("shared/Names.luau")) +
	wrap("World", read("server/Services/World.luau")) +
	wrap("BotService", read("server/Services/BotService.luau")) +
	run;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
	console.error(lua.lua_tojsstring(L, -1));
	process.exit(1);
}
