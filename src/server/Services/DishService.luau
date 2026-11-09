-- Opens and closes dishes (one per host in use, one per Arena floor in use), builds their look,
-- moves players between them and runs each dish's once-a-second events.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Net = require(script.Parent.Net)
local World = require(script.Parent.World)
local MapBuilder = require(script.Parent.MapBuilder)

local DishService = {}

local MAX_PLAYERS = 12 -- players per host dish before a second copy opens
local EMPTY_SECONDS = 45 -- a dish nobody has played in for this long is closed

local folders = {} -- [dish] = map folder
local emptySince = {} -- [dish] = time
local perSecond = {} -- functions(dish, now) called once a second for every dish
DishService.hooks = {
	created = function(dish) end, -- ArenaService rolls modifiers here
}
local onRemoved = {}
function DishService.onRemoved(fn)
	table.insert(onRemoved, fn)
end

function DishService.onSecond(fn)
	table.insert(perSecond, fn)
end

local onTick = {} -- functions(dish, dt, now) called every simulation tick
function DishService.onTick(fn)
	table.insert(onTick, fn)
end

local onEnter = {} -- functions(player, dish) called when a player arrives in a dish
function DishService.onEnter(fn)
	table.insert(onEnter, fn)
end

function DishService.playerCount(dish)
	local n = 0
	for _, germ in World.dishGerms(dish) do
		if germ.player then
			n += 1
		end
	end
	-- dead players waiting to respawn still belong to the dish
	for _, germ in World.allGerms() do
		if germ.player and not germ.alive and germ.dish == dish then
			n += 1
		end
	end
	return n
end

local function open(kind, index, layout)
	local dish = World.newDish(kind, index, layout)
	dish.openedAt = World.now()
	dish.timers = {}
	DishService.hooks.created(dish)
	folders[dish] = MapBuilder.buildDish(dish)
	return dish
end

function DishService.close(dish)
	for _, fn in onRemoved do
		pcall(fn, dish)
	end
	for _, germ in World.dishGerms(dish) do
		World.removeGerm(germ)
	end
	World.removeDish(dish)
	if folders[dish] then
		folders[dish]:Destroy()
		folders[dish] = nil
	end
	emptySince[dish] = nil
end

-- A dish for this host with room for one more player
function DishService.hostDish(host)
	host = math.clamp(host or 1, 1, #Config.Hosts)
	local best, bestCount = nil, -1
	for _, dish in World.dishes() do
		if dish.kind == "host" and dish.host == host then
			local n = DishService.playerCount(dish)
			if n < MAX_PLAYERS and n > bestCount then
				best, bestCount = dish, n
			end
		end
	end
	return best or open("host", host, Formulas.hostLayout(host))
end

-- A dish for this Arena floor with room. Its modifiers are rolled when it opens
-- (the Tiny Dish modifier makes it half the size).
DishService.rollModifiers = function(floor)
	return {}
end
function DishService.arenaDish(floor)
	for _, dish in World.dishes() do
		if dish.kind == "arena" and dish.floor == floor and DishService.playerCount(dish) < Config.Arena.PlayersPerFloor then
			return dish
		end
	end
	local mods = DishService.rollModifiers(floor)
	local radius = Config.Arena.Radius
	if table.find(mods, "TinyDish") then
		radius *= 0.5
	end
	local layout = Formulas.arenaLayout(radius)
	local dish = World.newDish("arena", floor, layout)
	dish.modifiers = mods
	dish.openedAt = World.now()
	dish.timers = {}
	DishService.hooks.created(dish)
	folders[dish] = MapBuilder.buildDish(dish)
	return dish
end

-- What the client needs to know about a dish
function DishService.info(dish)
	local zones = {}
	for i, z in dish.layout.zones do
		local name = "Petri Floor"
		if dish.kind == "host" then
			name = Config.Hosts[dish.host].Zones[i]
		end
		zones[i] = { name = name, outer = z.Outer, min = Formulas.zoneMinSize(i, dish.layout), max = z.MaxShare and Formulas.zoneMaxSize(i, dish.layout) or nil }
	end
	local info = {
		id = dish.id,
		kind = dish.kind,
		host = dish.host,
		floor = dish.floor,
		scale = dish.scale,
		radius = dish.layout.radius,
		wall = dish.wall,
		sneeze = dish.layout.sneeze,
		cx = dish.cx,
		cz = dish.cz,
		zones = zones,
		modifiers = dish.modifiers or {},
	}
	if dish.kind == "host" then
		local h = Config.Hosts[dish.host]
		info.name = h.Name
		info.hazard = h.HazardText
		info.outside = h.Outside
	else
		info.name = "The Infinite Petri: Floor " .. dish.floor
		info.outside = { 15, 20, 35 }
	end
	return info
end

-- Puts a player's germ into a dish and sends them everything they need to draw it.
function DishService.enter(germ, dish, size, x, z)
	local player = germ.player
	World.spawnGerm(germ, dish, size, x, z)
	if player then
		World.setViewer(player, dish)
		Net.DishInfo:FireClient(player, DishService.info(dish))
		local info, food = World.fullState(dish)
		Net.CellInfo:FireClient(player, info)
		Net.FoodSync:FireClient(player, food)
		emptySince[dish] = nil
		for _, fn in onEnter do
			task.spawn(fn, player, dish)
		end
	end
end

-- Takes a player's germ out of the world without closing anything (leaving the game)
function DishService.leave(germ)
	if germ.player then
		World.setViewer(germ.player, nil)
	end
	World.removeGerm(germ)
end

function DishService.start()
	MapBuilder.setup()
	World.hooks.dishTick = function(dish, dt)
		local now = World.now()
		for _, fn in onTick do
			fn(dish, dt, now)
		end
	end
	DishService.hostDish(1) -- host 1 is always open so the first player sees bots straight away
	task.spawn(function()
		while true do
			task.wait(1)
			local now = World.now()
			for _, dish in World.dishes() do
				for _, fn in perSecond do
					local ok, err = pcall(fn, dish, now)
					if not ok then
						warn("[Dish] " .. tostring(err))
					end
				end
				-- close dishes nobody plays in (keep one host 1 dish)
				if DishService.playerCount(dish) == 0 then
					emptySince[dish] = emptySince[dish] or now
					local keep = false
					if dish.kind == "host" and dish.host == 1 then
						keep = true
						for _, other in World.dishes() do
							if other ~= dish and other.kind == "host" and other.host == 1 and other.id < dish.id then
								keep = false
							end
						end
					end
					if not keep and now - emptySince[dish] > EMPTY_SECONDS then
						DishService.close(dish)
					end
				else
					emptySince[dish] = nil
				end
			end
		end
	end)

	-- golden food in every host dish
	DishService.onSecond(function(dish, now)
		if dish.kind ~= "host" then
			return
		end
		dish.timers.golden = dish.timers.golden or (now + Config.GoldenEverySeconds)
		if now >= dish.timers.golden then
			dish.timers.golden = now + Config.GoldenEverySeconds
			local zone = World.spawnGolden(dish)
			World.fireDish(dish, Net.Announce, "✨ Golden food appeared in the " .. Config.Hosts[dish.host].Zones[zone] .. "!")
		end
	end)
end

return DishService
