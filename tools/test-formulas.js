// Runs the pure game maths (src/shared/Config.luau + Formulas.luau) in a Lua VM and checks it.
//   npm install   (once)
//   npm test
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const shared = path.join(__dirname, "..", "src", "shared");
const read = (f) => fs.readFileSync(path.join(shared, f), "utf8");

// Small stand-ins for the Roblox bits the shared files touch.
const prelude = `
local modules = {}
local loaded = {}
function __define(name, fn) modules[name] = fn end
script = { Parent = setmetatable({}, { __index = function(_, k) return k end }) }
function require(name)
  if loaded[name] == nil then loaded[name] = modules[name]() end
  return loaded[name]
end
`;
const wrap = (name, src) => `__define(${JSON.stringify(name)}, function()\n${src}\nend)\n`;

const tests = `
local F = require("Formulas")
local C = require("Config")
local failed, passed = 0, 0
local function check(name, ok)
  if ok then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end
local H1, H2 = F.hostLayout(1), F.hostLayout(2)
local AR = F.arenaLayout()

-- radius / host scale
check("start radius ~1.9", near(F.radius(10, 1), 0.6 * math.sqrt(10)))
check("sneeze radius 30", near(F.radius(2500, 1), 30))
check("host 2 start looks as small as host 1 start", near(F.radius(H2.start, H2.scale), F.radius(H1.start, H1.scale)))
check("same visual radius in every host", near(F.radius(250000, 100), F.radius(2500, 1)))

-- speed
check("small germs are faster", F.speed(10, 1) > F.speed(2500, 1))
check("speed never below min", F.speed(1e12, 1) >= C.MinSpeed)
check("speed never above max", F.speed(1, 1) <= C.MaxSpeed)
check("same speed in host 2 at same look", near(F.speed(1000, 10), F.speed(100, 1)))

-- eating
check("125 eats 100", F.canEat(125, 100))
check("124 cannot eat 100", not F.canEat(124, 100))
check("black hole mouth eats at 1.15", F.canEat(115, 100, 1.15))
check("100 vs 110 is a fight", F.isFight(100, 110))
check("100 vs 130 is not a fight", not F.isFight(100, 130))
local keep, burst = F.eatSplit(100)
check("eat keeps 40%", near(keep, 40) and near(burst, 60))
check("swallowed when deep inside", F.isSwallowed(1, 10, 5))
check("not swallowed at the edge", not F.isSwallowed(9, 10, 5))

-- fights
local a, d = { size = 100 }, { size = 100 }
check("base fight damage 3%/s", near(F.fightDamage(a, d, 1), 3))
check("bite +60%", near(F.fightDamage({ size = 100, bite = 0.6 }, d, 1), 4.8))
check("armour blocks 40%", near(F.fightDamage(a, { size = 100, armor = 0.4 }, 1), 1.8))
check("drill pierces armour", near(F.fightDamage({ size = 100, pierce = 0.4 }, { size = 100, armor = 0.4 }, 1), 3))
check("spikes add 2%", near(F.fightDamage({ size = 100, thorns = 0.02 }, d, 1), 5))
check("bots go easy (mult)", near(F.fightDamage({ size = 100, mult = 0.5 }, d, 1), 1.5))
check("boss damage 15%/s", near(F.bossDamage(1000, 0, 1), 150))

-- zones
check("edge is zone 1", F.zoneAt(599, H1) == 1)
check("centre is zone 4", F.zoneAt(10, H1) == 4)
check("zone 2 band", F.zoneAt(420, H1) == 2)
check("min size zone 2 = 250", near(F.zoneMinSize(2, H1), 250))
check("host 2 zone 2 needs 2500", near(F.zoneMinSize(2, H2), 2500))
check("start size only zone 1", F.deepestZone(10, H1) == 1)
check("1500 reaches heart", F.deepestZone(1500, H1) == 4)
check("small germ pushed out of zone 2", F.clampDistance(420, 10, 2, H1) >= 480)
check("small germ stays in zone 1", near(F.clampDistance(520, 10, 2, H1), 520))
check("wall stops germs", near(F.clampDistance(700, 10, 2, H1), 600 - 2))
check("medicine wall moves in", near(F.clampDistance(400, 10, 2, H1, 300), 300 - 2))
check("big germ coughed out of zone 1", F.clampDistance(550, 800, 17, H1) <= 480)
check("big germ may go to the middle", near(F.clampDistance(5, 2000, 27, H1), 5))
check("arena has one zone", F.deepestZone(100, AR) == 1 and near(F.clampDistance(5, 100, 6, AR), 5))
check("arena wall", near(F.clampDistance(300, 100, 6, AR), C.Arena.Radius - 6))

-- respawn, DNA, bounty, growth
check("respawn keeps 50%", F.respawnSize(400) == 200)
check("respawn never below start", F.respawnSize(6) == C.StartSize)
check("vaccine keeps 75%", F.respawnSize(400, 0.75) == 300)
check("kill dna 10%", F.killDna(500) == 50)
check("kill dna uses host units", F.killDna(5000, { scale = 10 }) == 50)
check("revenge doubles", F.killDna(500, { revenge = true }) == 100)
check("feeding again gives half", F.killDna(500, { recentFeeds = 1 }) == 25)
check("bounty starts at 5%", near(F.bountyShare(0), 0.05))
check("bounty capped", near(F.bountyShare(1e6), C.BountyMaxShare))
check("crowned bonus", F.killDna(1000, { crowned = true }) == 150)
check("growth +25% per sneeze", near(F.growthMult(4), 2))
check("growth bonus capped", near(F.growthMult(60), F.growthMult(12)))
check("host 1 limits", F.hostLimits(1).slots == 2 and F.hostLimits(1).levelCap == 3 and not F.hostLimits(1).fusions)
check("host 9 clamps to last", F.hostLimits(9).slots == 4)
check("time format", F.formatTime(754) == "12:34" and F.formatTime(3723) == "1:02:03")

-- decay and camera
check("no decay when small", F.decay(100, 1, H1) == 0)
check("decay when big", F.decay(2000, 1, H1) > 0)
check("camera rises with size", F.cameraHeight(30) > F.cameraHeight(2))
check("camera capped", F.cameraHeight(1e9) == C.Camera.MaxHeight)

-- mutations
check("level 1 cost = base", F.mutationCost("Jaws", 1) == 50)
check("level 5 costs more", F.mutationCost("Jaws", 5) > F.mutationCost("Jaws", 4))
check("jaws bite level 1", near(F.mutationStat("Jaws", "Bite", 1), 0.4))
check("jaws bite level 5", near(F.mutationStat("Jaws", "Bite", 5), 1.0))
check("no stat at level 0", F.mutationStat("Jaws", "Bite", 0) == 0)
check("plain number stat", F.mutationStat("Magnet", "Magnet", 3) == 14)
for _, id in ipairs(C.MutationOrder) do check("mutation exists " .. id, C.Mutations[id] ~= nil) end
for _, id in ipairs(C.FusionOrder) do
  local f = C.Fusions[id]
  check("fusion parts exist " .. id, C.Mutations[f.Parts[1]] ~= nil and C.Mutations[f.Parts[2]] ~= nil)
end

-- arena
check("arena cap floor 1", F.arenaLevelCap(1) == 3)
check("arena cap floor 10", F.arenaLevelCap(10) == 4)
check("arena cap floor 30", F.arenaLevelCap(30) == 5)
check("rank sniffle", F.arenaRank(3) == "Sniffle")
check("rank plague", F.arenaRank(150) == "Plague")
check("checkpoint", F.arenaCheckpoint(27) == 20 and F.arenaCheckpoint(5) == 1)
check("modifier count", F.arenaModifierCount(1) == 1 and F.arenaModifierCount(30) == 2 and F.arenaModifierCount(60) == 3)
local s1 = F.season(C.Arena.SeasonStart + 10)
local s2 = F.season(C.Arena.SeasonStart + 29 * 86400)
check("season 1 then 2", s1 == 1 and s2 == 2)

-- every host has 4 zone names and colours
for i, h in ipairs(C.Hosts) do
  check("host " .. i .. " zones", #h.Zones == 4 and #h.Floors == 4 and #h.Membranes == 4 and C.Hazards[h.Hazard] ~= nil and C.Cores[h.Core] ~= nil)
end

-- numbers
check("format 950", F.formatNumber(950) == "950")
check("format 1250", F.formatNumber(1250) == "1.25K")
check("format 25000", F.formatNumber(25000) == "25.0K")
check("format 2.5M", F.formatNumber(2500000) == "2.50M")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error("tests failed") end
`;

const stubs = `
Color3 = { fromRGB = function(r, g, b) return { r, g, b } end }
Enum = setmetatable({}, { __index = function(t, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
`;
const code = prelude + stubs + wrap("Config", read("Config.luau")) + wrap("Formulas", read("Formulas.luau")) + tests;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
if (lauxlib.luaL_loadstring(L, to_luastring(code)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
	console.error(lua.lua_tojsstring(L, -1));
	process.exit(1);
}
