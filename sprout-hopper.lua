-- BSS Sprout Hopper (with GUI)
-- Pick which sprouts to farm and in what order, then press Start.
-- Hops servers, finds the highest-priority whitelisted sprout, tweens to it,
-- auto digs until it's gone, collects loot, then hops again.
-- NOTE: sprout names / loot folder are best guesses. Use the Add box + Dex to fix them.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local placeId = game.PlaceId

local CONFIG = {
    LOOT_FOLDER = "Collectibles",
    TWEEN_SPEED = 60,
    SCAN_TIME = 6,
    FARM_TIMEOUT = 180,
    LOOT_RADIUS = 45,
    HOP_DELAY = 2,
    SWING_DELAY = 0.15,
    HOVER_HEIGHT = 3,
    IGNORE_PATHS = {"Decoration", "Deco", "Honeycomb", "Hive"},
    SPAWN_IGNORE_RADIUS = 80,
    DEBUG = true,
}

local SCRIPT_URL = "https://raw.githubusercontent.com/YOUR_USERNAME/roblox-auto-rejoin/main/sprout-hopper.lua"
local SETTINGS_FILE = "sprout_hopper_settings.json"
local VISITED_FILE = "sprout_hopper_visited.json"

-- ===== settings (saved between hops) =====
local settings = {
    running = false,
    types = {
        {name = "Basic", on = true},
        {name = "Moon", on = true},
        {name = "Supreme", on = true},
    },
}

local function saveSettings()
    if writefile then
        pcall(function() writefile(SETTINGS_FILE, HttpService:JSONEncode(settings)) end)
    end
end

if isfile and isfile(SETTINGS_FILE) then
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(SETTINGS_FILE)) end)
    if ok and type(data) == "table" and type(data.types) == "table" then
        settings = data
    end
end

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

-- ===== GUI =====
local statusLabel
local function setStatus(text)
    if statusLabel then statusLabel.Text = "Status: " .. text end
end

local refreshList -- forward declaration
local startBtn

