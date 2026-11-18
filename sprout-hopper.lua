-- BSS Sprout Hopper
-- Hops servers until a sprout is found, tweens to it, collects loot, then hops again.
-- NOTE: object names below are best guesses. Check them in Dex and edit CONFIG.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local player = Players.LocalPlayer
local placeId = game.PlaceId

local CONFIG = {
    SPROUT_NAME = "Sprout",      -- name of the sprout object in Workspace (verify in Dex)
    LOOT_FOLDER = "Collectibles",-- folder where loot/tokens spawn (verify in Dex)
    TWEEN_SPEED = 60,            -- studs per second (keep low to avoid kicks)
    SCAN_TIME = 6,               -- seconds to look for a sprout after joining
    FARM_TIMEOUT = 180,          -- max seconds to stay on one sprout
    LOOT_RADIUS = 45,            -- only grab loot this close to the sprout
    HOP_DELAY = 2,               -- seconds before hopping
    SWING_DELAY = 0.15,          -- seconds between tool swings (auto dig)
    HOVER_HEIGHT = 3,            -- studs above the sprout to stand
}

local SCRIPT_URL = "https://raw.githubusercontent.com/Meiks1/roblox-auto-rejoin/main/sprout-hopper.lua"
local VISITED_FILE = "sprout_hopper_visited.json"

-- ===== helpers =====
local function getRoot()
    local char = player.Character or player.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 10)
end

local function posOf(obj)
    if obj:IsA("Model") then return obj:GetPivot().Position end
    return obj.Position
end

local function tweenTo(position)
    local root = getRoot()
    if not root then return end
    local dist = (root.Position - position).Magnitude
    local t = math.max(dist / CONFIG.TWEEN_SPEED, 0.1)
    local tween = TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = CFrame.new(position)})
    tween:Play()
    tween.Completed:Wait()
end

local function findSprout()
    for _, v in ipairs(workspace:GetDescendants()) do
        if v.Name == CONFIG.SPROUT_NAME and (v:IsA("BasePart") or v:IsA("Model")) then
            return v
        end
    end
end

local function waitForSprout()
    local start = os.clock()
    while os.clock() - start < CONFIG.SCAN_TIME do
        local s = findSprout()
        if s then return s end
        task.wait(0.5)
    end
end

local function collectLootNear(center)
    local folder = workspace:FindFirstChild(CONFIG.LOOT_FOLDER)
    if not folder then return end
    for _, item in ipairs(folder:GetChildren()) do
        if item:IsA("BasePart") and (item.Position - center).Magnitude <= CONFIG.LOOT_RADIUS then
            tweenTo(item.Position)
        end
    end
end

local function equipTool()
    local char = player.Character
    if not char then return end
    if char:FindFirstChildOfClass("Tool") then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local tool = player.Backpack:FindFirstChildOfClass("Tool")
    if hum and tool then hum:EquipTool(tool) end
end

-- auto dig: swing the equipped tool
local function swing()
    equipTool()
    local char = player.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Activate() end) end
    pcall(function()
        local cf = workspace.CurrentCamera.CFrame
        VirtualUser:Button1Down(Vector2.new(0, 0), cf)
        task.wait(0.03)
        VirtualUser:Button1Up(Vector2.new(0, 0), cf)
    end)
end

local function farm(sprout)
    local start = os.clock()
    tweenTo(posOf(sprout) + Vector3.new(0, CONFIG.HOVER_HEIGHT, 0))
    local lastLoot = 0

    -- farm until the sprout is gone (or timeout)
    while sprout.Parent and os.clock() - start < CONFIG.FARM_TIMEOUT do
        swing()
        -- every ~2s, grab loot, then return to the sprout
        if os.clock() - lastLoot > 2 then
            lastLoot = os.clock()
            collectLootNear(posOf(sprout))
            if sprout.Parent then
                tweenTo(posOf(sprout) + Vector3.new(0, CONFIG.HOVER_HEIGHT, 0))
            end
        end
        task.wait(CONFIG.SWING_DELAY)
    end

    -- final loot sweep after the sprout is gone
    local root = getRoot()
    if root then
        local center = root.Position
        local sweepEnd = os.clock() + 5
        while os.clock() < sweepEnd do
            collectLootNear(center)
            task.wait(0.25)
        end
    end
end

-- ===== server hopping =====
local function loadVisited()
    if isfile and isfile(VISITED_FILE) then
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(VISITED_FILE)) end)
        if ok and type(data) == "table" then return data end
    end
    return {}
end

local function saveVisited(list)
    if writefile then
        while #list > 60 do table.remove(list, 1) end
        pcall(function() writefile(VISITED_FILE, HttpService:JSONEncode(list)) end)
    end
end

local function hop()
    task.wait(CONFIG.HOP_DELAY)
    local visited = loadVisited()
    table.insert(visited, game.JobId)
    saveVisited(visited)

    if queue_on_teleport then
        queue_on_teleport(('loadstring(game:HttpGet("%s"))()'):format(SCRIPT_URL))
    end

    while true do
        local ok, result = pcall(function()
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if ok and result and result.data then
            local candidates = {}
            for _, s in ipairs(result.data) do
                if s.id ~= game.JobId and s.playing < s.maxPlayers and not table.find(visited, s.id) then
                    table.insert(candidates, s.id)
                end
            end
            if #candidates > 0 then
                local pick = candidates[math.random(#candidates)]
                pcall(function() TeleportService:TeleportToPlaceInstance(placeId, pick, player) end)
                task.wait(10) -- wait for the teleport; retry if it didn't happen
            else
                visited = {} -- everything visited, start over
                saveVisited(visited)
            end
        end
        task.wait(2)
    end
end

-- ===== main =====
if not game:IsLoaded() then game.Loaded:Wait() end
getRoot()
task.wait(3)

local sprout = waitForSprout()
if sprout then
    farm(sprout)
end
hop()
