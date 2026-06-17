local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")

local lp = Players.LocalPlayer

_G.AUTO_FEED_KILL = true
task.wait(0.2)
_G.AUTO_FEED_KILL = false

pcall(function()
    local old = lp:WaitForChild("PlayerGui"):FindFirstChild("AutoFeedOverlay")
    if old then old:Destroy() end
end)

local AUTO_FEED = false

local HUNGER_FULL = 100
local HUNGER_THRESHOLD = 50
local WORLD_SCAN_RADIUS = 75
local POLL_INTERVAL = 0.8
local POST_EAT_WAIT = 0.35
local EQUIP_WAIT = 0.45
local TEMP_WAIT = 2.0

local RemoteEvents = RS:WaitForChild("RemoteEvents")
local EquipItemHandle = RemoteEvents:WaitForChild("EquipItemHandle")
local UnequipItemHandle = RemoteEvents:FindFirstChild("UnequipItemHandle")
local RequestConsumeItem = RemoteEvents:WaitForChild("RequestConsumeItem")
local TempStorage = RS:WaitForChild("TempStorage")

local BLOCKED_NAMES = {
    ["Morsel"] = true,
    ["Steak"] = true,
    ["Mackerel"] = true,
    ["Salmon"] = true,
    ["Swordfish"] = true,
    ["Shark"] = true,
    ["Acorn"] = true,
}

local SAFE_FOOD_NAMES = {
    ["Cooked Morsel"] = true,
    ["Cooked Steak"] = true,
    ["Cooked Ribs"] = true,
    ["Cake"] = true,
    ["Berry"] = true,
    ["Carrot"] = true,
    ["Chilli"] = true,
    ["Stew"] = true,
    ["Hearty Stew"] = true,
    ["Pumpkin"] = true,
    ["Corn"] = true,
    ["BBQ ribs"] = true,
    ["Apple"] = true,
    ["Strawberry"] = true,
}

local function hrp()
    local ch = lp.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function getHunger()
    local ok, v = pcall(function()
        return lp.PlayerGui.Interface.StatBars.HungerBar.Bar.Size.X.Scale * 100
    end)
    return ok and tonumber(v) or 100
end