local function buildGui()
    local parent = (gethui and gethui()) or CoreGui
    local old = parent:FindFirstChild("SproutHopperGui")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "SproutHopperGui"
    gui.ResetOnSpawn = false
    gui.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 280, 0, 360)
    frame.Position = UDim2.new(0, 20, 0, 60)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -40, 0, 30)
    title.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    title.BorderSizePixel = 0
    title.Text = "  Sprout Hopper"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local mini = Instance.new("TextButton")
    mini.Size = UDim2.new(0, 40, 0, 30)
    mini.Position = UDim2.new(1, -40, 0, 0)
    mini.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
    mini.BorderSizePixel = 0
    mini.Text = "-"
    mini.TextColor3 = Color3.new(1, 1, 1)
    mini.Font = Enum.Font.GothamBold
    mini.TextSize = 18
    mini.Parent = frame

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, 0, 1, -30)
    body.Position = UDim2.new(0, 0, 0, 30)
    body.BackgroundTransparency = 1
    body.Parent = frame

    mini.MouseButton1Click:Connect(function()
        body.Visible = not body.Visible
        frame.Size = body.Visible and UDim2.new(0, 280, 0, 360) or UDim2.new(0, 280, 0, 30)
        mini.Text = body.Visible and "-" or "+"
    end)

    -- dragging (mouse + touch)
    local dragging, dragStart, startPos
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)

    local hint = Instance.new("TextLabel")
    hint.Size = UDim2.new(1, -16, 0, 32)
    hint.Position = UDim2.new(0, 8, 0, 4)
    hint.BackgroundTransparency = 1
    hint.Text = "Whitelist + priority (top = first). Tick to enable. Use 'Any' to farm every sprout."
    hint.TextWrapped = true
    hint.TextColor3 = Color3.fromRGB(180, 180, 190)
    hint.Font = Enum.Font.Gotham
    hint.TextSize = 11
    hint.TextXAlignment = Enum.TextXAlignment.Left
    hint.Parent = body

    local list = Instance.new("ScrollingFrame")
    list.Size = UDim2.new(1, -16, 0, 150)
    list.Position = UDim2.new(0, 8, 0, 40)
    list.BackgroundColor3 = Color3.fromRGB(22, 22, 27)
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 4
    list.CanvasSize = UDim2.new(0, 0, 0, 0)
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.Parent = body
    local layout = Instance.new("UIListLayout", list)
    layout.Padding = UDim.new(0, 3)

    local addBox = Instance.new("TextBox")
    addBox.Size = UDim2.new(1, -90, 0, 28)
    addBox.Position = UDim2.new(0, 8, 0, 198)
    addBox.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    addBox.BorderSizePixel = 0
    addBox.PlaceholderText = "sprout name (e.g. Moon)"
    addBox.Text = ""
    addBox.TextColor3 = Color3.new(1, 1, 1)
    addBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 140)
    addBox.Font = Enum.Font.Gotham
    addBox.TextSize = 13
    addBox.ClearTextOnFocus = false
    addBox.Parent = body

    local addBtn = Instance.new("TextButton")
    addBtn.Size = UDim2.new(0, 74, 0, 28)
    addBtn.Position = UDim2.new(1, -82, 0, 198)
    addBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 200)
    addBtn.BorderSizePixel = 0
    addBtn.Text = "Add"
    addBtn.TextColor3 = Color3.new(1, 1, 1)
    addBtn.Font = Enum.Font.GothamBold
    addBtn.TextSize = 13
    addBtn.Parent = body

    startBtn = Instance.new("TextButton")
    startBtn.Size = UDim2.new(1, -16, 0, 40)
    startBtn.Position = UDim2.new(0, 8, 0, 240)
    startBtn.BorderSizePixel = 0
    startBtn.Font = Enum.Font.GothamBold
    startBtn.TextSize = 16
    startBtn.TextColor3 = Color3.new(1, 1, 1)
    startBtn.Parent = body

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -16, 0, 40)
    statusLabel.Position = UDim2.new(0, 8, 0, 288)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Status: idle"
    statusLabel.TextWrapped = true
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 12
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.Parent = body

    local function mkBtn(parentRow, text, x, w, color)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0, w, 0, 26)
        b.Position = UDim2.new(0, x, 0, 2)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.Text = text
        b.TextColor3 = Color3.new(1, 1, 1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        b.Parent = parentRow
        return b
    end

    refreshList = function()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        for i, t in ipairs(settings.types) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -6, 0, 30)
            row.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
            row.BorderSizePixel = 0
            row.LayoutOrder = i
            row.Parent = list

            local check = mkBtn(row, t.on and "✓" or "", 2, 26, t.on and Color3.fromRGB(50, 160, 80) or Color3.fromRGB(70, 70, 80))
            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size = UDim2.new(0, 100, 1, 0)
            nameLbl.Position = UDim2.new(0, 34, 0, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Text = i .. ". " .. t.name
            nameLbl.TextColor3 = Color3.new(1, 1, 1)
            nameLbl.Font = Enum.Font.Gotham
            nameLbl.TextSize = 13
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            nameLbl.Parent = row
            local up = mkBtn(row, "▲", 138, 28, Color3.fromRGB(70, 70, 80))
            local down = mkBtn(row, "▼", 168, 28, Color3.fromRGB(70, 70, 80))
            local del = mkBtn(row, "✕", 200, 28, Color3.fromRGB(170, 60, 60))

            check.MouseButton1Click:Connect(function()
                t.on = not t.on; saveSettings(); refreshList()
            end)
            up.MouseButton1Click:Connect(function()
                if i > 1 then
                    settings.types[i], settings.types[i - 1] = settings.types[i - 1], settings.types[i]
                    saveSettings(); refreshList()
                end
            end)
            down.MouseButton1Click:Connect(function()
                if i < #settings.types then
                    settings.types[i], settings.types[i + 1] = settings.types[i + 1], settings.types[i]
                    saveSettings(); refreshList()
                end
            end)
            del.MouseButton1Click:Connect(function()
                table.remove(settings.types, i); saveSettings(); refreshList()
            end)
        end
    end

    addBtn.MouseButton1Click:Connect(function()
        local name = addBox.Text:match("^%s*(.-)%s*$")
        if name and name ~= "" then
            table.insert(settings.types, {name = name, on = true})
            addBox.Text = ""
            saveSettings(); refreshList()
        end
    end)

    refreshList()
    return gui
end

local function updateStartBtn()
    if not startBtn then return end
    if settings.running then
        startBtn.Text = "STOP"
        startBtn.BackgroundColor3 = Color3.fromRGB(190, 60, 60)
    else
        startBtn.Text = "START"
        startBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 80)
    end
end

-- ===== sprout detection =====
local spawnPos

