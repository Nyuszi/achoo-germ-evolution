-- Starts every part of the game in the right order.
local Services = script.Parent.Services
local Net = require(Services.Net) -- creates the remotes first
local DataService = require(Services.DataService)
local World = require(Services.World)
local MapBuilder = require(Services.MapBuilder)
local BotService = require(Services.BotService)
local PlayerService = require(Services.PlayerService)
local FeedbackService = require(Services.FeedbackService)

local _ = Net
World.start()
MapBuilder.build(World.bubbles)
DataService.start()
PlayerService.start()
BotService.start()
FeedbackService.start()

print("[Achoo!] Server ready")
