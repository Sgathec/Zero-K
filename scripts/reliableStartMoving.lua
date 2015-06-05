local isNewEngine = not ((Game.version:find('91.0') == 1) and (Game.version:find('91.0.1') == nil))

local spGetGroundHeight = Spring.GetGroundHeight
local spGetUnitVelocity = Spring.GetUnitVelocity
local spGetUnitPosition = Spring.GetUnitPosition

function StartStopMovingControl(startFunc, stopFunc, thresholdSpeed, fallingCountsAsMoving)
	thresholdSpeed = thresholdSpeed or 0.05
	local x,y,z, height, speed
	local moving = false
	while true do
		x,y,z = spGetUnitPosition(unitID)
		height = spGetGroundHeight(x,z)
		if y - height < 1 then
			if isNewEngine then
				speed = select(4,spGetUnitVelocity(unitID))
			else
				x,y,z = spGetUnitVelocity(unitID)
				speed = math.sqrt(x*x+y*y+z*z)
			end
			if moving then
				if speed <= thresholdSpeed then
					moving = false
					stopFunc()
				end
			else
				if speed > thresholdSpeed then
					moving = true
					startFunc()
				end
			end
		elseif fallingCountsAsMoving then
			if not moving then
				moving = true
				startFunc()
			end
		end
		Sleep(60)
	end
end