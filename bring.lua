return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local Run     = C.Services.Run or game:GetService("RunService")
    local lp      = Players.LocalPlayer
    local Stats   = game:GetService("Stats")
    local UIS     = game:GetService("UserInputService")

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    C.State = C.State or {}
    if C.State.BringLimitEnabled == nil then C.State.BringLimitEnabled = false end
    if not tonumber(C.State.BringLimitAmount) then C.State.BringLimitAmount = 10 end
    if C.State.BringLogEnabled == nil then C.State.BringLogEnabled = false end
    if C.State.BringTraceEnabled == nil then C.State.BringTraceEnabled = false end
    if C.State.BringMetricsHz == nil then C.State.BringMetricsHz = 1 end

    local function currentLimit()
        local v = tonumber(C.State.BringLimitAmount) or 10
        return math.clamp(v, 1, 100)
    end

    local function nowStr()
        local ok, s = pcall(function() return os.date("%H:%M:%S") end)
        return ok and s or "??:??:??"
    end

    local function fmtNum(n)
        if type(n) ~= "number" then return tostring(n) end
        return string.format("%.3f", n)
    end

    local function shallowKV(t, max)
        if type(t) ~= "table" then return tostring(t) end
        local out, c = {}, 0
        for k,v in pairs(t) do
            c += 1
            if max and c > max then out[#out+1] = "..." break end
            out[#out+1] = tostring(k) .. "=" .. tostring(v)
        end
        return "{" .. table.concat(out, ",") .. "}"
    end

    local function getPlayerGui()
        local ch = lp
        if not ch then return nil end
        return ch:FindFirstChildOfClass("PlayerGui")
    end

    local function getOrCreateBringConsole()
        local pg = getPlayerGui()
        if not pg then return nil end

        local existing = pg:FindFirstChild("BringDebugConsole")
        if existing and existing:IsA("ScreenGui") then
            local frame = existing:FindFirstChild("ConsoleFrame", true)
            local textBox = existing:FindFirstChild("ConsoleTextBox", true)
            local scroll = existing:FindFirstChild("ConsoleArea", true)
            local copyBtn = existing:FindFirstChild("CopyButton", true)
            local clearBtn = existing:FindFirstChild("ClearButton", true)
            local minBtn = existing:FindFirstChild("MinimizeButton", true)
            local closeBtn = existing:FindFirstChild("CloseButton", true)
            return {
                gui = existing,
                frame = frame,
                scroll = scroll,
                textBox = textBox,
                copyBtn = copyBtn,
                clearBtn = clearBtn,
                minBtn = minBtn,
                closeBtn = closeBtn,
            }
        end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BringDebugConsole"
        screenGui.Parent = pg
        screenGui.ResetOnSpawn = false

        local frame = Instance.new("Frame")
        frame.Name = "ConsoleFrame"
        frame.Parent = screenGui
        frame.Size = UDim2.new(0, 420, 0, 260)
        frame.Position = UDim2.new(0.65, -210, 0.45, -130)
        frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        frame.BorderSizePixel = 0
        frame.Active = true

        local titleBar = Instance.new("Frame")
        titleBar.Name = "TitleBar"
        titleBar.Parent = frame
        titleBar.Size = UDim2.new(1, 0, 0, 26)
        titleBar.Position = UDim2.new(0, 0, 0, 0)
        titleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        titleBar.BorderSizePixel = 0
        titleBar.Active = true

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Name = "TitleLabel"
        titleLabel.Parent = titleBar
        titleLabel.Size = UDim2.new(1, -110, 1, 0)
        titleLabel.Position = UDim2.new(0, 8, 0, 0)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = "Bring Debug Console"
        titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        titleLabel.TextSize = 14
        titleLabel.Font = Enum.Font.SourceSansBold
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.TextYAlignment = Enum.TextYAlignment.Center
        titleLabel.TextWrapped = true

        local minimizeButton = Instance.new("TextButton")
        minimizeButton.Name = "MinimizeButton"
        minimizeButton.Parent = titleBar
        minimizeButton.Size = UDim2.new(0, 26, 0, 26)
        minimizeButton.Position = UDim2.new(1, -78, 0, 0)
        minimizeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        minimizeButton.Text = "-"
        minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        minimizeButton.TextSize = 14
        minimizeButton.Font = Enum.Font.SourceSansBold
        minimizeButton.AutoButtonColor = true

        local copyButton = Instance.new("TextButton")
        copyButton.Name = "CopyButton"
        copyButton.Parent = titleBar
        copyButton.Size = UDim2.new(0, 52, 0, 26)
        copyButton.Position = UDim2.new(1, -52-26, 0, 0)
        copyButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
        copyButton.Text = "Copy"
        copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        copyButton.TextSize = 14
        copyButton.Font = Enum.Font.SourceSansBold
        copyButton.AutoButtonColor = true

        local closeButton = Instance.new("TextButton")
        closeButton.Name = "CloseButton"
        closeButton.Parent = titleBar
        closeButton.Size = UDim2.new(0, 26, 0, 26)
        closeButton.Position = UDim2.new(1, -26, 0, 0)
        closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        closeButton.Text = "X"
        closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        closeButton.TextSize = 14
        closeButton.Font = Enum.Font.SourceSansBold
        closeButton.AutoButtonColor = true

        local consoleArea = Instance.new("ScrollingFrame")
        consoleArea.Name = "ConsoleArea"
        consoleArea.Parent = frame
        consoleArea.Size = UDim2.new(1, -12, 1, -26-34)
        consoleArea.Position = UDim2.new(0, 6, 0, 26+6)
        consoleArea.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        consoleArea.BorderSizePixel = 0
        consoleArea.ScrollBarThickness = 6
        consoleArea.CanvasSize = UDim2.new(0, 0, 0, 0)
        consoleArea.AutomaticCanvasSize = Enum.AutomaticSize.None
        consoleArea.ScrollingDirection = Enum.ScrollingDirection.Y

        local consoleTextBox = Instance.new("TextBox")
        consoleTextBox.Name = "ConsoleTextBox"
        consoleTextBox.Parent = consoleArea
        consoleTextBox.Size = UDim2.new(1, -10, 0, 0)
        consoleTextBox.Position = UDim2.new(0, 5, 0, 5)
        consoleTextBox.BackgroundTransparency = 1
        consoleTextBox.Text = ""
        consoleTextBox.TextColor3 = Color3.fromRGB(220, 220, 220)
        consoleTextBox.TextSize = 12
        consoleTextBox.Font = Enum.Font.Code
        consoleTextBox.TextXAlignment = Enum.TextXAlignment.Left
        consoleTextBox.TextYAlignment = Enum.TextYAlignment.Top
        consoleTextBox.TextWrapped = true
        consoleTextBox.ClearTextOnFocus = false
        consoleTextBox.MultiLine = true
        consoleTextBox.TextEditable = false
        consoleTextBox.RichText = false

        local bottomBar = Instance.new("Frame")
        bottomBar.Name = "BottomBar"
        bottomBar.Parent = frame
        bottomBar.Size = UDim2.new(1, 0, 0, 28)
        bottomBar.Position = UDim2.new(0, 0, 1, -28)
        bottomBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        bottomBar.BorderSizePixel = 0

        local clearButton = Instance.new("TextButton")
        clearButton.Name = "ClearButton"
        clearButton.Parent = bottomBar
        clearButton.Size = UDim2.new(0, 70, 1, 0)
        clearButton.Position = UDim2.new(0, 0, 0, 0)
        clearButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        clearButton.Text = "Clear"
        clearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        clearButton.TextSize = 14
        clearButton.Font = Enum.Font.SourceSansBold
        clearButton.AutoButtonColor = true

        local statusLabel = Instance.new("TextLabel")
        statusLabel.Name = "StatusLabel"
        statusLabel.Parent = bottomBar
        statusLabel.Size = UDim2.new(1, -70-34, 1, 0)
        statusLabel.Position = UDim2.new(0, 70, 0, 0)
        statusLabel.BackgroundTransparency = 1
        statusLabel.Text = "Ready"
        statusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
        statusLabel.TextSize = 12
        statusLabel.Font = Enum.Font.SourceSans
        statusLabel.TextXAlignment = Enum.TextXAlignment.Left
        statusLabel.TextYAlignment = Enum.TextYAlignment.Center
        statusLabel.TextWrapped = true

        local resizeGrip = Instance.new("TextButton")
        resizeGrip.Name = "ResizeGrip"
        resizeGrip.Parent = bottomBar
        resizeGrip.Size = UDim2.new(0, 34, 1, 0)
        resizeGrip.Position = UDim2.new(1, -34, 0, 0)
        resizeGrip.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        resizeGrip.Text = "↘"
        resizeGrip.TextColor3 = Color3.fromRGB(255, 255, 255)
        resizeGrip.TextSize = 14
        resizeGrip.Font = Enum.Font.SourceSansBold
        resizeGrip.AutoButtonColor = true

        local dragging = false
        local dragStart = nil
        local startPos = nil
        titleBar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        titleBar.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)

        local resizing = false
        local resizeStart = nil
        local startSize = nil
        resizeGrip.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                resizing = true
                resizeStart = input.Position
                startSize = frame.Size
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        resizing = false
                    end
                end)
            end
        end)
        resizeGrip.InputChanged:Connect(function(input)
            if not resizing then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - resizeStart
                local newW = math.clamp((startSize.X.Offset + delta.X), 280, 900)
                local newH = math.clamp((startSize.Y.Offset + delta.Y), 140, 700)
                frame.Size = UDim2.new(0, newW, 0, newH)
            end
        end)

        local minimized = false
        local prevSize = frame.Size
        minimizeButton.MouseButton1Click:Connect(function()
            minimized = not minimized
            if minimized then
                prevSize = frame.Size
                frame.Size = UDim2.new(0, prevSize.X.Offset, 0, 26)
                consoleArea.Visible = false
                bottomBar.Visible = false
                minimizeButton.Text = "+"
            else
                frame.Size = prevSize
                consoleArea.Visible = true
                bottomBar.Visible = true
                minimizeButton.Text = "-"
            end
        end)

        closeButton.MouseButton1Click:Connect(function()
            screenGui:Destroy()
        end)

        local function setStatus(s)
            statusLabel.Text = tostring(s)
        end

        local function updateCanvas()
            task.defer(function()
                if not consoleTextBox or not consoleTextBox.Parent then return end
                local y = consoleTextBox.TextBounds.Y + 12
                consoleTextBox.Size = UDim2.new(1, -10, 0, y)
                consoleArea.CanvasSize = UDim2.new(0, 0, 0, y + 10)
                consoleArea.CanvasPosition = Vector2.new(0, math.max(0, y))
            end)
        end

        local function appendLine(line)
            if not consoleTextBox or not consoleTextBox.Parent then return end
            consoleTextBox.Text = consoleTextBox.Text .. tostring(line) .. "\n"
            updateCanvas()
        end

        copyButton.MouseButton1Click:Connect(function()
            local txt = consoleTextBox.Text or ""
            if setclipboard then
                pcall(function() setclipboard(txt) end)
                setStatus("Copied " .. tostring(#txt) .. " chars")
            else
                setStatus("setclipboard not available")
            end
        end)

        clearButton.MouseButton1Click:Connect(function()
            consoleTextBox.Text = ""
            updateCanvas()
            setStatus("Cleared")
        end)

        updateCanvas()
        return {
            gui = screenGui,
            frame = frame,
            scroll = consoleArea,
            textBox = consoleTextBox,
            copyBtn = copyButton,
            clearBtn = clearButton,
            minBtn = minimizeButton,
            closeBtn = closeButton,
            appendLine = appendLine,
            setStatus = setStatus,
        }
    end

    local consoleCache = nil
    local function ensureConsole()
        if consoleCache and consoleCache.gui and consoleCache.gui.Parent then return consoleCache end
        consoleCache = getOrCreateBringConsole()
        return consoleCache
    end

    local function CONSOLE(level, msg)
        local c = ensureConsole()
        if not c then return end
        c.appendLine(("[" .. nowStr() .. "] [" .. level .. "] " .. msg))
    end

    local function INFO(msg) if C.State.BringLogEnabled then CONSOLE("INFO", msg) end end
    local function STAT(msg) if C.State.BringLogEnabled then CONSOLE("STAT", msg) end end
    local function TRACE(msg) if C.State.BringTraceEnabled then CONSOLE("TRACE", msg) end end
    local function ERR(msg) CONSOLE("ERR", msg) end

    local function memMb()
        local ok, mb = pcall(function()
            if Stats and Stats.GetTotalMemoryUsageMb then
                return Stats:GetTotalMemoryUsageMb()
            end
            return nil
        end)
        if ok and type(mb) == "number" then return mb end
        return nil
    end

    local COLLIDE_OFF_SEC       = 0.22
    local DROP_ABOVE_HEAD_STUDS = 10
    local FALLBACK_UP           = 4
    local FALLBACK_AHEAD        = 5
    local ORB_OFFSET_Y          = 20
    local CLUSTER_RADIUS_MIN    = 0.75
    local CLUSTER_RADIUS_STEP   = 0.04
    local CLUSTER_RADIUS_MAX    = 2.25

    local AIR_DROP_WAVE_AMPLITUDE = 1.0
    local AIR_DROP_WAVE_FREQUENCY = 1.3

    local CAMPFIRE_PATH = workspace.Map.Campground.MainFire
    local SCRAPPER_PATH = workspace.Map.Campground.Scrapper

    local junkItems = {"Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine","UFO Junk","UFO Component"}
    local fuelItems = {"Log","Coal","Fuel Canister","Oil Barrel","Biofuel","Chair"}
    local foodItems = {"Morsel","Cooked Morsel","Steak","Cooked Steak","Ribs","Cooked Ribs","Cake","Berry","Carrot","Chilli","Stew","Pumpkin","Hearty Stew","Corn","BBQ ribs","Apple","Mackerel"}
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {"Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Hammer","Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot Shield","Spear","Tactical Shotgun","Wildfire","Sword","Ice Axe","Thorn Body"}
    local ammoMisc = {"Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling","Basketball","Blueprint","Diamond","Gem of the Forest Fragment","Flashlight","Old Taming flute","Cultist Gem","Tusk","Infernal Sack"}
    local pelts = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Scorpion Shell","Polar Bear Pelt","Arctic Fox Pelt"}

    local fuelSet, junkSet, cookSet, scrapAlso = {}, {}, {}, {}
    for _,n in ipairs(fuelItems) do fuelSet[n] = true end
    for _,n in ipairs(junkItems) do junkSet[n] = true end
    cookSet["Morsel"] = true; cookSet["Steak"] = true; cookSet["Ribs"] = true
    scrapAlso["Log"] = true;  scrapAlso["Chair"] = true

    local RAW_TO_COOKED = {["Morsel"]="Cooked Morsel",["Steak"]="Cooked Steak",["Ribs"]="Cooked Ribs"}

    local function hrp()
        local ch = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function headPart()
        local ch = Players.LocalPlayer.Character
        return ch and ch:FindFirstChild("Head")
    end

    local function isWallVariant(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        return n == "logwall" or n == "log wall" or (n:find("log",1,true) and n:find("wall",1,true))
    end

    local function isUnderLogWall(inst)
        local cur = inst
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm == "logwall" or nm == "log wall" or (nm:find("log",1,true) and nm:find("wall",1,true)) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end

    local function hasHumanoid(model)
        if not (model and model:IsA("Model")) then return false end
        return model:FindFirstChildOfClass("Humanoid") ~= nil
    end

    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        if n == "pelt trader" then return true end
        if n:find("trader",1,true) or n:find("shopkeeper",1,true) then return true end
        if isWallVariant(m) then return true end
        if isUnderLogWall(m) then return true end
        return false
    end

    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            if obj.PrimaryPart then return obj.PrimaryPart end
            return obj:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end

    local function getAllParts(target)
        local t = {}
        if not target then return t end
        if target:IsA("BasePart") then
            t[1] = target
        elseif target:IsA("Model") then
            for _,d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then t[#t+1] = d end
            end
        end
        return t
    end

    local function bboxHeight(m)
        if m:IsA("Model") then
            local s = m:GetExtentsSize()
            return (s and s.Y) or 2
        end
        local p = mainPart(m)
        return (p and p.Size.Y) or 2
    end

    local metrics = {
        remoteFires = 0,
        streamReqs = 0,
        overlapCalls = 0,
        overlapParts = 0,
        candidates = 0,
        queued = 0,
        dropped = 0,
        convJobs = 0,
        convWaves = 0,
        convMoved = 0,
        convActiveMax = 0,
        convKick = 0,
        errors = 0,
        lastAction = "idle"
    }

    local function requestMoreStreamingAround(posList)
        if not (WS and WS.StreamingEnabled) then
            TRACE("Streaming disabled; skipping RequestStreamAroundAsync")
            return
        end
        local seen = {}
        for _,pos in ipairs(posList) do
            if typeof(pos) == "Vector3" then
                local key = math.floor(pos.X/64) .. "|" .. math.floor(pos.Z/64)
                if not seen[key] then
                    seen[key] = true
                    metrics.streamReqs += 1
                    TRACE("RequestStreamAroundAsync pos=" .. tostring(pos))
                    local ok = pcall(function() WS:RequestStreamAroundAsync(pos) end)
                    if not ok then metrics.errors += 1 end
                end
            end
        end
        task.wait(0.12)
    end

    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return nil end
        for _,n in ipairs({...}) do
            local x = re:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local function resolveRemotes()
        local r = {
            StartDrag = getRemote("RequestStartDraggingItem","StartDraggingItem"),
            BurnItem  = getRemote("RequestBurnItem","BurnItem","RequestFireAdd"),
            CookItem  = getRemote("RequestCookItem","CookItem"),
            ScrapItem = getRemote("RequestScrapItem","ScrapItem","RequestWorkbenchScrap"),
            StopDrag  = getRemote("StopDraggingItem","RequestStopDraggingItem"),
        }
        TRACE("resolveRemotes " .. shallowKV({
            StartDrag = r.StartDrag and r.StartDrag.Name or "nil",
            BurnItem  = r.BurnItem and r.BurnItem.Name or "nil",
            CookItem  = r.CookItem and r.CookItem.Name or "nil",
            ScrapItem = r.ScrapItem and r.ScrapItem.Name or "nil",
            StopDrag  = r.StopDrag and r.StopDrag.Name or "nil",
        }, 10))
        return r
    end

    local function safeStartDrag(r, model)
        if r and r.StartDrag and model and model.Parent then
            metrics.remoteFires += 1
            TRACE("FireServer StartDrag model=" .. (model.Name or "nil"))
            local ok = pcall(function() r.StartDrag:FireServer(model) end)
            if not ok then metrics.errors += 1 end
            return true
        end
        TRACE("safeStartDrag skipped " .. shallowKV({hasR=not not r, hasStart=not not (r and r.StartDrag), hasModel=not not model, hasParent=not not (model and model.Parent)}, 10))
        return false
    end

    local function safeStopDrag(r, model)
        if r and r.StopDrag and model and model.Parent then
            metrics.remoteFires += 1
            TRACE("FireServer StopDrag model=" .. (model.Name or "nil"))
            local ok = pcall(function() r.StopDrag:FireServer(model) end)
            if not ok then metrics.errors += 1 end
            return true
        end
        TRACE("safeStopDrag skipped " .. shallowKV({hasR=not not r, hasStop=not not (r and r.StopDrag), hasModel=not not model, hasParent=not not (model and model.Parent)}, 10))
        return false
    end

    local function finallyStopDrag(r, model)
        task.delay(0.05, function() pcall(safeStopDrag, r, model) end)
        task.delay(0.20, function() pcall(safeStopDrag, r, model) end)
    end

    local function setCollide(model, on, snapshot)
        local parts = getAllParts(model)
        if on and snapshot then
            for part,can in pairs(snapshot) do
                if part and part.Parent then part.CanCollide = can end
            end
            return
        end
        local snap = {}
        for _,p in ipairs(parts) do snap[p] = p.CanCollide; p.CanCollide = false end
        return snap
    end

    local function zeroAssembly(model)
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function computeForwardDropCF()
        local root = hrp(); if not root then return nil end
        local head = headPart()
        local basePos = head and head.Position or (root.Position + Vector3.new(0,4,0))
        local look = root.CFrame.LookVector
        local center = basePos + Vector3.new(0, DROP_ABOVE_HEAD_STUDS, 0) + look * FALLBACK_AHEAD
        return CFrame.lookAt(center, center + look)
    end

    local function pivotOverTarget(model, target)
        local mp = mainPart(target)
        if not mp then
            TRACE("pivotOverTarget no mainPart target=" .. (target and target.Name or "nil"))
            return
        end
        local above = mp.CFrame + Vector3.new(0, FALLBACK_UP, 0)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(above)
        else
            local p = mainPart(model); if p then p.CFrame = above end
        end
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity = Vector3.new(0,-8,0)
        end
        task.delay(COLLIDE_OFF_SEC, function() setCollide(model, true, snap) end)
    end

    local function moveModel(model, cf)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model); if p then p.CFrame = cf end
        end
        setCollide(model, true, snap)
    end

    local function fireCenterCF(fire)
        local p = fire:FindFirstChild("Center") or fire:FindFirstChild("InnerTouchZone") or mainPart(fire) or fire.PrimaryPart
        return (p and p.CFrame) or fire:GetPivot()
    end

    local function fireHandoffCF(fire) return fireCenterCF(fire) + Vector3.new(0, 1.5, 0) end

    local function scrCenterCF(scr)
        local p = mainPart(scr) or scr.PrimaryPart
        return (p and p.CFrame) or scr:GetPivot()
    end

    local function refreshPrompts(model)
        if not (model and model.Parent) then return end
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local was = d.Enabled
                d.Enabled = false
                task.defer(function() d.Enabled = was ~= false end)
            end
        end
    end

    local INFLT_ATTR   = "OrbInFlightAt"
    local DELIVER_ATTR = "DeliveredAtOrb"
    local JOB_ATTR     = "OrbJob"

    local DRAG_SETTLE  = 0.06
    local ACTION_HOLD  = 0.12
    local CONSUME_WAIT = 1.0
    local JOB_HARD_TIMEOUT_S = 60

    local function awaitConsumedOrMoved(model, timeout)
        local t0 = os.clock()
        local p0 = model and model.Parent or nil
        local checks = 0
        while os.clock() - t0 < (timeout or 1) do
            checks += 1
            if not model or not model.Parent then TRACE("awaitConsumedOrMoved done: model missing checks=" .. checks) return true end
            if model.Parent ~= p0 then TRACE("awaitConsumedOrMoved done: parent changed checks=" .. checks) return true end
            if model:GetAttribute("Consumed") == true then TRACE("awaitConsumedOrMoved done: Consumed=true checks=" .. checks) return true end
            Run.Heartbeat:Wait()
        end
        TRACE("awaitConsumedOrMoved timeout checks=" .. checks .. " model=" .. (model and model.Name or "nil"))
        return false
    end

    local function burnFlow(model, campfire)
        metrics.lastAction = "burnFlow"
        INFO("burnFlow begin model=" .. (model and model.Name or "nil"))
        local t0 = os.clock()
        local r = resolveRemotes()
        local started = safeStartDrag(r, model)
        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)
        pivotOverTarget(model, campfire)
        task.wait(ACTION_HOLD)
        if r.BurnItem then
            metrics.remoteFires += 1
            TRACE("FireServer BurnItem campfire=" .. (campfire and campfire.Name or "nil"))
            local ok = pcall(function() r.BurnItem:FireServer(campfire, Instance.new("Model")) end)
            if not ok then metrics.errors += 1 end
        else
            TRACE("burnFlow no BurnItem remote")
        end
        awaitConsumedOrMoved(model, CONSUME_WAIT)
        if started then finallyStopDrag(r, model) end
        refreshPrompts(model)
        INFO("burnFlow end dt=" .. fmtNum(os.clock() - t0))
    end

    local function cookFlow(model, campfire)
        metrics.lastAction = "cookFlow"
        INFO("cookFlow begin model=" .. (model and model.Name or "nil"))
        local t0 = os.clock()
        local r = resolveRemotes()
        local started = safeStartDrag(r, model)
        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)
        moveModel(model, fireHandoffCF(campfire))
        local ok = false
        if r.CookItem then
            metrics.remoteFires += 1
            TRACE("FireServer CookItem campfire=" .. (campfire and campfire.Name or "nil"))
            ok = pcall(function() r.CookItem:FireServer(campfire, Instance.new("Model")) end)
            if not ok then metrics.errors += 1 end
        else
            TRACE("cookFlow no CookItem remote")
        end
        if not ok then TRACE("cookFlow fallback pivotOverTarget") pivotOverTarget(model, campfire) end
        task.wait(ACTION_HOLD)
        local cookedName = RAW_TO_COOKED[model.Name]
        awaitConsumedOrMoved(model, CONSUME_WAIT)
        if started then finallyStopDrag(r, model) end
        task.delay(0.15, function()
            if cookedName then
                local tScan0 = os.clock()
                local center = fireCenterCF(campfire).Position
                local best, bestD = nil, nil
                local desc = WS:GetDescendants()
                TRACE("cookFlow scan descendants=" .. tostring(#desc) .. " cookedName=" .. tostring(cookedName))
                for _,m in ipairs(desc) do
                    if m:IsA("Model") and m.Name == cookedName and not isExcludedModel(m) and not isUnderLogWall(m) then
                        local mp = mainPart(m)
                        if mp then
                            local d = (mp.Position - center).Magnitude
                            if d <= 10 and (not bestD or d < bestD) then best, bestD = m, d end
                        end
                    end
                end
                TRACE("cookFlow cookedScan dt=" .. fmtNum(os.clock() - tScan0) .. " found=" .. tostring(best and best:GetFullName() or "nil"))
                if best then
                    local mp = mainPart(best)
                    if mp then
                        local dir = (mp.Position - center)
                        if dir.Magnitude > 0.001 then dir = dir.Unit else dir = Vector3.zAxis end
                        local snap = setCollide(best, false)
                        best:PivotTo(mp.CFrame + CFrame.new(dir * 1.5).Position)
                        setCollide(best, true, snap)
                    end
                end
            else
                TRACE("cookFlow no cookedName mapping for " .. tostring(model and model.Name or "nil"))
            end
        end)
        refreshPrompts(model)
        INFO("cookFlow end dt=" .. fmtNum(os.clock() - t0))
    end

    local function scrapFlow(model, scrapper)
        metrics.lastAction = "scrapFlow"
        INFO("scrapFlow begin model=" .. (model and model.Name or "nil"))
        local t0 = os.clock()
        local r = resolveRemotes()
        local started = safeStartDrag(r, model)
        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)
        moveModel(model, scrCenterCF(scrapper) + Vector3.new(0, 1.5, 0))
        local ok = false
        if r.ScrapItem then
            metrics.remoteFires += 1
            TRACE("FireServer ScrapItem scrapper=" .. (scrapper and scrapper.Name or "nil"))
            ok = pcall(function() r.ScrapItem:FireServer(scrapper, Instance.new("Model")) end)
            if not ok then metrics.errors += 1 end
        else
            TRACE("scrapFlow no ScrapItem remote")
        end
        if not ok then TRACE("scrapFlow fallback pivotOverTarget") pivotOverTarget(model, scrapper) end
        task.wait(ACTION_HOLD)
        awaitConsumedOrMoved(model, CONSUME_WAIT)
        if started then finallyStopDrag(r, model) end
        refreshPrompts(model)
        INFO("scrapFlow end dt=" .. fmtNum(os.clock() - t0))
    end

    local dropCounter = 0
    local function ringOffset()
        dropCounter += 1
        local i = dropCounter
        local a = i * 2.399963229728653
        local r = math.min(CLUSTER_RADIUS_MIN + CLUSTER_RADIUS_STEP * (i - 1), CLUSTER_RADIUS_MAX)
        return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
    end

    local function groundCFAroundPlayer(model)
        local root = hrp(); if not root then return nil end
        local head = headPart()
        local mp = mainPart(model); if not mp then return nil end
        local basePos = head and head.Position or (root.Position + Vector3.new(0, 4, 0))
        local look = root.CFrame.LookVector
        local offset = ringOffset()
        local waveY = math.sin(dropCounter * AIR_DROP_WAVE_FREQUENCY) * AIR_DROP_WAVE_AMPLITUDE
        local pos = basePos + look * FALLBACK_AHEAD + Vector3.new(0, DROP_ABOVE_HEAD_STUDS, 0) + Vector3.new(offset.X, 0, offset.Z) + Vector3.new(0, waveY, 0)
        return CFrame.lookAt(pos, pos + look)
    end

    local function dropNearPlayer(model)
        if not (model and model.Parent) then return end
        metrics.lastAction = "dropNearPlayer"
        metrics.dropped += 1
        TRACE("dropNearPlayer model=" .. (model.Name or "nil") .. " idx=" .. tostring(dropCounter + 1))
        local r = resolveRemotes()
        local started = safeStartDrag(r, model)
        Run.Heartbeat:Wait()
        local cf = groundCFAroundPlayer(model) or computeForwardDropCF()
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model); if p then p.CFrame = cf end
        end
        setCollide(model, true, snap)
        if started then finallyStopDrag(r, model) end
        for _,p in ipairs(getAllParts(model)) do
            p.Anchored = false
            p.AssemblyLinearVelocity = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            local ok1 = pcall(function() p:SetNetworkOwner(nil) end)
            local ok2 = pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
            if (not ok1) or (not ok2) then metrics.errors += 1 end
        end
        refreshPrompts(model)
        task.delay(0.5, function()
            pcall(function()
                if model and model.Parent then
                    model:SetAttribute("OrbInFlightAt", nil)
                    model:SetAttribute("OrbJob", nil)
                    model:SetAttribute("DeliveredAtOrb", nil)
                end
            end)
        end)
    end

    local function makeOrb(cf, name)
        local part = Instance.new("Part")
        part.Name = name
        part.Shape = Enum.PartType.Ball
        part.Size = Vector3.new(1.5, 1.5, 1.5)
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(255, 200, 50)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CanQuery = false
        part.CFrame = cf
        part.Parent = WS
        local light = Instance.new("PointLight")
        light.Range = 16
        light.Brightness = 3
        light.Parent = part
        TRACE("makeOrb name=" .. tostring(name) .. " pos=" .. tostring(cf.Position))
        return part
    end

    local function mergedSet(a, b)
        local t = {}
        for k,v in pairs(a) do if v then t[k] = true end end
        for k,v in pairs(b) do if v then t[k] = true end end
        return t
    end

    local DRAG_SPEED = 18
    local VERTICAL_MULT = 1.35
    local STEP_WAIT = 0.03
    local STUCK_TTL = 6.0
    local ORB_PICK_RADIUS = 60

    local function setPivot(model, cf)
        if model:IsA("Model") then model:PivotTo(cf) else
            local p = mainPart(model); if p then p.CFrame = cf end
        end
    end

    local function dropFromOrbSmooth(model, orbPos, jobId, origSnap, H)
        if not (model and model.Parent) then return end
        metrics.lastAction = "dropFromOrbSmooth"
        zeroAssembly(model)
        local above = orbPos + Vector3.new(0, math.max(0.5, H * 0.25), 0)
        setPivot(model, CFrame.new(above))
        for _,p in ipairs(getAllParts(model)) do
            p.Anchored = false
            p.AssemblyLinearVelocity = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            local ok1 = pcall(function() p:SetNetworkOwner(nil) end)
            local ok2 = pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
            if (not ok1) or (not ok2) then metrics.errors += 1 end
        end
        setCollide(model, true, origSnap)
        pcall(function()
            model:SetAttribute(INFLT_ATTR, nil)
            model:SetAttribute(JOB_ATTR, nil)
            model:SetAttribute(DELIVER_ATTR, tostring(jobId))
        end)
        refreshPrompts(model)
        task.delay(0.5, function()
            pcall(function()
                if model and model.Parent then
                    model:SetAttribute(DELIVER_ATTR, nil)
                end
            end)
        end)
    end

    local function itemsRootOrNil() return WS:FindFirstChild("Items") end

    local function isInsideTree(m)
        local cur = m and m.Parent
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm:find("tree", 1, true) then return true end
            if cur == itemsRootOrNil() then break end
            cur = cur.Parent
        end
        return false
    end

    local function nameMatches(selectedSet, m)
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        local nm = m and m.Name or ""
        local l = nm:lower()

        if selectedSet["Apple"] and nm == "Apple" then
            if itemsFolder and m.Parent ~= itemsFolder then return false end
            if isInsideTree(m) then return false end
            return true
        end
        if selectedSet["Berry"] and nm == "Berry" then
            if itemsFolder and m.Parent ~= itemsFolder then return false end
            if isInsideTree(m) then return false end
            return true
        end

        if selectedSet[nm] then return true end
        if selectedSet["Mossy Coin"] and (nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$")) then return true end
        if selectedSet["Cultist"] and m:IsA("Model") and l:find("cultist", 1, true) and hasHumanoid(m) then return true end
        if selectedSet["Sapling"] and nm == "Sapling" then return true end
        if selectedSet["Alpha Wolf Pelt"] and l:find("alpha", 1, true) and l:find("wolf", 1, true) then return true end
        if selectedSet["Bear Pelt"] and l:find("bear", 1, true) and not l:find("polar", 1, true) then return true end
        if selectedSet["Wolf Pelt"] and nm == "Wolf Pelt" then return true end
        if selectedSet["Bunny Foot"] and nm == "Bunny Foot" then return true end
        if selectedSet["Polar Bear Pelt"] and nm == "Polar Bear Pelt" then return true end
        if selectedSet["Arctic Fox Pelt"] and nm == "Arctic Fox Pelt" then return true end
        if selectedSet["Spear"] and l:find("spear", 1, true) and not hasHumanoid(m) then return true end
        if selectedSet["Sword"] and l:find("sword", 1, true) and not hasHumanoid(m) then return true end
        if selectedSet["Crossbow"] and l:find("crossbow", 1, true) and not l:find("cultist", 1, true) and not hasHumanoid(m) then return true end
        if selectedSet["Blueprint"] and l:find("blueprint", 1, true) then return true end
        if selectedSet["Flashlight"] and l:find("flashlight", 1, true) and not hasHumanoid(m) then return true end
        if selectedSet["Cultist Gem"] and l:find("cultist", 1, true) and l:find("gem", 1, true) then return true end
        if selectedSet["Forest Gem"] and (l:find("forest gem", 1, true) or (l:find("forest", 1, true) and l:find("fragment", 1, true))) then return true end
        if selectedSet["Tusk"] and l:find("tusk", 1, true) then return true end
        return false
    end

    local function topModelUnderItems(part, itemsFolder)
        local cur = part
        local lastModel = nil
        while cur and cur ~= WS and cur ~= itemsFolder do
            if cur:IsA("Model") then lastModel = cur end
            cur = cur.Parent
        end
        if lastModel and lastModel.Parent == itemsFolder then return lastModel end
        return lastModel
    end

    local function nearestSelectedModelFromPart(part, selectedSet)
        if not part or not part:IsA("BasePart") then return nil end
        local itemsFolder = itemsRootOrNil()
        local m = topModelUnderItems(part, itemsFolder) or part:FindFirstAncestorOfClass("Model")
        if m and nameMatches(selectedSet, m) then return m end
        return nil
    end

    local function canPick(m, center, radius, selectedSet, jobId)
        if not (m and m.Parent and m:IsA("Model")) then return false end
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        if isExcludedModel(m) or isUnderLogWall(m) then return false end
        if m.Name == "Log" and isWallVariant(m) then return false end
        local tIn = m:GetAttribute(INFLT_ATTR)
        local jIn = m:GetAttribute(JOB_ATTR)
        if tIn and jIn and tostring(jIn) ~= tostring(jobId) and os.clock() - tIn < STUCK_TTL then return false end
        if not nameMatches(selectedSet, m) then return false end
        local mp = mainPart(m); if not mp then return false end
        return (mp.Position - center).Magnitude <= radius
    end

    local function getCandidates(center, radius, selectedSet, jobId)
        local t0 = os.clock()
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        metrics.overlapCalls += 1
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        metrics.overlapParts += #parts
        local uniq, out = {}, {}
        for _,part in ipairs(parts) do
            local pick = nil
            if part:IsA("BasePart") then pick = nearestSelectedModelFromPart(part, selectedSet) end
            if pick and not uniq[pick] and canPick(pick, center, radius, selectedSet, jobId) then
                uniq[pick] = true
                out[#out+1] = pick
            end
        end
        metrics.candidates += #out
        TRACE("getCandidates center=" .. tostring(center) .. " r=" .. tostring(radius) .. " parts=" .. tostring(#parts) .. " models=" .. tostring(#out) .. " dt=" .. fmtNum(os.clock() - t0))
        return out
    end

    local function startConveyor(model, orbPos, jobId)
        if not (model and model.Parent) then return end
        metrics.lastAction = "startConveyor"
        pcall(function()
            model:SetAttribute(INFLT_ATTR, os.clock())
            model:SetAttribute(JOB_ATTR, tostring(jobId))
        end)
        local mp = mainPart(model); if not mp then return end
        local H = bboxHeight(model)

        local riserY = orbPos.Y - 1.0 + math.clamp(H * 0.45, 0.8, 3.0)
        local lookDir = (Vector3.new(orbPos.X, mp.Position.Y, orbPos.Z) - mp.Position)
        lookDir = (lookDir.Magnitude > 0.001) and lookDir.Unit or Vector3.zAxis

        local snapOrig = setCollide(model, false)
        zeroAssembly(model)

        local function setPivotLocal(model0, cf)
            if model0:IsA("Model") then model0:PivotTo(cf) else
                local p = mainPart(model0); if p then p.CFrame = cf end
            end
        end

        local stepsV, stepsH = 0, 0
        while model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local dy = riserY - pos.Y
            if math.abs(dy) <= 0.4 then break end
            local stepY = math.sign(dy) * math.min(DRAG_SPEED * VERTICAL_MULT * STEP_WAIT, math.abs(dy))
            local newPos = Vector3.new(pos.X, pos.Y + stepY, pos.Z)
            setPivotLocal(model, CFrame.new(newPos, newPos + lookDir))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            stepsV += 1
            task.wait(STEP_WAIT)
        end

        while model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local delta = Vector3.new(orbPos.X - pos.X, 0, orbPos.Z - pos.Z)
            local dist = delta.Magnitude
            if dist <= 1.0 then break end
            local step = math.min(DRAG_SPEED * STEP_WAIT, dist)
            local dir = delta.Unit
            local newPos = Vector3.new(pos.X, riserY, pos.Z) + dir * step
            setPivotLocal(model, CFrame.new(newPos, newPos + dir))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            stepsH += 1
            task.wait(STEP_WAIT)
        end

        TRACE("startConveyor done model=" .. (model.Name or "nil") .. " stepsV=" .. tostring(stepsV) .. " stepsH=" .. tostring(stepsH))
        dropFromOrbSmooth(model, orbPos, jobId, snapOrig, H)
    end

    local function runConveyorWave(centerPos, orbPos, targets, jobId)
        metrics.lastAction = "runConveyorWave"
        metrics.convWaves += 1
        local t0 = os.clock()
        local picked = getCandidates(centerPos, ORB_PICK_RADIUS, targets, jobId)
        if #picked == 0 then
            TRACE("runConveyorWave none dt=" .. fmtNum(os.clock() - t0))
            return 0
        end

        local limitOn = C.State.BringLimitEnabled and true or false
        local maxPerName = currentLimit()

        local cnt, out = {}, {}
        for _,m in ipairs(picked) do
            local nm = m.Name or ""
            cnt[nm] = (cnt[nm] or 0) + 1
            if (not limitOn) or cnt[nm] <= maxPerName then out[#out+1] = m end
        end
        picked = out

        local active = 0
        local function spawnOne(m)
            if m and m.Parent then
                active += 1
                if active > metrics.convActiveMax then metrics.convActiveMax = active end
                task.spawn(function()
                    startConveyor(m, orbPos, jobId)
                    active -= 1
                end)
            end
        end

        for i = 1, #picked do
            while active >= 10 do Run.Heartbeat:Wait() end
            spawnOne(picked[i])
            task.wait(0.5)
        end

        local deadline = os.clock() + math.max(5, 0.5 * #picked + 5)
        while active > 0 and os.clock() < deadline do Run.Heartbeat:Wait() end

        metrics.convMoved += #picked
        TRACE("runConveyorWave moved=" .. tostring(#picked) .. " dt=" .. fmtNum(os.clock() - t0))
        return #picked
    end

    local function runConveyorJob(centerPos, orbPos, targets, jobId)
        metrics.lastAction = "runConveyorJob"
        metrics.convJobs += 1
        INFO("runConveyorJob begin jobId=" .. tostring(jobId) .. " center=" .. tostring(centerPos) .. " orb=" .. tostring(orbPos))
        local t0 = os.clock()
        local emptyPasses = 0
        while true do
            if os.clock() - t0 >= JOB_HARD_TIMEOUT_S then TRACE("runConveyorJob hard-timeout jobId=" .. tostring(jobId)) break end
            local moved = runConveyorWave(centerPos, orbPos, targets, jobId)
            if moved == 0 then
                emptyPasses += 1
                TRACE("runConveyorJob emptyPass=" .. tostring(emptyPasses))
                if emptyPasses >= 2 then break end
                requestMoreStreamingAround({centerPos, orbPos})
                task.wait(0.2)
            else
                emptyPasses = 0
            end
        end
        INFO("runConveyorJob end jobId=" .. tostring(jobId) .. " dt=" .. fmtNum(os.clock() - t0))
    end

    local function burnNearby()
        metrics.lastAction = "burnNearby"
        INFO("Burn/Cook Nearby clicked")
        local camp = CAMPFIRE_PATH
        if not camp then INFO("burnNearby no campfire path") return end
        local root = hrp()
        if not root then INFO("burnNearby no HRP") return end
        local campCF = (mainPart(camp) and mainPart(camp).CFrame or camp:GetPivot())
        requestMoreStreamingAround({root.Position, campCF.Position})
        local jobId = ("%d-%d"):format(os.time(), math.random(1, 1000000))
        local orb2 = makeOrb(root.CFrame, "orb2")
        local orb1 = makeOrb(campCF + Vector3.new(0, ORB_OFFSET_Y + 10, 0), "orb1")
        local targets = mergedSet(fuelSet, cookSet)
        runConveyorJob(orb2.Position, orb1.Position, targets, jobId)
        if orb1 then orb1:Destroy() end
        if orb2 then orb2:Destroy() end
    end

    local function scrapNearby()
        metrics.lastAction = "scrapNearby"
        INFO("Scrap Nearby clicked")
        local scr = SCRAPPER_PATH
        if not scr then INFO("scrapNearby no scrapper path") return end
        local root = hrp()
        if not root then INFO("scrapNearby no HRP") return end
        local scrCF = (mainPart(scr) and mainPart(scr).CFrame or scr:GetPivot())
        requestMoreStreamingAround({root.Position, scrCF.Position})
        local jobId = ("%d-%d"):format(os.time(), math.random(1, 1000000))
        local orb2 = makeOrb(root.CFrame, "orb2")
        local orb1 = makeOrb(scrCF + Vector3.new(0, ORB_OFFSET_Y + 10, 0), "orb1")
        local targets = mergedSet(junkSet, scrapAlso)
        runConveyorJob(orb2.Position, orb1.Position, targets, jobId)
        if orb1 then orb1:Destroy() end
        if orb2 then orb2:Destroy() end
    end

    local function setFromChoice(choice)
        local s = {}
        if type(choice) == "table" then
            for _,v in ipairs(choice) do if v and v ~= "" then s[v] = true end end
        elseif choice and choice ~= "" then
            s[choice] = true
        end
        return s
    end

    local selJunkMany, selFuelMany, selFoodMany, selMedicalMany, selWAMany, selMiscMany, selPeltMany = {},{},{},{},{},{},{}

    local _bringBusy = false
    local function fastBringToGround(selectedSet)
        ensureConsole()
        if not selectedSet or next(selectedSet) == nil then INFO("fastBringToGround no selection") return end
        if _bringBusy then INFO("fastBringToGround busy") return end
        _bringBusy = true
        metrics.lastAction = "fastBringToGround"
        local tAll = os.clock()
        local ok = pcall(function()
            dropCounter = 0
            local perNameCount, seenModel, queue = {}, {}, {}
            local itemsFolder = itemsRootOrNil()
            if not itemsFolder then INFO("fastBringToGround: Items missing") return end
            local root = hrp()
            if root then requestMoreStreamingAround({root.Position}) end

            local limitOn = C.State.BringLimitEnabled and true or false
            local maxPerName = currentLimit()

            local t0 = os.clock()
            local desc = itemsFolder:GetDescendants()
            TRACE("fastBringToGround scan descendants=" .. tostring(#desc) .. " limitOn=" .. tostring(limitOn) .. " maxPerName=" .. tostring(maxPerName))
            for _,d in ipairs(desc) do
                local m = nil
                if d:IsA("Model") then
                    if nameMatches(selectedSet, d) then m = d end
                elseif d:IsA("BasePart") then
                    m = nearestSelectedModelFromPart(d, selectedSet)
                end
                if m and not seenModel[m] then
                    seenModel[m] = true
                    if not isExcludedModel(m) and not isUnderLogWall(m) then
                        local nm = m.Name
                        if not (nm == "Log" and isWallVariant(m)) then
                            perNameCount[nm] = (perNameCount[nm] or 0) + 1
                            if (not limitOn) or perNameCount[nm] <= maxPerName then
                                local mp = mainPart(m)
                                if mp then queue[#queue+1] = m end
                            end
                        end
                    end
                end
            end
            metrics.queued += #queue
            TRACE("fastBringToGround scan done queue=" .. tostring(#queue) .. " dt=" .. fmtNum(os.clock() - t0))

            local dropped = 0
            for i = 1, #queue do
                dropNearPlayer(queue[i])
                dropped += 1
                if i % 25 == 0 then Run.Heartbeat:Wait() end
            end
            TRACE("fastBringToGround dropped=" .. tostring(dropped))
        end)
        _bringBusy = false
        if not ok then metrics.errors += 1; ERR("fastBringToGround crashed inside pcall") return end
        INFO("fastBringToGround end dt=" .. fmtNum(os.clock() - tAll))
    end

    local function multiSelectDropdown(args)
        return tab:Dropdown({
            Title = args.title,
            Values = args.values,
            Multi = true,
            AllowNone = true,
            Callback = function(choice)
                local set = setFromChoice(choice)
                TRACE("Dropdown " .. tostring(args.title) .. " choice=" .. (type(choice) == "table" and ("count=" .. tostring(#choice)) or tostring(choice)))
                args.setter(set)
            end
        })
    end

    tab:Section({Title="Debug Console"})
    tab:Button({
        Title = "Open Debug Console",
        Callback = function()
            ensureConsole()
            INFO("Console opened")
        end
    })
    tab:Toggle({
        Title = "Logging",
        Default = C.State.BringLogEnabled and true or false,
        Callback = function(on)
            C.State.BringLogEnabled = on and true or false
            ensureConsole()
            INFO("Logging " .. (C.State.BringLogEnabled and "ENABLED" or "DISABLED"))
        end
    })
    tab:Toggle({
        Title = "Trace (very verbose)",
        Default = C.State.BringTraceEnabled and true or false,
        Callback = function(on)
            C.State.BringTraceEnabled = on and true or false
            ensureConsole()
            INFO("Trace " .. (C.State.BringTraceEnabled and "ENABLED" or "DISABLED"))
        end
    })
    tab:Slider({
        Title = "Metrics Hz",
        Value = {Min=1, Max=10, Default=tonumber(C.State.BringMetricsHz) or 1},
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max end
            nv = tonumber(nv)
            if nv then
                C.State.BringMetricsHz = math.clamp(nv, 1, 10)
                ensureConsole()
                INFO("Metrics Hz set to " .. tostring(C.State.BringMetricsHz))
            end
        end
    })
    tab:Button({Title="Dump Counters", Callback=function() ensureConsole(); INFO("Counters " .. shallowKV(metrics, 60)) end})
    tab:Button({
        Title="Reset Counters",
        Callback=function()
            ensureConsole()
            for k,_ in pairs(metrics) do if type(metrics[k]) == "number" then metrics[k] = 0 end end
            metrics.lastAction = "idle"
            INFO("Counters reset")
        end
    })

    tab:Section({Title="Actions"})
    tab:Button({Title="Burn/Cook Nearby", Callback=burnNearby})
    tab:Button({Title="Scrap Nearby", Callback=scrapNearby})

    tab:Section({Title="Bring Limits"})
    tab:Toggle({
        Title="Enable per-name limit",
        Default=C.State.BringLimitEnabled and true or false,
        Callback=function(on)
            C.State.BringLimitEnabled = on and true or false
            ensureConsole()
            INFO("BringLimitEnabled=" .. tostring(C.State.BringLimitEnabled))
        end
    })
    tab:Slider({
        Title="Max per item name",
        Value={Min=1, Max=100, Default=currentLimit()},
        Callback=function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max end
            nv = tonumber(nv)
            if nv then
                C.State.BringLimitAmount = math.clamp(nv, 1, 100)
                ensureConsole()
                INFO("BringLimitAmount=" .. tostring(C.State.BringLimitAmount))
            end
        end
    })

    tab:Section({Title="Junk → Ground (Multi)"})
    multiSelectDropdown({title="Select Junk Items", values=junkItems, setter=function(s) selJunkMany = s end})
    tab:Button({Title="Bring Selected (Fast)", Callback=function() fastBringToGround(selJunkMany) end})

    tab:Section({Title="Fuel → Ground (Multi)"})
    multiSelectDropdown({title="Select Fuel Items", values=fuelItems, setter=function(s) selFuelMany = s end})
    tab:Button({Title="Bring Selected (Fast)", Callback=function() fastBringToGround(selFuelMany) end})

    tab:Section({Title="Food → Ground (Multi)"})
    multiSelectDropdown({title="Select Food Items", values=foodItems, setter=function(s) selFoodMany = s end})
    tab:Button({Title="Bring Selected (Fast)", Callback=function() fastBringToGround(selFoodMany) end})

    tab:Section({Title="Medical → Ground (Multi)"})
    multiSelectDropdown({title="Select Medical Items", values=medicalItems, setter=function(s) selMedicalMany = s end})
    tab:Button({Title="Bring Selected (Fast)", Callback=function() fastBringToGround(selMedicalMany) end})

    tab:Section({Title="Weapons/Armor → Ground (Multi)"})
    multiSelectDropdown({title="Select Weapons/Armor", values=weaponsArmor, setter=function(s) selWAMany = s end})
    tab:Button({Title="Bring Selected (Fast)", Callback=function() fastBringToGround(selWAMany) end})

    tab:Section({Title="Ammo & Misc → Ground (Multi)"})
    multiSelectDropdown({title="Select Ammo/Misc", values=ammoMisc, setter=function(s) selMiscMany = s end})
    tab:Button({Title="Bring Selected (Fast)", Callback=function() fastBringToGround(selMiscMany) end})

    tab:Section({Title="Pelts → Ground (Multi)"})
    multiSelectDropdown({title="Select Pelts", values=pelts, setter=function(s) selPeltMany = s end})
    tab:Button({Title="Bring Selected (Fast)", Callback=function() fastBringToGround(selPeltMany) end})

    do
        local ORB_RADIUS     = 2.2
        local ORB_STUCK_SECS = 0.9
        local ORB_FALL_DELTA = 2.5
        local ORB_MAX_KICKS  = 2
        local ORB_RESET_UP   = 1.2
        local ORB_KICK_VY    = -60
        local GUARD_HZ       = 12

        local function campOrbPos()
            local camp = CAMPFIRE_PATH
            if not camp then return nil end
            local c = (mainPart(camp) and mainPart(camp).CFrame or camp:GetPivot()).Position
            return Vector3.new(c.X, c.Y + ORB_OFFSET_Y + 10, c.Z)
        end

        local function scrapOrbPos()
            local scr = SCRAPPER_PATH
            if not scr then return nil end
            local c = (mainPart(scr) and mainPart(scr).CFrame or scr:GetPivot()).Position
            return Vector3.new(c.X, c.Y + ORB_OFFSET_Y + 10, c.Z)
        end

        local function liveOrb1Pos()
            local o = WS:FindFirstChild("orb1")
            return o and o:IsA("BasePart") and o.Position or nil
        end

        local function kickDown(m, orbY)
            local mp = mainPart(m); if not mp then return end
            metrics.convKick += 1
            TRACE("ORB kickDown model=" .. (m.Name or "nil") .. " orbY=" .. tostring(orbY))
            pcall(function() mp.Anchored = false end)
            pcall(function() mp.AssemblyLinearVelocity = Vector3.new(0, ORB_KICK_VY, 0) end)
            pcall(function() mp.AssemblyAngularVelocity = Vector3.new() end)
            pcall(function() mp:SetNetworkOwner(nil) end)
            pcall(function() if mp.SetNetworkOwnershipAuto then mp:SetNetworkOwnershipAuto() end end)
            pcall(function()
                local p = mp.Position
                mp.CFrame = CFrame.new(Vector3.new(p.X, orbY + ORB_RESET_UP, p.Z))
            end)
            refreshPrompts(m)
        end

        local watched = setmetatable({}, {__mode="k"})
        local acc = 0
        Run.Heartbeat:Connect(function(dt)
            acc += dt
            if acc < (1 / GUARD_HZ) then return end
            acc = 0

            local positions = {}
            local pLive = liveOrb1Pos(); if pLive then positions[#positions+1] = pLive end
            local pCamp = campOrbPos();  if pCamp then positions[#positions+1] = pCamp end
            local pScr  = scrapOrbPos(); if pScr then positions[#positions+1] = pScr end
            if #positions == 0 then return end

            local items = WS:FindFirstChild("Items"); if not items then return end
            for _,m in ipairs(items:GetChildren()) do
                if not m:IsA("Model") then continue end
                local mp = mainPart(m); if not mp then continue end

                local nearest, orbY = nil, nil
                local pos = mp.Position
                for _,o in ipairs(positions) do
                    local d = (pos - o).Magnitude
                    if d <= ORB_RADIUS then nearest, orbY = true, o.Y; break end
                end

                if nearest then
                    local rec = watched[m]
                    if not rec then
                        watched[m] = {t=os.clock(), y0=pos.Y, kicks=0}
                    else
                        local fell = (rec.y0 - pos.Y) >= ORB_FALL_DELTA or pos.Y < (orbY - ORB_FALL_DELTA)
                        if fell then
                            watched[m] = nil
                        elseif (os.clock() - rec.t) >= ORB_STUCK_SECS then
                            if rec.kicks < ORB_MAX_KICKS then
                                rec.kicks += 1
                                rec.t = os.clock()
                                rec.y0 = pos.Y
                                kickDown(m, orbY)
                            else
                                watched[m] = nil
                            end
                        end
                    end
                else
                    watched[m] = nil
                end
            end
        end)
    end

    task.spawn(function()
        local acc = 0
        while true do
            local dt = Run.Heartbeat:Wait()
            acc += dt
            local hz = tonumber(C.State.BringMetricsHz) or 1
            local period = 1 / math.clamp(hz, 1, 10)
            if acc >= period then
                acc = 0
                if C.State.BringLogEnabled then
                    ensureConsole()
                    local luaKB = collectgarbage("count")
                    local items = itemsRootOrNil()
                    local itemsDesc = 0
                    if items then
                        local ok, d = pcall(function() return items:GetDescendants() end)
                        if ok and d then itemsDesc = #d end
                    end
                    local mb = memMb()
                    STAT(("METRICS luaKB=%d itemsDesc=%d last=%s remoteFires=%d streamReqs=%d overlapCalls=%d overlapParts=%d cand=%d queued=%d dropped=%d convJobs=%d convWaves=%d convMoved=%d convActiveMax=%d convKick=%d errors=%d totalMemMB=%s")
                        :format(
                            math.floor(luaKB + 0.5),
                            tonumber(itemsDesc) or 0,
                            tostring(metrics.lastAction),
                            metrics.remoteFires,
                            metrics.streamReqs,
                            metrics.overlapCalls,
                            metrics.overlapParts,
                            metrics.candidates,
                            metrics.queued,
                            metrics.dropped,
                            metrics.convJobs,
                            metrics.convWaves,
                            metrics.convMoved,
                            metrics.convActiveMax,
                            metrics.convKick,
                            metrics.errors,
                            mb and fmtNum(mb) or "n/a"
                        )
                    )
                end
            end
        end
    end)
end
