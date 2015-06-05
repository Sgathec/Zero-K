
if (gadgetHandler:IsSyncedCode()) then

local version = "1.0.6"

function gadget:GetInfo()
	return {
		name		= "Ore mexes!",
		desc		= "Prespawn mex spots and make them spit ore. Version "..version,
		author		= "Tom Fyuri",
		date		= "Mar-Apr 2014",
		license		= "GPL v2 or later",
		layer		= -5,
		enabled	 	= true				-- now it comes with design!
	}
end

--SYNCED-------------------------------------------------------------------

--TODO storage should drop ore on death should you have no allies left to transfer ore to.
--TODO terrain and smoke gfx...

--BUGS:
-- 1) Overdrive breakage.
--	Steps to reproduce:
-- 	1) connect gaia mex to grid.
--	2) disconnect gaia mex by destroying your own stuff.
--	3) /luarules reload.
--	4) reconnect mex.
--	5) it will say "not connected to grid".
-- Impossible to reproduce in regular zero-k, because you never meet gaia giving you stuff, so I don't know what's wrong.

-- changelog
-- 1 april 2014  - 1.0.6. Spawn rate is now once per 2 seconds (or slower). Map size ore hardlimits. Mining communism.
-- 30 march 2014 - 1.0.5. Income rewrite. Damage off. Crystals on. You can check income by looking over extractors.
-- 22 march 2014 - 1.0.4. Widget is now AI micro assistant. It also has it's own changelog from now on.
-- 11 march 2014 - 1.0.3. Growth rewrite, ore metal yield change, ore harm units now. Disobey OD fix. And transfer logic improvement.
-- 10 march 2014 - 1.0.2. Could be considered first working version.

local modOptions = Spring.GetModOptions()

local getMovetype = Spring.Utilities.getMovetype

local spGetUnitsInCylinder				= Spring.GetUnitsInCylinder
local spCallCOBScript					= Spring.CallCOBScript
local spGetGroundHeight					= Spring.GetGroundHeight
local spGetUnitPosition					= Spring.GetUnitPosition
local spGetTeamInfo						= Spring.GetTeamInfo
local spCreateFeature 					= Spring.CreateFeature
local spSetFeatureReclaim				= Spring.SetFeatureReclaim
local spSetFeatureDirection				= Spring.SetFeatureDirection
local spGetFeaturePosition				= Spring.GetFeaturePosition
local spCreateUnit						= Spring.CreateUnit
local spGetUnitRulesParam				= Spring.GetUnitRulesParam
local spSetUnitRulesParam				= Spring.SetUnitRulesParam
local spGetUnitDefID					= Spring.GetUnitDefID
local GaiaTeamID						= Spring.GetGaiaTeamID()
local spGetUnitTeam						= Spring.GetUnitTeam
local spGetFeaturesInRectangle			= Spring.GetFeaturesInRectangle
local spGetUnitsInRectangle				= Spring.GetUnitsInRectangle
local spGetFeatureDefID					= Spring.GetFeatureDefID
local spTransferUnit					= Spring.TransferUnit
local spGetAllUnits						= Spring.GetAllUnits
local spGetUnitAllyTeam					= Spring.GetUnitAllyTeam
local spGetTeamList						= Spring.GetTeamList
local spSetUnitNeutral					= Spring.SetUnitNeutral
local spValidUnitID						= Spring.ValidUnitID
local spGetUnitHealth					= Spring.GetUnitHealth
local spSetUnitHealth					= Spring.SetUnitHealth
local spAddUnitDamage					= Spring.AddUnitDamage
local spDestroyUnit						= Spring.DestroyUnit
local spGetAllFeatures					= Spring.GetAllFeatures
local spGetFeatureResources				= Spring.GetFeatureResources
local spGiveOrderToUnit					= Spring.GiveOrderToUnit
local spGetCommandQueue					= Spring.GetCommandQueue
local spValidFeatureID					= Spring.ValidFeatureID
local spGetUnitLosState					= Spring.GetUnitLosState
local spGetAllyTeamList	  				= Spring.GetAllyTeamList
local spGetTeamResources  				= Spring.GetTeamResources
local spAddTeamResource   				= Spring.AddTeamResource
local spUseTeamResource   				= Spring.UseTeamResource
local spShareTeamResource				= Spring.ShareTeamResource
local spGetPlayerInfo					= Spring.GetPlayerInfo

local waterLevel = modOptions.waterlevel and tonumber(modOptions.waterlevel) or 0
local GaiaAllyTeamID					= select(6,spGetTeamInfo(GaiaTeamID))

