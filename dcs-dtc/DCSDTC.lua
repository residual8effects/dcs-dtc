local tcpServer = nil
local udpSpeaker = nil
package.path  = package.path..";"..lfs.currentdir().."/LuaSocket/?.lua"
package.cpath = package.cpath..";"..lfs.currentdir().."/LuaSocket/?.dll"
package.path  = package.path..";"..lfs.currentdir().."/Scripts/?.lua"
local socket = require("socket")

local JSON = loadfile("Scripts\\JSON.lua")()
local needDelay = false
local keypressinprogress = false
local data
local delay = 0
local delayNeeded = 0
local delayStart = 0
local code = ""
local device = ""
local nextIndex = 1

local tcpPort = 43001
local udpPort = 43000

local upstreamLuaExportStart = LuaExportStart
local upstreamLuaExportAfterNextFrame = LuaExportAfterNextFrame
local upstreamLuaExportBeforeNextFrame = LuaExportBeforeNextFrame

function LuaExportStart()
    if upstreamLuaExportStart ~= nil then
        successful, err = pcall(upstreamLuaExportStart)
        if not successful then
            log.write("DCS-DTC", log.ERROR, "Error in upstream LuaExportStart function"..tostring(err))
        end
    end
    
	udpSpeaker = socket.udp()
	udpSpeaker:settimeout(0)
	tcpServer = socket.tcp()
    successful, err = tcpServer:bind("127.0.0.1", tcpPort)
    tcpServer:listen(1)
    tcpServer:settimeout(0)
	if not successful then
		log.write("DCS-DTC", log.ERROR, "Error opening tcp socket - "..tostring(err))
	else
		log.write("DCS-DTC", log.INFO, "Opened connection")
	end
end

function LuaExportBeforeNextFrame()
    if upstreamLuaExportBeforeNextFrame ~= nil then
        successful, err = pcall(upstreamLuaExportBeforeNextFrame)
        if not successful then
           log.write("DCS-DTC", log.ERROR, "Error in upstream LuaExportBeforeNextFrame function"..tostring(err))
        end
    end

    if needDelay then
		local currentTime = socket.gettime()
		if ((currentTime - delayStart) > delayNeeded) then
			needDelay = false
			GetDevice(device):performClickableAction(code, 0)
		end
	else
		if keypressinprogress then
			local keys = JSON:decode(data)
			for i=nextIndex, #keys do
				local keyObj = keys[i]
				device = keyObj["device"]
				code = keyObj["code"]
				delay = tonumber(keyObj["delay"])
				
				local activate = tonumber(keyObj["activate"])

				if delay > 0 then
					needDelay = true
					delayNeeded = delay / 1000
					delayStart = socket.gettime()
					GetDevice(device):performClickableAction(code, activate)
					nextIndex = i+1
					break
				else
					GetDevice(device):performClickableAction(code, activate)
                    if delay == 0 then
					    GetDevice(device):performClickableAction(code, 0)
                    end
				end
			end
			if not needDelay then
				keypressinprogress = false
				nextIndex = 1
			end
		else
		    local client, err = tcpServer:accept()

            if err ~= nil then
                log.write("DCS-DTC", log.ERROR, "Error at accepting connection: "..err)
            end
            if client ~= nil then
                client:settimeout(10)
			    data, err = client:receive()
			    if err then
				    log.write("DCS-DTC", log.ERROR, "Error at receiving: "..err)  
			    end

			    if data then 
				    keypressinprogress = true
			    end
            end
		end
	end
end

function LuaExportAfterNextFrame()
    if upstreamLuaExportAfterNextFrame ~= nil then
        successful, err = pcall(upstreamLuaExportAfterNextFrame)
        if not successful then
            log.write("DCS-DTC", log.ERROR, "Error in upstream LuaExportAfterNextFrame function"..tostring(err))
        end
    end


  local camPos = LoGetCameraPosition()
	local loX = camPos['p']['x']
	local loZ = camPos['p']['z']
	local elevation = LoGetAltitude(loX, loZ)
	local coords = LoLoCoordinatesToGeoCoordinates(loX, loZ)
	local model = LoGetSelfData()["Name"];

	local toSend = "{"..
		"\"model\": ".."\""..model.."\""..
		", ".."\"latitude\": ".."\""..coords.latitude.."\""..
		", ".."\"longitude\": ".."\""..coords.longitude.."\""..
		", ".."\"elevation\": ".."\""..elevation.."\""..
		"}"

	if pcall(function()
		socket.try(udpSpeaker:sendto(toSend, "127.0.0.1", udpPort)) 
	end) then
	else
		log.write("DCS-DTC", log.ERROR, "Unable to send data")
	end
end