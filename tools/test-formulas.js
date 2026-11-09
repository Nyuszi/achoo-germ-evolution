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

-- radius / host scale
check("start radius ~1.9", near(F.radius(10, 1), 0.6 * math.sqrt(10)))
check("sneeze radius 30", near(F.radius(2500, 1), 30))
check("host 2 start looks as small as host 1 start", near(F.radius(25000, 10), F.radius(2500, 1)))
check("same visual radius in every host", near(F.radius(250000, 100), F.radius(2500, 1)))

-- speed
check("small germs are faster", F.speed(10, 1) > F.speed(2500, 1))
check("speed never below min", F.speed(1e12, 1) >= C.MinSpeed)
check("speed never above max", F.speed(1, 1) <= C.MaxSpeed)
check("flagella mult", near(F.speed(100, 1, 1.15), F.speed(100, 1) * 1.15))

-- eating
check("125 eats 100", F.canEat(125, 100))
check("124 cannot eat 100", not F.canEat(124, 100))
check("100 vs 110 is a fight", F.isFight(100, 110))
check("100 vs 130 is not a fight", not F.isFight(100, 130))
local keep, burst = F.eatSplit(100)
check("eat keeps 40%", near(keep, 40) and near(burst, 60))
check("swallowed when deep inside", F.isSwallowed(1, 10, 5))
check("not swallowed at the edge", not F.isSwallowed(9, 10, 5))

-- fights
local a = { size = 100 }
local d = { size = 100 }
check("base fight damage 3%/s", near(F.fightDamage(a, d, 1), 3))
check("jaws +60%", near(F.fightDamage({ size = 100, bite = 0.6 }, d, 1), 4.8))
check("shell blocks 40%", near(F.fightDamage(a, { size = 100, armor = 0.4 }, 1), 1.8))
check("spikes add 2%", near(F.fightDamage({ size = 100, thorns = 0.02 }, d, 1), 5))
check("bots go easy (mult)", near(F.fightDamage({ size = 100, mult = 0.5 }, d, 1), 1.5))

-- zones
check("edge is zone 1", F.zoneAt(499) == 1)
check("centre is zone 4", F.zoneAt(10) == 4)
check("zone 2 band", F.zoneAt(300) == 2)
check("min size zone 2 = 250", near(F.zoneMinSize(2, 1), 250))
check("start size only zone 1", F.deepestZone(10, 1) == 1)
check("1500 reaches heart", F.deepestZone(1500, 1) == 4)
check("small germ pushed out of zone 2", F.clampDistance(300, 10, 2, 1) >= 350)
check("small germ stays in zone 1", near(F.clampDistance(400, 10, 2, 1), 400))
check("wall stops germs", near(F.clampDistance(600, 10, 2, 1), 500 - 2))
check("big germ coughed out of zone 1", F.clampDistance(450, 800, 17, 1) <= 350)
check("big germ may go to the middle", near(F.clampDistance(5, 2000, 27, 1), 5))

-- respawn, DNA, bounty
check("respawn keeps 50%", F.respawnSize(400) == 200)
check("respawn never below start", F.respawnSize(6) == C.StartSize)
check("kill dna 10%", F.killDna(500) == 50)
check("revenge doubles", F.killDna(500, { revenge = true }) == 100)
check("feeding again gives half", F.killDna(500, { recentFeeds = 1 }) == 25)
check("bounty starts at 5%", near(F.bountyShare(0), 0.05))
check("bounty capped", near(F.bountyShare(1e6), C.BountyMaxShare))
check("crowned bonus", F.killDna(1000, { crowned = true }) == 150)

-- decay and camera
check("no decay when small", F.decay(100, 1, 1) == 0)
check("decay when big", F.decay(2000, 1, 1) > 0)
check("camera rises with size", F.cameraHeight(30) > F.cameraHeight(2))
check("camera capped", F.cameraHeight(1e9) == C.Camera.MaxHeight)

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