local OreMex = {} -- by UnitID

local random = math.random
local cos	 = math.cos
local sin	 = math.sin
local pi		= math.pi
local floor = math.floor
local abs	 = math.abs

local mapWidth
local mapHeight

local teamIDs
local UnderAttack = {} -- holds frameID per mex so it goes neutral, if someone attacks it, for 5 seconds, it will not return to owner if no grid connected.
local Ore = {} -- hold features should they emit harm they will ongameframe
local OreIncome = GG.oreIncome --is set by unit_mex_overdrive.lua every 32th frame
local gameframe = Spring.GetGameFrame()

local TiberiumProofDefs = {
	[UnitDefNames["armestor"].id] = true,
	[UnitDefNames["armwin"].id] = true,
	[UnitDefNames["armsolar"].id] = true,
	[UnitDefNames["armfus"].id] = true,
	[UnitDefNames["cafus"].id] = true,
	[UnitDefNames["geo"].id] = true,
	[UnitDefNames["amgeo"].id] = true,
	[UnitDefNames["cormex"].id] = true,
	[UnitDefNames['pw_generic'].id] = true,
	[UnitDefNames['pw_hq'].id] = true,
	[UnitDefNames['tele_beacon'].id] = true, -- why not
	[UnitDefNames['terraunit'].id] = true, -- totally why not
} -- also any unit that has "chicken" inside its unitname and anything that can reclaim is also tiberium proof
-- more setup
for i=1,#UnitDefs do
	local ud = UnitDefs[i]
--	 if (ud.isBuilder and not(ud.isFactory) and not(ud.customParams.commtype)) or ud.name:find("chicken") then -- I pray this works and doesn't slow down load times too much
--	 if (ud.isBuilder and not(ud.isFactory)) or (ud.customParams.commtype) or ud.name:find("chicken") then -- I pray this works and doesn't slow down load times too much
	if not((getMovetype(ud) ~= false) or ud.name:find("chicken")) then -- anything that can move and not chicken can be damaged by tiberium
		TiberiumProofDefs[i] = true
	end
end

-- NOTE probably below defs could be generated on gamestart too
local EnergyDefs = { -- if gaia mex get's in range of any of below structures, it will transmit it ownership
	[UnitDefNames["armestor"].id] = UnitDefNames["armestor"].customParams.pylonrange,
	[UnitDefNames["armwin"].id] = UnitDefNames["armwin"].customParams.pylonrange,
	[UnitDefNames["armsolar"].id] = UnitDefNames["armsolar"].customParams.pylonrange,
	[UnitDefNames["armfus"].id] = UnitDefNames["armfus"].customParams.pylonrange,
	[UnitDefNames["cafus"].id] = UnitDefNames["cafus"].customParams.pylonrange,
	[UnitDefNames["geo"].id] = UnitDefNames["geo"].customParams.pylonrange,
	[UnitDefNames["amgeo"].id] = UnitDefNames["amgeo"].customParams.pylonrange,
	[UnitDefNames["cormex"].id] = UnitDefNames["cormex"].customParams.pylonrange,
}
local MexDefs = {
	[UnitDefNames["cormex"].id] = true,
}
local PylonRange = UnitDefNames["armestor"].customParams.pylonrange + 39

local INVULNERABLE_EXTRACTORS = (tonumber(modOptions.oremex_invul) == 1) -- invulnerability of extractors. they can still switch team side should OD get connected
if (modOptions.oremex_invul == nil) then INVULNERABLE_EXTRACTORS = true end
local LIMIT_PRESPAWNED_METAL = tonumber(modOptions.oremex_metal)
if (tonumber(LIMIT_PRESPAWNED_METAL)==nil) then LIMIT_PRESPAWNED_METAL = 35 end
local PRESPAWN_EXTRACTORS = (tonumber(modOptions.oremex_prespawn) == 1)
if (modOptions.oremex_prespawn == nil) then PRESPAWN_EXTRACTORS = true end
local OBEY_OD = (tonumber(modOptions.oremex_overdrive) == 1)
if (modOptions.oremex_overdrive == nil) then OBEY_OD = true end
local INFINITE_GROWTH = (tonumber(modOptions.oremex_inf) == 1) -- this causes performance drop you know...
if (modOptions.oremex_inf == nil) then INFINITE_GROWTH = false end
local ORE_DMG = tonumber(modOptions.oremex_harm) -- TODO does it take float?
if (tonumber(ORE_DMG)==nil) then ORE_DMG = 0 end -- it's both slow and physical damage, be advised. albeit range is small. also it stacks, ore damages adjacent tiles!!
local ORE_DMG_RANGE = 81 -- so standing in adjacent tile is gonna harm you
local OBEY_ZLEVEL = (tonumber(modOptions.oremex_uphill) == 1) -- slower uphill growth
if (modOptions.oremex_uphill == nil) then OBEY_ZLEVEL = true end
local CRYSTALS = (tonumber(modOptions.oremex_crystal) == 1) -- crystals instead of ore
if (modOptions.oremex_crystal == nil) then CRYSTALS = true end
local COMMUNISM = (tonumber(modOptions.oremex_communism) == 1) -- implemented as seperate modoption... because it's not overdrive, but rather all ore reclaim income...
if (modOptions.oremex_communism == nil) then COMMUNISM = true end
local ZLEVEL_PROTECTION = 300 -- if adjacent tile is over 300 it's not gonna grow there at all -- lower Z tiles do not give speed boost though
local MAX_STEPS = 15 -- vine length
local MAX_PIECES = 50 -- anti spam measure, 144, it looks like cute ~7x7 square rotated 45 degree
local MIN_PRODUCE = 10 -- no less than 10 ore per 40x40 square otherwise spam lol...

