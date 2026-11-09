-- All game settings live here. Change a number, save, and Rojo sends it to Studio.
-- Keep this file plain Lua (no types, no +=) so tools/test-formulas.js can load it.
local Config = {}

Config.DataStoreName = "AchooPlayers_v1"
Config.AutosaveSeconds = 120

-- Hosts -----------------------------------------------------------------------
-- Each host is 10x bigger than the last. The size NUMBER keeps growing, but the germ is
-- drawn at size / Scale, so it looks small again in every new host (and stays cheap to render).
Config.Hosts = {
	{ Name = "Nibbles the Hamster", Scale = 1, SneezeSize = 2500 },
	{ Name = "Big Barkley the Dog", Scale = 10, SneezeSize = 25000 },
	{ Name = "Grandma Trunk the Elephant", Scale = 100, SneezeSize = 250000 },
	{ Name = "Ember the Dragon", Scale = 1000, SneezeSize = 2500000 },
	{ Name = "The Deep Kraken", Scale = 10000, SneezeSize = 25000000 },
	{ Name = "Zorb the Alien Titan", Scale = 100000, SneezeSize = 250000000 },
}
Config.HostIndex = 1 -- which host this place is (each host is its own place)

-- The host's insides are a big round dish seen from above. Zones are rings:
-- zone 1 is the outer ring, zone 4 (the heart) is the middle.
Config.ArenaRadius = 500
Config.Zones = {
	-- Outer = outer edge distance from the centre, MinShare = share of SneezeSize needed to enter,
	-- MaxShare = above this the host coughs you inward (only zone 1 has one).
	{ Name = "Nose Cave", Outer = 500, MinShare = 0, MaxShare = 0.3, FoodValue = 2, FoodCount = 320 },
	{ Name = "Cheek Pouch", Outer = 350, MinShare = 0.1, FoodValue = 4, FoodCount = 160 },
	{ Name = "Tummy", Outer = 220, MinShare = 0.3, FoodValue = 7, FoodCount = 90 },
	{ Name = "Heart", Outer = 110, MinShare = 0.6, FoodValue = 12, FoodCount = 45 },
}

-- Germ size and movement ------------------------------------------------------
Config.StartSize = 10
Config.MinSize = 5
Config.RadiusPerRootSize = 0.6 -- drawn radius = 0.6 * sqrt(size / Scale): size 10 -> 1.9 studs, 2500 -> 30
Config.BaseSpeed = 40 -- studs per second, slowed by size (see Formulas.speed)
Config.SpeedSizeExponent = 0.15
Config.MinSpeed = 9
Config.MaxSpeed = 34
-- Big germs slowly shrink so nobody sits at the top forever (share of size lost per second)
Config.DecayStartShare = 0.3 -- of SneezeSize
Config.DecayPerSecond = 0.002
-- Phase 1 has no sneeze yet, so germs stop growing at the sneeze size (bots stop earlier)
Config.MaxSizeShare = 1

-- Eating ------------------------------------------------------------------------
Config.EatRatio = 1.25 -- you can swallow a germ 25% smaller than you
Config.EatOverlap = 0.4 -- the prey's centre must be this deep inside you (share of its radius)
Config.EatKeepShare = 0.4 -- you gain 40% of a swallowed germ's size
Config.BurstPellets = 8 -- the rest bursts into food pellets around you
Config.RespawnShare = 0.5 -- eaten germs come back with 50% of their size
Config.RespawnSeconds = 2.5

-- Same-size fights (sizes within 1/EatRatio .. EatRatio): touching germs hurt each other.
Config.FightDamagePerSecond = 0.03 -- share of the defender's size lost per second
Config.FightStealShare = 0.5 -- the attacker gains half of the damage dealt

-- Moves -------------------------------------------------------------------------
Config.Dash = { Cooldown = 4, Duration = 0.3, SpeedMult = 3, CostShare = 0.02, MinSize = 12 }
Config.Split = { Cooldown = 10, MinSize = 40, MergeSeconds = 8, LaunchSpeed = 90, MaxCells = 2 }

-- Fairness ----------------------------------------------------------------------
Config.SpawnBubbleRadius = 26
Config.SpawnBubbleSeconds = 20 -- protection inside the bubble runs out after this long
Config.SpawnShieldSeconds = 5
Config.QuarantineMinutes = 10 -- brand new players cannot be eaten (and cannot eat players)
Config.RevengeSeconds = 60
Config.RevengeDnaMult = 2
Config.FeedWindowSeconds = 300 -- eating the same player again within 5 min gives less
Config.FeedRepeatMult = 0.5

-- DNA and the crown -------------------------------------------------------------
Config.DnaPerFood = 0.2 -- per point of food value
Config.DnaKillShare = 0.1 -- 10% of the swallowed germ's size
Config.BountyStartShare = 0.05 -- the crowned (biggest) germ carries 5% of its size as bonus DNA
Config.BountyPerMinute = 0.01
Config.BountyMaxShare = 0.25

-- Golden food -------------------------------------------------------------------
Config.GoldenEverySeconds = 90
Config.GoldenShare = 0.05 -- of SneezeSize

-- Mutations (Phase 1: four to try). Cost is in DNA.
Config.Mutations = {
	Jaws = { Slot = "Front", Cost = 50, Name = "Jaws", Text = "Bite harder in same-size fights (+60% damage)", Bite = 0.6 },
	Flagella = { Slot = "Back", Cost = 50, Name = "Flagella Tail", Text = "Swim 15% faster", Speed = 0.15 },
	Spikes = { Slot = "Sides", Cost = 120, Name = "Spikes", Text = "Hurt any germ that touches you", Thorns = 0.02 },
	Shell = { Slot = "Sides", Cost = 120, Name = "Shell Plates", Text = "Take 40% less fight damage, 8% slower", Armor = 0.4, Speed = -0.08 },
}
Config.MutationOrder = { "Jaws", "Flagella", "Spikes", "Shell" }

-- Bots ----------------------------------------------------------------------------
-- Bots keep the dish busy while the game is new. They never show up in the Roblox player list.
Config.Bots = {
	TargetGerms = 12, -- players + bots
	MaxSizeShare = 0.8, -- bots never get bigger than 80% of the sneeze size
	ThinkSeconds = 0.25,
	RespawnMin = 3,
	RespawnMax = 8,
	HunterGiveUp = 8,
	-- Size mix for new bots (share of bots, min size, max size)
	SizeMix = {
		{ 0.4, 5, 9 },
		{ 0.4, 10, 60 },
		{ 0.15, 60, 400 },
		{ 0.05, 400, 900 },
	},
	-- Bots go easy on brand new players: less fight damage and they do not hunt them
	NewPlayerMinutes = 5,
	NewPlayerDamageMult = 0.5,
}

-- Germ colours (players get one at random until the Germ Editor arrives)
Config.GermColors = {
	Color3.fromRGB(120, 220, 120), Color3.fromRGB(110, 200, 255), Color3.fromRGB(255, 150, 200),
	Color3.fromRGB(255, 210, 90), Color3.fromRGB(190, 140, 255), Color3.fromRGB(255, 140, 100),
	Color3.fromRGB(100, 230, 210), Color3.fromRGB(240, 120, 140), Color3.fromRGB(170, 230, 90),
}

-- Camera --------------------------------------------------------------------------
Config.Camera = { BaseHeight = 40, PerRadius = 9, MaxHeight = 900, Smooth = 4 }

-- Network ------------------------------------------------------------------------
Config.TickRate = 20 -- server simulation steps per second
Config.SnapshotEvery = 2 -- send positions every 2 ticks (10 per second)
Config.GridCell = 32

return Config
