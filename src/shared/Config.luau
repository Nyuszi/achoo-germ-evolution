-- All game settings live here. Change a number, save, and Rojo sends it to Studio.
-- Keep this file plain Lua (no types, no +=) so tools/test-formulas.js can load it.
local Config = {}

Config.DataStoreName = "AchooPlayers_v1"
Config.AutosaveSeconds = 120

-- The dish ----------------------------------------------------------------------------
-- Every host's insides are a round dish seen from above with 4 ring-shaped zones.
-- The geometry is the same in every host; sizes are multiplied by the host's Scale.
Config.DishRadius = 600
Config.DishSpacing = 2400 -- dishes (hosts and Arena floors) sit this far apart in the world
Config.Zones = {
	-- Outer = outer edge distance from the centre, MinShare = share of SneezeSize needed to enter,
	-- MaxShare = above this the host coughs you inward (only zone 1 has one).
	-- FoodValue is multiplied by the host's Scale.
	-- Inner zones hold bigger germs, so they get much more room than a plain bullseye would
	-- (area per germ: Heart 4.7x and Tummy 2.2x what they had at 110/220).
	{ Outer = 600, MinShare = 0, MaxShare = 0.3, FoodValue = 1.2, FoodCount = 720 },
	{ Outer = 480, MinShare = 0.1, FoodValue = 2.4, FoodCount = 400 },
	{ Outer = 370, MinShare = 0.3, FoodValue = 4.5, FoodCount = 220 },
	{ Outer = 240, MinShare = 0.6, FoodValue = 8, FoodCount = 160 },
}
-- Thorn bushes: hiding spots in every host. A germ smaller than FitShare of a bush's radius
-- slips inside and can't be seen or eaten; bigger ones are pushed out and lose Damage of their
-- size per second while they touch the thorns. Radius in studs (the same in every host).
Config.Hideouts = { PerZone = { 5, 4, 3, 2 }, Radius = { 14, 22, 30, 38 }, FitShare = 0.55, Damage = 0.04 }
Config.NerveRadius = 13 -- the Sneeze Nerve in the middle of every host

-- Hosts --------------------------------------------------------------------------------
-- Each host is 10x bigger than the last. The size NUMBER keeps growing, but the germ is drawn at
-- size / Scale, so it looks small again in every new host (and stays cheap to render).
-- Hazard: the host's own mechanic (see HazardService).
Config.Hosts = {
	{
		Name = "Nibbles the Hamster", Scale = 1, SneezeSize = 2500, Core = "Blob",
		Zones = { "Nose Cave", "Cheek Pouch", "Tummy", "Heart" },
		Hazard = "Whiskers", HazardText = "Whisker sweep! Big whiskers knock germs back",
		Floors = { { 255, 196, 196 }, { 255, 220, 180 }, { 250, 200, 140 }, { 220, 90, 100 } },
		Membranes = { { 255, 120, 150 }, { 255, 170, 90 }, { 230, 120, 60 }, { 255, 60, 80 } },
		Wall = { 200, 110, 120 }, Outside = { 60, 20, 30 },
	},
	{
		Name = "Big Barkley the Dog", Scale = 10, SneezeSize = 25000, Core = "Rod",
		Zones = { "Snout", "Drool Lake", "Stomach", "Brain" },
		Hazard = "Drool", HazardText = "Drool wave! Everything slides one way",
		Floors = { { 215, 170, 130 }, { 170, 210, 235 }, { 230, 175, 150 }, { 240, 170, 200 } },
		Membranes = { { 160, 110, 70 }, { 80, 160, 220 }, { 210, 110, 90 }, { 230, 90, 160 } },
		Wall = { 150, 100, 70 }, Outside = { 45, 30, 20 },
	},
	{
		Name = "Grandma Trunk the Elephant", Scale = 100, SneezeSize = 250000, Core = "Spiral",
		Zones = { "Trunk Tunnel", "Peanut Belly", "Bloodstream", "Tusk Core" },
		Hazard = "Suction", HazardText = "Trunk suction! Everyone is pulled to the middle",
		Floors = { { 190, 190, 200 }, { 225, 200, 150 }, { 220, 90, 90 }, { 245, 240, 225 } },
		Membranes = { { 120, 120, 140 }, { 190, 150, 80 }, { 170, 30, 40 }, { 210, 200, 170 } },
		Wall = { 130, 130, 145 }, Outside = { 30, 30, 40 },
	},
	{
		Name = "Ember the Dragon", Scale = 1000, SneezeSize = 2500000, Core = "Star",
		Zones = { "Smoke Nostrils", "Fire Belly", "Gold Vault", "Flame Heart" },
		Hazard = "FireBurp", HazardText = "Fire burp! The outer ring is burning, get inside",
		Floors = { { 120, 110, 110 }, { 240, 130, 60 }, { 245, 205, 90 }, { 255, 90, 40 } },
		Membranes = { { 80, 70, 70 }, { 255, 90, 20 }, { 255, 180, 30 }, { 255, 40, 20 } },
		Wall = { 90, 40, 30 }, Outside = { 25, 10, 10 },
	},
	{
		Name = "The Deep Kraken", Scale = 10000, SneezeSize = 25000000, Core = "Jelly",
		Zones = { "Ink Sac", "Tentacle Maze", "Glow Gut", "Abyss Heart" },
		Hazard = "Ink", HazardText = "Ink clouds! Germs inside a cloud are hidden",
		Floors = { { 70, 60, 110 }, { 90, 120, 170 }, { 60, 170, 170 }, { 30, 40, 80 } },
		Membranes = { { 40, 30, 80 }, { 60, 100, 200 }, { 80, 255, 230 }, { 120, 80, 255 } },
		Wall = { 40, 30, 70 }, Outside = { 5, 5, 20 },
	},
	{
		Name = "Zorb the Alien Titan", Scale = 100000, SneezeSize = 250000000, Core = "Crystal",
		Zones = { "Antenna", "Zero-G Gut", "Crystal Brain", "Core Reactor" },
		Hazard = "Warp", HazardText = "Warp holes open! Jump in to teleport",
		Floors = { { 160, 230, 160 }, { 200, 170, 255 }, { 150, 240, 255 }, { 255, 255, 170 } },
		Membranes = { { 80, 255, 120 }, { 170, 90, 255 }, { 80, 220, 255 }, { 255, 240, 60 } },
		Wall = { 70, 140, 90 }, Outside = { 10, 25, 15 },
	},
}

