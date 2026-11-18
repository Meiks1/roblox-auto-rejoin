-- Roblox Auto Rejoin
-- Rejoins automatically when you get disconnected or kicked.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local placeId = game.PlaceId
local jobId = game.JobId

local REJOIN_SAME_SERVER = true -- false = join any server
local DELAY = 2 -- seconds before rejoining
local RELOAD_ON_TELEPORT = true -- re-run this script after rejoining

local SCRIPT_URL = "https://raw.githubusercontent.com/YOUR_USERNAME/roblox-auto-rejoin/main/autorejoin.lua"

local rejoining = false

local function rejoin()
    if rejoining then return end
    rejoining = true
    task.wait(DELAY)

    if RELOAD_ON_TELEPORT and queue_on_teleport then
        queue_on_teleport(('loadstring(game:HttpGet("%s"))()'):format(SCRIPT_URL))
    end

    if REJOIN_SAME_SERVER and #Players:GetPlayers() > 1 then
        TeleportService:TeleportToPlaceInstance(placeId, jobId, player)
    else
        TeleportService:Teleport(placeId, player)
    end
end

-- Fires when the disconnect/kick error prompt appears
local overlay = CoreGui:WaitForChild("RobloxPromptGui"):WaitForChild("promptOverlay")
overlay.ChildAdded:Connect(function(child)
    if child.Name == "ErrorPrompt" then
        rejoin()
    end
end)

-- Retry if a teleport fails
TeleportService.TeleportInitFailed:Connect(function()
    rejoining = false
    rejoin()
end)
