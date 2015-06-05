function gadget:GetInfo()
  return {
    name      = "StartSetup",
    desc      = "Implements initial setup: start units, resources, and plop for construction",
    author    = "Licho, CarRepairer, Google Frog, SirMaverick",
    date      = "2008-2010",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true  --  loaded by default?
  }
end

-- partially based on Spring's unit spawn gadget
include "LuaRules/Configs/start_setup.lua"

if VFS.FileExists("mission.lua") then -- this is a mission, we just want to set starting storage (and enable facplopping)
  if not gadgetHandler:IsSyncedCode() then
    return false -- no unsynced code
  end

  local ploppableDefs = {}
  
  function gadget:Initialize()
    for _, teamID in ipairs(Spring.GetTeamList()) do
      Spring.SetTeamResource(teamID, "es", START_STORAGE + OVERDRIVE_BUFFER)
      Spring.SetTeamResource(teamID, "ms", START_STORAGE)
    end
    for i, v in pairs(ploppables) do
      local name = UnitDefNames[v]
      if name then
        local ud = name.id
        if ud then
          ploppableDefs[ud] = true
        end
      end
    end
  end

  function GG.SetStartLocation() end
  
  function gadget:UnitCreated(unitID, unitDefID, teamID, builderID)
    if ploppableDefs[unitDefID] and (Spring.GetUnitRulesParam(builderID, "facplop") == 1) then
      Spring.SetUnitRulesParam(builderID,"facplop",0, {inlos = true})
      local maxHealth = select(2,Spring.GetUnitHealth(unitID))
      Spring.SetUnitHealth(unitID, {health = maxHealth, build = 1})
      local x,y,z = Spring.GetUnitPosition(unitID)
      Spring.SpawnCEG("gate", x, y, z)
    end
  end
  
  return
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
local spGetTeamInfo 		= Spring.GetTeamInfo
local spGetPlayerInfo 		= Spring.GetPlayerInfo
local spGetSpectatingState 	= Spring.GetSpectatingState
local spGetPlayerList		= Spring.GetPlayerList

local modOptions = Spring.GetModOptions()

local coop = Spring.Utilities.tobool(Spring.GetModOption("coop", false, false))
local dotaMode = Spring.GetModOptions().zkmode == "dota"
local ctfMode = Spring.GetModOptions().zkmode == "ctf"
local playerChickens = Spring.Utilities.tobool(Spring.GetModOption("playerchickens", false, false))
local startboxString = Spring.GetModOptions().startboxes
local startboxConfig = startboxString and (loadstring(startboxString)()) or {}
--Spring.Echo(coop == 1, coop == 0)

local gaiateam = Spring.GetGaiaTeamID()
local gaiaally = select(6, spGetTeamInfo(gaiateam))

local SAVE_FILE = "Gadgets/start_unit_setup.lua"

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if (gadgetHandler:IsSyncedCode()) then
  
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local ploppableDefs = {}

local gamestart = false
--local createBeforeGameStart = {}	-- no longer used
local scheduledSpawn = {}
local luaSetStartPositions = {}
local playerSides = {} -- sides selected ingame from widget  - per players
local teamSides = {} -- sides selected ingame from widgets - per teams

local playerIDsByName = {}
local customComms = {}
local commChoice = {}
local customKeys = {}	-- [playerID] = {}

--local prespawnedCommIDs = {}	-- [teamID] = unitID

GG.startUnits = {}
GG.CommanderSpawnLocation = {}

local waitingForComm = {}
GG.waitingForComm = waitingForComm

-- overlaps with the rulesparam
local commSpawnedTeam = {}
local commSpawnedPlayer = {}

-- allow gadget:Save (unsynced) to reach them
_G.waitingForComm = waitingForComm
_G.scheduledSpawn = scheduledSpawn
_G.playerSides = playerSides
_G.teamSides = teamSides
_G.commSpawnedTeam = commSpawnedTeam
_G.commSpawnedPlayer = commSpawnedPlayer