local function isValidSprout(v)
    local path = v:GetFullName()
    for _, bad in ipairs(CONFIG.IGNORE_PATHS) do
        if path:find(bad, 1, true) then return false end
    end
    if spawnPos and (posOf(v) - spawnPos).Magnitude < CONFIG.SPAWN_IGNORE_RADIUS then
        return false
    end
    return true
end

-- returns priority index (1 = first choice) or nil if not whitelisted
local function rankOf(v)
    local hay = (v.Name .. " " .. v:GetFullName()):lower()
    for i, t in ipairs(settings.types) do
        if t.on then
            local n = t.name:lower()
            if n == "any" or hay:find(n, 1, true) then
                return i
            end
        end
    end
end

local function findBestSprout()
    local best, bestRank
    for _, v in ipairs(workspace:GetDescendants()) do
        if (v:IsA("BasePart") or v:IsA("Model")) and v.Name:lower():find("sprout", 1, true) then
            local valid = isValidSprout(v)
            local rank = valid and rankOf(v) or nil
            if CONFIG.DEBUG then
                print(("[SproutHopper] %s | valid=%s | rank=%s"):format(v:GetFullName(), tostring(valid), tostring(rank)))
            end
            if rank and (not bestRank or rank < bestRank) then
                best, bestRank = v, rank
            end
        end
    end
    return best
end

local function waitForSprout()
    local start = os.clock()
    while os.clock() - start < CONFIG.SCAN_TIME and settings.running do
        local s = findBestSprout()
        if s then return s end
        task.wait(0.5)
    end
end

-- ===== farming =====
local function collectLootNear(center)
    local folder = workspace:FindFirstChild(CONFIG.LOOT_FOLDER)
    if not folder then return end
    for _, item in ipairs(folder:GetChildren()) do
        if not settings.running then return end
        if item:IsA("BasePart") and (item.Position - center).Magnitude <= CONFIG.LOOT_RADIUS then
            tweenTo(item.Position)
        end
    end
end

local function equipTool()
    local char = player.Character
    if not char or char:FindFirstChildOfClass("Tool") then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local tool = player.Backpack:FindFirstChildOfClass("Tool")
    if hum and tool then hum:EquipTool(tool) end
end

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

    while settings.running and sprout.Parent and os.clock() - start < CONFIG.FARM_TIMEOUT do
        swing()
        if os.clock() - lastLoot > 2 then
            lastLoot = os.clock()
            collectLootNear(posOf(sprout))
            if sprout.Parent and settings.running then
                tweenTo(posOf(sprout) + Vector3.new(0, CONFIG.HOVER_HEIGHT, 0))
            end
        end
        task.wait(CONFIG.SWING_DELAY)
    end

    if not settings.running then return end
    setStatus("Collecting loot...")
    local root = getRoot()
    if root then
        local center = root.Position
        local sweepEnd = os.clock() + 5
        while settings.running and os.clock() < sweepEnd do
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
    setStatus("Hopping...")
    task.wait(CONFIG.HOP_DELAY)
    if not settings.running then return end

    local visited = loadVisited()
    table.insert(visited, game.JobId)
    saveVisited(visited)

    if queue_on_teleport then
        queue_on_teleport(('loadstring(game:HttpGet("%s"))()'):format(SCRIPT_URL))
    end

    while settings.running do
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
                task.wait(10)
            else
                visited = {}
                saveVisited(visited)
            end
        end
        task.wait(2)
    end
end

-- ===== main loop =====
local loopActive = false

local function mainLoop()
    if loopActive then return end
    loopActive = true

    if not game:IsLoaded() then game.Loaded:Wait() end
    local r = getRoot()
    setStatus("Loading...")
    task.wait(3)
    spawnPos = r and r.Position or nil

    while settings.running do
        setStatus("Scanning for sprouts...")
        local sprout = waitForSprout()
        if not settings.running then break end
        if sprout then
            setStatus("Farming " .. sprout.Name)
            farm(sprout)
        else
            setStatus("No whitelisted sprout here")
        end
        if not settings.running then break end
        hop()
    end

    setStatus("Stopped")
    loopActive = false
end

-- ===== start =====
buildGui()
updateStartBtn()

startBtn.MouseButton1Click:Connect(function()
    settings.running = not settings.running
    saveSettings()
    updateStartBtn()
    if settings.running then
        task.spawn(mainLoop)
    else
        setStatus("Stopping...")
    end
end)

-- after a hop the script reloads; keep going if it was running
if settings.running then
    task.spawn(mainLoop)
end
