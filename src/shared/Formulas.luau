-- Pure maths for the game: no Roblox objects, so tools/test-formulas.js can test it.
-- Keep this file plain Lua (no types, no +=).
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
	return Config.Hosts[index or Config.HostIndex]
end

-- Drawn radius in studs. The size number is divided by the host's scale, so a germ
-- looks small again in every new host.
function Formulas.radius(size, scale)
	scale = scale or Formulas.host().Scale
	return Config.RadiusPerRootSize * math.sqrt(math.max(size, 0) / scale)
end

-- Swim speed in studs per second: bigger germs are slower. mult = 1 + mutation bonuses.
function Formulas.speed(size, scale, mult)
	scale = scale or Formulas.host().Scale
	local visual = math.max(size / scale, 1)
	local s = Config.BaseSpeed * visual ^ -Config.SpeedSizeExponent
	return clamp(s, Config.MinSpeed, Config.MaxSpeed) * (mult or 1)
end

-- Can a germ of eaterSize swallow a germ of preySize?
function Formulas.canEat(eaterSize, preySize)
	return eaterSize >= preySize * Config.EatRatio
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

-- Fight damage per second dealt by attacker to defender (in size points).
-- attacker/defender: { size, bite, thorns, armor, mult } (mutation numbers, 0 when missing).
-- Spikes (thorns) hurt whoever you touch; mult lets bots go easy on new players.
function Formulas.fightDamage(attacker, defender, dt)
	local share = Config.FightDamagePerSecond * (1 + (attacker.bite or 0)) + (attacker.thorns or 0)
	share = share * (1 - (defender.armor or 0)) * (attacker.mult or 1)
	return defender.size * share * dt
end

-- Which zone (1 = outer ring) a distance from the centre is in.
function Formulas.zoneAt(dist)
	local zones = Config.Zones
	for i = #zones, 1, -1 do
		if dist <= zones[i].Outer then
			return i
		end
	end
	return 1
end

function Formulas.zoneMinSize(zone, hostIndex)
	return Config.Zones[zone].MinShare * Formulas.host(hostIndex).SneezeSize
end

function Formulas.zoneMaxSize(zone, hostIndex)
	local share = Config.Zones[zone].MaxShare
	if not share then
		return math.huge
	end
	return share * Formulas.host(hostIndex).SneezeSize
end

-- The deepest zone a germ of this size may enter.
function Formulas.deepestZone(size, hostIndex)
	local deepest = 1
	for i = 1, #Config.Zones do
		if size >= Formulas.zoneMinSize(i, hostIndex) then
			deepest = i
		end
	end
	return deepest
end

-- The band of distances from the centre a germ of this size may use (ignoring its radius).
-- Too small for an inner zone: kept outside it. Too big for zone 1: kept inside zone 2.
function Formulas.allowedRange(size, hostIndex)
	local zones = Config.Zones
	local deepest = Formulas.deepestZone(size, hostIndex)
	local minDist = 0
	if deepest < #zones then
		minDist = zones[deepest + 1].Outer
	end
	local maxDist = Config.ArenaRadius
	if size > Formulas.zoneMaxSize(1, hostIndex) and #zones > 1 then
		maxDist = zones[2].Outer
	end
	return math.min(minDist, maxDist), maxDist
end

-- The outermost zone a germ of this size may use (1 unless it is too big for zone 1).
function Formulas.shallowestZone(size, hostIndex)
	if size > Formulas.zoneMaxSize(1, hostIndex) and #Config.Zones > 1 then
		return 2
	end
	return 1
end

-- Keeps a germ inside the zones it is allowed in. Returns the corrected distance from the centre.
function Formulas.clampDistance(dist, size, radius, hostIndex)
	local minDist, maxDist = Formulas.allowedRange(size, hostIndex)
	maxDist = math.min(maxDist, Config.ArenaRadius - radius)
	if minDist > 0 then
		minDist = minDist + radius
	end
	if minDist > maxDist then
		minDist = maxDist
	end
	return clamp(dist, minDist, maxDist)
end

-- Size after being eaten.
function Formulas.respawnSize(sizeAtDeath, share)
	return math.max(Config.StartSize, math.floor(sizeAtDeath * (share or Config.RespawnShare)))
end

-- Repeated feeding from the same player gives less each time (anti-boosting).
function Formulas.feedMult(timesRecently)
	return Config.FeedRepeatMult ^ (timesRecently or 0)
end

-- Bonus DNA share carried by the crowned germ.
function Formulas.bountyShare(secondsCrowned)
	return math.min(Config.BountyMaxShare, Config.BountyStartShare + Config.BountyPerMinute * (secondsCrowned / 60))
end

-- DNA for swallowing a germ.
function Formulas.killDna(preySize, opts)
	opts = opts or {}
	local dna = preySize * Config.DnaKillShare
	if opts.crowned then
		dna = dna + preySize * Formulas.bountyShare(opts.crownedSeconds or 0)
	end
	if opts.revenge then
		dna = dna * Config.RevengeDnaMult
	end
	dna = dna * Formulas.feedMult(opts.recentFeeds)
	return math.floor(dna + 0.5)
end

-- Size lost per second by big germs.
function Formulas.decay(size, dt, hostIndex)
	local start = Config.DecayStartShare * Formulas.host(hostIndex).SneezeSize
	if size <= start then
		return 0
	end
	return (size - start) * Config.DecayPerSecond * dt
end

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

return Formulas
