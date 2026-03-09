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
    local PPS      = game:GetService("ProximityPromptService")
    local VIM      = game:GetService("VirtualInputManager")
    local VU       = game:GetService("VirtualUser")

    local lp  = C.LocalPlayer or Players.LocalPlayer
    local tab = UI.Tabs.Diamonds

    C.State = C.State or {}
    if C.State.DiamondsAutoTake == nil then C.State.DiamondsAutoTake = true end
    if C.State.DiamondsCycle == nil then C.State.DiamondsCycle = false end
    if C.State.DiamondsSetLocations == nil then C.State.DiamondsSetLocations = false end
    if C.State.DiamondsLocations == nil then C.State.DiamondsLocations = {} end
    if C.State.DiamondsCycleIndex == nil then C.State.DiamondsCycleIndex = 1 end
    if C.State.DiamondsFirePrompts == nil then C.State.DiamondsFirePrompts = false end
    if C.State.DiamondsJumpInput == nil then C.State.DiamondsJumpInput = false end
    if C.State.DiamondsKey1Input == nil then C.State.DiamondsKey1Input = false end
    if C.State.DiamondsAutoAfkAction == nil then C.State.DiamondsAutoAfkAction = true end

    if C.State._DiamondsJumpConn ~= nil then
        pcall(function() C.State._DiamondsJumpConn:Disconnect() end)
        C.State._DiamondsJumpConn = nil
    end
    if C.State._DiamondsKey1Conn ~= nil then
        pcall(function() C.State._DiamondsKey1Conn:Disconnect() end)
        C.State._DiamondsKey1Conn = nil
    end

    do
        local v = tonumber(C.State.DiamondsCycleInterval)
        if not v then
            C.State.DiamondsCycleInterval = 10
        else
            if v >= 1 and v <= 10 then
                C.State.DiamondsCycleInterval = math.clamp(v * 60, 1, 1200)
            else
                C.State.DiamondsCycleInterval = math.clamp(v, 1, 1200)
            end
        end
    end

    local RADIUS             = 75
    local SCAN_INTERVAL      = 0.15
    local FIRE_COOLDOWN_S    = 0.35
    local MAX_FIRES_PER_SCAN = 8

    local INPUT_BASE_INTERVAL_S = 5
    local AUTO_AFK_IDLE_S       = 300

    local function now() return os.clock() end

    local _seeded = false
    local function seedOnce()
        if _seeded then return end
        _seeded = true
        pcall(function()
            math.randomseed(tonumber(string.gsub(tostring(os.clock()), "%D", "")) or tick())
        end)
    end
    seedOnce()

    local function randf(a, b)
        return a + (b - a) * math.random()
    end

    local function nextJitteredIntervalSeconds(base)
        local b = tonumber(base) or INPUT_BASE_INTERVAL_S
        local v = randf(b - 2.0, b + 1.5)
        if v < 1.0 then v = 1.0 end
        return v
    end

    local function cycleIntervalWithJitter()
        local base = math.clamp(tonumber(C.State and C.State.DiamondsCycleInterval) or 10, 1, 1200)
        local j = randf(-2.0, 2.0)
        return math.clamp(base + j, 1, 1200)
    end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:WaitForChild("HumanoidRootPart", 10)
    end

    local function hum()
        local ch = lp.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end

    local CAM_BACK       = 12
    local CAM_UP         = 4.5
    local CAM_LOOK_AHEAD = 60
    local CAM_HOLD_S     = 0.12

    local function snapCameraBehindPlayer()
        local cam = WS.CurrentCamera
        if not cam then return end
        local root = hrp()
        if not root then return end

        local look = root.CFrame.LookVector
        local camPos = root.Position - (look * CAM_BACK) + Vector3.new(0, CAM_UP, 0)
        local focus = root.Position + (look * CAM_LOOK_AHEAD)

        local prevType = cam.CameraType
        cam.CameraType = Enum.CameraType.Scriptable
        cam.CFrame = CFrame.new(camPos, focus)

        task.delay(CAM_HOLD_S, function()
            if not cam then return end
            cam.CameraType = prevType or Enum.CameraType.Custom
            local h = hum()
            if h then pcall(function() cam.CameraSubject = h end) end
        end)
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
        if ok then
            task.defer(snapCameraBehindPlayer)
        end
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

    local function destroyAllDiamondOrbsEverywhere()
        local list = C.State.DiamondsLocations or {}
        for i = 1, #list do
            local rec = list[i]
            if type(rec) == "table" and rec.orb then
                pcall(function() rec.orb:Destroy() end)
                rec.orb = nil
            end
        end
        for _, inst in ipairs(WS:GetChildren()) do
            if inst and inst:IsA("BasePart") then
                if tostring(inst.Name):match("^DiamondsLoc_%d+$") then
                    pcall(function() inst:Destroy() end)
                end
            end
        end
    end

    local function clearDiamondLocationsAndOrbs()
        ensureOrbsVisible(false)
        destroyAllDiamondOrbsEverywhere()
        C.State.DiamondsLocations = {}
        C.State.DiamondsCycleIndex = 1
        C.State._DiamondsCycleNextAt = nil
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

    local function getOrCreateEdgeStack()
        local playerGui = lp:WaitForChild("PlayerGui")

        local edgeGui = playerGui:FindFirstChild("EdgeButtons")
        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
            pcall(function() edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
            edgeGui.Parent = playerGui
        end

        local stack = edgeGui:FindFirstChild("EdgeStack")
        if not stack then
            stack = Instance.new("Frame")
            stack.Name = "EdgeStack"
            stack.AnchorPoint = Vector2.new(1, 0)
            stack.Position = UDim2.new(1, -6, 0, 6)
            stack.Size = UDim2.new(0, 130, 1, -12)
            stack.BackgroundTransparency = 1
            stack.BorderSizePixel = 0
            stack.Parent = edgeGui

            local list = Instance.new("UIListLayout")
            list.Name = "VList"
            list.FillDirection = Enum.FillDirection.Vertical
            list.SortOrder = Enum.SortOrder.LayoutOrder
            list.Padding = UDim.new(0, 6)
            list.HorizontalAlignment = Enum.HorizontalAlignment.Right
            list.Parent = stack
        end

        return stack
    end

    local SET_LOC_ORDER = 6

    local function getOrCreateSetLocationEdgeButton()
        local stack = getOrCreateEdgeStack()
        local btn = stack:FindFirstChild("Diamonds_SetLocation")
        if btn and btn:IsA("TextButton") then
            btn.LayoutOrder = SET_LOC_ORDER
            return btn
        end

        btn = Instance.new("TextButton")
        btn.Name = "Diamonds_SetLocation"
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.Text = "Set Location"
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamBold
        btn.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.BorderSizePixel = 0
        btn.Visible = false
        btn.LayoutOrder = SET_LOC_ORDER
        btn.Parent = stack

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = btn

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

    local firePromptsConn = nil
    local firePromptLastAt = setmetatable({}, { __mode = "k" })
    local FIRE_PROMPT_COOLDOWN = 0.25

    local function triggerPrompt(prompt)
        if not (prompt and prompt.Parent and prompt.Enabled) then return false end

        local t = firePromptLastAt[prompt]
        if t and (now() - t) < FIRE_PROMPT_COOLDOWN then return false end
        firePromptLastAt[prompt] = now()

        pcall(function() prompt.RequiresLineOfSight = false end)
        pcall(function()
            if typeof(prompt.HoldDuration) == "number" and prompt.HoldDuration > 0.12 then
                prompt.HoldDuration = 0.12
            end
        end)

        Run.Heartbeat:Wait()

        local ok = pcall(function()
            PPS:TriggerPrompt(prompt)
        end)
        if ok then return true end

        local ok2 = pcall(function()
            PPS:TriggerPrompt(prompt, lp)
        end)
        if ok2 then return true end

        local hold = 0
        pcall(function() hold = tonumber(prompt.HoldDuration) or 0 end)

        local ok3 = pcall(function() prompt:InputHoldBegin() end)
        if not ok3 then return false end

        task.delay(math.max(0.03, hold + 0.03), function()
            if prompt and prompt.Parent then
                pcall(function() prompt:InputHoldEnd() end)
            end
        end)

        return true
    end

    local function enableFirePrompts()
        if firePromptsConn then return end
        firePromptsConn = PPS.PromptShown:Connect(function(prompt, _inputType)
            if not (C.State and C.State.DiamondsFirePrompts) then return end
            if not (prompt and prompt:IsA("ProximityPrompt")) then return end
            task.defer(function() triggerPrompt(prompt) end)
        end)
    end

    local function disableFirePrompts()
        if firePromptsConn then firePromptsConn:Disconnect() firePromptsConn = nil end
        firePromptLastAt = setmetatable({}, { __mode = "k" })
    end

    local function vimTap(keyCode)
        local ok = pcall(function()
            VIM:SendKeyEvent(true, keyCode, false, game)
            task.wait(0.05)
            VIM:SendKeyEvent(false, keyCode, false, game)
        end)
        return ok
    end

    local function diamondsKey1SendTap()
        return vimTap(Enum.KeyCode.One)
    end

    local function vuDoRandomAction()
        local ok = pcall(function()
            VU:CaptureController()
            local cam = WS.CurrentCamera
            local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
            local x = math.floor(randf(40, math.max(41, vp.X - 40)))
            local y = math.floor(randf(40, math.max(41, vp.Y - 40)))
            local pos = Vector2.new(x, y)
            if math.random(1, 3) == 1 then
                VU:ClickButton2(pos)
            else
                VU:ClickButton1(pos)
            end
        end)
        return ok
    end

    local AFK_KEYS = {
        Enum.KeyCode.One,
        Enum.KeyCode.Two,
        Enum.KeyCode.Three,
        Enum.KeyCode.W,
        Enum.KeyCode.A,
        Enum.KeyCode.S,
        Enum.KeyCode.D,
        Enum.KeyCode.Space,
    }

    local function afkKeyAction()
        local kc = AFK_KEYS[math.random(1, #AFK_KEYS)]
        return vimTap(kc)
    end

    local function afkComboAction()
        local roll = math.random(1, 100)
        if roll <= 45 then
            afkKeyAction()
        elseif roll <= 80 then
            vuDoRandomAction()
        else
            afkKeyAction()
            task.wait(0.08)
            vuDoRandomAction()
        end
    end

    local function diamondsJumpStart()
        if C.State._DiamondsJumpConn then return end
        local nextAt = now() + nextJitteredIntervalSeconds(INPUT_BASE_INTERVAL_S)
        C.State._DiamondsJumpConn = Run.Heartbeat:Connect(function()
            if not (C.State and C.State.DiamondsJumpInput) then return end
            local t = now()
            if t < nextAt then return end
            nextAt = t + nextJitteredIntervalSeconds(INPUT_BASE_INTERVAL_S)
            task.spawn(afkComboAction)
        end)
    end

    local function diamondsJumpStop()
        if C.State._DiamondsJumpConn then
            pcall(function() C.State._DiamondsJumpConn:Disconnect() end)
            C.State._DiamondsJumpConn = nil
        end
    end

    local function diamondsKey1Start()
        if C.State._DiamondsKey1Conn then return end
        local nextAt = now() + nextJitteredIntervalSeconds(INPUT_BASE_INTERVAL_S)
        C.State._DiamondsKey1Conn = Run.Heartbeat:Connect(function()
            if not (C.State and C.State.DiamondsKey1Input) then return end
            local t = now()
            if t < nextAt then return end
            nextAt = t + nextJitteredIntervalSeconds(INPUT_BASE_INTERVAL_S)
            task.spawn(diamondsKey1SendTap)
        end)
    end

    local function diamondsKey1Stop()
        if C.State._DiamondsKey1Conn then
            pcall(function() C.State._DiamondsKey1Conn:Disconnect() end)
            C.State._DiamondsKey1Conn = nil
        end
    end

    tab:Section({ Title = "Teleport" })

    tab:Toggle({
        Title = "Cycle",
        Default = C.State.DiamondsCycle and true or false,
        Callback = function(on)
            C.State.DiamondsCycle = on and true or false

            if C.State.DiamondsCycle then
                C.State.DiamondsJumpInput = false
                diamondsJumpStop()
            end

            if C.State.DiamondsCycle then
                local seconds = cycleIntervalWithJitter()
                C.State._DiamondsCycleNextAt = now() + seconds
                C.State._DiamondsCycleLastInputAt = now()
                C.State._DiamondsCycleNextInputAt = now() + nextJitteredIntervalSeconds(INPUT_BASE_INTERVAL_S)
            else
                C.State._DiamondsCycleNextAt = nil
                C.State._DiamondsCycleLastInputAt = nil
                C.State._DiamondsCycleNextInputAt = nil
            end
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

    tab:Button({
        Title = "Clear Locations (Delete Orbs)",
        Callback = function()
            clearDiamondLocationsAndOrbs()
            if C.State and C.State.DiamondsSetLocations then
                ensureOrbsVisible(true)
                rebuildOrbNamesAndPositions()
            end
        end
    })

    tab:Slider({
        Title = "Cycle Interval (sec)",
        Value = { Min = 1, Max = 1200, Default = math.clamp(tonumber(C.State.DiamondsCycleInterval) or 10, 1, 1200) },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default
            end
            nv = tonumber(nv)
            if nv then
                C.State.DiamondsCycleInterval = math.clamp(nv, 1, 1200)
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
        Value = (C.State.DiamondsAutoTake == true),
        Callback = function(on)
            C.State.DiamondsAutoTake = (on == true)
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
                if C.State and C.State.DiamondsCycle then
                    local t = now()

                    local nextInputAt = tonumber(C.State._DiamondsCycleNextInputAt)
                    if not nextInputAt then
                        C.State._DiamondsCycleNextInputAt = t + nextJitteredIntervalSeconds(INPUT_BASE_INTERVAL_S)
                    else
                        if t >= nextInputAt then
                            pcall(afkComboAction)
                            C.State._DiamondsCycleNextInputAt = t + nextJitteredIntervalSeconds(INPUT_BASE_INTERVAL_S)
                        end
                    end

                    local nextAt = tonumber(C.State._DiamondsCycleNextAt)
                    if not nextAt then
                        C.State._DiamondsCycleNextAt = t + cycleIntervalWithJitter()
                    else
                        if t >= nextAt then
                            pcall(cycleStep)
                            C.State._DiamondsCycleNextAt = t + cycleIntervalWithJitter()
                        end
                    end
                end
                task.wait(0.1)
            end
        end)

        task.spawn(function()
            local lastPos = nil
            local lastMoveAt = now()

            while true do
                task.wait(1)

                if not (C.State and C.State.DiamondsAutoAfkAction) then
                    lastPos = nil
                    lastMoveAt = now()
                else
                    local root = hrp()
                    local pos = root and root.Position

                    if pos then
                        if lastPos then
                            if (pos - lastPos).Magnitude > 0.5 then
                                lastMoveAt = now()

                                if C.State.DiamondsKey1Input then
                                    C.State.DiamondsKey1Input = false
                                    diamondsKey1Stop()
                                end
                            end
                        end
                        lastPos = pos
                    end

                    if not C.State.DiamondsKey1Input then
                        local idleFor = now() - lastMoveAt
                        if idleFor >= AUTO_AFK_IDLE_S then
                            C.State.DiamondsKey1Input = true
                            diamondsKey1Start()
                        end
                    end
                end
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

    tab:Section({ Title = "Prompts" })

    tab:Toggle({
        Title = "Fire Prompts",
        Default = C.State.DiamondsFirePrompts and true or false,
        Callback = function(on)
            C.State.DiamondsFirePrompts = on and true or false
            if C.State.DiamondsFirePrompts then
                enableFirePrompts()
            else
                disableFirePrompts()
            end
        end
    })

    if C.State.DiamondsFirePrompts then
        enableFirePrompts()
    end

    tab:Section({ Title = "Jump Debug" })

    tab:Toggle({
        Title = "Auto AFK Action",
        Default = C.State.DiamondsAutoAfkAction and true or false,
        Callback = function(on)
            C.State.DiamondsAutoAfkAction = on and true or false
        end
    })

    tab:Toggle({
        Title = "AFK",
        Default = C.State.DiamondsJumpInput and true or false,
        Callback = function(on)
            if on and (C.State and C.State.DiamondsCycle) then
                C.State.DiamondsJumpInput = false
                diamondsJumpStop()
                return
            end

            C.State.DiamondsJumpInput = on and true or false
            if C.State.DiamondsJumpInput then
                diamondsJumpStart()
            else
                diamondsJumpStop()
            end
        end
    })

    tab:Toggle({
        Title = "Input 1",
        Default = C.State.DiamondsKey1Input and true or false,
        Callback = function(on)
            C.State.DiamondsKey1Input = on and true or false
            if C.State.DiamondsKey1Input then
                diamondsKey1Start()
            else
                diamondsKey1Stop()
            end
        end
    })

    if C.State and C.State.DiamondsCycle and C.State.DiamondsJumpInput then
        C.State.DiamondsJumpInput = false
        diamondsJumpStop()
    end

    if C.State.DiamondsJumpInput then
        diamondsJumpStart()
    else
        diamondsJumpStop()
    end

    if C.State.DiamondsKey1Input then
        diamondsKey1Start()
    else
        diamondsKey1Stop()
    end
end