local loadGame = false	-- was this loaded from a savegame?

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function gadget:UnitCreated(unitID, unitDefID, teamID, builderID)
	if ploppableDefs[unitDefID] and (Spring.GetUnitRulesParam(builderID, "facplop") == 1) then
		Spring.SetUnitRulesParam(builderID,"facplop",0, {inlos = true})
		local maxHealth = select(2,Spring.GetUnitHealth(unitID))
		Spring.SetUnitHealth(unitID, {health = maxHealth, build = 1 })
		local x,y,z = Spring.GetUnitPosition(unitID)
		Spring.SpawnCEG("gate", x, y, z)
		if GG.mod_stats_AddFactoryPlop then
			GG.mod_stats_AddFactoryPlop(teamID, unitDefID)
		end
		-- Spring.PlaySoundFile("sounds/misc/teleport2.wav", 10, x, y, z) -- performance loss
	end
end

local function InitUnsafe()
	-- for name, id in pairs(playerIDsByName) do
	for index, id in pairs(Spring.GetPlayerList()) do	
		-- copied from PlanetWars
		local commData, success
		customKeys[id] = select(10, spGetPlayerInfo(id))
		local commDataRaw = customKeys[id] and customKeys[id].commanders
		if not (commDataRaw and type(commDataRaw) == 'string') then
			if commDataRaw then
				err = "Comm data entry for player "..id.." is in invalid format"
			end
			commData = {}
		else
			commDataRaw = string.gsub(commDataRaw, '_', '=')
			commDataRaw = Spring.Utilities.Base64Decode(commDataRaw)
			--Spring.Echo(commDataRaw)
			local commDataFunc, err = loadstring("return "..commDataRaw)
			if commDataFunc then 
				success, commData = pcall(commDataFunc)
				if not success then
					err = commData
					commData = {}
				end
			end
		end
		if err then 
			Spring.Log(gadget:GetInfo().name, LOG.WARNING, 'Start Unit Setup warning: ' .. err)
		end

		-- record the player's first-level comm def for each chassis
		for commSeries, subdata in pairs(commData) do
			customComms[id] = customComms[id] or {}
			customComms[id][commSeries] = subdata[1]
			--Spring.Echo(id,"comm"..chassis, subdata[1])
		end
		
		-- this method makes no sense, it's not like any given generated def will be used for more than one replacement/player!
		-- would be more logical to use replacee as key and replacement as value in player customkeys
		--[[
		customComms[id] = customComms[id] or {}
		for replacementComm, replacees in pairs(commData) do
			for _,name in pairs(replacees) do
				customComms[id][name] = replacementComm
			end
		end
		]]--
	end
end


function gadget:Initialize()
  -- self linking

    for i, v in pairs(ploppables) do
      local name = UnitDefNames[v]
      if name then
        local ud = name.id
        if ud then
          ploppableDefs[ud] = true
        end
      end
    end

  -- needed if you reload luarules
  local frame = Spring.GetGameFrame()
  if frame and frame > 0 then
    gamestart = true
  end
  
  InitUnsafe()
  local allUnits = Spring.GetAllUnits()
  for _, unitID in pairs(allUnits) do
	local udid = Spring.GetUnitDefID(unitID)
	if udid then
		gadget:UnitCreated(unitID, udid, Spring.GetUnitTeam(unitID))
	end
  end

end

local function GetStartUnit(teamID, playerID, isAI)

	if Spring.GetModOption("forcejunior", true, false) then
		return "commbasic"
	end

  local startUnit

  if isAI then -- AI that didn't pick comm type gets default comm
    return (Spring.GetTeamRulesParam(teamID, "start_unit") or "armcom1")
  end

  if (teamID and teamSides[teamID]) then 
	startUnit = startUnits[teamSides[teamID]]
  end

  if (playerID and playerSides[playerID]) then 
	startUnit = startUnits[playerSides[playerID]]
  end
  
  -- if a replacement def is available, use it  
  playerID = playerID or (teamID and select(2, spGetTeamInfo(teamID)) )
  if (playerID and commChoice[playerID]) then
	--Spring.Echo("Attempting to load alternate comm")
	local altComm = customComms[playerID][(commChoice[playerID])]
	startUnit = (altComm and UnitDefNames[altComm] and altComm) or startUnit
  end
  
  -- hack workaround for chicken
  --local luaAI = Spring.GetTeamLuaAI(teamID)
  --if luaAI and string.find(string.lower(luaAI), "chicken") then startUnit = nil end
  
  --if didn't pick a comm, wait for user to pick
  return startUnit or nil	-- startUnit or DEFAULT_UNIT
