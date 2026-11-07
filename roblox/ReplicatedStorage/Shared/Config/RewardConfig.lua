--!strict
--[[
	RewardConfig.lua
	Configurable reward values and progression rules (Section 7.1 & 7.2).
]]

local RewardConfig = {
	-- Primary mission completion base Scrap reward
	PRIMARY_MISSION_SCRAP = 50,

	-- Bonus Scrap granted only to players who successfully extract before train departure
	EXTRACTION_BONUS_SCRAP = 35,

	-- Optional cache Scrap reward
	SUPPLY_CACHE_SCRAP = 15,

	-- Whether an eliminated player still receives the primary mission reward if the crew completes it (Section 3.4)
	ELIMINATED_RECEIVES_PRIMARY_MISSION_REWARD = true,
}

return table.freeze(RewardConfig)