if (INFINITE_GROWTH) then -- not enabled by default
	MAX_STEPS = 40 -- 40*40 = 1600 distance is maximum in length per mex, considering there are usually more than 1 mex on 2000x2000 map, it's supposed to surely cover entire map in "tiberium"
end

local OreDefs = {
      [FeatureDefNames["ore"].id] = true,
      [FeatureDefNames["ore_tiberium1"].id] = true,
      [FeatureDefNames["ore_tiberium2"].id] = true,
      [FeatureDefNames["ore_tiberium3"].id] = true,
      [FeatureDefNames["ore_tiberium4"].id] = true,
}

local AllyTeams = {}
local TeamData = {} -- by teamID, holds array of allied teamIDs
local MinedOre = {} -- by teamID, holds amount of ore mined
local OwnsOreToTeam = {}

local CMD_SELFD								= CMD.SELFD
local CMD_ATTACK				= CMD.ATTACK
local CMD_REMOVE				= CMD.REMOVE

local function TransferMexTo(unitID, unitTeam)
	if (spValidUnitID(unitID)) and (OreMex[unitID]) then
-- 		spSetUnitRulesParam(unitID, "mexIncome", OreMex[unitID].income)
-- 		spCallCOBScript(unitID, "SetSpeed", 0, OreMex[unitID].income * 500) 
		-- ^ hacks?
		UnderAttack[unitID] = gameframe+160
		spTransferUnit(unitID, unitTeam, false)
		spSetUnitNeutral(unitID, true)
	end
end

local function disSQ(x1,y1,x2,y2)
	return (x1 - x2)^2 + (y1 - y2)^2
end

function gadget:UnitPreDamaged_GetWantedWeaponDef()
	return WeaponDefs
end

function gadget:UnitPreDamaged(unitID, unitDefID, unitTeam)
	if (OreMex[unitID]) then
		if (unitTeam ~= GaiaTeamID) then
			TransferMexTo(unitID, GaiaTeamID)
		end
		return 0
	end
end

local TransferLoop = function() --transfer mex to nearest team that deliver energy
	for unitID, data in pairs(OreMex) do
		local x = data.x
		local z = data.z
		local unitTeam = spGetUnitTeam(unitID)
		local allyTeam = spGetUnitAllyTeam(unitID)
		if (x) and ((unitTeam==GaiaTeamID) or (INVULNERABLE_EXTRACTORS)) and (UnderAttack[unitID] <= gameframe) then
			local units = spGetUnitsInCylinder(x, z, PylonRange)
			local best_eff = -1 -- lel
			local best_team
			local best_ally
			local enearby = false
			for i=1,#units do
				local targetID = units[i]
				local targetDefID = spGetUnitDefID(targetID)
				local targetTeam = spGetUnitTeam(targetID)
				local targetAllyTeam = spGetUnitAllyTeam(targetID)
				if (EnergyDefs[targetDefID]) and (unitID ~= targetID) and (targetTeam~=GaiaTeamID) then
					local maxdist = EnergyDefs[targetDefID] + 39
					maxdist=maxdist*maxdist
					local x2,_,z2 = spGetUnitPosition(targetID)
					if (disSQ(x,z,x2,z2) <= maxdist) or (UnitDefs[targetDefID].name == "armestor") then
						enearby = true
						local eff = spGetUnitRulesParam(targetID,"gridefficiency")