end


local function GetFacingDirection(x, z, teamID)
	local facing = "south"

	local allyCount = #Spring.GetAllyTeamList()
	if (allyCount ~= 2+1) then -- +1 cause of gaia
		-- face to map center
		facing = (math.abs(Game.mapSizeX/2 - x) > math.abs(Game.mapSizeZ/2 - z))
			and ((x>Game.mapSizeX/2) and "west" or "east")
			or ((z>Game.mapSizeZ/2) and "north" or "south")
	else
		local allyID = select(6, spGetTeamInfo(teamID))
		local enemyAllyID = gaiaally

		-- detect enemy allyid
		local allyList = Spring.GetAllyTeamList()
		for i=1,#allyList do
			if (allyList[i] ~= allyID)and(allyList[i] ~= gaiaally) then
				enemyAllyID = allyList[i]
				break
			end
		end
		assert(enemyAllyID ~= gaiaally, "couldn't detect enemy ally id!")

		-- face to enemy
		local enemyStartbox = {Spring.GetAllyTeamStartBox(enemyAllyID)}
		local midPosX = (enemyStartbox[1] + enemyStartbox[3]) * 0.5
		local midPosZ = (enemyStartbox[2] + enemyStartbox[4]) * 0.5

		local dirX = midPosX - x
		local dirZ = midPosZ - z

		if (math.abs(dirX) > math.abs(dirZ)) then --distance in X direction is greater than distance in Z direction?
			facing = (dirX < 0)and("west")or("east") --is distance (X) in negative direction? (left?)
		else --if distance in Z direction is greater, then:
			facing = (dirZ > 0)and("south")or("north") --is distance (Z) in positive direction? (down?)
		end
	end

	return facing
end

local function getMiddleOfStartBox(teamID)
	if not startboxString then -- legacy boxes
		local allyTeam = select(6, spGetTeamInfo(teamID))
		local x1, z1, x2, z2 = Spring.GetAllyTeamStartBox(allyTeam)

		local x = x1 + (x2 - x1)*0.5
		local z = z1 + (z2 - z1)*0.5
		local y = Spring.GetGroundHeight(x,z)

		return x, y, z
	else
		local boxID = Spring.GetTeamRulesParam(teamID, "start_box_id")
		local box = boxID and startboxConfig[boxID] or {0,0,1,1}
		local x = (box[1]+box[3])/2 * Game.mapSizeX
		local z = (box[2]+box[4])/2 * Game.mapSizeZ
		local y = Spring.GetGroundHeight(x,z)

		return x, y, z
	end
end

