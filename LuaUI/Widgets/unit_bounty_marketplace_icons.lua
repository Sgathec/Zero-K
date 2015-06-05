-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "Bounty & Marketplace Icons (experimental)",
    desc      = "Shows bounty and marketplace icons",
    author    = "CarRepairer",
	version   = "0.023",
    date      = "2012-01-28",
    license   = "GNU GPL, v2 or later",
    layer     = 5,
    enabled   = true,
  }
end

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------

local echo = Spring.Echo

local spGetAllUnits			= Spring.GetAllUnits
local spGetVisibleUnits		= Spring.GetVisibleUnits

local min   = math.min
local floor = math.floor

----------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------


include("keysym.h.lua")
local iconTypes = { 'bounty', 'buy', 'sell' }
local teamList = {}
local teamColors = {}
local myAllyTeamID = 666

local imageDir = 'LuaUI/Images/bountymarketplaceicons/'

local marketandbounty 	= false

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------

local function tobool(val)
  local t = type(val)
  if (t == 'nil') then return false
  elseif (t == 'boolean') then	return val
  elseif (t == 'number') then	return (val ~= 0)
  elseif (t == 'string') then	return ((val ~= '0') and (val ~= 'false'))
  end
  return false
end

function SetIcons(unitID, iconType)
	--for _, teamID in ipairs(Spring.GetTeamList()) do
	for i = 1, #teamList do
		local teamID = teamList[i]
		local price = Spring.GetUnitRulesParam( unitID, iconType .. teamID )
		
		if price and price > 0 then
			local icon = imageDir .. iconType.. price ..'.png'
			if not VFS.FileExists(icon) then
				icon = imageDir .. iconType .. 'notfound.png'
			end
					
			local teamColor = teamColors[teamID] or {1,1,1,1}
			WG.icons.SetUnitIcon( unitID, {name=iconType..teamID, texture=icon, color=teamColor } )
		else
			WG.icons.SetUnitIcon( unitID, {name=iconType..teamID, texture=nil } )
		end
	end
	
end

local function UpdateAllUnits()
	teamList = Spring.GetTeamList()
	for i = 1, #teamList do
		local teamID = teamList[i]
		teamColors[teamID] = {Spring.GetTeamColor(teamID)}
	end
	
	for _,unitID in ipairs( spGetAllUnits() ) do
		for _,iconType in ipairs( iconTypes ) do
			SetIcons(unitID, iconType )
		end
	end
end

local function UpdateVisibleUnits()
	for _,unitID in ipairs( spGetVisibleUnits() ) do
		for _,iconType in ipairs( iconTypes ) do
			SetIcons(unitID, iconType )
		end
	end
end

-------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------


function widget:UnitCreated(unitID, unitDefID, unitTeam)
	for _,iconType in ipairs( iconTypes ) do
		SetIcons(unitID, iconType )
	end
end


function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
	if not Spring.IsUnitAllied(unitID) then return end

	for _,iconType in ipairs( iconTypes ) do
		for _, teamID in ipairs(Spring.GetTeamList()) do
			WG.icons.SetUnitIcon( unitID, {name=iconType.. teamID, texture=nil} )
		end
	end
end

--needed if icon widget gets disabled/enabled after this one. find a better way?
function widget:GameFrame(f)
	if f%(32*6) == 0 then
		UpdateAllUnits()
	elseif f%(32*2) == 0 then
		UpdateVisibleUnits()
	end
end


function widget:Initialize()
	if not tobool(Spring.GetModOptions().marketandbounty) then
		echo('Marketplace and Bounty Icons: Widget removed.')
		widgetHandler:RemoveWidget()
	end 
	for _, teamID in ipairs(Spring.GetTeamList()) do
		WG.icons.SetOrder( 'bounty'..teamID, 9+teamID )
		WG.icons.SetDisplay('bounty'..teamID, true)
		
		WG.icons.SetOrder( 'sell'..teamID, 10+teamID )
		WG.icons.SetDisplay('bounty'..teamID, true)
		
		WG.icons.SetOrder( 'sell'..teamID, 11+teamID )
		WG.icons.SetDisplay('bounty'..teamID, true)	
	
	end
	
	UpdateAllUnits()
	
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