Config.Hazards = {
	-- a whisker sweeps once round the dish and knocks germs sideways. It shows up Warn seconds early;
	-- a germ that is dashing goes straight through it.
	Whiskers = { Every = 22, Warn = 2.5, Duration = 8, Push = 55 },
	Drool = { Every = 25, Duration = 5, Push = 14 }, -- a current pushing everyone one way
	Suction = { Every = 25, Duration = 5, Pull = 12 }, -- pull toward the middle
	FireBurp = { Every = 25, Warn = 3, Duration = 5, DamagePerSecond = 0.05 }, -- zone 1 burns
	Ink = { Clouds = 6, CloudRadius = 45, MoveEvery = 20 }, -- germs inside a cloud are hidden
	Warp = { Holes = 4, HoleRadius = 10, Cooldown = 3 }, -- pairs of holes teleport you
}

-- Germ size and movement ------------------------------------------------------
Config.StartSize = 10 -- multiplied by the host's Scale
Config.MinSize = 5
Config.RadiusPerRootSize = 0.6 -- drawn radius = 0.6 * sqrt(size / Scale): size 10 -> 1.9 studs, 2500 -> 30
Config.BaseSpeed = 40 -- studs per second, slowed by size (see Formulas.speed)
Config.SpeedSizeExponent = 0.15
Config.MinSpeed = 9
Config.MaxSpeed = 34
-- Big germs slowly shrink so nobody sits at the top forever (share of size lost per second)
Config.DecayStartShare = 0.5 -- of SneezeSize
Config.DecayPerSecond = 0.0012
Config.MaxSizeShare = 1.15 -- nobody grows past 115% of the sneeze size (go sneeze!)

-- Eating ------------------------------------------------------------------------
Config.EatRatio = 1.25 -- you can swallow a germ 25% smaller than you
Config.EatOverlap = 0.4 -- the prey's centre must be this deep inside you (share of its radius)
Config.EatKeepShare = 0.4 -- you gain 40% of a swallowed germ's size
-- Big crumbs: a few chunky pellets in every zone, worth ValueMult normal pellets. You can only eat
-- one once you are at least NeedMult times its value (drawn that big), so brand-new germs can't.
-- RefillChance: chance per food refill (about once a second) that an eaten crumb grows back.
Config.BigFood = { Share = 0.025, ValueMult = 10, NeedMult = 2.5, RefillChance = 0.15 }
Config.BurstPellets = 8 -- the rest bursts into food pellets around you
Config.RespawnShare = 0.5 -- eaten germs come back with 50% of their size
Config.VaccineRespawnShare = 0.75 -- with the Vaccine pass
Config.RespawnSeconds = 2.5

-- Same-size fights (sizes within 1/EatRatio .. EatRatio): touching germs hurt each other.
Config.FightDamagePerSecond = 0.03 -- share of the defender's size lost per second
Config.FightStealShare = 0.5 -- the attacker gains half of the damage dealt