local function SpawnStartUnit(teamID, playerID, isAI, bonusSpawn, notAtTheStartOfTheGame)
  local luaAI = Spring.GetTeamLuaAI(teamID)
  if luaAI and string.find(string.lower(luaAI), "chicken") then
    return false
  elseif playerChickens then
    -- allied to latest chicken team? no com for you
    local chickenTeamID = -1
    for _,t in pairs(Spring.GetTeamList()) do
      local luaAI = Spring.GetTeamLuaAI(t)
      if luaAI and string.find(string.lower(luaAI), "chicken") then
	chickenTeamID = t
      end
    end
    if (chickenTeamID > -1) and (Spring.AreTeamsAllied(teamID,chickenTeamID)) then
      --Spring.Echo("chicken_control detected no com for "..playerID)
      return false
    end
  end
  
  -- get start unit
  local startUnit = GetStartUnit(teamID, playerID, isAI)
  
  if ((coop and playerID and commSpawnedPlayer[playerID]) or (not coop and commSpawnedTeam[teamID]))
  and not bonusSpawn then
    return false
  end

  if bonusSpawn then
  	--startUnit = DEFAULT_UNIT
  end
  
  local keys = customKeys[playerID] or customKeys[select(2, spGetTeamInfo(teamID))]
  if keys and keys.jokecomm then
	startUnit = DEFAULT_UNIT
  end    
  
  if startUnit then
    -- replace with shuffled position
	local x,y,z
	local startPosition = luaSetStartPositions[teamID]
	if not startPosition then
		if (startboxString and not Spring.GetTeamRulesParam(teamID, "valid_startpos")) or (notAtTheStartOfTheGame and (Game.startPosType == 2)) then
			x,y,z = getMiddleOfStartBox(teamID)
		else
			x,y,z = Spring.GetTeamStartPosition(teamID)
		end
	else
		x,y,z = startPosition.x, startPosition.y, startPosition.z
	end

    -- get facing direction
    local facing = GetFacingDirection(x, z, teamID)

	GG.startUnits[teamID] = startUnit
	GG.CommanderSpawnLocation[teamID] = {x = x, y = y, z = z, facing = facing}
	
    -- CREATE UNIT
	local unitID
    --if Spring.GetGameFrame() <= 1 then
	--	unitID = Spring.CreateUnit(startUnit, x, y, z, facing, teamID)
	--else
		unitID = GG.DropUnit(startUnit, x, y, z, facing, teamID)
	--end
	if Spring.GetGameFrame() <= 1 then
		Spring.SpawnCEG("gate", x, y, z)
		-- Spring.PlaySoundFile("sounds/misc/teleport2.wav", 10, x, y, z) -- performance loss
	end
	
	if not bonusSpawn then
		Spring.SetTeamRulesParam(teamID, "commSpawned", 1, {allied = true})
		commSpawnedTeam[teamID] = true
		if playerID then
		  Spring.SetGameRulesParam("commSpawnedPlayer"..playerID, 1, {allied = true})
		  commSpawnedPlayer[playerID] = true 
		end
		waitingForComm[teamID] = nil
	end
	
    -- set the *team's* lineage root
    if Spring.SetUnitLineage then
      Spring.SetUnitLineage(unitID, teamID, true)
    end

    -- add facplop
    local teamLuaAI = Spring.GetTeamLuaAI(teamID)
    local udef = UnitDefs[Spring.GetUnitDefID(unitID)]

    local validTeam = (teamID ~= gaiateam and ((not teamLuaAI) or teamLuaAI == "" or teamLuaAI:sub(1,3) == "CAI"))

	local commCost = (udef.metalCost or BASE_COMM_COST) - BASE_COMM_COST			
				
    if validTeam then

	  local metal, metalStore = Spring.GetTeamResources(teamID, "metal")
	  local energy, energyStore = Spring.GetTeamResources(teamID, "energy")
		
        -- the adding of existing resources is necessary for handling /take and spawn
		local bonus = (keys and tonumber(keys.bonusresources)) or 0
		
        Spring.SetTeamResource(teamID, "es", START_STORAGE + energyStore  + bonus)
        Spring.SetTeamResource(teamID, "ms", START_STORAGE + metalStore + bonus)
        Spring.SetTeamResource(teamID, "energy", START_ENERGY + energy - commCost + bonus)
        Spring.SetTeamResource(teamID, "metal", START_METAL + metal - commCost + bonus)

      if (udef.customParams.level and udef.name ~= "chickenbroodqueen") then
        Spring.SetUnitRulesParam(unitID, "facplop", 1, {inlos = true})
      end

    end

    return true
  end
  return false
end