local function mainPart(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        if obj.PrimaryPart then return obj.PrimaryPart end
        local main = obj:FindFirstChild("Main", true)
        if main and main:IsA("BasePart") then return main end
        return obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function baseAllowed(item)
    if not item then return false end

    local name = tostring(item.Name or "")
    if BLOCKED_NAMES[name] then return false end
    if item:GetAttribute("FoodRot") ~= nil then return false end

    return true
end

local function isInventoryFood(item)
    if not baseAllowed(item) then return false end

    local name = tostring(item.Name or "")
    if SAFE_FOOD_NAMES[name] then return true end
    if item:GetAttribute("ToolName") == "Consumable" then return true end
    if item:GetAttribute("PreparedMeal") == true then return true end
    if name:lower():find("cooked", 1, true) then return true end

    return false
end

local function isWorldFood(item)
    if not baseAllowed(item) then return false end

    local name = tostring(item.Name or "")
    local restore = tonumber(item:GetAttribute("RestoreHunger"))

    if not restore or restore <= 0 then return false end
    if SAFE_FOOD_NAMES[name] then return true end
    if item:GetAttribute("ToolName") == "Consumable" then return true end
    if item:GetAttribute("PreparedMeal") == true then return true end
    if name:lower():find("cooked", 1, true) then return true end

    return false
end

local function isModelWeldedToOutside(m)
    if not (m and m.Parent) then return false end

    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("WeldConstraint") then
            local p0, p1 = d.Part0, d.Part1
            if (p0 and not p0:IsDescendantOf(m)) or (p1 and not p1:IsDescendantOf(m)) then
                return true
            end
        elseif d:IsA("JointInstance") then
            local p0, p1 = d.Part0, d.Part1
            if (p0 and not p0:IsDescendantOf(m)) or (p1 and not p1:IsDescendantOf(m)) then
                return true
            end
        elseif d:IsA("Constraint") then
            local a0, a1 = d.Attachment0, d.Attachment1
            if (a0 and not a0:IsDescendantOf(m)) or (a1 and not a1:IsDescendantOf(m)) then
                return true
            end
        end
    end

    return false
end

local CROCKPOT_SCAN_PERIOD = 3.0
local crockCache = { t = 0, parts = {} }

local function refreshCrockpotsIfNeeded()
    if (os.clock() - (crockCache.t or 0)) < CROCKPOT_SCAN_PERIOD then return end

    crockCache.t = os.clock()
    crockCache.parts = {}

    local seen = {}

    local function scan(root)
        if not root then return end

        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("Model") then
                local n = (d.Name or ""):lower()

                if n == "crockpot"
                    or n == "crock pot"
                    or n:find("crockpot", 1, true)
                    or (n:find("crock", 1, true) and n:find("pot", 1, true))
                then
                    local mp = mainPart(d)

                    if mp and mp.Parent and not seen[mp] then
                        seen[mp] = true
                        crockCache.parts[#crockCache.parts + 1] = mp
                        if #crockCache.parts >= 8 then return end
                    end
                end
            end
        end
    end

    local structures = WS:FindFirstChild("Structures")
    local map = WS:FindFirstChild("Map")
    local camp = map and map:FindFirstChild("Campground")

    scan(structures)
    if #crockCache.parts == 0 then scan(camp) end
    if #crockCache.parts == 0 then scan(WS) end
end

local function isStewOnCrockpot(stewModel)
    if not (stewModel and stewModel.Parent) then return false end

    local smp = mainPart(stewModel)
    if not smp then return false end

    refreshCrockpotsIfNeeded()

    if not crockCache.parts or #crockCache.parts == 0 then return false end

    local p = smp.Position

    for _, cp in ipairs(crockCache.parts) do
        if cp and cp.Parent then
            local q = cp.Position
            local dxz = (Vector3.new(p.X, 0, p.Z) - Vector3.new(q.X, 0, q.Z)).Magnitude
            local dy = p.Y - q.Y

            if dxz <= 2.2 and dy >= 0 and dy <= 5.0 then
                return true
            end
        end
    end

    return false
end

local function getBestInventoryFood()
    local inv = lp:FindFirstChild("Inventory")
    if not inv then return nil end

    local best, bestRestore = nil, -1

    for _, item in ipairs(inv:GetChildren()) do
        if item:IsA("Model") and isInventoryFood(item) then
            local restore = tonumber(item:GetAttribute("RestoreHunger")) or 0

            if item.Name == "Stew" then
                restore = math.max(restore, 1000)
            end

            if restore > bestRestore then
                best = item
                bestRestore = restore
            end
        end
    end

    return best
end

local function getTempFoodByName(name)
    if not name then return nil end

    local exact = TempStorage:FindFirstChild(name)
    if exact and exact:IsA("Model") and isInventoryFood(exact) then
        return exact
    end

    return nil
end

local function waitForTempFoodByName(name)
    local deadline = os.clock() + TEMP_WAIT

    while os.clock() < deadline do
        local item = getTempFoodByName(name)
        if item then return item end
        task.wait(0.05)
    end

    return nil
end

local function invokeConsume(item, requireHungerChange)
    if not item or not item.Parent then return false end

    local before = getHunger()

    local ok = pcall(function()
        RequestConsumeItem:InvokeServer(item)
    end)

    task.wait(POST_EAT_WAIT)

    if not ok then return false end

    if not requireHungerChange then
        return true
    end

    local after = getHunger()
    return after > before or after >= HUNGER_FULL
end

local function eatInventoryItem(item)
    if not item or not item.Parent then return false end
    if not isInventoryFood(item) then return false end

    local name = item.Name

    local okEquip = pcall(function()
        EquipItemHandle:FireServer("FireAllClients", item)
    end)

    if not okEquip then return false end

    task.wait(EQUIP_WAIT)

    local tempItem = waitForTempFoodByName(name)
    if not tempItem then return false end

    local okConsume = invokeConsume(tempItem, false)

    task.delay(0.4, function()
        if UnequipItemHandle and item and item.Parent then
            pcall(function()
                UnequipItemHandle:FireServer("FireAllClients", item)
            end)
        end
    end)

    return okConsume
end

local function findClosestWorldFood()
    local root = hrp()
    if not root then return nil end

    local items = WS:FindFirstChild("Items")
    if not items then return nil end

    local center = root.Position
    local best, bestDist = nil, nil

    for _, item in ipairs(items:GetChildren()) do
        if item:IsA("Model") and isWorldFood(item) then
            if item.Name == "Stew" and (isModelWeldedToOutside(item) or isStewOnCrockpot(item)) then
                continue
            end

            local p = mainPart(item)
            if p then
                local dist = (p.Position - center).Magnitude
                if dist <= WORLD_SCAN_RADIUS and (not bestDist or dist < bestDist) then
                    best = item
                    bestDist = dist
                end
            end
        end
    end

    return best
end

local function consumeWorldItem(item)
    if not item or not item.Parent then return false end
    if not isWorldFood(item) then return false end

    if item.Name == "Stew" and (isModelWeldedToOutside(item) or isStewOnCrockpot(item)) then
        return false
    end

    local temp = TempStorage:FindFirstChild(item.Name)
    local target = temp or item

    return invokeConsume(target, true)
end

local function eatOnce(ignoreFullCheck)
    if not ignoreFullCheck and getHunger() >= HUNGER_FULL then
        return true
    end

    local invFood = getBestInventoryFood()
    if invFood and eatInventoryItem(invFood) then
        return true
    end

    local worldFood = findClosestWorldFood()
    if worldFood and consumeWorldItem(worldFood) then
        return true
    end

    return false
end

local gui = Instance.new("ScreenGui")
gui.Name = "AutoFeedOverlay"
gui.ResetOnSpawn = false
gui.Parent = lp:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(190, 126)
frame.Position = UDim2.fromOffset(20, 240)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.Parent = gui

local function makeButton(text, y)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(170, 30)
    b.Position = UDim2.fromOffset(10, y)
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.TextSize = 14
    b.Font = Enum.Font.SourceSansBold
    b.Text = text
    b.Parent = frame
    return b
end

local autoBtn = makeButton("Auto Feed: OFF", 10)
local eatBtn = makeButton("Eat Now", 46)
local unloadBtn = makeButton("Unload Script", 82)

autoBtn.MouseButton1Click:Connect(function()
    AUTO_FEED = not AUTO_FEED
    autoBtn.Text = AUTO_FEED and "Auto Feed: ON" or "Auto Feed: OFF"
    autoBtn.BackgroundColor3 = AUTO_FEED and Color3.fromRGB(35, 95, 35) or Color3.fromRGB(45, 45, 45)
end)

eatBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
        eatOnce(true)
    end)
end)

unloadBtn.MouseButton1Click:Connect(function()
    AUTO_FEED = false
    _G.AUTO_FEED_KILL = true
    if gui then gui:Destroy() end
end)

task.spawn(function()
    while gui.Parent and not _G.AUTO_FEED_KILL do
        if AUTO_FEED and getHunger() <= HUNGER_THRESHOLD then
            local fails = 0

            while AUTO_FEED and gui.Parent and not _G.AUTO_FEED_KILL and getHunger() < HUNGER_FULL do
                local ate = eatOnce(false)

                if ate then
                    fails = 0
                    task.wait(POST_EAT_WAIT)
                else
                    fails += 1
                    if fails >= 3 then break end
                    task.wait(0.25)
                end
            end
        end

        task.wait(POLL_INTERVAL)
    end
end)