-- Moves -------------------------------------------------------------------------
Config.Dash = { Cooldown = 4, Duration = 0.3, SpeedMult = 3, CostShare = 0.02, MinSize = 4 } -- MinSize below StartSize, so a new germ can dash
Config.Split = { Cooldown = 1, MinSize = 40, MergeSeconds = 10, LaunchSpeed = 90, MaxCells = 8 } -- split again and again, up to 8 cells
Config.Spit = { Cooldown = 6, CostShare = 0.01, Speed = 70, Life = 4, SlowMult = 0.6, SlowSeconds = 2 }

-- Fairness ----------------------------------------------------------------------
Config.SpawnBubbleRadius = 26
Config.SpawnBubbleSeconds = 20 -- protection inside the bubble runs out after this long
Config.SpawnShieldSeconds = 5
Config.QuarantineMinutes = 10 -- brand new players cannot be eaten (they can still eat food and bots)
Config.RevengeSeconds = 60
Config.RevengeDnaMult = 2
Config.FeedWindowSeconds = 300 -- eating the same player again within 5 min gives less
Config.FeedRepeatMult = 0.5

-- DNA, the crown and growth bonuses -------------------------------------------------------
Config.DnaPerFood = 0.3 -- per point of food value (before Scale)
Config.DnaKillShare = 0.1 -- 10% of the swallowed germ's size (before Scale)
Config.BountyStartShare = 0.05 -- the crowned (biggest) germ carries 5% of its size as bonus DNA
Config.BountyPerMinute = 0.01
Config.BountyMaxShare = 0.25
Config.SneezeGrowthBonus = 0.25 -- +25% food and eat gains per sneeze, forever
Config.MutantDnaBonus = 0.5 -- +50% DNA per Mutant tier

-- Strains (new runs), item limits and fair play ------------------------------------------
-- A strain is one build: its mutations, fusions, core and which host it has reached.
-- "New Run" starts a fresh strain in host 1 and keeps the old one saved in its slot.
-- Cosmetics, DNA, Germ Points, skills, sneezes and Mutant tiers belong to the player, not the strain.
Config.StrainSlots = 3
Config.StrainNames = { "Strain A", "Strain B", "Strain C" }
Config.StrainSwitchCooldown = 20 -- seconds between New Run / switching
-- What a build can use grows host by host, so the first host stays simple.
-- (Inside each host of every run, also for veterans looping back to host 1.)
Config.SlotsPerHost = { 2, 3, 4, 4, 4, 4 } -- mutation slots you can fill
Config.LevelCapPerHost = { 3, 4, 5, 5, 5, 5 } -- highest mutation level you can buy, and that counts, there
Config.FusionHost = 3 -- fusions work from this host on
-- Your DNA bag: earning DNA by playing stops when it is full (quests and purchases still add).
Config.DnaCapPerHost = { 2000, 5000, 12000, 25000, 50000, 100000 }
Config.MaxQuestPotions = 5 -- free Growth Potions you can stack up (bought ones always count)
-- Bonuses that stack forever are capped so a many-times replayer is fast, not untouchable.
Config.SneezeBonusCap = 12 -- growth bonus counts at most 12 sneezes (+300%)
Config.MutantBonusCap = 4 -- DNA bonus counts at most 4 Mutant tiers (+200%)
-- Rookies (players on their first run) can't be eaten or bitten by veterans (finished a run)
-- inside hosts. Rookies can still eat veterans. The Arena is open PvP for everyone.
Config.RookieGuard = true

-- Golden food -------------------------------------------------------------------
Config.GoldenEverySeconds = 90
Config.GoldenShare = 0.05 -- of SneezeSize

