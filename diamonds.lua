-- diamonds.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Diamonds, "diamonds.lua: missing context or Diamonds tab")

    local Services = (C and C.Services) or {}
    local Players  = Services.Players or game:GetService("Players")
    local RS       = Services.RS      or game:GetService("ReplicatedStorage")
    local WS       = Services.WS      or game:GetService("Workspace")
    local Run      = Services.Run     or game:GetService("RunService")

    local lp  = C.LocalPlayer or Players.LocalPlayer
    local tab = UI.Tabs.Diamonds

    C.State = C.State or {}
    if C.State.DiamondsAutoTake == nil then C.State.DiamondsAutoTake = false end
    if C.State.DiamondsCycle == nil then C.State.DiamondsCycle = false end
    if C.State.DiamondsSetLocations == nil then C.State.DiamondsSetLocations = false end
    if C.State.DiamondsCycleInterval == nil then C.State.DiamondsCycleInterval = 3 end
    if C.State.DiamondsLocations == nil then C.State.DiamondsLocations = {} end
    if C.State.DiamondsCycleIndex == nil then C.State.DiamondsCycleIndex = 1 end

    local RADIUS             = 75
    local SCAN_INTERVAL      = 0.15
    local FIRE_COOLDOWN_S    = 0.35
    local MAX_FIRES_PER_SCAN = 8

    local function now() return os.clock() end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:WaitForChild("HumanoidRootPart", 10)
    end

    local function itemsFolder()
        return WS:FindFirstChild("Items") or WS
    end

    local function topModelUnderItems(part, items)
        local cur = part
        local lastModel = nil
        while cur and cur ~= WS and cur ~= items do
            if cur:IsA("Model") then lastModel = cur end
            cur = cur.Parent
        end
        return lastModel
    end

    local function resolveDiamondFromPart(part)
        if not (part and part.Parent) then return nil end
        local items = itemsFolder()
        local m = topModelUnderItems(part, items)
        if m and m.Parent and m.Name == "Diamond" and (not items or m:IsDescendantOf(items)) then
            return m
        end
        local anc = part:FindFirstAncestorOfClass("Model")
        if anc and anc.Parent and anc.Name == "Diamond" and (not items or anc:IsDescendantOf(items)) then
            return anc
        end
        if part.Name == "Diamond" then
            return part
        end
        return nil
    end

    local function getRemote()
        local re = RS:FindFirstChild("RemoteEvents")
        if not re then return nil end
        return re:FindFirstChild("RequestTakeDiamonds")
    end

    local takeRemote = getRemote()
    local lastFireAt = setmetatable({}, { __mode = "k" })

    local function fireTake(target)
        if not (takeRemote and takeRemote.Parent) then return false end
        if not (target and target.Parent) then return false end
        local ok = pcall(function()
            takeRemote:FireServer(target)
        end)
        return ok
    end

    local function scanOnce()
        local root = hrp()
        if not root then return end
        local center = root.Position

        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }

        local parts = WS:GetPartBoundsInRadius(center, RADIUS, params) or {}
        local uniq = {}
        local fired = 0

        for _,p in ipairs(parts) do
            if fired >= MAX_FIRES_PER_SCAN then break end
            if p:IsA("BasePart") then
                local d = resolveDiamondFromPart(p)
                if d and not uniq[d] then
                    uniq[d] = true
                    local lt = lastFireAt[d]
                    if (not lt) or (now() - lt >= FIRE_COOLDOWN_S) then
                        lastFireAt[d] = now()
                        if fireTake(d) then
                            fired += 1
                        end
                    end
                end
            end
        end
    end

    local function pivotCharacterTo(cf)
        local ch = lp.Character or lp.CharacterAdded:Wait()
        if not ch then return false end
        local ok = pcall(function()
            ch:PivotTo(cf)
        end)
        return ok
    end

    local function makeOrb(cf, name)
        local part = Instance.new("Part")
        part.Name = name
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(1.2, 1.2, 1.2)
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(120, 200, 255)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CFrame = cf
        part.Parent = WS

        local light = Instance.new("PointLight")
        light.Range = 12
        light.Brightness = 2.5
        light.Color = part.Color
        light.Parent = part

        return part
    end

    local function ensureOrbsVisible(visible)
        local list = C.State.DiamondsLocations or {}
        for i = 1, #list do
            local rec = list[i]
            if type(rec) == "table" and rec.cf and typeof(rec.cf) == "CFrame" then
                if visible then
                    if not (rec.orb and rec.orb.Parent) then
                        rec.orb = makeOrb(CFrame.new(rec.cf.Position), ("DiamondsLoc_%d"):format(i))
                    else
                        pcall(function()
                            rec.orb.CFrame = CFrame.new(rec.cf.Position)
                        end)
                    end
                else
                    if rec.orb and rec.orb.Parent then
                        pcall(function() rec.orb.Parent = nil end)
                    end
                end
            end
        end
    end

    local function rebuildOrbNamesAndPositions()
        local list = C.State.DiamondsLocations or {}
        for i = 1, #list do
            local rec = list[i]
            if type(rec) == "table" and rec.orb then
                pcall(function()
                    rec.orb.Name = ("DiamondsLoc_%d"):format(i)
                    rec.orb.CFrame = CFrame.new(rec.cf.Position)
                end)
            end
        end
    end

    local function addLocationFromPlayer()
        local root = hrp()
        if not root then return end

        local cf = root.CFrame
        local list = C.State.DiamondsLocations or {}
        list[#list + 1] = { cf = cf, orb = nil, t = now() }
        C.State.DiamondsLocations = list

        if C.State.DiamondsSetLocations then
            ensureOrbsVisible(true)
            rebuildOrbNamesAndPositions()
        end
    end

    local function findExistingEdgeStack(playerGui)
        local wanted = {
            ["EdgeButtons"] = true,
            ["EdgeButtonsStack"] = true,
            ["EdgeStack"] = true,
            ["EdgeButtonStack"] = true,
            ["EdgeButtonContainer"] = true,
        }

        for _,d in ipairs(playerGui:GetDescendants()) do
            if d:IsA("Frame") and wanted[d.Name] then
                return d
            end
        end
        return nil
    end

    local function getOrCreateEdgeStack()
        local playerGui = lp:WaitForChild("PlayerGui")
        local existing = findExistingEdgeStack(playerGui)
        if existing then return existing end

        local sg = playerGui:FindFirstChild("EdgeButtonsGui")
        if not (sg and sg:IsA("ScreenGui")) then
            sg = Instance.new("ScreenGui")
            sg.Name = "EdgeButtonsGui"
            sg.ResetOnSpawn = false
            sg.Parent = playerGui
        end

        local frame = sg:FindFirstChild("EdgeButtonsStack")
        if not (frame and frame:IsA("Frame")) then
            frame = Instance.new("Frame")
            frame.Name = "EdgeButtonsStack"
            frame.Size = UDim2.new(0, 170, 0, 320)
            frame.Position = UDim2.new(1, -8, 0.5, 0)
            frame.AnchorPoint = Vector2.new(1, 0.5)
            frame.BackgroundTransparency = 1
            frame.BorderSizePixel = 0
            frame.Parent = sg

            local layout = Instance.new("UIListLayout")
            layout.FillDirection = Enum.FillDirection.Vertical
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
            layout.VerticalAlignment = Enum.VerticalAlignment.Top
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Padding = UDim.new(0, 6)
            layout.Parent = frame
        end

        return frame
    end

    local function getOrCreateSetLocationEdgeButton()
        local stack = getOrCreateEdgeStack()
        local btn = stack:FindFirstChild("Diamonds_SetLocation")
        if btn and btn:IsA("TextButton") then return btn end

        btn = Instance.new("TextButton")
        btn.Name = "Diamonds_SetLocation"
        btn.Size = UDim2.new(0, 160, 0, 36)
        btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = true
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.SourceSansBold
        btn.TextSize = 14
        btn.Text = "Set Location"
        btn.LayoutOrder = 50
        btn.Parent = stack

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = btn

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1
        stroke.Color = Color3.fromRGB(70, 70, 70)
        stroke.Parent = btn

        btn.MouseButton1Click:Connect(function()
            if C.State and C.State.DiamondsSetLocations then
                addLocationFromPlayer()
            end
        end)

        return btn
    end

    local function showSetLocationButton(show)
        local stack = getOrCreateEdgeStack()
        local btn = stack:FindFirstChild("Diamonds_SetLocation")
        if show then
            local b = getOrCreateSetLocationEdgeButton()
            b.Visible = true
        else
            if btn and btn:IsA("TextButton") then
                btn.Visible = false
            end
        end
    end

    local function cycleStep()
        local list = C.State.DiamondsLocations or {}
        if #list == 0 then return end

        local idx = tonumber(C.State.DiamondsCycleIndex) or 1
        if idx < 1 or idx > #list then idx = 1 end

        local rec = list[idx]
        if type(rec) == "table" and rec.cf and typeof(rec.cf) == "CFrame" then
            pivotCharacterTo(rec.cf)
        end

        idx += 1
        if idx > #list then idx = 1 end
        C.State.DiamondsCycleIndex = idx
    end

    local _testBusy = false
    local function testTeleportSequence()
        if _testBusy then return end
        _testBusy = true
        task.spawn(function()
            local list = C.State.DiamondsLocations or {}
            for i = 1, #list do
                local rec = list[i]
                if type(rec) == "table" and rec.cf and typeof(rec.cf) == "CFrame" then
                    pivotCharacterTo(rec.cf)
                end
                task.wait(1)
            end
            _testBusy = false
        end)
    end

    tab:Section({ Title = "Teleport" })

    tab:Toggle({
        Title = "Cycle",
        Default = C.State.DiamondsCycle and true or false,
        Callback = function(on)
            C.State.DiamondsCycle = on and true or false
        end
    })

    tab:Toggle({
        Title = "Set Locations",
        Default = C.State.DiamondsSetLocations and true or false,
        Callback = function(on)
            C.State.DiamondsSetLocations = on and true or false
            if C.State.DiamondsSetLocations then
                showSetLocationButton(true)
                ensureOrbsVisible(true)
                rebuildOrbNamesAndPositions()
            else
                showSetLocationButton(false)
                ensureOrbsVisible(false)
            end
        end
    })

    tab:Slider({
        Title = "Cycle Interval (sec)",
        Value = { Min = 1, Max = 10, Default = math.clamp(tonumber(C.State.DiamondsCycleInterval) or 3, 1, 10) },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default
            end
            nv = tonumber(nv)
            if nv then
                C.State.DiamondsCycleInterval = math.clamp(nv, 1, 10)
            end
        end
    })

    tab:Button({
        Title = "test",
        Callback = function()
            testTeleportSequence()
        end
    })

    tab:Section({ Title = "Diamonds" })

    tab:Toggle({
        Title = "Auto-take Diamonds (75 studs)",
        Default = C.State.DiamondsAutoTake and true or false,
        Callback = function(on)
            C.State.DiamondsAutoTake = on and true or false
            if C.State.DiamondsAutoTake then
                if not takeRemote or not takeRemote.Parent then
                    takeRemote = getRemote()
                end
            end
        end
    })

    local loopStarted = false
    local function startLoopsOnce()
        if loopStarted then return end
        loopStarted = true

        task.spawn(function()
            while true do
                if C.State and C.State.DiamondsAutoTake then
                    if not takeRemote or not takeRemote.Parent then
                        takeRemote = getRemote()
                    end
                    pcall(scanOnce)
                end
                task.wait(SCAN_INTERVAL)
            end
        end)

        task.spawn(function()
            while true do
                local interval = math.clamp(tonumber(C.State and C.State.DiamondsCycleInterval) or 3, 1, 10)
                if C.State and C.State.DiamondsCycle then
                    pcall(cycleStep)
                end
                task.wait(interval)
            end
        end)
    end

    startLoopsOnce()

    if C.State.DiamondsSetLocations then
        showSetLocationButton(true)
        ensureOrbsVisible(true)
        rebuildOrbNamesAndPositions()
    else
        showSetLocationButton(false)
        ensureOrbsVisible(false)
    end
end