local function StartUnitPicked(playerID, name)
	local _,_,spec,teamID = spGetPlayerInfo(playerID)
	if spec then return end
	teamSides[teamID] = name
	local startUnit = GetStartUnit(teamID, playerID)
	if startUnit then
		Spring.SetTeamRulesParam(teamID, "commChoice", UnitDefNames[startUnit].id)
	end
	if gamestart then
		-- picked commander after game start, prep for orbital drop
		-- can't do it directly because that's an unsafe change
		local frame = Spring.GetGameFrame() + 3
		if not scheduledSpawn[frame] then scheduledSpawn[frame] = {} end
		scheduledSpawn[frame][#scheduledSpawn[frame] + 1] = {teamID, playerID}
	else
		--[[
		if startPosition[teamID] then
			local oldCommID = prespawnedCommIDs[teamID]
			local pos = startPosition[teamID]
			local startUnit = GetStartUnit(teamID, playerID, isAI)
			if startUnit then
				local newCommID = Spring.CreateUnit(startUnit, pos.x, pos.y, pos.z , "s", 0)
				if oldCommID then
					local cmds = Spring.GetCommandQueue(oldCommID, -1)
					--//transfer command queue
					for i = 1, #cmds do
						local cmd = cmds[i]
						Spring.GiveOrderToUnit(newUnit, cmd.id, cmd.params, cmd.options.coded)
					end
					Spring.DestroyUnit(oldCommID, false, true)
				end
				prespawnedCommIDs[teamID] = newCommID
			end
		end
		]]
	end
	GG.startUnits[teamID] = GetStartUnit(teamID) -- ctf compatibility
end

local function workAroundSpecsInTeamZero(playerlist, team)
  if team == 0 then
    local players = #playerlist
    local specs = 0
    -- count specs
    for i=1,#playerlist do
      local _,_,spec = spGetPlayerInfo(playerlist[i])
      if spec then specs = specs + 1 end
    end
    if players == specs then
      return nil
    end
  end
  return playerlist
end

--[[
   This function return true if everyone in the team resigned.
   This function is alternative to "isDead" from: "_,_,isDead,isAI = spGetTeamInfo(team)"
   because "isDead" failed to return true when human team resigned before GameStart() event.
--]]
local function IsTeamResigned(team)
	local playersInTeam = spGetPlayerList(team)
	for j=1,#playersInTeam do
		local spec = select(3,spGetPlayerInfo(playersInTeam[j]))
		if not spec then
			return false
		end
	end
	return true
end

function gadget:GameStart()
	if Spring.Utilities.tobool(Spring.GetGameRulesParam("loadedGame")) then
		return
	end
  gamestart = true

  -- spawn units
  for i,team in ipairs(Spring.GetTeamList()) do

    -- clear resources
    -- actual resources are set depending on spawned unit and setup
	if not loadGame then
		Spring.SetTeamResource(team, "es", 0 + OVERDRIVE_BUFFER)
		Spring.SetTeamResource(team, "ms", 0)
		Spring.SetTeamResource(team, "energy", 0)
		Spring.SetTeamResource(team, "metal", 0)
	end
	
	--check if player resigned before game started
	local _,playerID,_,isAI = spGetTeamInfo(team)
	local deadPlayer = (not isAI) and IsTeamResigned(team)
	
	if team ~= gaiateam and not deadPlayer then
	  local luaAI = Spring.GetTeamLuaAI(team)
	  if not (luaAI and string.find(string.lower(luaAI), "chicken")) then
		waitingForComm[team] = true
	  end
      if coop then
        -- 1 start unit per player
        local playerlist = Spring.GetPlayerList(team, true)
        playerlist = workAroundSpecsInTeamZero(playerlist, team)
        if playerlist and (#playerlist > 0) then
          for i=1,#playerlist do
            local _,_,spec = spGetPlayerInfo(playerlist[i])
            if (not spec) then
              SpawnStartUnit(team, playerlist[i])
            end
          end
        else
          -- AI etc.
          SpawnStartUnit(team, nil, true)
        end
      else -- no coop
        if (playerID) then
          local _,_,spec,teamID = spGetPlayerInfo(playerID)
          if (teamID == team and not spec) then
            isAI = false
          else
            playerID = nil
          end
        end
        
        SpawnStartUnit(team, playerID, isAI)
      end
	  
	  -- extra comms
	  local playerlist = Spring.GetPlayerList(team, true)
      playerlist = workAroundSpecsInTeamZero(playerlist, team)
      if playerlist then
        for i=1,#playerlist do
			if customKeys[playerlist[i]] and customKeys[playerlist[i]].extracomm then
				for j=1, tonumber(customKeys[playerlist[i]].extracomm) do
					SpawnStartUnit(team, playerlist[i], false, true)
				end
			end
        end
      end
    end
  end
end

function gadget:RecvLuaMsg(msg, playerID)
	if msg:find("faction:",1,true) then
		local side = msg:sub(9)
		playerSides[playerID] = side
		commChoice[playerID] = nil	-- unselect existing custom comm, if any
		StartUnitPicked(playerID, side)
	elseif msg:find("customcomm:",1,true) then
		local name = msg:sub(12)
		SendToUnsynced("CommSelected",playerID, name) --activate an event called "CommSelected" that can be detected in unsynced part
		commChoice[playerID] = name
		StartUnitPicked(playerID, name)
	end	
end

-- used by CAI. Could be extended to allow widgets to set start location? 
local function SetStartLocation(teamID, x, z)
    luaSetStartPositions[teamID] = {x = x, y = Spring.GetGroundHeight(x,z), z = z}
end
GG.SetStartLocation = SetStartLocation

function gadget:GameFrame(n)
  if n == (COMM_SELECT_TIMEOUT) then
	for team in pairs(waitingForComm) do
		local _,playerID = spGetTeamInfo(team)
		teamSides[team] = DEFAULT_UNIT_TEAMSIDES
		--playerSides[playerID] = "basiccomm"
		scheduledSpawn[n] = scheduledSpawn[n] or {}
		scheduledSpawn[n][#scheduledSpawn[n] + 1] = {team, playerID} -- playerID is needed here so the player can't spawn coms 2 times in coop mode
	end
  end
  if scheduledSpawn[n] then
	for _, spawnData in pairs(scheduledSpawn[n]) do
    local teamID, playerID = spawnData[1], spawnData[2]
    local canSpawn = SpawnStartUnit(teamID, playerID, false, false, true)
    
    if (canSpawn) then
      -- extra comms
      if playerID and customKeys[playerID] and customKeys[playerID].extracomm then
        for j=1, tonumber(customKeys[playerID].extracomm) do
          SpawnStartUnit(teamID, playerID, false, true, true)
        end
      end
    end
	end
	scheduledSpawn[n] = nil
  end
end

function gadget:Shutdown()
	--Spring.Echo("<Start Unit Setup> Going to sleep...")
end

function gadget:Load(zip)
	if not GG.SaveLoad then
		Spring.Log(gadget:GetInfo().name, LOG.ERROR, "Start Unit Setup failed to access save/load API")
		return
	end
	loadGame = true
	local data = GG.SaveLoad.ReadFile(zip, "Start Unit Setup", SAVE_FILE) or {}

	-- load data wholesale
	waitingForComm = data.waitingForComm or {}
	scheduledSpawn = data.scheduledSpawn or {}
	playerSides = data.playerSides or {}
	teamSides = data.teamSides or {}
	commSpawnedPlayer = data.commSpawnedPlayer or {}
	commSpawnedTeam = data.commSpawnedTeam or {}
end

--------------------------------------------------------------------
-- unsynced code
--------------------------------------------------------------------
else

local teamID 			= Spring.GetLocalTeamID()
local spGetUnitDefID 	= Spring.GetUnitDefID
local spGetUnitLosState = Spring.GetUnitLosState
local spValidUnitID 	= Spring.ValidUnitID
local spAreTeamsAllied 	= Spring.AreTeamsAllied
local spGetUnitTeam 	= Spring.GetUnitTeam


function gadget:Initialize()
  gadgetHandler:AddSyncAction('CommSelected',CommSelection) --Associate "CommSelected" event to "WrapToLuaUI". Reference: http://springrts.com/phpbb/viewtopic.php?f=23&t=24781 "Gadget and Widget Cross Communication"

end
  
function CommSelection(_,playerID,commSeries)
	if (Script.LuaUI('CommSelection')) then --if there is widgets subscribing to "CommSelection" function then:
		local isSpec = Spring.GetSpectatingState() --receiver player is spectator?
		local myAllyID = Spring.GetMyAllyTeamID() --receiver player's alliance?
		local _,_,_,_, eventAllyID,_,_,_,_ = Spring.GetPlayerInfo(playerID) --source alliance?
		if isSpec or myAllyID == eventAllyID then
			Script.LuaUI.CommSelection(playerID, commSeries) --send to widgets as event
		end
	end
end

local MakeRealTable = Spring.Utilities.MakeRealTable

function gadget:Save(zip)
	if not GG.SaveLoad then
		Spring.Log(gadget:GetInfo().name, LOG.ERROR, "Start Unit Setup failed to access save/load API")
		return
	end
	local toSave = {
		waitingForComm = MakeRealTable(SYNCED.waitingForComm),
		scheduledSpawn = MakeRealTable(SYNCED.scheduledSpawn),
		playerSides = MakeRealTable(SYNCED.playerSides),
		teamSides = MakeRealTable(SYNCED.teamSides),
		commSpawnedPlayer = MakeRealTable(SYNCED.commSpawnedPlayer),
		commSpawnedTeam = MakeRealTable(SYNCED.commSpawnedTeam),
	}
	GG.SaveLoad.WriteSaveData(zip, SAVE_FILE, toSave)
end

end