-- Mutations ---------------------------------------------------------------------------
-- Each mutation has 5 levels. Level L costs Cost * L^1.6 DNA (times the host's Scale for
-- the DNA you earn there, see Formulas.mutationCost). Effects grow per level.
-- Active abilities: Front slot = Q, Special slot = E.
Config.MaxMutationLevel = 5
Config.Mutations = {
	Jaws = { Slot = "Front", Cost = 50, Name = "Jaws", Text = "Bite harder in same-size fights", Bite = { 0.4, 0.15 },
		Active = "Chomp", ActiveText = "Chomp: lunge forward with a triple bite", Cooldown = 8 },
	Suction = { Slot = "Front", Cost = 80, Name = "Suction Mouth", Text = "Food is worth more and gets pulled in", Absorb = { 0.15, 0.05 }, Magnet = 8,
		Active = "Vacuum", ActiveText = "Vacuum: pull smaller germs toward you", Cooldown = 12 },
	Drill = { Slot = "Front", Cost = 120, Name = "Drill Nose", Text = "Ignore part of the enemy's armour", Pierce = { 0.3, 0.1 },
		Active = "Pierce", ActiveText = "Pierce: ignore all armour for 3 s", Cooldown = 12 },
	Flagella = { Slot = "Back", Cost = 50, Name = "Flagella Tail", Text = "Swim faster", Speed = { 0.1, 0.03 } },
	Jet = { Slot = "Back", Cost = 90, Name = "Jet Sac", Text = "Dash goes much farther", DashMult = { 0.4, 0.15 } },
	Slime = { Slot = "Back", Cost = 90, Name = "Slime Trail", Text = "Germs chasing you are slowed", Trail = { 0.15, 0.05 } },
	Spikes = { Slot = "Sides", Cost = 120, Name = "Spikes", Text = "Hurt any germ that touches you", Thorns = { 0.015, 0.005 } },
	Toxin = { Slot = "Sides", Cost = 140, Name = "Toxin Glands", Text = "Germs you fight are poisoned", Poison = { 0.01, 0.004 } },
	Shell = { Slot = "Sides", Cost = 120, Name = "Shell Plates", Text = "Take less fight damage, a bit slower", Armor = { 0.3, 0.06 }, Speed = { -0.08, 0 } },
	Camo = { Slot = "Special", Cost = 200, Name = "Camo Skin", Text = "Hard to see while you stand still",
		Active = "Ghost", ActiveText = "Ghost: invisible for 3 s", Cooldown = 20 },
	Magnet = { Slot = "Special", Cost = 200, Name = "Magnet Core", Text = "Pulls food from farther away", Magnet = 14,
		Active = "GravityWell", ActiveText = "Gravity well: pull everything nearby for 2 s", Cooldown = 18 },
	Sneezer = { Slot = "Special", Cost = 250, Name = "Mini Sneeze", Text = "Burst away from danger",
		Active = "Blast", ActiveText = "Blast: knock every germ near you away", Cooldown = 15 },
}
Config.MutationOrder = { "Jaws", "Suction", "Drill", "Flagella", "Jet", "Slime", "Spikes", "Toxin", "Shell", "Camo", "Magnet", "Sneezer" }
Config.Slots = { "Front", "Back", "Sides", "Special" }