--							 Spring.MarkerAddPoint(x2,0,z2,eff)
						if (eff~=nil) and (best_eff < eff) then
							best_eff = eff
							best_team = targetTeam
							best_ally = targetAllyTeam
						end
					end
				end
			end
			if (best_team ~= nil) and (unitTeam ~= best_team) and (allyTeam ~= best_ally) then
				TransferMexTo(unitID, best_team)
			elseif (INVULNERABLE_EXTRACTORS) and not(enearby) and (best_team == nil) and (unitTeam ~= GaiaTeamID) then -- back to Gaia you go
				TransferMexTo(unitID, GaiaTeamID)
			end
		end
	end
end

local function OreHarms(unitID)
	local health = spGetUnitHealth(unitID)
	if (health ~= nil) then
		if (health > ORE_DMG) then
			GG.addSlowDamage(unitID, ORE_DMG*2)
			spAddUnitDamage(unitID, ORE_DMG, 0, GaiaTeamID, 1)
--			 spSetUnitHealth(unitID, health-ORE_DMG)
		else
			spDestroyUnit(unitID, false, false, GaiaTeamID)
		end
	end
end

-- damage is cylinder, not spherical
local InflictOreDamage = function()
	for oreID, _ in pairs(Ore) do
		local x,y,z = spGetFeaturePosition(oreID)
		if (x) then
			local units = spGetUnitsInCylinder(x,z,ORE_DMG_RANGE)
			for i=1,#units do
				local unitID = units[i]
				local unitDefID = spGetUnitDefID(unitID)
				if not(TiberiumProofDefs[unitDefID]) then
					local ux,uy,uz = spGetUnitPosition(unitID)
					if (abs(y-uy) <= ORE_DMG_RANGE) then
						OreHarms(unitID)
					end
				end
			end
		end
	end
end

-- example how it works:
-- consider 31 metal ore chunk/crystal,
-- reclaiming it will call this function 84 times, part will be 0.375,
-- doing some math 0.375/1*84=31.5 which is very accurate to what we had in the begining: 31.
-- test was done with 12 BP com. same test in similar fashion was performed for other cons, result was aprox the same.
function gadget:AllowFeatureBuildStep(builderID, builderTeam, featureID, featureDefID, part)
	if not(OreDefs[featureDefID]) or not(MinedOre[builderTeam]) or (builderTeam == GaiaTeamID) then
		return true
	end
 	MinedOre[builderTeam] = MinedOre[builderTeam] + (-part/FeatureDefs[featureDefID].metal) --reclaiming ore
	return true
end

function gadget:AllowUnitBuildStep(builderID, builderTeam, step) -- was not documented in spring wiki
	if (OwnsOreToTeam[builderTeam]) and (MinedOre[builderTeam] >= 10) then -- (halt construction until reclaimed ore is shared with teams,) You owe your team some metal, until you repay the amount you can't build, i'm so sorry
		return false
	end
	return true
end

