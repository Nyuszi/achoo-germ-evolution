-- Pure maths for the game: no Roblox objects, so tools/test-formulas.js can test it.
-- Keep this file plain Lua (no types, no +=).
--
-- A "layout" describes one dish: { zones, radius, sneeze, scale, start, host }.
-- Hosts and Arena floors each have one (Formulas.hostLayout / Formulas.arenaLayout).
local Config = require(script.Parent.Config)

local Formulas = {}

local function clamp(x, lo, hi)
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end
Formulas.clamp = clamp

function Formulas.host(index)
	return Config.Hosts[index or 1]
end

function Formulas.hostLayout(index)
	local h = Config.Hosts[index or 1]
	return {
		host = index or 1,
		zones = Config.Zones,
		radius = Config.DishRadius,
		sneeze = h.SneezeSize,
		scale = h.Scale,
		start = Config.StartSize * h.Scale,
	}
end

-- Arena floors: one zone, everyone starts at the same size.
local arenaZones = { { Outer = Config.Arena.Radius, MinShare = 0, FoodValue = 3, FoodCount = 280 } }
function Formulas.arenaLayout(radius)
	local r = radius or Config.Arena.Radius
	local zones = { { Outer = r, MinShare = 0, FoodValue = arenaZones[1].FoodValue, FoodCount = math.floor(arenaZones[1].FoodCount * (r / Config.Arena.Radius) ^ 2) } }
	return {
		arena = true,
		zones = zones,
		radius = r,
		sneeze = Config.Arena.GoalSize,
		scale = 1,
		start = Config.Arena.StartSize,
	}
end

-- Drawn radius in studs. The size number is divided by the host's scale, so a germ
-- looks small again in every new host.
function Formulas.radius(size, scale)
	return Config.RadiusPerRootSize * math.sqrt(math.max(size, 0) / (scale or 1))
end

-- Swim speed in studs per second: bigger germs are slower. mult = 1 + bonuses.
function Formulas.speed(size, scale, mult)
	local visual = math.max(size / (scale or 1), 1)
	local s = Config.BaseSpeed * visual ^ -Config.SpeedSizeExponent
	return clamp(s, Config.MinSpeed, Config.MaxSpeed) * (mult or 1)
end

-- Can a germ of eaterSize swallow a germ of preySize? (ratio: Black Hole Mouth lowers it)
function Formulas.canEat(eaterSize, preySize, ratio)
	return eaterSize >= preySize * (ratio or Config.EatRatio)
end

-- Are two germs close enough in size to fight instead?
function Formulas.isFight(a, b)
	return not Formulas.canEat(a, b) and not Formulas.canEat(b, a)
end

-- Is the prey's centre deep enough inside the eater to be swallowed?
function Formulas.isSwallowed(dist, eaterRadius, preyRadius)
	return dist <= eaterRadius - preyRadius * Config.EatOverlap
end

-- What the eater gains and what bursts out as pellets.
function Formulas.eatSplit(preySize)
	local keep = preySize * Config.EatKeepShare
	return keep, preySize - keep
end

-- Fight damage dealt by attacker to defender over dt (in size points).
-- attacker: { size, bite, thorns, mult, pierce }  defender: { size, armor }
function Formulas.fightDamage(attacker, defender, dt)
	local share = Config.FightDamagePerSecond * (1 + (attacker.bite or 0)) + (attacker.thorns or 0)
	local armor = math.max(0, (defender.armor or 0) - (attacker.pierce or 0))
	share = share * (1 - math.min(armor, 0.8)) * (attacker.mult or 1)
	return defender.size * share * dt
end

-- Damage a germ deals to an immune boss while touching it.
function Formulas.bossDamage(attackerSize, bite, dt)
	return attackerSize * Config.Immune.PlayerDamage * (1 + (bite or 0)) * dt
end

-- Zones ----------------------------------------------------------------------------------

