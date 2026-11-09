-- Starts every part of the game in the right order.
local Services = script.Parent.Services
local Net = require(Services.Net) -- creates the remotes first
local DataService = require(Services.DataService)
local World = require(Services.World)
local DishService = require(Services.DishService)
local HazardService = require(Services.HazardService)
local ImmuneService = require(Services.ImmuneService)
local BotService = require(Services.BotService)
local PlayerService = require(Services.PlayerService)
local LabService = require(Services.LabService)
local ShopService = require(Services.ShopService)
local ArenaService = require(Services.ArenaService)
local QuestService = require(Services.QuestService)
local DevService = require(Services.DevService)
local FeedbackService = require(Services.FeedbackService)

local _ = Net
BotService.playerCount = DishService.playerCount
DishService.onRemoved(BotService.dishRemoved)
World.hooks.bossDefeated = ImmuneService.onBossDefeated
ShopService.startFever = ImmuneService.startFever
ShopService.immuneStrike = function(dish, target)
	ImmuneService.spawnWhitey(dish, { hunt = target })
end

World.start()
DataService.start()
ArenaService.start() -- before the first dish opens (it sets the dish hooks)
DishService.start()
HazardService.start()
ImmuneService.start()
DevService.start()
ShopService.start()
LabService.start()
QuestService.start()
PlayerService.start()
BotService.start()
FeedbackService.start()

print("[Achoo!] Server ready")
