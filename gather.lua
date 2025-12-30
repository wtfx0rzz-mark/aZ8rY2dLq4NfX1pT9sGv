-- gather.lua
return function(C, R, UI)
    local function run()
        C  = C  or _G.C
        UI = UI or _G.UI

        local Services = (C and C.Services) or {}
        local Players  = Services.Players or game:GetService("Players")
        local RS       = Services.RS or game:GetService("ReplicatedStorage")
        local WS       = Services.WS or game:GetService("Workspace")
        local Run      = Services.Run or game:GetService("RunService")
        local UIS      = game:GetService("UserInputService")
        local Stats    = game:GetService("Stats")

        local lp = Players.LocalPlayer
        if not lp then return end

        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Gather or Tabs.Auto
        if not tab then
            warn("[Gather] Gather tab not found")
            return
        end

        if type(C.State) ~= "table" then C.State = {} end
        if type(C.State.Toggles) ~= "table" then C.State.Toggles = {} end
        if C.State.AuraRadius == nil then C.State.AuraRadius = 150 end
        if not tonumber(C.State.GatherRadius) then
            C.State.GatherRadius = tonumber(C.State.AuraRadius) or 150
        end

        if C.State.GatherLogEnabled == nil then C.State.GatherLogEnabled = true end
        if C.State.GatherLogTrace == nil then C.State.GatherLogTrace = false end
        if not tonumber(C.State.GatherLogMaxLines) then C.State.GatherLogMaxLines = 1400 end
        if not tonumber(C.State.GatherLogFlushHz) then C.State.GatherLogFlushHz = 10 end
        if not tonumber(C.State.GatherMetricsHz) then C.State.GatherMetricsHz = 1 end

        local function clamp(n, lo, hi)
            n = tonumber(n)
            if not n then return lo end
            if n < lo then return lo end
            if n > hi then return hi end
            return n
        end

        local function ensureGatherConsole()
            if _G._GatherConsole and _G._GatherConsole.Gui and _G._GatherConsole.Gui.Parent then
                return _G._GatherConsole
            end

            local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")

            local screenGui = Instance.new("ScreenGui")
            screenGui.Name = "GatherConsoleGui"
            screenGui.ResetOnSpawn = false
            screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            screenGui.Parent = playerGui

            local frame = Instance.new("Frame")
            frame.Name = "ConsoleFrame"
            frame.Parent = screenGui
            frame.Size = UDim2.new(0, 420, 0, 260)
            frame.Position = UDim2.new(1, -430, 0, 12)
            frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            frame.BorderSizePixel = 0
            frame.Active = true
            frame.Draggable = true

            local titleBar = Instance.new("Frame")
            titleBar.Name = "TitleBar"
            titleBar.Parent = frame
            titleBar.Size = UDim2.new(1, 0, 0, 26)
            titleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            titleBar.BorderSizePixel = 0

            local titleLabel = Instance.new("TextLabel")
            titleLabel.Name = "TitleLabel"
            titleLabel.Parent = titleBar
            titleLabel.Size = UDim2.new(1, -84, 1, 0)
            titleLabel.Position = UDim2.new(0, 8, 0, 0)
            titleLabel.BackgroundTransparency = 1
            titleLabel.Text = "Gather Console"
            titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            titleLabel.TextSize = 14
            titleLabel.Font = Enum.Font.SourceSansBold
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.TextWrapped = false

            local minimizeButton = Instance.new("TextButton")
            minimizeButton.Name = "Minimize"
            minimizeButton.Parent = titleBar
            minimizeButton.Size = UDim2.new(0, 26, 0, 26)
            minimizeButton.Position = UDim2.new(1, -52, 0, 0)
            minimizeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            minimizeButton.Text = "-"
            minimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            minimizeButton.TextSize = 14
            minimizeButton.Font = Enum.Font.SourceSansBold
            minimizeButton.BorderSizePixel = 0

            local closeButton = Instance.new("TextButton")
            closeButton.Name = "Close"
            closeButton.Parent = titleBar
            closeButton.Size = UDim2.new(0, 26, 0, 26)
            closeButton.Position = UDim2.new(1, -26, 0, 0)
            closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
            closeButton.Text = "X"
            closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            closeButton.TextSize = 14
            closeButton.Font = Enum.Font.SourceSansBold
            closeButton.BorderSizePixel = 0

            local consoleArea = Instance.new("ScrollingFrame")
            consoleArea.Name = "ConsoleArea"
            consoleArea.Parent = frame
            consoleArea.Size = UDim2.new(1, 0, 1, -52)
            consoleArea.Position = UDim2.new(0, 0, 0, 26)
            consoleArea.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            consoleArea.BorderSizePixel = 0
            consoleArea.ScrollBarThickness = 6
            consoleArea.CanvasSize = UDim2.new(0, 0, 0, 0)

            local consoleText = Instance.new("TextBox")
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
            consoleText.TextWrapped = false
            consoleText.ClearTextOnFocus = false
            consoleText.MultiLine = true
            consoleText.TextEditable = false

            local buttonBar = Instance.new("Frame")
            buttonBar.Name = "ButtonBar"
            buttonBar.Parent = frame
            buttonBar.Size = UDim2.new(1, 0, 0, 26)
            buttonBar.Position = UDim2.new(0, 0, 1, -26)
            buttonBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            buttonBar.BorderSizePixel = 0

            local copyButton = Instance.new("TextButton")
            copyButton.Name = "Copy"
            copyButton.Parent = buttonBar
            copyButton.Size = UDim2.new(0.5, 0, 1, 0)
            copyButton.Position = UDim2.new(0, 0, 0, 0)
            copyButton.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
            copyButton.Text = "Copy Text"
            copyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            copyButton.TextSize = 14
            copyButton.Font = Enum.Font.SourceSansBold
            copyButton.BorderSizePixel = 0

            local clearButton = Instance.new("TextButton")
            clearButton.Name = "Clear"
            clearButton.Parent = buttonBar
            clearButton.Size = UDim2.new(0.5, 0, 1, 0)
            clearButton.Position = UDim2.new(0.5, 0, 0, 0)
            clearButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
            clearButton.Text = "Clear"
            clearButton.TextColor3 = Color3.fromRGB(255, 255, 255)
            clearButton.TextSize = 14
            clearButton.Font = Enum.Font.SourceSansBold
            clearButton.BorderSizePixel = 0

            local resizeGrip = Instance.new("Frame")
            resizeGrip.Name = "ResizeGrip"
            resizeGrip.Parent = frame
            resizeGrip.Size = UDim2.new(0, 16, 0, 16)
            resizeGrip.Position = UDim2.new(1, -16, 1, -16)
            resizeGrip.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
            resizeGrip.BorderSizePixel = 0

            local gripCorner = Instance.new("UICorner")
            gripCorner.CornerRadius = UDim.new(0, 4)
            gripCorner.Parent = resizeGrip

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 10)
            corner.Parent = frame

            local st = {
                Gui = screenGui,
                Frame = frame,
                Title = titleLabel,
                Area = consoleArea,
                Text = consoleText,
                Copy = copyButton,
                Clear = clearButton,
                Min = minimizeButton,
                Close = closeButton,
                Grip = resizeGrip,
                Lines = {},
                Queue = {},
                Enabled = true,
                Trace = false,
                MaxLines = 1400,
                FlushHz = 10,
                LastFlush = 0,
                MinSize = Vector2.new(280, 140),
                MaxSize = Vector2.new(920, 680),
                Minimized = false
            }

            local function setTextFromLines()
                st.Text.Text = table.concat(st.Lines, "\n")
                st.Text.Size = UDim2.new(1, -10, 0, st.Text.TextBounds.Y + 8)
                st.Area.CanvasSize = UDim2.new(0, 0, 0, st.Text.TextBounds.Y + 16)
                st.Area.CanvasPosition = Vector2.new(0, math.max(0, st.Text.TextBounds.Y))
            end

            local resizing = false
            local resizeStartPos, resizeStartSize

            resizeGrip.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    resizing = true
                    resizeStartPos = input.Position
                    resizeStartSize = Vector2.new(st.Frame.AbsoluteSize.X, st.Frame.AbsoluteSize.Y)
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then
                            resizing = false
                        end
                    end)
                end
            end)

            UIS.InputChanged:Connect(function(input)
                if not resizing then return end
                if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
                local delta = input.Position - resizeStartPos
                local newW = clamp(resizeStartSize.X + delta.X, st.MinSize.X, st.MaxSize.X)
                local newH = clamp(resizeStartSize.Y + delta.Y, st.MinSize.Y, st.MaxSize.Y)
                st.Frame.Size = UDim2.new(0, newW, 0, newH)
            end)

            st.Copy.MouseButton1Click:Connect(function()
                local txt = st.Text.Text or ""
                if setclipboard then
                    pcall(function() setclipboard(txt) end)
                end
            end)

            st.Clear.MouseButton1Click:Connect(function()
                table.clear(st.Lines)
                st.Text.Text = ""
                st.Area.CanvasSize = UDim2.new(0, 0, 0, 0)
            end)

            st.Close.MouseButton1Click:Connect(function()
                if st.Gui then st.Gui:Destroy() end
                _G._GatherConsole = nil
            end)

            st.Min.MouseButton1Click:Connect(function()
                st.Minimized = not st.Minimized
                if st.Minimized then
                    st.Area.Visible = false
                    buttonBar.Visible = false
                    resizeGrip.Visible = false
                    st.Frame.Size = UDim2.new(0, st.Frame.AbsoluteSize.X, 0, 26)
                    st.Min.Text = "+"
                else
                    st.Area.Visible = true
                    buttonBar.Visible = true
                    resizeGrip.Visible = true
                    st.Frame.Size = UDim2.new(0, math.max(st.MinSize.X, st.Frame.AbsoluteSize.X), 0, 260)
                    st.Min.Text = "-"
                    setTextFromLines()
                end
            end)

            st.log = function(_, level, msg)
                if not st.Enabled then return end
                local ts = os.date("%H:%M:%S")
                st.Queue[#st.Queue + 1] = ("[%s] [%s] %s"):format(ts, tostring(level or "INFO"), tostring(msg or ""))
            end

            st.flush = function(_)
                if #st.Queue == 0 then return end
                local q = st.Queue
                st.Queue = {}
                local maxLines = clamp(C.State.GatherLogMaxLines, 200, 10000)
                st.MaxLines = maxLines
                for i = 1, #q do
                    st.Lines[#st.Lines + 1] = q[i]
                end
                if #st.Lines > st.MaxLines then
                    local drop = #st.Lines - st.MaxLines
                    for _ = 1, drop do
                        table.remove(st.Lines, 1)
                    end
                end
                if not st.Minimized then
                    setTextFromLines()
                end
            end

            st.setEnabled = function(_, on)
                st.Enabled = on and true or false
            end

            st.setTrace = function(_, on)
                st.Trace = on and true or false
            end

            st.bumpTitle = function(_, suffix)
                st.Title.Text = "Gather Console" .. (suffix and ("  " .. tostring(suffix)) or "")
            end

            local flushDt = 1 / clamp(C.State.GatherLogFlushHz, 1, 60)
            Run.Heartbeat:Connect(function()
                if not _G._GatherConsole or _G._GatherConsole ~= st then return end
                local now = os.clock()
                if (now - st.LastFlush) >= flushDt then
                    st.LastFlush = now
                    st:flush()
                end
            end)

            _G._GatherConsole = st
            st:log("INFO", "Console initialized")
            st:flush()
            return st
        end

        local Console = ensureGatherConsole()
        Console:setEnabled(C.State.GatherLogEnabled)
        Console:setTrace(C.State.GatherLogTrace)
        Console:bumpTitle()

        local function logI(msg) Console:log("INFO", msg) end
        local function logW(msg) Console:log("WARN", msg) end
        local function logE(msg) Console:log("ERR",  msg) end
        local function logT(msg) if Console.Trace then Console:log("TRACE", msg) end end

        local junkItems = {
            "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
            "UFO Junk","UFO Component"
        }
        local fuelItems = { "Log","Coal","Fuel Canister","Oil Barrel","Chair","Biofuel" }
        local foodItems = {
            "Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot",
            "Chilli","Stew","Ribs","Pumpkin","Hearty Stew","Cooked Ribs","Corn","BBQ ribs","Apple","Mackerel"
        }
        local medicalItems = {"Bandage","MedKit"}
        local weaponsArmor = {
            "Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Hammer",
            "Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot Shield","Spear","Tactical Shotgun","Wildfire",
            "Sword","Ice Axe","Thorn Body"
        }
        local ammoMisc = {
            "Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling",
            "Basketball","Blueprint","Diamond","Gem of the Forest Fragment","Flashlight","Old Taming flute","Cultist Gem","Tusk","Infernal Sack"
        }
        local pelts = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Scorpion Shell","Polar Bear Pelt","Arctic Fox Pelt"}

        local Selected = { Junk = {}, Fuel = {}, Food = {}, Medical = {}, WA = {}, Misc = {}, Pelts = {} }
        local wantMossy, wantCultist, wantSapling = false, false, false
        local wantBlueprint, wantForestGem, wantKey, wantFlashlight, wantTamingFlute = false, false, false, false, false

        local hoverHeight  = 5
        local forwardDrop  = 5
        local upDrop       = 5
        local scanInterval = 0.1

        local DROP_ABOVE_HEAD_STUDS = 10

        local UNANCHOR_BATCH = 10
        local UNANCHOR_STEP  = 0.04
        local NUDGE_DOWN     = 4
        local CULTIST_LIMIT  = math.huge

        local PLACE_BATCH    = 10
        local PLACE_YIELD_FN = function() Run.Heartbeat:Wait() end

        local CLUSTER_RADIUS_MIN  = 0.75
        local CLUSTER_RADIUS_STEP = 0.05
        local CLUSTER_RADIUS_MAX  = 2.35
        local AIR_DROP_WAVE_AMPLITUDE = 0.8
        local AIR_DROP_WAVE_FREQUENCY = 1.35

        local PLACE_USE_DELAY          = false
        local PLACE_INITIAL_DELAY_SEC  = 0.00
        local PLACE_PER_ITEM_DELAY_SEC = 0.00

        local PLACE_USE_NUDGE_DOWN     = false
        local PLACE_NUDGE_DOWN_STUDS   = 16

        local function waitIf(v)
            v = tonumber(v)
            if v and v > 0 then task.wait(v) end
        end

        local function getRemote(...)
            local f = RS:FindFirstChild("RemoteEvents")
            if not f then
                logW("RemoteEvents folder not found under ReplicatedStorage")
                return nil
            end
            for i = 1, select("#", ...) do
                local n = select(i, ...)
                local x = f:FindFirstChild(n)
                if x then
                    logI("Remote found: " .. tostring(n))
                    return x
                end
            end
            logW("Remote not found (tried): " .. table.concat({ ... }, ", "))
            return nil
        end

        local RF_Start  = getRemote("RequestStartDraggingItem","StartDraggingItem")
        local RF_Stop   = getRemote("RequestStopDraggingItem","StopDraggingItem","StopDraggingItemRemote")

        local DragActive = {}
        local DRAG_TTL   = 3.0

        local function itemsRootOrNil()
            return WS:FindFirstChild("Items")
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

        local function hrp()
            local ch = lp.Character or lp.CharacterAdded:Wait()
            return ch and ch:FindFirstChild("HumanoidRootPart")
        end

        local function gatherRadius()
            return math.clamp(tonumber(C.State and C.State.GatherRadius) or 150, 0, 500)
        end

        local function isWallVariant(m)
            if not (m and m:IsA("Model")) then return false end
            local n = (m.Name or ""):lower()
            return n == "logwall" or n == "log wall" or (n:find("log", 1, true) and n:find("wall", 1, true))
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

        local function isInsideTree(m)
            local itemsFolder = itemsRootOrNil()
            local cur = m and m.Parent
            while cur and cur ~= WS do
                local nm = (cur.Name or ""):lower()
                if nm:find("tree",1,true) then return true end
                if itemsFolder and cur == itemsFolder then break end
                cur = cur.Parent
            end
            return false
        end

        local function isCultist(m)
            if not (m and m:IsA("Model")) then return false end
            local nl = (m.Name or ""):lower()
            return nl:find("cultist",1,true) and hasHumanoid(m)
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

        local function setNoCollideModel(m, on)
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.CanCollide = not on
                    d.CanQuery   = not on
                    d.CanTouch   = not on
                    d.Massless   = on and true or false
                    d.AssemblyLinearVelocity  = Vector3.new()
                    d.AssemblyAngularVelocity = Vector3.new()
                end
            end
        end

        local function setAnchoredModel(m, on)
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then d.Anchored = on end
            end
        end

        local function dragSafeStop(m)
            if not (m and RF_Stop) then return end
            local ok, e = pcall(function() RF_Stop:FireServer(m) end)
            if not ok then
                logW("dragSafeStop failed for " .. tostring(m.Name) .. " :: " .. tostring(e))
            end
        end

        local function dragTrackRelease(m)
            local rec = DragActive[m]
            if not rec then return end
            DragActive[m] = nil
            for _,c in ipairs(rec.conns) do pcall(function() c:Disconnect() end) end
            dragSafeStop(m)
            logT("Drag released: " .. tostring(m.Name))
        end

        local function dragStart(m)
            if not (m and m.Parent and RF_Start) then
                logT("dragStart skipped (missing m/parent/remote)")
                return false
            end
            if DragActive[m] then
                DragActive[m].t0 = os.clock()
                return true
            end
            local ok, e = pcall(function() RF_Start:FireServer(m) end)
            if not ok then
                logW("dragStart FireServer failed for " .. tostring(m.Name) .. " :: " .. tostring(e))
                return false
            end
            local conns = {}
            conns[#conns+1] = m.AncestryChanged:Connect(function(_, parent)
                if not parent then dragTrackRelease(m) end
            end)
            conns[#conns+1] = m:GetPropertyChangedSignal("Parent"):Connect(function()
                if not m.Parent then dragTrackRelease(m) end
            end)
            DragActive[m] = { t0 = os.clock(), conns = conns }
            logT("Drag started: " .. tostring(m.Name))
            return true
        end

        local function dragStop(m)
            dragTrackRelease(m)
        end

        Run.Heartbeat:Connect(function()
            local now = os.clock()
            for m, rec in pairs(DragActive) do
                if (not m) or (not m.Parent) or (now - rec.t0) > DRAG_TTL then
                    dragTrackRelease(m)
                end
            end
        end)

        local function buildSelectedSet()
            local set = {}
            for name,_ in pairs(Selected.Junk or {})    do set[name] = true end
            for name,_ in pairs(Selected.Fuel or {})    do set[name] = true end
            for name,_ in pairs(Selected.Food or {})    do set[name] = true end
            for name,_ in pairs(Selected.Medical or {}) do set[name] = true end
            for name,_ in pairs(Selected.WA or {})      do set[name] = true end
            for name,_ in pairs(Selected.Misc or {})    do set[name] = true end
            for name,_ in pairs(Selected.Pelts or {})   do set[name] = true end
            if wantMossy       then set["Mossy Coin"]   = true end
            if wantCultist     then set["Cultist"]      = true end
            if wantSapling     then set["Sapling"]      = true end
            if wantBlueprint   then set["Blueprint"]    = true end
            if wantForestGem   then set["Forest Gem"]   = true end
            if wantKey         then set["Key"]          = true end
            if wantFlashlight  then set["Flashlight"]   = true end
            if wantTamingFlute then set["Taming flute"] = true end
            return set
        end

        local function nameMatches(selectedSet, m)
            local itemsFolder = itemsRootOrNil()
            if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
            local nm = m and m.Name or ""
            local l  = nm:lower()
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
            if selectedSet["Cultist"] and m:IsA("Model") and l:find("cultist",1,true) and hasHumanoid(m) then return true end
            if selectedSet["Sapling"] and nm == "Sapling" then return true end
            if selectedSet["Alpha Wolf Pelt"] and l:find("alpha",1,true) and l:find("wolf",1,true) then return true end
            if selectedSet["Bear Pelt"] and l:find("bear",1,true) and not l:find("polar",1,true) then return true end
            if selectedSet["Wolf Pelt"] and nm == "Wolf Pelt" then return true end
            if selectedSet["Bunny Foot"] and nm == "Bunny Foot" then return true end
            if selectedSet["Polar Bear Pelt"] and nm == "Polar Bear Pelt" then return true end
            if selectedSet["Arctic Fox Pelt"] and nm == "Arctic Fox Pelt" then return true end
            if selectedSet["Spear"] and l:find("spear",1,true) and not hasHumanoid(m) then return true end
            if selectedSet["Sword"] and l:find("sword",1,true) and not hasHumanoid(m) then return true end
            if selectedSet["Crossbow"] and l:find("crossbow",1,true) and not l:find("cultist",1,true) and not hasHumanoid(m) then return true end
            if selectedSet["Blueprint"] and l:find("blueprint",1,true) then return true end
            if selectedSet["Flashlight"] and l:find("flashlight",1,true) and not hasHumanoid(m) then return true end
            if selectedSet["Cultist Gem"] and l:find("cultist",1,true) and l:find("gem",1,true) then return true end
            if selectedSet["Forest Gem"] and (l:find("forest gem",1,true) or (l:find("forest",1,true) and l:find("fragment",1,true))) then return true end
            if selectedSet["Tusk"] and l:find("tusk",1,true) then return true end
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

        local function canGather(m, selectedSet, origin, rad)
            if not (m and m.Parent and m:IsA("Model")) then return false end
            local itemsFolder = itemsRootOrNil()
            if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
            if isExcludedModel(m) or isUnderLogWall(m) then return false end
            if m.Name == "Log" and isWallVariant(m) then return false end
            local mp = mainPart(m)
            if not mp or mp.Anchored then return false end
            if origin and rad then
                if (mp.Position - origin).Magnitude > rad then return false end
            end
            if not nameMatches(selectedSet, m) then return false end
            return true
        end

        local gatherOn = false
        local scanConn, hoverConn = nil, nil
        local gathered, list = {}, {}
        local cultistCount = 0
        local itemsChildConn = nil

        local function addGather(m)
            if gathered[m] then return end
            gathered[m] = true
            list[#list+1] = m
            if isCultist(m) then cultistCount = cultistCount + 1 end
            logI(("Gathered: %s  (list=%d dragActive=%d cultists=%d)"):format(tostring(m.Name), #list, (function()
                local n = 0
                for _ in pairs(DragActive) do n += 1 end
                return n
            end)(), cultistCount))
        end

        local function removeGather(m)
            if not gathered[m] then return end
            if isCultist(m) then cultistCount = math.max(0, cultistCount - 1) end
            gathered[m] = nil
            for i = #list, 1, -1 do
                if list[i] == m then
                    table.remove(list, i)
                    break
                end
            end
            logT("Removed from list: " .. tostring(m and m.Name))
        end

        local function clearAll()
            for m,_ in pairs(gathered) do gathered[m] = nil end
            table.clear(list)
            cultistCount = 0
            logI("Cleared gathered list")
        end

        local function releaseAll()
            logI(("ReleaseAll begin (list=%d)"):format(#list))
            for _,m in ipairs(list) do
                if m and m.Parent then
                    dragStop(m)
                    setNoCollideModel(m, false)
                    setAnchoredModel(m, false)
                    local mp = mainPart(m)
                    if mp then
                        pcall(function() mp:SetNetworkOwner(nil) end)
                        pcall(function() if mp.SetNetworkOwnershipAuto then mp:SetNetworkOwnershipAuto() end end)
                    end
                end
            end
            logI("ReleaseAll end")
        end

        local function anySelection()
            if wantMossy or wantCultist or wantSapling or wantBlueprint or wantForestGem or wantKey or wantFlashlight or wantTamingFlute then
                return true
            end
            for _,set in pairs(Selected) do
                for _ in pairs(set) do return true end
            end
            return false
        end

        local lastScan   = 0
        local START_YIELD = 0.06

        local overlapParams = OverlapParams.new()
        overlapParams.MaxParts = 1000

        local function refreshOverlapFilter()
            local items = itemsRootOrNil()
            if items then
                overlapParams.FilterType = Enum.RaycastFilterType.Include
                overlapParams.FilterDescendantsInstances = { items }
            else
                overlapParams.FilterType = Enum.RaycastFilterType.Exclude
                overlapParams.FilterDescendantsInstances = { lp.Character }
            end
        end

        refreshOverlapFilter()

        local function pivotModel(m, cf)
            if m:IsA("Model") then
                m:PivotTo(cf)
            else
                local p = mainPart(m)
                if p then p.CFrame = cf end
            end
        end

        local scanCounter = 0
        local captureCounter = 0
        local function captureIfNear_FullScan(origin, rad, selectedSet)
            local pool = itemsRootOrNil() or WS
            local got = 0
            local desc = pool:GetDescendants()
            logW(("FullScan fallback: pool=%s desc=%d rad=%.1f"):format(pool.Name, #desc, rad))
            for _,d in ipairs(desc) do
                repeat
                    if not (d:IsA("Model") or d:IsA("BasePart")) then break end
                    local m
                    if d:IsA("Model") then
                        if not nameMatches(selectedSet, d) then break end
                        m = d
                    else
                        m = nearestSelectedModelFromPart(d, selectedSet)
                        if not m then break end
                    end
                    if gathered[m] then break end
                    if isCultist(m) and cultistCount >= CULTIST_LIMIT then break end
                    if not canGather(m, selectedSet, origin, rad) then break end
                    local mp = mainPart(m); if not mp then break end
                    if not dragStart(m) then break end
                    task.wait(START_YIELD)
                    pcall(function() mp:SetNetworkOwner(lp) end)
                    setNoCollideModel(m, true)
                    setAnchoredModel(m, true)
                    addGather(m)
                    dragStop(m)
                    got += 1
                    captureCounter += 1
                until true
            end
            logW(("FullScan captured=%d (list=%d)"):format(got, #list))
        end

        local lastPartsCountLog = 0
        local function captureIfNear()
            local now = os.clock()
            if now - lastScan < scanInterval then return end
            lastScan = now
            if not gatherOn then return end
            if not anySelection() then return end
            local root = hrp(); if not root then return end
            local origin = root.Position
            local rad = gatherRadius()
            local selectedSet = buildSelectedSet()
            refreshOverlapFilter()

            scanCounter += 1

            local ok, parts = pcall(function()
                return WS:GetPartBoundsInRadius(origin, rad, overlapParams)
            end)

            if not ok or type(parts) ~= "table" then
                logW("GetPartBoundsInRadius failed -> FullScan fallback")
                captureIfNear_FullScan(origin, rad, selectedSet)
                return
            end

            if (now - lastPartsCountLog) > 1 then
                lastPartsCountLog = now
                logI(("Scan #%d parts=%d rad=%.1f list=%d selected=%s"):format(
                    scanCounter, #parts, rad, #list, anySelection() and "yes" or "no"
                ))
            end

            for _,p in ipairs(parts) do
                repeat
                    if not p or not p.Parent or not p:IsA("BasePart") then break end
                    local m = nearestSelectedModelFromPart(p, selectedSet)
                    if not m then
                        logT("Part hit no selected model: " .. tostring(p.Name))
                        break
                    end
                    if gathered[m] then break end
                    if isCultist(m) and cultistCount >= CULTIST_LIMIT then break end
                    if not canGather(m, selectedSet, origin, rad) then break end
                    local mp = mainPart(m); if not mp then break end
                    if not dragStart(m) then break end
                    task.wait(START_YIELD)
                    pcall(function() mp:SetNetworkOwner(lp) end)
                    setNoCollideModel(m, true)
                    setAnchoredModel(m, true)
                    addGather(m)
                    dragStop(m)
                    captureCounter += 1
                until true
            end
        end

        local function onItemsChildAdded(child)
            if not gatherOn then return end
            if not child or not child:IsA("Model") then return end
            local items = itemsRootOrNil()
            if not items or not child:IsDescendantOf(items) then return end
            if not anySelection() then return end
            local root = hrp(); if not root then return end
            local origin = root.Position
            local rad = gatherRadius()
            local selectedSet = buildSelectedSet()
            if gathered[child] then return end
            if isCultist(child) and cultistCount >= CULTIST_LIMIT then return end
            if not canGather(child, selectedSet, origin, rad) then return end
            local mp = mainPart(child); if not mp then return end
            if not dragStart(child) then return end

            logT("ChildAdded capture scheduled: " .. tostring(child.Name))

            task.delay(START_YIELD, function()
                if not gatherOn then dragStop(child); return end
                if not child or not child.Parent then dragStop(child); return end
                local mp2 = mainPart(child); if not mp2 then dragStop(child); return end
                pcall(function() mp2:SetNetworkOwner(lp) end)
                setNoCollideModel(child, true)
                setAnchoredModel(child, true)
                addGather(child)
                dragStop(child)
                captureCounter += 1
            end)
        end

        local lastHoverLog = 0
        local function hoverFollow()
            if not gatherOn then return end
            local root = hrp(); if not root then return end
            local forward = root.CFrame.LookVector
            local above   = root.Position + Vector3.new(0, hoverHeight, 0)
            local baseCF  = CFrame.lookAt(above, above + forward)

            local now = os.clock()
            if (now - lastHoverLog) > 2 then
                lastHoverLog = now
                logI(("Hover tick list=%d dragActive=%d captured=%d"):format(#list, (function()
                    local n = 0
                    for _ in pairs(DragActive) do n += 1 end
                    return n
                end)(), captureCounter))
            end

            for _,m in ipairs(list) do
                if m and m.Parent then
                    pivotModel(m, baseCF)
                else
                    removeGather(m)
                end
            end
        end

        local function startGather()
            if gatherOn then return end
            if not anySelection() then
                logW("startGather blocked: no selection")
                return
            end
            gatherOn = true
            scanConn  = Run.Heartbeat:Connect(captureIfNear)
            hoverConn = Run.RenderStepped:Connect(hoverFollow)
            local items = itemsRootOrNil()
            if items then
                if itemsChildConn then pcall(function() itemsChildConn:Disconnect() end) end
                itemsChildConn = items.ChildAdded:Connect(onItemsChildAdded)
                logI("Items.ChildAdded connected")
            else
                logW("Items folder not found (no ChildAdded hook)")
            end
            if _G._PlaceEdgeBtn then _G._PlaceEdgeBtn.Visible = true end
            logI("Gather ON")
        end

        local function stopGather()
            if not gatherOn then return end
            gatherOn = false
            if scanConn  then pcall(function() scanConn:Disconnect()  end) end; scanConn = nil
            if hoverConn then pcall(function() hoverConn:Disconnect() end) end; hoverConn = nil
            if itemsChildConn then pcall(function() itemsChildConn:Disconnect() end) end; itemsChildConn = nil
            logI("Gather OFF")
        end

        local dropCounter = 0
        local function ringOffset()
            dropCounter += 1
            local i = dropCounter
            local a = i * 2.399963229728653
            local r = math.min(CLUSTER_RADIUS_MIN + CLUSTER_RADIUS_STEP * (i - 1), CLUSTER_RADIUS_MAX)
            return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
        end

        local function baseDropAnchorSnapshot()
            local root = hrp(); if not root then return nil end
            local forward = root.CFrame.LookVector
            local basePos = root.Position + Vector3.new(0, DROP_ABOVE_HEAD_STUDS, 0) + forward * forwardDrop
            return forward, basePos
        end

        local function sprinkleCF(baseForward, basePos)
            local off = ringOffset()
            local jitterX = (math.random() - 0.5) * 0.14
            local jitterZ = (math.random() - 0.5) * 0.14
            local waveY = math.sin(dropCounter * AIR_DROP_WAVE_FREQUENCY) * AIR_DROP_WAVE_AMPLITUDE
            local dropPos = basePos + Vector3.new(off.X + jitterX, upDrop + waveY, off.Z + jitterZ)
            return CFrame.lookAt(dropPos, dropPos + baseForward)
        end

        local function dropOneItem(m, baseForward, basePos)
            if not (m and m.Parent) then return end
            local mp = mainPart(m)
            if not mp then return end

            pcall(function() mp:SetNetworkOwner(lp) end)
            setNoCollideModel(m, true)
            setAnchoredModel(m, true)

            local cf = sprinkleCF(baseForward, basePos)
            pivotModel(m, cf)

            waitIf(PLACE_PER_ITEM_DELAY_SEC)

            setAnchoredModel(m, false)
            setNoCollideModel(m, false)

            if PLACE_USE_NUDGE_DOWN then
                for _,p in ipairs(m:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.AssemblyLinearVelocity  = Vector3.new(0, -PLACE_NUDGE_DOWN_STUDS, 0)
                        p.AssemblyAngularVelocity = Vector3.new()
                    end
                end
            end

            pcall(function() mp:SetNetworkOwner(nil) end)
            pcall(function() if mp.SetNetworkOwnershipAuto then mp:SetNetworkOwnershipAuto() end end)

            dragSafeStop(m)
        end

        local function placeDown()
            local baseForward, basePos = baseDropAnchorSnapshot()
            if not baseForward then return end

            if _G._PlaceEdgeBtn then _G._PlaceEdgeBtn.Visible = false end
            stopGather()

            local n = #list
            logI(("PlaceDown begin list=%d"):format(n))
            if n == 0 then return end

            local items = table.create(n)
            for i = 1, n do items[i] = list[i] end

            dropCounter = 0

            if PLACE_USE_DELAY then
                logT(("Place initial delay %.3fs"):format(tonumber(PLACE_INITIAL_DELAY_SEC) or 0))
                waitIf(PLACE_INITIAL_DELAY_SEC)
            end

            local placed = 0
            for i = 1, #items do
                local m = items[i]
                if m and m.Parent then
                    pcall(function() dragStart(m) end)
                    dropOneItem(m, baseForward, basePos)
                    placed += 1
                    if placed % PLACE_BATCH == 0 then
                        PLACE_YIELD_FN()
                        logT(("Place progress placed=%d/%d"):format(placed, #items))
                    end
                else
                    logT("Place skipped missing item at i=" .. tostring(i))
                end
            end

            clearAll()
            logI(("PlaceDown end placed=%d"):format(placed))
        end

        C.Gather = C.Gather or {}
        C.Gather.IsOn      = function() return gatherOn end
        C.Gather.PlaceDown = placeDown

        local lastMetrics = 0
        Run.Heartbeat:Connect(function()
            if not C.State.GatherLogEnabled then return end
            local hz = clamp(C.State.GatherMetricsHz, 0.1, 10)
            local now = os.clock()
            if (now - lastMetrics) < (1 / hz) then return end
            lastMetrics = now

            local luaKb = 0
            pcall(function() luaKb = collectgarbage("count") end)

            local itemsCount = 0
            local items = itemsRootOrNil()
            if items then
                local ok, desc = pcall(function() return items:GetDescendants() end)
                if ok and type(desc) == "table" then itemsCount = #desc end
            end

            local dragN = 0
            for _ in pairs(DragActive) do dragN += 1 end

            local statsMem = nil
            pcall(function()
                if Stats and Stats.GetTotalMemoryUsageMb then
                    statsMem = Stats:GetTotalMemoryUsageMb()
                end
            end)

            local s = ("METRICS luaKB=%.0f itemsDesc=%d list=%d gathered=%d dragActive=%d scans=%d captured=%d rad=%.1f"):format(
                luaKb,
                itemsCount,
                #list,
                (function()
                    local n = 0
                    for _ in pairs(gathered) do n += 1 end
                    return n
                end)(),
                dragN,
                scanCounter,
                captureCounter,
                gatherRadius()
            )
            if statsMem then
                s = s .. (" totalMemMB=%.1f"):format(statsMem)
            end
            Console:log("STAT", s)
        end)

        tab:Section({ Title = "Gather Settings", Icon = "sliders" })

        tab:Toggle({
            Title = "Console Logging",
            Default = C.State.GatherLogEnabled and true or false,
            Callback = function(v)
                local on = v
                if type(v) == "table" then on = v.Value end
                C.State.GatherLogEnabled = on and true or false
                Console:setEnabled(C.State.GatherLogEnabled)
                logI("Logging " .. (C.State.GatherLogEnabled and "ENABLED" or "DISABLED"))
            end
        })

        tab:Toggle({
            Title = "Trace (Very Verbose)",
            Default = C.State.GatherLogTrace and true or false,
            Callback = function(v)
                local on = v
                if type(v) == "table" then on = v.Value end
                C.State.GatherLogTrace = on and true or false
                Console:setTrace(C.State.GatherLogTrace)
                logI("Trace " .. (C.State.GatherLogTrace and "ON" or "OFF"))
            end
        })

        tab:Slider({
            Title = "Console Max Lines",
            Min = 200,
            Max = 10000,
            Default = clamp(C.State.GatherLogMaxLines, 200, 10000),
            Value = { Min = 200, Max = 10000, Default = clamp(C.State.GatherLogMaxLines, 200, 10000) },
            Callback = function(v)
                local nv = v
                if type(v) == "table" then
                    nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
                end
                nv = tonumber(nv)
                if nv then
                    C.State.GatherLogMaxLines = clamp(nv, 200, 10000)
                    logI("Console Max Lines set to " .. tostring(C.State.GatherLogMaxLines))
                end
            end
        })

        tab:Slider({
            Title = "Metrics Hz",
            Min = 0.1,
            Max = 10,
            Default = clamp(C.State.GatherMetricsHz, 0.1, 10),
            Value = { Min = 0.1, Max = 10, Default = clamp(C.State.GatherMetricsHz, 0.1, 10) },
            Callback = function(v)
                local nv = v
                if type(v) == "table" then
                    nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
                end
                nv = tonumber(nv)
                if nv then
                    C.State.GatherMetricsHz = clamp(nv, 0.1, 10)
                    logI("Metrics Hz set to " .. tostring(C.State.GatherMetricsHz))
                end
            end
        })

        tab:Slider({
            Title = "Distance",
            Min = 0,
            Max = 500,
            Default = gatherRadius(),
            Value = { Min = 0, Max = 500, Default = gatherRadius() },
            Callback = function(v)
                local nv = v
                if type(v) == "table" then
                    nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
                end
                nv = tonumber(nv)
                if nv then
                    C.State.GatherRadius = math.clamp(nv, 0, 500)
                    logI("GatherRadius set to " .. tostring(C.State.GatherRadius))
                end
            end
        })

        tab:Button({
            Title = "Gather Items",
            Callback = function()
                if anySelection() then
                    clearAll()
                    startGather()
                else
                    logW("Gather Items clicked but no selection")
                end
            end
        })

        tab:Button({
            Title = "Stop Gather",
            Callback = function()
                stopGather()
            end
        })

        tab:Button({ Title = "Drop Items", Callback = function() placeDown() end })

        tab:Button({
            Title = "Show Console",
            Callback = function()
                if _G._GatherConsole and _G._GatherConsole.Gui then
                    _G._GatherConsole.Gui.Enabled = true
                    logI("Console shown")
                end
            end
        })

        tab:Button({
            Title = "Hide Console",
            Callback = function()
                if _G._GatherConsole and _G._GatherConsole.Gui then
                    _G._GatherConsole.Gui.Enabled = false
                    logI("Console hidden")
                end
            end
        })

        local function dropdownMulti(args)
            return tab:Dropdown({
                Title = args.title,
                Values = args.values,
                Multi = true,
                AllowNone = true,
                Callback = function(options)
                    local set = args.set
                    for k,_ in pairs(set) do set[k] = nil end
                    if args.kind == "Misc" then
                        wantMossy, wantCultist, wantSapling = false, false, false
                        wantBlueprint, wantForestGem, wantKey, wantFlashlight, wantTamingFlute = false, false, false, false, false
                        for _,vv in ipairs(options) do
                            if vv == "Mossy Coin" then
                                wantMossy = true
                            elseif vv == "Cultist" then
                                wantCultist = true
                            elseif vv == "Sapling" then
                                wantSapling = true
                            elseif vv == "Blueprint" then
                                wantBlueprint = true
                            elseif vv == "Forest Gem" then
                                wantForestGem = true
                            elseif vv == "Key" then
                                wantKey = true
                            elseif vv == "Flashlight" then
                                wantFlashlight = true
                            elseif vv == "Taming flute" then
                                wantTamingFlute = true
                            else
                                set[vv] = true
                            end
                        end
                    else
                        for _,vv in ipairs(options) do set[vv] = true end
                    end
                    logI(("Selection updated: %s"):format(tostring(args.kind)))
                end
            })
        end

        tab:Section({ Title = "Junk" })
        dropdownMulti({ title="Select Junk Items", values=junkItems, set=Selected.Junk, kind="Junk" })

        tab:Section({ Title = "Fuel" })
        dropdownMulti({ title="Select Fuel Items", values=fuelItems, set=Selected.Fuel, kind="Fuel" })

        tab:Section({ Title = "Food" })
        dropdownMulti({ title="Select Food Items", values=foodItems, set=Selected.Food, kind="Food" })

        tab:Section({ Title = "Medical" })
        dropdownMulti({ title="Select Medical Items", values=medicalItems, set=Selected.Medical, kind="Medical" })

        tab:Section({ Title = "Weapons & Armor" })
        dropdownMulti({ title="Select Weapon/Armor", values=weaponsArmor, set=Selected.WA, kind="WA" })

        tab:Section({ Title = "Ammo & Misc." })
        dropdownMulti({ title="Select Ammo/Misc", values=ammoMisc, set=Selected.Misc, kind="Misc" })

        tab:Section({ Title = "Pelts" })
        dropdownMulti({ title="Select Pelts", values=pelts, set=Selected.Pelts, kind="Pelts" })

        local function ensurePlaceEdge()
            local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
            local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
            if not edgeGui then
                edgeGui = Instance.new("ScreenGui")
                edgeGui.Name = "EdgeButtons"
                edgeGui.ResetOnSpawn = false
                edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
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

                local listLay = Instance.new("UIListLayout")
                listLay.Name = "VList"
                listLay.FillDirection = Enum.FillDirection.Vertical
                listLay.SortOrder = Enum.SortOrder.LayoutOrder
                listLay.Padding = UDim.new(0, 6)
                listLay.HorizontalAlignment = Enum.HorizontalAlignment.Right
                listLay.Parent = stack
            end

            local btn = stack:FindFirstChild("PlaceEdge")
            if not btn then
                btn = Instance.new("TextButton")
                btn.Name = "PlaceEdge"
                btn.Size = UDim2.new(1, 0, 0, 30)
                btn.Text = "Place"
                btn.TextSize = 12
                btn.Font = Enum.Font.GothamBold
                btn.BackgroundColor3 = Color3.fromRGB(30,30,35)
                btn.TextColor3  = Color3.new(1,1,1)
                btn.BorderSizePixel = 0
                btn.Visible     = false
                btn.LayoutOrder = 1000
                btn.Parent      = stack

                local corner2  = Instance.new("UICorner")
                corner2.CornerRadius = UDim.new(0, 8)
                corner2.Parent = btn
            end

            return btn
        end

        _G._PlaceEdgeBtn = _G._PlaceEdgeBtn or ensurePlaceEdge()

        if _G._PlaceEdgeBtnConn then
            pcall(function() _G._PlaceEdgeBtnConn:Disconnect() end)
        end
        _G._PlaceEdgeBtnConn = _G._PlaceEdgeBtn.MouseButton1Click:Connect(function()
            _G._PlaceEdgeBtn.Visible = false
            logI("Edge Place clicked")
            placeDown()
        end)

        lp.CharacterAdded:Connect(function()
            logI("CharacterAdded")
            if _G._PlaceEdgeBtn then _G._PlaceEdgeBtn.Visible = false end
            releaseAll()
            if gatherOn then
                task.defer(function()
                    stopGather()
                    startGather()
                end)
            end
            refreshOverlapFilter()
        end)

        logI("Gather module loaded")
    end

    local ok, err = xpcall(run, function(e)
        return tostring(e) .. "\n" .. debug.traceback()
    end)
    if not ok then
        if _G._GatherConsole and _G._GatherConsole.log then
            _G._GatherConsole:log("FATAL", "[Gather] module error:\n" .. tostring(err))
            _G._GatherConsole:flush()
        end
        warn("[Gather] module error: " .. tostring(err))
    end
end
