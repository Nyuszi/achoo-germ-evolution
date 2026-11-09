-- A tiny event bus so services can react to game events without knowing each other.
-- Events used: AteGerm(player, victimGerm, info), AteFood(player, count), Golden(player),
-- Boss(player, kind), Revenge(player), Dash(player), Zone(player, zone), Fever(player),
-- Sneeze(player, data), ArenaFloor(player, floor)
local Bus = {}

local listeners = {}

function Bus.on(name, fn)
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], fn)
end

function Bus.fire(name, ...)
	for _, fn in listeners[name] or {} do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[Bus] " .. name .. ": " .. tostring(err))
		end
	end
end

return Bus