local function AlliesNeedM(teamIDs)
	local needs = {}
	for i=1, #teamIDs do
		local teamID = teamIDs[i]
		local _,leader,_,isAI = spGetTeamInfo(teamID)
		if (leader >= 0) or (isAI) then -- otherwise spec
			if (isAI) then
				local mCur, mMax, mPull, mInc, _, _, _, _ = spGetTeamResources(teamID, "metal")
				if (mCur+mInc) < mMax then 
					needs[#needs+1] = teamID
				end
			else
				local active = select(2, spGetPlayerInfo(leader))
				if (active) then
					local mCur, mMax, mPull, mInc, _, _, _, _ = spGetTeamResources(teamID, "metal")
					if (mCur+mInc) < mMax then 
						needs[#needs+1] = teamID
					end
				end
			end
		end
	end
	return needs
end

local ShareMinedOre = function() --perform communism/resource-sharing and allocation
	for teamID, allies in pairs(TeamData) do
		if (MinedOre[teamID] > 1) then
			MinedOre[teamID] = floor(MinedOre[teamID]) -- keep the change!
			local needs = AlliesNeedM(allies)
			if (#needs > 0) then
				local mCur, mMax, mPull, mInc, _, _, _, _ = spGetTeamResources(teamID, "metal")
				local single_member = MinedOre[teamID]/(#needs+1)
				local to_allies = MinedOre[teamID] - single_member
				if (to_allies <= mCur) then
					-- give all
					for i=1, #needs do
						spUseTeamResource(teamID, "metal", single_member)
						spAddTeamResource(needs[i], "metal", single_member)
-- 						spShareTeamResource(teamID, needs[i], "metal", single_member) -- interferes with share bear
					end
					MinedOre[teamID] = 0 -- gave everything, very good comrade
					if (OwnsOreToTeam[teamID]) then
						OwnsOreToTeam[teamID] = nil
					end
				else	-- can't give all? O_o
					single_member = mCur/(#needs+1)
					to_allies = mCur - single_member
					for i=1, #needs do
						spUseTeamResource(teamID, "metal", to_allies)
						spAddTeamResource(needs[i], "metal", to_allies)
-- 						spShareTeamResource(teamID, needs[i], "metal", single_member) -- interferes with share bear
					end
					MinedOre[teamID] = MinedOre[teamID] - to_allies -- since we are gonna give out more than we should
					OwnsOreToTeam[teamID] = true
				end
			end
		end
	end
end

-- if mex OD is off and it's godmode on, transfer mex to gaia team
-- if mex is inside EnergyDefs transfer mex to ally team having most gridefficiency (if im correct team having most gridefficiency should produce most E for M?)
function gadget:GameFrame(f)
	gameframe = f
	if ((f%32)==1) then
		ShareMinedOre() --distribute metal from reclaimed ores to ally
		MineMoreOreLoop() --spawn a reclaimable ore around mex
		InflictOreDamage() --damage units walking on the ore, like tiberium
		TransferLoop() --transfer mex to team which connect energy to it
	end
end

function gadget:AllowWeaponTarget(attackerID, targetID, attackerWeaponNum, attackerWeaponDefID, defPriority)
	if (attackerID) and (OreMex[targetID]) then
		return false, 1
	end
	return true, 1
end

local function UnitFin(unitID, unitDefID, unitTeam)
	if (MexDefs[unitDefID]) then
		local x,y,z = spGetUnitPosition(unitID)
		if (x) then
			OreMex[unitID] = {
				unitID = unitID,
				ore = 0, -- metal.
-- 				income = spGetUnitRulesParam(unitID,"mexIncome"),
				x = x,
				z = z,
			}
			UnderAttack[unitID] = -100
			if not(OBEY_OD) then -- this blocks OD should oremex_overdrive==false
				TransferMexTo(unitID, GaiaTeamID)
			end
		end
	end
end

local function CanSpawnOreAt(x,z)
	if (CRYSTALS) then -- extra check, don't spawn crystals inside building it's lame... extractor is exception
		local units = spGetUnitsInRectangle(x-15,z-15,x+15,z+15)
		for i=1,#units do
			local unitID = units[i]
			local unitDefID = spGetUnitDefID(unitID)
			if (getMovetype(UnitDefs[unitDefID]) == false) and not(MexDefs[unitDefID]) then
				return false
			end
		end
	end
	local features = spGetFeaturesInRectangle(x-30,z-30,x+30,z+30)
	for i=1,#features do
		local featureID = features[i]
		local featureDefID = spGetFeatureDefID(featureID)
		if (OreDefs[featureDefID]) then
			return false
		end
	end
	return true
end

-- lets pick a direction where to grow, west/east/north/south
-- try to grow there, if it's not possible and map end reached, do not grow there and fail that "try"
-- hopefully random number will roll better direction next time, ore is not wasted anyway
local GrowBranch = function(x,y,z)
	local steps=0
	local direction = random(0,3)
	while (steps < MAX_STEPS) do
		if (CanSpawnOreAt(x,z)) then return x,z
		else -- could be slightly better optimised
			local way = random(0,3)
			if (way ~= direction) then
				if (way==0) then
					if ((x-40)<=0) then
						return nil -- fail
					end
					x=x-40
				elseif (way==2) then
					if ((x+40)>=mapWidth) then
						return nil -- fail
					end
					x=x+40
				elseif (way==1) then
					if ((z-40)<=0) then
						return nil -- fail
					end
					z=z-40
				elseif (way==3) then
					if ((z+40)>=mapHeight) then
						return nil -- fail
					end
					z=z+40
				end -- otherwise stay at place
			end
		end
		steps = steps+1
	end
	return nil
end
if (OBEY_ZLEVEL) then -- more expensive algo if we obey z level (dont grow uphill)
	GrowBranch = function(x,y,z)
		local ox = x
		local oz = z
		local steps=0
		local direction = random(0,3)
		while (steps < MAX_STEPS) do
			if (CanSpawnOreAt(x,z)) then return x,z
			else -- could be slightly better optimised
				local way = random(0,3)
				if (way ~= direction) then
					if (way==0) then
						if ((x-40)<=0) then
							return nil -- fail
						end
						if (spGetGroundHeight(x-40,z)-random(0,ZLEVEL_PROTECTION) <= spGetGroundHeight(x,z)) then 
							x=x-40
						else -- try again, can't grow there
							x = ox
							z = oz
							steps = floor(steps/2)
						end
					elseif (way==2) then
						if ((x+40)>=mapWidth) then
							return nil -- fail
						end
						if (spGetGroundHeight(x+40,z)-random(0,ZLEVEL_PROTECTION) <= spGetGroundHeight(x,z)) then 
							x=x+40
						else -- try again, can't grow there
							x = ox
							z = oz
							steps = floor(steps/2)
						end
					elseif (way==1) then
						if ((z-40)<=0) then
							return nil -- fail
						end
						if (spGetGroundHeight(x,z-40)-random(0,ZLEVEL_PROTECTION) <= spGetGroundHeight(x,z)) then 
							z=z-40
						else -- try again, can't grow there
							x = ox
							z = oz
							steps = floor(steps/2)
						end
					elseif (way==3) then
						if ((z+40)>=mapHeight) then
							return nil -- fail
						end
						if (spGetGroundHeight(x,z+40)-random(0,ZLEVEL_PROTECTION) <= spGetGroundHeight(x,z)) then 
							z=z+40
						else -- try again, can't grow there
							x = ox
							z = oz
							steps = floor(steps/2)
						end
					end -- otherwise stay at place
				end
			end
			steps = steps+1
		end
		return nil
	end
end

local function SpawnOre(a, b, spawn_amount, teamID)
	local oreID
	if (CRYSTALS) then
		oreID = spCreateFeature("ore_tiberium"..(random(1,3)), a, spGetGroundHeight(a, b), b, "n", teamID)
	else
		oreID = spCreateFeature("ore", a, spGetGroundHeight(a, b), b, "n", teamID)
	end
	if (oreID) then
		spSetFeatureReclaim(oreID, spawn_amount)
		local rd = random(360) * pi / 180
		if not(CRYSTALS) then
			spSetFeatureDirection(oreID,sin(rd),0,cos(rd))
		end
		Ore[oreID] = true
		return true
	end
	return false
end

local function AddOreMetal(oreID, amount) -- should add more metal on existing ore tile, hopefully it works...
	--local remM, maxM, remE, maxE, left = spGetFeatureResources(oreID)
	if (spValidFeatureID(oreID)) then
		local left = select(5,spGetFeatureResources(oreID))
		spSetFeatureReclaim(oreID, left+amount)
		return true
	end
	return false
end

function gadget:FeatureDestroyed(featureID, allyTeam)
	if (Ore[featureID]) then
		Ore[featureID] = nil
	end
end

local spawn_or_wait = false
function MineMoreOreLoop()
	spawn_or_wait = not(spawn_or_wait)
	for unitID, data in pairs(OreMex) do
		if (OreIncome[unitID]) then
			MineMoreOre(unitID, OreIncome[unitID], false, spawn_or_wait)
		end
	end
end

local function isUnitVisible(unitID, allyTeam)
	if spValidUnitID(unitID) then
	      local state = spGetUnitLosState(unitID,allyTeam)
	      return state and state.los
	else
	      return false
	end
end

local function notifyPlayers(unitID, spawn_amount)
	for i=1,#AllyTeams do
		local allyTeam = AllyTeams[i]
		if (isUnitVisible(unitID, allyTeam)) then
			--SendToUnsynced("oremexIncomeAdd", allyTeam, unitID, spawn_amount)
		end
	end
end

function MineMoreOre(unitID, howMuch, forcefully, wait)
	if not(OreMex[unitID]) then return end -- in theory never happens...
	OreMex[unitID].ore = OreMex[unitID].ore + howMuch
	if not(wait) then
		local ore = OreMex[unitID].ore
	-- 	if not(forcefully) then
	-- 		OreMex[unitID].income = howMuch
	-- 	end
		local x,y,z = spGetUnitPosition(unitID)
		local features = spGetFeaturesInRectangle(x-240,z-240,x+240,z+240)
		local random_feature
		if (#features > 0) then
			random_feature = features[random(1,#features)]
		end
		local spawn_allow = true
		if not(INFINITE_GROWTH) then -- rejoice Killer
			if (#features > MAX_PIECES) and not(forcefully) then spawn_allow = false end -- too much reclaim, please reclaim
		end
		local sp_count = 3
		if (ore < 6) then
			sp_count = 2
			if (ore < 3) then
				sp_count = 1
			end
		end
		local teamID = spGetUnitTeam(unitID)
		if (#teamIDs>1) then
			teamID = random(0,#teamIDs)
			while (teamID == GaiaTeamID) do
				teamID = random(0,#teamIDs)
			end
		end
		local spawned = 0
		if (ore>=1) then
			if spawn_allow then
				try=0
				-- lets see, it tries to spawn 3 ore chunks every time
				-- lets try spawning 40% of ore amount every time
				local spawn_amount = ore*0.4
				if (forcefully) then
					spawn_amount = ore*0.6 -- more chance to drop everything, regardless
				elseif (spawn_amount<MIN_PRODUCE) then -- try to spawn minchunk
					spawn_amount = MIN_PRODUCE
				end
				while (try < sp_count) do
					local a,b = GrowBranch(x,y,z) -- v2, pick direction grow there, do not go back in direction, it should be more like a tree, probably
					if (a~=nil) then
						if (ore >= spawn_amount) then -- is it enough?
							if (SpawnOre(a,b,spawn_amount,teamID)) then
								spawned = spawned + spawn_amount
								ore = ore - spawn_amount
							end
						end
					end
					try=try+1
				end
			end
			if (ore >= 1) then
				if not(forcefully) and (ore >= MIN_PRODUCE) and (Ore[random_feature]) then -- simply grow "random_feature"
					if (AddOreMetal(random_feature, ore)) then
						spawned = spawned + ore
						ore = 0
					end
				elseif (forcefully) then -- drop all thats left on mex
					if (SpawnOre(x,z,ore,teamID)) then
						spawned = spawned + ore
						ore = 0
					end
				end
			end
		end
		if (spawned > 0) then
			notifyPlayers(unitID, spawned)
		end
		OreMex[unitID].ore = ore
	end
end

local function GetFloatHeight(x,z)
	local height = spGetGroundHeight(x,z)
	if (height < waterLevel) then
		return waterLevel
	end
	return height
end

function gadget:UnitDestroyed(unitID, unitDefID, teamID, attackerID, attackerDefID, attackerTeamID)
	if (OreMex[unitID]) then
		MineMoreOre(unitID, 0, true, false) -- this will order it to spawn everything it ha
		OreMex[unitID]=nil
		UnderAttack[unitID]=0
		OreIncome[unitID]=0
	end
end

local function PreSpawn()
	if (GG.metalSpots) then -- if map has metal spots, prespawn mexes, otherwise players can build them themselves. also prespawn 120 metal ore. scattered.
		for i = 1, #GG.metalSpots do
			local units = spGetUnitsInRectangle(GG.metalSpots[i].x-1,GG.metalSpots[i].z-1,GG.metalSpots[i].x+1,GG.metalSpots[i].z+1)
			if (units == nil) or (#units==0) then
				local unitID = spCreateUnit("cormex",GG.metalSpots[i].x, GetFloatHeight(GG.metalSpots[i].x,GG.metalSpots[i].z), GG.metalSpots[i].z, "n", GaiaTeamID)
				if (unitID) then
					OreMex[unitID] = {
						unitID = unitID,
						ore = 0, -- metal.
-- 						income = GG.metalSpots[i].metal,
						x = GG.metalSpots[i].x,
						z = GG.metalSpots[i].z,
					}
					if (INVULNERABLE_EXTRACTORS) then
						spSetUnitNeutral(unitID, true)
					end
					UnderAttack[unitID] = -100
					spSetUnitRulesParam(unitID, "mexIncome", GG.metalSpots[i].metal) --hacky
					spCallCOBScript(unitID, "SetSpeed", 0, GG.metalSpots[i].metal * 500) --hacky
					local prespawn = 0
					while (prespawn < LIMIT_PRESPAWNED_METAL) do
						MineMoreOre(unitID, 10, true, false)
						prespawn=prespawn+10
					end
					if (LIMIT_PRESPAWNED_METAL-prespawn)>=5 then -- i dont want to spawn ~1m "leftovers", chunks are ok
						MineMoreOre(unitID, LIMIT_PRESPAWNED_METAL-prespawn, true, false)
					end
				end
			end
		end
		return true
	else
		return false
	end
end

local function ReInit(reinit)
	mapWidth = Game.mapSizeX
	mapHeight = Game.mapSizeZ
	if not(INFINITE_GROWTH) then -- TODO should also consider mex amount, if possible
		local size = mapWidth + mapHeight
		if (size > 12001) then
			MAX_PIECES = 10
		elseif (size > 9001) then
			MAX_PIECES = 25
		elseif (size > 6001) then
			MAX_PIECES = 35
		end	-- else size is small and 50 pieces by default
	end
-- 	Spring.Echo("yay for "..MAX_PIECES)
	teamIDs = spGetTeamList()
	if (PRESPAWN_EXTRACTORS) then
		if not(PreSpawn()) and INVULNERABLE_EXTRACTORS then
			INVULNERABLE_EXTRACTORS = false
			gadgetHandler:RemoveCallIn("AllowWeaponTarget")
			gadgetHandler:RemoveCallIn("UnitPreDamaged")
			gadgetHandler:RemoveCallIn("AllowCommand")
		end
	end
	if (reinit) then
		local units = spGetAllUnits()
		for i=1,#units do
			UnitFin(units[i], spGetUnitDefID(units[i]), spGetUnitTeam(units[i]))
		end
		local features = spGetAllFeatures()
		for i=1,#features do
			local featureDefID = spGetFeatureDefID(features[i])
			if (OreDefs[featureDefID]) then
				Ore[features[i]] = true
			end
		end
	end
end
		
function gadget:Initialize()
	if not (tonumber(modOptions.oremex) == 1) then
		gadgetHandler:RemoveGadget()
		return
	end
	local allyteams = spGetAllyTeamList()
	for _,allyTeam in pairs(allyteams) do
		AllyTeams[#AllyTeams+1] = allyTeam
	end
	if (COMMUNISM) then -- TODO, spectator team should be ignored... not like it matters much
		local teams = spGetTeamList()
		for _,t in pairs(teams) do
			TeamData[t] = {}
			OwnsOreToTeam[t] = false
			local allies = 0
			local myAllyTeam = select(6,spGetTeamInfo(t))
			for _,t2 in pairs(teams) do
				if (t ~= t2) and (myAllyTeam == select(6,spGetTeamInfo(t2))) then
					TeamData[t][#TeamData[t]+1] = t2
					allies = allies + 1
				end
			end
			if (allies > 0) then
				MinedOre[t] = 0 -- more than 1 ally, >=2 player team!
			else
				TeamData[t] = nil -- 1 team allyteam, no need to share income!
			end
		end
	else
		gadgetHandler:RemoveCallIn("AllowFeatureBuildStep")
		gadgetHandler:RemoveCallIn("AllowUnitBuildStep")
		ShareMinedOre = function() end
	end
	if not(INVULNERABLE_EXTRACTORS) then
		gadgetHandler:RemoveCallIn("AllowWeaponTarget")
		gadgetHandler:RemoveCallIn("UnitPreDamaged")
		gadgetHandler:RemoveCallIn("AllowCommand")
	end
	if not(INVULNERABLE_EXTRACTORS) or not(OBEY_OD) then
		TransferLoop = function() end
	end
	if (ORE_DMG==0) then
		InflictOreDamage = function() end
	end
	if (gameframe > 1) then
		ReInit(true)
	end
end

function gadget:GameStart()
	if Spring.Utilities.tobool(Spring.GetGameRulesParam("loadedGame")) then
		return
	end
	if (tonumber(modOptions.oremex) == 1) then
		ReInit(false)
	end
end

function gadget:UnitFinished(unitID, unitDefID, unitTeam)
	UnitFin(unitID, unitDefID, unitTeam)
end

function gadget:AllowCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions) --, fromSynced)
	if (cmdID == CMD_ATTACK) then
--		 local unitIDs = {}
		cmdList = Spring.GetCommandQueue(unitID, -1)
		for i=1,#cmdList do
			if (OreMex[cmdList[i].params[1]]) then
				spGiveOrderToUnit(unitID, CMD_REMOVE, {cmdList[i].tag}, {})
			end
		end
		if (#cmdParams == 1) and (OreMex[cmdParams[1]]) then
			return false 
		end
	end
	if (OreMex[unitID]) and (cmdID == CMD_SELFD) then
		return false
	end
	return true
end


----------------------------------------------------------------
-- UNSYNCED
----------------------------------------------------------------
else
--[[
local spGetLocalAllyTeamID = Spring.GetLocalAllyTeamID
local spGetMyPlayerID	   = Spring.GetMyPlayerID

local function showIncomeLabel(_, allyTeam, unitID, income)
	local myAllyTeam = spGetLocalAllyTeamID()
	if (Script.LuaUI('oremexIncomeAdd') and (myAllyTeam == allyTeam)) then
		Script.LuaUI.oremexIncomeAdd(spGetMyPlayerID(),unitID,income)
	end
end

function gadget:Initialize()
	gadgetHandler:AddSyncAction("oremexIncomeAdd", showIncomeLabel)
end


function gadget:Shutdown()
	gadgetHandler:RemoveSyncAction("oremexIncomeAdd")
end
--]]
end