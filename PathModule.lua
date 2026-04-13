-- This.. is pretty simple to use, may not be the best idea to give away such script, but why not help newer scripters with this - is what went through my mind by posting this, hehe.

--[[

PATHMODULE

@RealManMun 27th August 2025
Shared between client & server

Handles path caching and position / orientation queries.
I fancied a different math coding style (less spaces in codes for the little ones) to handle beziers overall.

--]]

local PathModule = {}

local RunService = game:GetService("RunService")
local IsServer = RunService:IsServer()

local function lerpVec3(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

local function quadraticBezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local u = 1 - t
	return u*u*p0 + 2*u*t*p1 + t*t*p2
end

local function quadraticBezierTangentXZ(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
	local u = 1 - t
	local vx = 2*u*(p1.X - p0.X) + 2*t*(p2.X - p1.X)
	local vz = 2*u*(p1.Z - p0.Z) + 2*t*(p2.Z - p1.Z)
	return Vector3.new(vx,0,vz)
end

local function bezierLength(p0,p1,p2,steps)
	local length = 0
	local prev = p0
	for i = 1,steps do
		local t = i/steps
		local pt = quadraticBezier(p0,p1,p2,t)
		length += (pt-prev).Magnitude
		prev = pt
	end
	return length
end

local function returnBasedOnServer(...)
	local args = {...}
	if IsServer then
		return ...
	end
	return args[1], args[2]
end

--// Cache format: pathIndex → { segments = { {type, p0,p1,p2,length} }, totalLength }
local pathCache = {}

function PathModule.precomputePath(pathIndex: number, waypoints: {Instance}, lockedY: number)
	if pathCache[pathIndex] then return end

	local segments = {}
	local totalLength = 0
	local lastPos = nil

	for i, wp in waypoints do
		local sp = wp:FindFirstChild("StartPoint")
		local ep = wp:FindFirstChild("EndPoint")
		local center = wp.Position

		if sp and ep then
			local spPos = Vector3.new(sp.Position.X, lockedY, sp.Position.Z)
			local epPos = Vector3.new(ep.Position.X, lockedY, ep.Position.Z)
			local wpPos = Vector3.new(center.X, lockedY, center.Z)

			-- 1. Linear: lastPos > StartPoint
			if lastPos then
				local len = (spPos - lastPos).Magnitude
				table.insert(segments,{
					type="line", p0=lastPos, p1=spPos, length=len, waypoint=wp,
				})
				totalLength += len
			end

			-- 2. Bezier: StartPoint > EndPoint using waypoint as control
			local bLen = bezierLength(spPos, wpPos, epPos, 12)
			table.insert(segments,{
				type="bezier", p0=spPos, p1=wpPos, p2=epPos, length=bLen, waypoint=wp,
			})
			totalLength += bLen

			lastPos = epPos
		else
			-- No start/end, just linear from lastPos > center
			local centerPos = Vector3.new(center.X, lockedY, center.Z)
			if lastPos then
				local len = (centerPos - lastPos).Magnitude
				table.insert(segments,{
					type="line", p0=lastPos, p1=centerPos, length=len, waypoint=wp,
				})
				totalLength += len
			end
			lastPos = centerPos
		end
	end

	pathCache[pathIndex] = { segments=segments, totalLength=totalLength }
end

--// Returns position, forward vector given distance along path
function PathModule.getPathPositionFromDistance(pathIndex: number, distance: number): (Vector3?, Vector3?)
	local data = pathCache[pathIndex]
	if not data then return end
	local segs = data.segments
	local total = data.totalLength
	distance = math.clamp(distance,0,total)

	for _, seg in segs do
		if distance <= seg.length then
			if seg.type=="line" then
				local t = distance/seg.length
				local pos = lerpVec3(seg.p0,seg.p1,t)
				local forward = (seg.p1 - seg.p0).Unit
				return returnBasedOnServer(pos, forward, seg.waypoint)
			elseif seg.type=="bezier" then
				local t = distance/seg.length
				local pos = quadraticBezier(seg.p0,seg.p1,seg.p2,t)
				local forward = quadraticBezierTangentXZ(seg.p0,seg.p1,seg.p2,t).Unit
				return returnBasedOnServer(pos, forward, seg.waypoint)
			end
		else
			distance -= seg.length
		end
	end

	-- fallback: last point
	local last = segs[#segs]
	if last.type=="line" then
		return last.p1,(last.p1 - last.p0).Unit
	else
		return last.p2,(last.p2 - last.p0).Unit
	end
end

function PathModule.getPathByIndex(pathIndex: number): { any }
	return pathCache[pathIndex]
end

return PathModule