local function layoutOf(layout)
	return layout or Formulas.hostLayout(1)
end

-- Which zone (1 = outer ring) a distance from the centre is in.
function Formulas.zoneAt(dist, layout)
	local zones = layoutOf(layout).zones
	for i = #zones, 1, -1 do
		if dist <= zones[i].Outer then
			return i
		end
	end
	return 1
end

function Formulas.zoneMinSize(zone, layout)
	layout = layoutOf(layout)
	return layout.zones[zone].MinShare * layout.sneeze
end

function Formulas.zoneMaxSize(zone, layout)
	layout = layoutOf(layout)
	local share = layout.zones[zone].MaxShare
	if not share then
		return math.huge
	end
	return share * layout.sneeze
end

-- The deepest zone a germ of this size may enter.
function Formulas.deepestZone(size, layout)
	layout = layoutOf(layout)
	local deepest = 1
	for i = 1, #layout.zones do
		if size >= Formulas.zoneMinSize(i, layout) then
			deepest = i
		end
	end
	return deepest
end

-- The outermost zone a germ of this size may use (1 unless it is too big for zone 1).
function Formulas.shallowestZone(size, layout)
	layout = layoutOf(layout)
	if #layout.zones > 1 and size > Formulas.zoneMaxSize(1, layout) then
		return 2
	end
	return 1
end

-- The band of distances from the centre a germ of this size may use (ignoring its radius).
-- Too small for an inner zone: kept outside it. Too big for zone 1: kept inside zone 2.
function Formulas.allowedRange(size, layout, radiusOverride)
	layout = layoutOf(layout)
	local zones = layout.zones
	local deepest = Formulas.deepestZone(size, layout)
	local minDist = 0
	if deepest < #zones then
		minDist = zones[deepest + 1].Outer
	end
	local maxDist = radiusOverride or layout.radius
	if Formulas.shallowestZone(size, layout) == 2 then
		maxDist = math.min(maxDist, zones[2].Outer)
	end
	return math.min(minDist, maxDist), maxDist
end

-- Keeps a germ inside the zones it is allowed in. Returns the corrected distance from the centre.
-- wall: the current outer wall (it moves in during a Medicine drop or Arena sudden death).
function Formulas.clampDistance(dist, size, radius, layout, wall)
	local minDist, maxDist = Formulas.allowedRange(size, layout, wall)
	maxDist = math.max(0, maxDist - radius)
	if minDist > 0 then
		minDist = minDist + radius
	end
	if minDist > maxDist then
		minDist = maxDist
	end
	return clamp(dist, minDist, maxDist)
end

-- Growth, respawn, DNA ---------------------------------------------------------------------

-- Size after being eaten.
function Formulas.respawnSize(sizeAtDeath, share, startSize)
	return math.max(startSize or Config.StartSize, math.floor(sizeAtDeath * (share or Config.RespawnShare)))
end

-- Food and eat gains grow +25% per sneeze, forever.
function Formulas.growthMult(sneezes)
	return 1 + Config.SneezeGrowthBonus * math.min(sneezes or 0, Config.SneezeBonusCap)
end

-- What a build may use in a host (see Config.SlotsPerHost)
function Formulas.hostLimits(host)
	local n = #Config.SlotsPerHost
	host = math.max(1, math.min(host or 1, n))
	return {
		slots = Config.SlotsPerHost[host],
		levelCap = Config.LevelCapPerHost[host],
		fusions = host >= Config.FusionHost,
		dnaCap = Config.DnaCapPerHost[host],
	}
end

-- "12:34" or "1:02:03"
function Formulas.formatTime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local h, m, s = seconds // 3600, (seconds // 60) % 60, seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- Repeated feeding from the same player gives less each time (anti-boosting).
function Formulas.feedMult(timesRecently)
	return Config.FeedRepeatMult ^ (timesRecently or 0)
end