-- Fusions: two mutations at level 5 fuse into one combo (it takes both slots' places).
Config.Fusions = {
	Buzzsaw = { Name = "Buzzsaw", Parts = { "Spikes", "Flagella" }, Text = "Spikes spin: triple spike damage while dashing" },
	PlagueTrail = { Name = "Plague Trail", Parts = { "Toxin", "Slime" }, Text = "Your slime trail poisons" },
	BlackHole = { Name = "Black Hole Mouth", Parts = { "Jaws", "Suction" }, Text = "Swallow germs only 15% smaller than you" },
	Ninja = { Name = "Ninja Germ", Parts = { "Camo", "Jet" }, Text = "Dashing makes you invisible for 2 s" },
	Fortress = { Name = "Fortress", Parts = { "Shell", "Spikes" }, Text = "Armour and spikes both doubled" },
	Driller = { Name = "Turbo Drill", Parts = { "Drill", "Jet" }, Text = "Dashing into a germ ignores all armour" },
	Venom = { Name = "Venom Fangs", Parts = { "Jaws", "Toxin" }, Text = "Bites poison twice as hard" },
	Storm = { Name = "Sneeze Storm", Parts = { "Sneezer", "Magnet" }, Text = "Your Blast also pulls food in" },
}
Config.FusionOrder = { "Buzzsaw", "PlagueTrail", "BlackHole", "Ninja", "Fortress", "Driller", "Venom", "Storm" }

-- Cores (body shapes), unlocked by reaching a host
Config.Cores = {
	Blob = { Name = "Blob", Host = 1, Text = "Balanced" },
	Rod = { Name = "Rod", Host = 2, Text = "+15% speed, -10% armour", Speed = 0.15, Armor = -0.1 },
	Spiral = { Name = "Spiral", Host = 3, Text = "Turns faster, dash cooldown -1 s", DashCooldown = -1 },
	Star = { Name = "Star", Host = 4, Text = "Built-in spikes", Thorns = 0.01 },
	Jelly = { Name = "Jelly", Host = 5, Text = "20% less damage while split", SplitArmor = 0.2 },
	Crystal = { Name = "Crystal", Host = 6, Text = "+10% food value, but you glow", Absorb = 0.1 },
}
Config.CoreOrder = { "Blob", "Rod", "Spiral", "Star", "Jelly", "Crystal" }

-- Germ Points: 1 per sneeze, spent on a permanent skill tree
Config.Skills = {
	Hunter = { Name = "Hunter", Text = "+10% DNA from germs per level", Max = 5, Per = 0.1 },
	Glutton = { Name = "Glutton", Text = "+8% food value per level", Max = 5, Per = 0.08 },
	Sprinter = { Name = "Sprinter", Text = "+4% speed per level", Max = 5, Per = 0.04 },
	Dasher = { Name = "Dasher", Text = "-0.4 s dash cooldown per level", Max = 5, Per = 0.4 },
	Survivor = { Name = "Survivor", Text = "+5% size kept when eaten per level", Max = 5, Per = 0.05 },
	Starter = { Name = "Head Start", Text = "Start each host 50% bigger per level", Max = 5, Per = 0.5 },
}
Config.SkillOrder = { "Hunter", "Glutton", "Sprinter", "Dasher", "Survivor", "Starter" }

-- Immune system --------------------------------------------------------------------------
Config.Immune = {
	Whitey = { MinZone = 2, SizeShare = 0.45, HpShare = 3, Speed = 14, RespawnSeconds = 90, DrainPerSecond = 0.06, RewardShare = 0.06 },
	Macrophage = { EverySeconds = 480, FirstAfter = 150, SizeShare = 1.4, HpShare = 6, Speed = 9, DrainPerSecond = 0.1,
		GulpEvery = 12, GulpReach = 1.4, GulpMaxShare = 0.35, RewardShare = 0.5, Lifetime = 240 },
	PlayerDamage = 0.15, -- a touching germ deals 15% of its own size per second to a boss
	MinContribution = 0.05, -- deal at least 5% of a boss's health to share the reward
	-- a germ bigger than an antibody eats it (EatShare of its size, Dna x EatDnaMult); smaller ones get slowed
	Antibodies = { Count = 10, MinZone = 2, Speed = 10, SlowMult = 0.6, SlowSeconds = 3, Dna = 2, EatShare = 0.5, EatDnaMult = 5 },
	Fever = { EverySeconds = 900, FirstAfter = 300, Duration = 90, FoodMult = 2, DamageMult = 1.5, DnaMult = 2 },
	Medicine = { EverySeconds = 1200, FirstAfter = 600, Duration = 60, ShrinkTo = 0.55 },
}

-- Bots ----------------------------------------------------------------------------
-- Bots keep the dish busy while the game is new. They never show up in the Roblox player list.
Config.Bots = {
	TargetGerms = 12, -- players + bots per dish
	MaxSizeShare = 0.8, -- bots never get bigger than 80% of the sneeze size
	ThinkSeconds = 0.25,
	RespawnMin = 3,
	RespawnMax = 8,
	HunterGiveUp = 8,
	SizeMix = { -- share of bots, min size, max size (times Scale)
		{ 0.4, 5, 9 },
		{ 0.4, 10, 60 },
		{ 0.15, 60, 400 },
		{ 0.05, 400, 900 },
	},
	NewPlayerMinutes = 5, -- bots go easy on brand new players
	NewPlayerDamageMult = 0.5,
}

-- Arena: The Infinite Petri ---------------------------------------------------------------
Config.Arena = {
	UnlockMutant = 1, -- reach Mutant I (finish host 6 once)
	Radius = 220,
	StartSize = 100,
	GoalSize = 700,
	WinnersPerFloor = 3,
	FloorSeconds = 240,
	SuddenDeathShrink = 0.5,
	PlayersPerFloor = 12,
	BotFloors = 9, -- bots fill floors 1-9 only
	CheckpointEvery = 10,
	ChampionEvery = 10,
	TokensPerFloor = 5,
	TokensPerKill = 2,
	SeasonDays = 28,
	SeasonStart = 1793577600, -- 2026-11-02 00:00 UTC; seasons are counted from here
	LevelCaps = { { 1, 3 }, { 10, 4 }, { 25, 5 } }, -- from floor N, mutation levels are capped at L
	FusionFloor = 25,
	Ranks = {
		{ Name = "Sniffle", From = 1 },
		{ Name = "Cough", From = 10 },
		{ Name = "Fever", From = 25 },
		{ Name = "Flu", From = 50 },
		{ Name = "Plague", From = 100 },
	},
	Modifiers = {
		LowGravity = { Name = "Low Gravity", Text = "Dashes go twice as far" },
		Fog = { Name = "Fog", Text = "You can only see close by" },
		Fever = { Name = "Fever", Text = "Fight damage +50%, double food" },
		SpikeField = { Name = "Spike Field", Text = "Spikes in the dish hurt everyone" },
		TinyDish = { Name = "Tiny Dish", Text = "The dish is half the size" },
		GoldenRain = { Name = "Golden Rain", Text = "Golden food every 10 seconds" },
		Mirror = { Name = "Mirror", Text = "Controls flip for 5 s every 30 s" },
		MagnetStorm = { Name = "Magnet Storm", Text = "Everyone is pulled to the middle" },
		CloneParty = { Name = "Clone Party", Text = "Everyone starts split in two" },
		GiantWhitey = { Name = "Giant Whitey", Text = "A white blood cell hunts the floor" },
	},
	ModifierOrder = { "LowGravity", "Fog", "Fever", "SpikeField", "TinyDish", "GoldenRain", "Mirror", "MagnetStorm", "CloneParty", "GiantWhitey" },
	-- Arena-only cosmetics, bought with Arena Tokens (never with Robux)
	TokenShop = {
		{ Kind = "Trail", Id = "ArenaFlame", Cost = 60 },
		{ Kind = "Trail", Id = "ArenaLightning", Cost = 120 },
		{ Kind = "SneezeFx", Id = "Galaxy", Cost = 150 },
		{ Kind = "Hat", Id = "Laurel", Cost = 200 },
		{ Kind = "Body", Id = "Champion", Cost = 400 },
	},
}

-- Shop -----------------------------------------------------------------------------------
-- Put the real ids from the Creator Hub here (Monetization > Passes / Developer Products).
-- While an id is 0 the item is FREE in Roblox Studio so you can test it, and hidden online.
Config.GamePasses = {
	DoubleDna = { Id = 0, Price = 199, Name = "2x DNA", Text = "Double DNA in hosts" },
	Vaccine = { Id = 0, Price = 99, Name = "Vaccine", Text = "Come back with 75% of your size instead of 50%" },
	FastGrowth = { Id = 0, Price = 249, Name = "Fast Growth", Text = "+50% food value in hosts" },
	ExtraLoadout = { Id = 0, Price = 79, Name = "Extra Loadouts", Text = "Save 3 mutation builds" },
	VIP = { Id = 0, Price = 299, Name = "VIP Germ", Text = "Golden name and +10% DNA" },
	SneezeCam = { Id = 0, Price = 49, Name = "Sneeze Cam", Text = "A longer sneeze moment with a sticker photo frame" },
	AutoCollect = { Id = 0, Price = 149, Name = "Auto Collect", Text = "Pulls nearby food to you (not germs)" },
	Radar = { Id = 0, Price = 199, Name = "Germ Radar", Text = "Arrows point to the 3 nearest germs: green = you can eat it, red = run (hosts only)" },
}
Config.GamePassOrder = { "DoubleDna", "Vaccine", "FastGrowth", "AutoCollect", "Radar", "VIP", "ExtraLoadout", "SneezeCam" }
Config.Products = {
	Revive = { Id = 0, Price = 25, Name = "Revive at Size", Text = "After being eaten, come back at full size (hosts only)" },
	GrowthPotion = { Id = 0, Price = 39, Name = "Growth Potion", Text = "2x growth for 15 minutes" },
	DnaSmall = { Id = 0, Price = 49, Name = "DNA Pack S", Dna = 300 },
	DnaMedium = { Id = 0, Price = 149, Name = "DNA Pack M", Dna = 1200 },
	DnaLarge = { Id = 0, Price = 399, Name = "DNA Pack L", Dna = 4000 },
	ServerFever = { Id = 0, Price = 99, Name = "Server Fever", Text = "Start a Fever for everyone (double DNA)" },
	ImmuneStrike = { Id = 0, Price = 79, Name = "Immune Strike", Text = "A white blood cell hunts the king" },
	-- skins: one product per price; the server remembers which skin you picked
	Skin25 = { Id = 0, Price = 25, Name = "Skin item" },
	Skin49 = { Id = 0, Price = 49, Name = "Skin item" },
	Skin79 = { Id = 0, Price = 79, Name = "Skin item" },
	Skin99 = { Id = 0, Price = 99, Name = "Skin item" },
	Skin149 = { Id = 0, Price = 149, Name = "Skin item" },
	Skin199 = { Id = 0, Price = 199, Name = "Skin bundle" },
	Skin399 = { Id = 0, Price = 399, Name = "Skin bundle" },
	Skin499 = { Id = 0, Price = 499, Name = "World flag pack" },
}
Config.ProductOrder = { "Revive", "GrowthPotion", "DnaSmall", "DnaMedium", "DnaLarge", "ServerFever", "ImmuneStrike" }
Config.GrowthPotionMinutes = 15
Config.RadarRange = 450 -- studs; hidden germs (ink, camo, ghost) never show up
Config.PrivateServerNote = "Private servers: 100 Robux a month (set it in the Creator Hub)"

-- Germ Editor (cosmetics only, no stats) ----------------------------------------------------
-- Price = Robux; Dna = can also be bought with DNA (times the host's Scale); Free = owned by everyone.
Config.Skins = {
	Body = {
		{ Id = "Jelly", Name = "Jelly", Free = true, Material = "SmoothPlastic", Transparency = 0.12 },
		{ Id = "Fuzzy", Name = "Fuzzy", Free = true, Material = "Fabric", Transparency = 0 },
		{ Id = "Slime", Name = "Slime", Free = true, Material = "Glass", Transparency = 0.25 },
		{ Id = "Crystal", Name = "Crystal", Price = 49, Material = "Glass", Transparency = 0.35 },
		{ Id = "Lava", Name = "Lava", Price = 99, Material = "CrackedLava", Transparency = 0 },
		{ Id = "Galaxy", Name = "Galaxy", Price = 149, Material = "Neon", Transparency = 0.1 },
		{ Id = "Candy", Name = "Candy", Price = 79, Material = "Plastic", Transparency = 0 },
		{ Id = "Robot", Name = "Robot", Price = 99, Material = "DiamondPlate", Transparency = 0 },
		{ Id = "Champion", Name = "Champion", Arena = true, Material = "Foil", Transparency = 0 },
	},
	Pattern = {
		{ Id = "None", Name = "None", Free = true },
		{ Id = "Spots", Name = "Spots", Dna = 100, Price = 25 },
		{ Id = "Stripes", Name = "Stripes", Dna = 100, Price = 25 },
		{ Id = "Swirl", Name = "Swirl", Dna = 200, Price = 49 },
		{ Id = "Camo", Name = "Camo", Dna = 200, Price = 49 },
		{ Id = "Checkers", Name = "Checkers", Dna = 250, Price = 49 },
		{ Id = "Flames", Name = "Flames", Dna = 300, Price = 49 },
		{ Id = "Hearts", Name = "Hearts", Dna = 250, Price = 49 },
		{ Id = "Leopard", Name = "Leopard", Dna = 300, Price = 49 },
	},
	Eyes = {
		{ Id = "Cute", Name = "Big Cute", Free = true },
		{ Id = "Angry", Name = "Angry", Dna = 80, Price = 25 },
		{ Id = "Sleepy", Name = "Sleepy", Dna = 80, Price = 25 },
		{ Id = "Cyclops", Name = "Cyclops", Dna = 120, Price = 25 },
		{ Id = "Googly", Name = "Googly", Dna = 120, Price = 25 },
		{ Id = "Three", Name = "Three Eyes", Dna = 160, Price = 25 },
		{ Id = "Cat", Name = "Cat Eyes", Dna = 160, Price = 25 },
		{ Id = "Wink", Name = "Wink", Dna = 120, Price = 25 },
		{ Id = "Heart", Name = "Heart Eyes", Price = 49 },
	},
	Mouth = {
		{ Id = "None", Name = "None", Free = true },
		{ Id = "Smile", Name = "Smile", Free = true },
		{ Id = "Fangs", Name = "Fangs", Dna = 100, Price = 25 },
		{ Id = "Tongue", Name = "Tongue Out", Dna = 100, Price = 25 },
		{ Id = "Mustache", Name = "Mustache", Dna = 150, Price = 25 },
		{ Id = "Braces", Name = "Braces", Dna = 150, Price = 25 },
		{ Id = "Kitty", Name = "Kitty", Dna = 120, Price = 25 },
		{ Id = "Surprised", Name = "Surprised", Dna = 100, Price = 25 },
	},
	Hat = {
		{ Id = "None", Name = "None", Free = true },
		{ Id = "Crown", Name = "Tiny Crown", Price = 99 },
		{ Id = "Party", Name = "Party Hat", Price = 49 },
		{ Id = "Propeller", Name = "Propeller Cap", Price = 79 },
		{ Id = "Halo", Name = "Halo", Price = 99 },
		{ Id = "Horns", Name = "Horns", Price = 49 },
		{ Id = "Bow", Name = "Bow", Price = 49 },
		{ Id = "CatEars", Name = "Cat Ears", Price = 79 },
		{ Id = "TopHat", Name = "Top Hat", Price = 99 },
		{ Id = "Laurel", Name = "Champion Laurel", Arena = true },
	},
	Trail = {
		{ Id = "None", Name = "None", Free = true },
		{ Id = "Bubbles", Name = "Bubbles", Price = 49 },
		{ Id = "Sparkles", Name = "Sparkles", Price = 79 },
		{ Id = "SlimeTrail", Name = "Slime", Price = 49 },
		{ Id = "Hearts", Name = "Hearts", Price = 79 },
		{ Id = "Fire", Name = "Fire", Price = 99 },
		{ Id = "ArenaFlame", Name = "Arena Flame", Arena = true },
		{ Id = "ArenaLightning", Name = "Arena Lightning", Arena = true },
	},
	SneezeFx = {
		{ Id = "Classic", Name = "Classic", Free = true },
		{ Id = "Glitter", Name = "Glitter", Price = 79 },
		{ Id = "Fireworks", Name = "Fireworks", Price = 99 },
		{ Id = "Rainbow", Name = "Rainbow", Price = 149 },
		{ Id = "Confetti", Name = "Confetti", Price = 79 },
		{ Id = "Galaxy", Name = "Galaxy", Arena = true },
	},
}
Config.SkinCategories = { "Body", "Pattern", "Eyes", "Mouth", "Hat", "Trail", "SneezeFx", "Flag" }
Config.Bundles = {
	{ Id = "DragonGerm", Name = "Dragon Germ", Price = 199, Items = { Body = "Lava", Pattern = "Flames", Eyes = "Angry", Hat = "Horns", Trail = "Fire" } },
	{ Id = "SpaceGerm", Name = "Space Germ", Price = 199, Items = { Body = "Galaxy", Pattern = "Swirl", Eyes = "Three", Hat = "Halo", Trail = "Sparkles" } },
	{ Id = "PartyGerm", Name = "Party Germ", Price = 399, Items = { Body = "Candy", Pattern = "Spots", Eyes = "Googly", Mouth = "Tongue", Hat = "Party", Trail = "Hearts", SneezeFx = "Confetti" } },
}
Config.FlagPrice = 49
Config.ContinentPackPrice = 199
Config.WorldPackPrice = 499
Config.OutfitSlots = 3

-- Quests and daily rewards --------------------------------------------------------------------
Config.DailyQuests = {
	{ Id = "EatGerms", Text = "Eat %d germs", Goals = { 5, 8, 12 }, Dna = 60 },
	{ Id = "EatFood", Text = "Eat %d food", Goals = { 150, 250, 400 }, Dna = 40 },
	{ Id = "Fever", Text = "Survive %d Fever events", Goals = { 1, 1, 2 }, Dna = 80 },
	{ Id = "Golden", Text = "Grab golden food %d times", Goals = { 1, 2, 3 }, Dna = 80 },
	{ Id = "Boss", Text = "Help beat %d immune bosses", Goals = { 1, 2, 3 }, Dna = 120 },
	{ Id = "Revenge", Text = "Get revenge %d times", Goals = { 1, 2, 3 }, Dna = 80 },
	{ Id = "Dash", Text = "Dash %d times", Goals = { 20, 40, 60 }, Dna = 30 },
	{ Id = "Grow", Text = "Reach the %s zone", Goals = { 2, 3, 4 }, Dna = 60 },
}
Config.QuestsPerDay = 3
Config.WeeklySteps = 7 -- finish 7 daily quests in a week for a card set piece
Config.StreakRewards = { 50, 80, 120, 160, 220, 300, "Sneeze:Glitter" } -- day 7 gives a sneeze effect

Config.Codes = {
	ACHOO = { Dna = 100 },
	BLESSYOU = { Dna = 150 },
	GERMSQUAD = { Potion = 1 },
}
Config.ReferralReward = { Potion = 1 }

-- Cards: collectible, from quests and bosses (never sold, never random for Robux)
Config.CardSets = {
	Hosts = { "Nibbles", "Barkley", "Grandma Trunk", "Ember", "Kraken", "Zorb" },
	Bosses = { "Whitey", "Macrophage Mama", "Antibody Swarm", "Fever", "Medicine Drop", "Arena Macrophage" },
	Germs = { "Sir Sneezalot", "Booger Baron", "Lady Snifflesworth", "Captain Cough", "The Hiccup", "Dr. Drippy" },
}
Config.CardSetRewards = { Hosts = "Eyes:Three", Bosses = "Hat:Halo", Germs = "Trail:Sparkles" }

-- Germ colours: the starting colours (the Germ Editor has a full colour picker)
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

-- Leaderboards (OrderedDataStores). Ascending boards list the smallest value first (times).
Config.Leaderboards = {
	{ Id = "BestSize", Tab = "Size", Name = "Biggest germ ever", Store = "LB_BestSize_v1" },
	{ Id = "Sneezes", Tab = "Sneezes", Name = "Most sneezes", Store = "LB_Sneezes_v1" },
	{ Id = "Kills", Tab = "Eaten", Name = "Most germs eaten", Store = "LB_Kills_v1" },
	{ Id = "ArenaFloor", Tab = "Arena", Name = "Arena: highest floor", Store = "LB_ArenaFloor_v1" },
	{ Id = "FastestRun", Tab = "Speedrun", Name = "Fastest run through all 6 hosts", Store = "LB_FastestRun_v1", Ascending = true, Time = true },
	{ Id = "Runs", Tab = "Runs", Name = "Most runs finished", Store = "LB_Runs_v1" },
}

return Config
