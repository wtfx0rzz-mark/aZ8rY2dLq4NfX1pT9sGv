-- extra.lua
return function(C, R, UI)
    local function run()
        C  = C  or _G.C
        UI = UI or _G.UI

        local Services = (C and C.Services) or {}
        local Players  = Services.Players or game:GetService("Players")
        local RS       = Services.RS or game:GetService("ReplicatedStorage")
        local WS       = Services.WS or game:GetService("Workspace")
        local Run      = Services.Run or game:GetService("RunService")
        local VIM      = Services.VIM or game:GetService("VirtualInputManager")
        local UIS      = Services.UIS or game:GetService("UserInputService")

        local lp = Players.LocalPlayer
        if not lp then return end

        local function nowStr()
            local ok, s = pcall(function() return os.date("%H:%M:%S") end)
            if ok and s then return s end
            return tostring(math.floor(os.clock() * 1000))
        end

        local function makeLogger()
            local pg = lp:WaitForChild("PlayerGui")

            local old = pg:FindFirstChild("ExtraLoggerGui")
            if old then pcall(function() old:Destroy() end) end

            local screenGui = Instance.new("ScreenGui")
            screenGui.Name = "ExtraLoggerGui"
            screenGui.Parent = pg
            screenGui.ResetOnSpawn = false

            local frame = Instance.new("Frame")
            frame.Name = "Window"
            frame.Parent = screenGui
            frame.Size = UDim2.new(0, 420, 0, 240)
            frame.Position = UDim2.new(0, 18, 0, 120)
            frame.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
            frame.BorderSizePixel = 0
            frame.Active = true
            frame.Draggable = true

            local titleBar = Instance.new("Frame")
            titleBar.Name = "TitleBar"
            titleBar.Parent = frame
            titleBar.Size = UDim2.new(1, 0, 0, 26)
            titleBar.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
            titleBar.BorderSizePixel = 0

            local titleLabel = Instance.new("TextLabel")
            titleLabel.Name = "Title"
            titleLabel.Parent = titleBar
            titleLabel.Size = UDim2.new(1, -90, 1, 0)
            titleLabel.Position = UDim2.new(0, 8, 0, 0)
            titleLabel.BackgroundTransparency = 1
            titleLabel.Text = "Extra Logger"
            titleLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
            titleLabel.TextSize = 14
            titleLabel.Font = Enum.Font.SourceSansBold
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left

            local minimizeButton = Instance.new("TextButton")
            minimizeButton.Name = "Minimize"
            minimizeButton.Parent = titleBar
            minimizeButton.Size = UDim2.new(0, 28, 0, 26)
            minimizeButton.Position = UDim2.new(1, -62, 0, 0)
            minimizeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
            minimizeButton.BorderSizePixel = 0
            minimizeButton.Text = "-"
            minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            minimizeButton.TextSize = 16
            minimizeButton.Font = Enum.Font.SourceSansBold

            local closeButton = Instance.new("TextButton")
            closeButton.Name = "Close"
            closeButton.Parent = titleBar
            closeButton.Size = UDim2.new(0, 34, 0, 26)
            closeButton.Position = UDim2.new(1, -34, 0, 0)
            closeButton.BackgroundColor3 = Color3.fromRGB(160, 60, 60)
            closeButton.BorderSizePixel = 0
            closeButton.Text = "X"
            closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            closeButton.TextSize = 14
            closeButton.Font = Enum.Font.SourceSansBold

            local consoleArea = Instance.new("ScrollingFrame")
            consoleArea.Name = "ConsoleArea"
            consoleArea.Parent = frame
            consoleArea.Size = UDim2.new(1, 0, 1, -52)
            consoleArea.Position = UDim2.new(0, 0, 0, 26)
            consoleArea.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
            consoleArea.BorderSizePixel = 0
            consoleArea.ScrollBarThickness = 6
            consoleArea.CanvasSize = UDim2.new(0, 0, 0, 0)
            consoleArea.AutomaticCanvasSize = Enum.AutomaticSize.Y

            local consoleText = Instance.new("TextLabel")
            consoleText.Name = "ConsoleText"
            consoleText.Parent = consoleArea
            consoleText.Size = UDim2.new(1, -10, 0, 0)
            consoleText.Position = UDim2.new(0, 6, 0, 6)
            consoleText.BackgroundTransparency = 1
            consoleText.Text = ""
            consoleText.TextColor3 = Color3.fromRGB(210, 210, 210)
            consoleText.TextSize = 12
            consoleText.Font = Enum.Font.Code
            consoleText.TextXAlignment = Enum.TextXAlignment.Left
            consoleText.TextYAlignment = Enum.TextYAlignment.Top
            consoleText.TextWrapped = true
            consoleText.AutomaticSize = Enum.AutomaticSize.Y

            local buttonBar = Instance.new("Frame")
            buttonBar.Name = "ButtonBar"
            buttonBar.Parent = frame
            buttonBar.Size = UDim2.new(1, 0, 0, 26)
            buttonBar.Position = UDim2.new(0, 0, 1, -26)
            buttonBar.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
            buttonBar.BorderSizePixel = 0

            local copyButton = Instance.new("TextButton")
            copyButton.Name = "Copy"
            copyButton.Parent = buttonBar
            copyButton.Size = UDim2.new(0, 120, 1, 0)
            copyButton.Position = UDim2.new(0, 0, 0, 0)
            copyButton.BackgroundColor3 = Color3.fromRGB(55, 125, 65)
            copyButton.BorderSizePixel = 0
            copyButton.Text = "Copy"
            copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            copyButton.TextSize = 14
            copyButton.Font = Enum.Font.SourceSansBold

            local clearButton = Instance.new("TextButton")
            clearButton.Name = "Clear"
            clearButton.Parent = buttonBar
            clearButton.Size = UDim2.new(0, 120, 1, 0)
            clearButton.Position = UDim2.new(0, 120, 0, 0)
            clearButton.BackgroundColor3 = Color3.fromRGB(125, 55, 55)
            clearButton.BorderSizePixel = 0
            clearButton.Text = "Clear"
            clearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            clearButton.TextSize = 14
            clearButton.Font = Enum.Font.SourceSansBold

            local isMinimized = false
            minimizeButton.MouseButton1Click:Connect(function()
                if isMinimized then
                    frame.Size = UDim2.new(0, 420, 0, 240)
                    consoleArea.Visible = true
                    buttonBar.Visible = true
                    minimizeButton.Text = "-"
                    isMinimized = false
                else
                    frame.Size = UDim2.new(0, 420, 0, 26)
                    consoleArea.Visible = false
                    buttonBar.Visible = false
                    minimizeButton.Text = "+"
                    isMinimized = true
                end
            end)

            closeButton.MouseButton1Click:Connect(function()
                pcall(function() screenGui:Destroy() end)
            end)

            clearButton.MouseButton1Click:Connect(function()
                consoleText.Text = ""
                pcall(function() consoleArea.CanvasPosition = Vector2.new(0, 0) end)
            end)

            copyButton.MouseButton1Click:Connect(function()
                local txt = consoleText.Text or ""
                local ok = false
                if typeof(setclipboard) == "function" then
                    ok = pcall(function() setclipboard(txt) end)
                elseif typeof(toClipboard) == "function" then
                    ok = pcall(function() toClipboard(txt) end)
                end
                if not ok then
                    consoleText.Text = (consoleText.Text or "") .. "\n[" .. nowStr() .. "] " .. "COPY FAILED (no clipboard function)\n"
                end
            end)

            local function append(line)
                consoleText.Text = (consoleText.Text or "") .. line .. "\n"
                task.defer(function()
                    pcall(function()
                        consoleArea.CanvasPosition = Vector2.new(0, consoleText.TextBounds.Y + 999)
                    end)
                end)
            end

            return {
                Gui = screenGui,
                Append = append,
                GetText = function() return consoleText.Text end,
                Clear = function() consoleText.Text = "" end
            }
        end

        if type(C.State) ~= "table" then C.State = {} end
        C.State.Extra = C.State.Extra or {}
        local ST = C.State.Extra

        ST.Logger = ST.Logger or makeLogger()
        local Log = ST.Logger

        local function logf(msg)
            if not Log or not Log.Append then return end
            Log.Append("[" .. nowStr() .. "] " .. tostring(msg))
        end

        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Extra or Tabs.Auto or Tabs.Main
        if not tab then
            logf("[Extra] Tab not found (Extra/Auto/Main)")
        end

        if ST.AutoOpenChests == nil then ST.AutoOpenChests = false end
        ST.Captured      = ST.Captured or {}
        ST.CapturedSet   = ST.CapturedSet or {}
        ST._chestToken   = ST._chestToken or 0
        ST.DebugLog      = (ST.DebugLog ~= false)
        ST.TreatPromptGoneAsOpened = ST.TreatPromptGoneAsOpened or false
        ST.ScanDescendantsForItems = ST.ScanDescendantsForItems or false

        C.Config = C.Config or {}
        local CFG = C.Config
        CFG.CHEST_SCAN_INTERVAL     = CFG.CHEST_SCAN_INTERVAL     or 0.20
        CFG.CHEST_PRE_RADIUS        = CFG.CHEST_PRE_RADIUS        or 22
        CFG.CHEST_CAPTURE_RADIUS    = CFG.CHEST_CAPTURE_RADIUS    or 26
        CFG.CHEST_POST_OPEN_DELAY   = CFG.CHEST_POST_OPEN_DELAY   or 0.50
        CFG.CHEST_NOT_OPEN_WAIT     = CFG.CHEST_NOT_OPEN_WAIT     or 5.00
        CFG.CHEST_TELEPORT_UP       = CFG.CHEST_TELEPORT_UP       or 3.0
        CFG.CHEST_TELEPORT_BACK     = CFG.CHEST_TELEPORT_BACK     or 2.5
        CFG.DROP_SPREAD             = CFG.DROP_SPREAD             or 7.0
        CFG.FLOAT_FIX_DELAY         = CFG.FLOAT_FIX_DELAY         or 5.0
        CFG.FLOAT_FIX_RADIUS        = CFG.FLOAT_FIX_RADIUS        or 30.0

        local UID_OPEN_KEY = tostring(lp.UserId) .. "Opened"

        local function hrp()
            local ch = lp.Character or lp.CharacterAdded:Wait()
            return ch and ch:WaitForChild("HumanoidRootPart")
        end

        local function itemsFolder()
            return WS:FindFirstChild("Items")
        end

        local function getRootPart(x)
            if not x or not x.Parent then return nil end
            if x:IsA("BasePart") then return x end
            if x:IsA("Model") then
                if x.PrimaryPart and x.PrimaryPart:IsA("BasePart") then return x.PrimaryPart end
                local p = x:FindFirstChildWhichIsA("BasePart", true)
                if p then
                    pcall(function() x.PrimaryPart = p end)
                    return p
                end
            end
            return nil
        end

        local function getPos(x)
            local p = getRootPart(x)
            return p and p.Position or nil
        end

        local function safePath(inst)
            if not inst then return "nil" end
            local ok, s = pcall(function() return inst:GetFullName() end)
            if ok and s then return s end
            return tostring(inst)
        end

        local function setAnchored(x, v)
            if not x or not x.Parent then return end
            if x:IsA("BasePart") then
                pcall(function() x.Anchored = v end)
                return
            end
            if x:IsA("Model") then
                for _, d in ipairs(x:GetDescendants()) do
                    if d:IsA("BasePart") then
                        pcall(function() d.Anchored = v end)
                    end
                end
            end
        end

        local function setCollide(x, v)
            if not x or not x.Parent then return end
            if x:IsA("BasePart") then
                pcall(function() x.CanCollide = v end)
                return
            end
            if x:IsA("Model") then
                for _, d in ipairs(x:GetDescendants()) do
                    if d:IsA("BasePart") then
                        pcall(function() d.CanCollide = v end)
                    end
                end
            end
        end

        local function zeroVelocity(x)
            local p = getRootPart(x)
            if not p then return end
            pcall(function()
                p.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)
        end

        local function moveTo(x, cf)
            if not x or not x.Parent then return false end
            if x:IsA("BasePart") then
                local ok = pcall(function() x.CFrame = cf end)
                return ok
            end
            if x:IsA("Model") then
                local pp = getRootPart(x)
                if not pp then return false end
                local ok = pcall(function() x:SetPrimaryPartCFrame(cf) end)
                return ok
            end
            return false
        end

        local function findProxPrompt(chest)
            if not chest or not chest.Parent then return nil end
            for _, d in ipairs(chest:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    return d
                end
            end
            return nil
        end

        local RE = RS:FindFirstChild("RemoteEvents")
        local function findRemoteEvent(names)
            if not RE then return nil end
            for _, n in ipairs(names) do
                local r = RE:FindFirstChild(n)
                if r and r:IsA("RemoteEvent") then return r end
            end
            local lower = {}
            for _, n in ipairs(names) do lower[string.lower(n)] = true end
            for _, d in ipairs(RE:GetDescendants()) do
                if d:IsA("RemoteEvent") then
                    local dn = string.lower(d.Name)
                    if lower[dn] then return d end
                end
            end
            return nil
        end

        local StartDragRE = findRemoteEvent({
            "RequestStartDraggingItem",
            "StartDraggingItem",
            "StartDragging",
            "RequestDragItem",
            "RequestDrag"
        })

        local StopDragRE = findRemoteEvent({
            "StopDraggingItem",
            "RequestStopDraggingItem",
            "StopDragging",
            "RequestStopDragging",
            "RequestStopDragItem",
            "RequestStopDrag"
        })

        local function startDragOnce(item)
            if not item or not item.Parent then return end
            if ST.CapturedSet[item] then return end
            ST.CapturedSet[item] = true
            if StartDragRE then
                local ok, err = pcall(function() StartDragRE:FireServer(item) end)
                if ST.DebugLog then
                    logf("StartDragRE=" .. tostring(StartDragRE.Name) .. " item=" .. (item.Name or "?") .. " ok=" .. tostring(ok) .. (err and (" err=" .. tostring(err)) or ""))
                end
            else
                if ST.DebugLog then logf("StartDragRE=nil item=" .. (item.Name or "?")) end
            end
        end

        local function stopDragRetries(item, tries, stepDelay)
            if not item or not item.Parent then return end
            tries = tries or 8
            stepDelay = stepDelay or 0.15
            for i = 1, tries do
                if StopDragRE then
                    local ok, err = pcall(function() StopDragRE:FireServer(item) end)
                    if ST.DebugLog and i == 1 then
                        logf("StopDragRE=" .. tostring(StopDragRE.Name) .. " item=" .. (item.Name or "?") .. " ok=" .. tostring(ok) .. (err and (" err=" .. tostring(err)) or ""))
                    end
                else
                    if ST.DebugLog and i == 1 then logf("StopDragRE=nil item=" .. (item.Name or "?")) end
                end
                task.wait(stepDelay)
            end
        end

        local function isChest(x)
            if not x or not x.Parent then return false end
            local n = string.lower(x.Name or "")
            if n:find("chest") then return true end
            return false
        end

        local function isItemCandidate(x)
            if not x or not x.Parent then return false end
            if x:IsA("Model") or x:IsA("BasePart") then
                if isChest(x) then return false end
                return true
            end
            return false
        end

        local function iterItems(folder)
            if not folder then return function() end end
            if ST.ScanDescendantsForItems then
                local all = folder:GetDescendants()
                local i = 0
                return function()
                    i += 1
                    return all[i]
                end
            else
                local kids = folder:GetChildren()
                local i = 0
                return function()
                    i += 1
                    return kids[i]
                end
            end
        end

        local function snapshotNear(pos, radius)
            local folder = itemsFolder()
            local set = {}
            if not folder or not pos then return set end
            local count = 0
            for child in iterItems(folder) do
                if child and child.Parent and isItemCandidate(child) then
                    local p = getPos(child)
                    if p and (p - pos).Magnitude <= radius then
                        set[child] = true
                        count += 1
                    end
                end
            end
            if ST.DebugLog then logf("snapshotNear r=" .. tostring(radius) .. " count=" .. tostring(count) .. " mode=" .. (ST.ScanDescendantsForItems and "desc" or "children")) end
            return set
        end

        local function diffNear(pos, radius, preSet)
            local folder = itemsFolder()
            local out = {}
            if not folder or not pos then return out end
            for child in iterItems(folder) do
                if child and child.Parent and isItemCandidate(child) and not preSet[child] and not ST.CapturedSet[child] then
                    local p = getPos(child)
                    if p and (p - pos).Magnitude <= radius then
                        table.insert(out, child)
                    end
                end
            end
            return out
        end

        local function hoverCaptured(item)
            if not item or not item.Parent then return end
            startDragOnce(item)
            setAnchored(item, true)
            setCollide(item, false)
            zeroVelocity(item)
            local h = hrp()
            local i = #ST.Captured
            local y = 6 + (i * 1.2)
            local cf = h.CFrame * CFrame.new(0, y, 0)
            moveTo(item, cf)
            table.insert(ST.Captured, item)
            if ST.DebugLog then logf("CAPTURE item=" .. (item.Name or "?") .. " path=" .. safePath(item)) end
        end

        local function rayDown(fromPos, ignore)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = ignore or {}
            params.IgnoreWater = false
            return WS:Raycast(fromPos, Vector3.new(0, -600, 0), params)
        end

        local function dropCaptured()
            local h = hrp()
            local ch = lp.Character
            local ignore = {}
            if ch then table.insert(ignore, ch) end

            local keep = {}
            local keepSet = {}

            logf("DROP begin captured=" .. tostring(#ST.Captured))

            for _, item in ipairs(ST.Captured) do
                if item and item.Parent then
                    local offset = Vector3.new((math.random() - 0.5) * 2 * CFG.DROP_SPREAD, 0, (math.random() - 0.5) * 2 * CFG.DROP_SPREAD)
                    local start = h.Position + Vector3.new(0, 6, 0) + offset
                    local hit = rayDown(start, ignore)
                    local placePos = start
                    if hit and hit.Position then placePos = hit.Position + Vector3.new(0, 0.7, 0) end

                    setAnchored(item, false)
                    setCollide(item, true)
                    zeroVelocity(item)
                    moveTo(item, CFrame.new(placePos))
                    stopDragRetries(item, 10, 0.12)

                    keep[#keep + 1] = item
                    keepSet[item] = true
                    if ST.DebugLog then logf("DROP item=" .. (item.Name or "?") .. " -> " .. string.format("(%.1f,%.1f,%.1f)", placePos.X, placePos.Y, placePos.Z)) end
                end
            end

            ST.Captured = keep
            ST.CapturedSet = keepSet

            logf("DROP end kept=" .. tostring(#ST.Captured))

            task.delay(CFG.FLOAT_FIX_DELAY, function()
                local h2 = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                if not h2 then return end
                local folder = itemsFolder()
                if not folder then return end

                local ch2 = lp.Character
                local ignore2 = {}
                if ch2 then table.insert(ignore2, ch2) end

                local center = h2.Position
                local fixed = 0
                for _, obj in ipairs(folder:GetChildren()) do
                    if isItemCandidate(obj) then
                        local p = getPos(obj)
                        if p and (p - center).Magnitude <= CFG.FLOAT_FIX_RADIUS then
                            local start = p + Vector3.new(0, 3, 0)
                            local hit = rayDown(start, ignore2)
                            if hit and hit.Position then
                                local ground = hit.Position + Vector3.new(0, 0.7, 0)
                                if (p - ground).Magnitude >= 3.0 then
                                    setAnchored(obj, false)
                                    setCollide(obj, true)
                                    zeroVelocity(obj)
                                    moveTo(obj, CFrame.new(ground))
                                    stopDragRetries(obj, 6, 0.14)
                                    fixed += 1
                                end
                            end
                        end
                    end
                end
                if ST.DebugLog then logf("FLOAT_FIX fixed=" .. tostring(fixed)) end
            end)
        end

        local function tryTriggerPrompt(prompt)
            if not prompt or not prompt.Parent then return false, "no_prompt" end

            if typeof(fireproximityprompt) == "function" then
                local ok, err = pcall(function() fireproximityprompt(prompt, 1) end)
                return ok, ok and "fireproximityprompt" or ("fireproximityprompt_err:" .. tostring(err))
            end

            if VIM then
                local ok, err = pcall(function()
                    VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.03)
                    VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end)
                if ok then return true, "VIM_E" end
                return false, "VIM_err:" .. tostring(err)
            end

            local ok, err = pcall(function()
                prompt:InputHoldBegin()
                task.wait(0.06)
                prompt:InputHoldEnd()
            end)
            if ok then return true, "InputHoldBeginEnd" end
            return false, "InputHold_err:" .. tostring(err)
        end

        local function teleportNear(pos)
            if not pos then return end
            local h = hrp()
            local target = pos + Vector3.new(0, CFG.CHEST_TELEPORT_UP, 0) + Vector3.new(0, 0, CFG.CHEST_TELEPORT_BACK)
            pcall(function() h.CFrame = CFrame.new(target, pos) end)
        end

        local function promptInfo(prompt)
            if not prompt then return "prompt=nil" end
            local parent = prompt.Parent
            local s = {}
            s[#s + 1] = "prompt=" .. prompt.Name
            s[#s + 1] = "enabled=" .. tostring(prompt.Enabled)
            s[#s + 1] = "hold=" .. tostring(prompt.HoldDuration)
            s[#s + 1] = "los=" .. tostring(prompt.RequiresLineOfSight)
            s[#s + 1] = "maxDist=" .. tostring(prompt.MaxActivationDistance)
            s[#s + 1] = "parent=" .. (parent and parent.Name or "nil")
            return table.concat(s, " ")
        end

        local function distToPrompt(prompt)
            if not prompt or not prompt.Parent then return nil end
            local h = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            if not h then return nil end
            local p = (prompt.Parent:IsA("BasePart") and prompt.Parent.Position) or getPos(prompt.Parent)
            if not p then return nil end
            return (h.Position - p).Magnitude
        end

        local function processChest(chest)
            if not chest or not chest.Parent then return false end
            if chest:GetAttribute(UID_OPEN_KEY) == true then
                if ST.DebugLog then logf("CHEST skip alreadyMarked name=" .. (chest.Name or "?")) end
                return false
            end

            local cpos = getPos(chest)
            if not cpos then
                if ST.DebugLog then logf("CHEST no_pos name=" .. (chest.Name or "?") .. " path=" .. safePath(chest)) end
                return false
            end

            local h = hrp()
            local dist = (h.Position - cpos).Magnitude
            logf("CHEST begin name=" .. (chest.Name or "?") .. " dist=" .. string.format("%.1f", dist) .. " path=" .. safePath(chest))

            teleportNear(cpos)
            task.wait(0.10)

            local prompt = findProxPrompt(chest)
            if ST.DebugLog then
                local pd = distToPrompt(prompt)
                logf("CHEST prompt " .. promptInfo(prompt) .. (pd and (" distToPrompt=" .. string.format("%.1f", pd)) or ""))
            end

            local pre = snapshotNear(cpos, CFG.CHEST_PRE_RADIUS)

            local capturedAny = false
            local opened = false
            local promptWasPresent = (prompt ~= nil)
            local promptWentNilAt = nil
            local tries = 0
            local lastTry = 0
            local t0 = os.clock()

            while os.clock() - t0 <= CFG.CHEST_NOT_OPEN_WAIT do
                if not chest.Parent then
                    logf("CHEST removed mid-loop -> treating as opened")
                    opened = true
                    break
                end

                if prompt and (not prompt.Parent or prompt.Enabled == false) then
                    if promptWentNilAt == nil then promptWentNilAt = os.clock() end
                    if ST.DebugLog then logf("CHEST prompt invalid/disabled -> nil (" .. promptInfo(prompt) .. ")") end
                    prompt = nil
                end

                if not prompt then
                    local p2 = findProxPrompt(chest)
                    if p2 then
                        prompt = p2
                        if ST.DebugLog then
                            local pd = distToPrompt(prompt)
                            logf("CHEST prompt reacquired " .. promptInfo(prompt) .. (pd and (" distToPrompt=" .. string.format("%.1f", pd)) or ""))
                        end
                    end
                end

                if prompt == nil and promptWasPresent and promptWentNilAt == nil then
                    promptWentNilAt = os.clock()
                end

                if prompt and (os.clock() - lastTry) >= 0.45 then
                    lastTry = os.clock()
                    tries += 1
                    local ok, how = tryTriggerPrompt(prompt)
                    local pd = distToPrompt(prompt)
                    logf("CHEST try#" .. tostring(tries) .. " ok=" .. tostring(ok) .. " via=" .. tostring(how) .. " " .. promptInfo(prompt) .. (pd and (" distToPrompt=" .. string.format("%.1f", pd)) or ""))
                end

                local newItems = diffNear(cpos, CFG.CHEST_CAPTURE_RADIUS, pre)
                if #newItems > 0 then
                    logf("CHEST diff items=" .. tostring(#newItems) .. " (r=" .. tostring(CFG.CHEST_CAPTURE_RADIUS) .. ")")
                    for i = 1, math.min(#newItems, 10) do
                        local it = newItems[i]
                        logf("  + " .. (it and it.Name or "?") .. " path=" .. safePath(it))
                    end
                    for _, it in ipairs(newItems) do
                        if it and it.Parent and not ST.CapturedSet[it] then
                            hoverCaptured(it)
                            capturedAny = true
                        end
                    end
                end

                if capturedAny then
                    opened = true
                    logf("CHEST opened_by_items tries=" .. tostring(tries))
                    break
                end

                if ST.TreatPromptGoneAsOpened and promptWentNilAt then
                    local dt = os.clock() - promptWentNilAt
                    if dt >= 0.35 then
                        opened = true
                        logf("CHEST opened_by_promptGone dt=" .. string.format("%.2f", dt) .. " tries=" .. tostring(tries))
                        break
                    end
                end

                task.wait(CFG.CHEST_SCAN_INTERVAL)
            end

            if opened then
                pcall(function() chest:SetAttribute(UID_OPEN_KEY, true) end)
                task.wait(CFG.CHEST_POST_OPEN_DELAY)
                logf("CHEST end OPENED marked=" .. UID_OPEN_KEY)
                return true
            end

            logf("CHEST end NOT_OPENED tries=" .. tostring(tries) .. " promptWasPresent=" .. tostring(promptWasPresent) .. " promptNow=" .. tostring(prompt ~= nil) .. " treatPromptGone=" .. tostring(ST.TreatPromptGoneAsOpened))
            return false
        end

        local function listChests()
            local folder = itemsFolder()
            if not folder then return {} end
            local out = {}
            for _, child in ipairs(folder:GetChildren()) do
                if isChest(child) then
                    table.insert(out, child)
                end
            end
            table.sort(out, function(a, b) return (a.Name or "") < (b.Name or "") end)
            return out
        end

        local function chestWorker(token)
            logf("WORKER start token=" .. tostring(token))
            while ST.AutoOpenChests and ST._chestToken == token do
                local chests = listChests()
                logf("WORKER scan chests=" .. tostring(#chests))
                local didAny = false
                for _, chest in ipairs(chests) do
                    if not ST.AutoOpenChests or ST._chestToken ~= token then break end
                    local ok = processChest(chest)
                    if ok then didAny = true end
                    task.wait(0.05)
                end
                if not ST.AutoOpenChests or ST._chestToken ~= token then break end
                task.wait(didAny and 0.20 or 0.60)
            end
            logf("WORKER stop token=" .. tostring(token))
        end

        local function addToggle(label, default, cb)
            if not tab then return end
            local ok
            if type(tab.Toggle) == "function" then
                ok = pcall(function() tab:Toggle(label, { Default = default, Callback = cb }) end)
                if ok then return end
            end
            if type(tab.AddToggle) == "function" then
                ok = pcall(function() tab:AddToggle(label, default, cb) end)
                if ok then return end
            end
            if type(tab.CreateToggle) == "function" then
                pcall(function() tab:CreateToggle(label, default, cb) end)
            end
        end

        local function addButton(label, cb)
            if not tab then return end
            local ok
            if type(tab.Button) == "function" then
                ok = pcall(function() tab:Button(label, cb) end)
                if ok then return end
            end
            if type(tab.AddButton) == "function" then
                ok = pcall(function() tab:AddButton(label, cb) end)
                if ok then return end
            end
            if type(tab.CreateButton) == "function" then
                pcall(function() tab:CreateButton(label, cb) end)
            end
        end

        addToggle("Auto Open Chests", ST.AutoOpenChests, function(v)
            ST.AutoOpenChests = (v == true)
            ST._chestToken = (ST._chestToken or 0) + 1
            logf("TOGGLE AutoOpenChests=" .. tostring(ST.AutoOpenChests) .. " token=" .. tostring(ST._chestToken))
            if ST.AutoOpenChests then
                local token = ST._chestToken
                task.spawn(function() chestWorker(token) end)
            end
        end)

        addToggle("Debug Log", ST.DebugLog, function(v)
            ST.DebugLog = (v == true)
            logf("TOGGLE DebugLog=" .. tostring(ST.DebugLog))
        end)

        addToggle("Treat Prompt Gone As Opened", ST.TreatPromptGoneAsOpened, function(v)
            ST.TreatPromptGoneAsOpened = (v == true)
            logf("TOGGLE TreatPromptGoneAsOpened=" .. tostring(ST.TreatPromptGoneAsOpened))
        end)

        addToggle("Scan Items Descendants", ST.ScanDescendantsForItems, function(v)
            ST.ScanDescendantsForItems = (v == true)
            logf("TOGGLE ScanDescendantsForItems=" .. tostring(ST.ScanDescendantsForItems))
        end)

        addButton("Drop Captured Items", function()
            dropCaptured()
        end)

        addButton("Log Nearby Prompt Info", function()
            local h = hrp()
            local chests = listChests()
            logf("NEARBY hrp=" .. string.format("(%.1f,%.1f,%.1f)", h.Position.X, h.Position.Y, h.Position.Z) .. " chests=" .. tostring(#chests))
            for i = 1, math.min(#chests, 8) do
                local chest = chests[i]
                local cpos = getPos(chest)
                local dist = (cpos and (h.Position - cpos).Magnitude) or -1
                local prompt = findProxPrompt(chest)
                local pd = distToPrompt(prompt)
                logf("  chest=" .. (chest.Name or "?") .. " dist=" .. string.format("%.1f", dist) .. " " .. promptInfo(prompt) .. (pd and (" distToPrompt=" .. string.format("%.1f", pd)) or ""))
            end
        end)

        logf("extra.lua loaded; logger ready")
    end

    local ok, err = pcall(run)
    if not ok then
        warn("[extra.lua] error: " .. tostring(err))
        local C2 = _G.C
        local lp2 = game:GetService("Players").LocalPlayer
        if lp2 and C2 and C2.State and C2.State.Extra and C2.State.Extra.Logger and C2.State.Extra.Logger.Append then
            C2.State.Extra.Logger.Append("[FATAL] " .. tostring(err))
        end
    end
end