-- Bonus DNA share carried by the crowned germ.
function Formulas.bountyShare(secondsCrowned)
	return math.min(Config.BountyMaxShare, Config.BountyStartShare + Config.BountyPerMinute * (secondsCrowned / 60))
end

-- DNA for swallowing a germ. DNA is counted in host-1 units: sizes are divided by the scale.
function Formulas.killDna(preySize, opts)
	opts = opts or {}
	local dna = preySize / (opts.scale or 1) * Config.DnaKillShare
	if opts.crowned then
		dna = dna + preySize / (opts.scale or 1) * Formulas.bountyShare(opts.crownedSeconds or 0)
	end
	if opts.revenge then
		dna = dna * Config.RevengeDnaMult
	end
	dna = dna * Formulas.feedMult(opts.recentFeeds) * (opts.mult or 1)
	return math.floor(dna + 0.5)
end

-- Size lost per second by big germs.
function Formulas.decay(size, dt, layout)
	layout = layoutOf(layout)
	local start = Config.DecayStartShare * layout.sneeze
	if size <= start then
		return 0
	end
	return (size - start) * Config.DecayPerSecond * dt
end

-- Mutations ------------------------------------------------------------------------------------

-- DNA cost of buying level `level` of a mutation.
function Formulas.mutationCost(id, level)
	local m = Config.Mutations[id]
	return math.floor(m.Cost * level ^ 1.6 + 0.5)
end

-- The value of one stat of a mutation at a level: { base, perLevel } or a plain number.
function Formulas.mutationStat(id, stat, level)
	local m = Config.Mutations[id]
	local v = m and m[stat]
	if v == nil or (level or 0) <= 0 then
		return 0
	end
	if type(v) == "number" then
		return v
	end
	return v[1] + v[2] * (level - 1)
end

-- In the Arena, mutation levels are capped by floor.
function Formulas.arenaLevelCap(floor)
	local cap = 1
	for _, step in ipairs(Config.Arena.LevelCaps) do
		if floor >= step[1] then
			cap = step[2]
		end
	end
	return cap
end

function Formulas.arenaRank(floor)
	local rank = Config.Arena.Ranks[1]
	for _, r in ipairs(Config.Arena.Ranks) do
		if floor >= r.From then
			rank = r
		end
	end
	return rank.Name
end

function Formulas.arenaCheckpoint(floor)
	local every = Config.Arena.CheckpointEvery
	return math.max(1, math.floor(floor / every) * every)
end

-- How many modifiers a floor rolls
function Formulas.arenaModifierCount(floor)
	if floor >= 50 then
		return 3
	elseif floor >= 25 then
		return 2
	end
	return 1
end

-- Season number and seconds left, from a unix time
function Formulas.season(unixTime)
	local length = Config.Arena.SeasonDays * 86400
	local since = unixTime - Config.Arena.SeasonStart
	local index = math.floor(since / length) + 1
	local left = length - (since % length)
	return index, left
end

-- Camera and text ----------------------------------------------------------------------------

-- Camera height above the dish for a germ (or group of cells) with this drawn radius.
function Formulas.cameraHeight(radius)
	local c = Config.Camera
	return math.min(c.MaxHeight, c.BaseHeight + radius * c.PerRadius)
end

-- Short number for the HUD: 1250 -> 1.25K
function Formulas.formatNumber(n)
	n = math.floor(n + 0.5)
	local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
	for _, u in ipairs(units) do
		if n >= u[1] then
			local v = n / u[1]
			if v >= 100 then
				return string.format("%d%s", math.floor(v), u[2])
			elseif v >= 10 then
				return string.format("%.1f%s", math.floor(v * 10) / 10, u[2])
			end
			return string.format("%.2f%s", math.floor(v * 100) / 100, u[2])
		end
	end
	return tostring(n)
end

-- Today's day number (UTC) for daily quests and streaks
function Formulas.dayNumber(unixTime)
	return math.floor(unixTime / 86400)
end

return Formulas
