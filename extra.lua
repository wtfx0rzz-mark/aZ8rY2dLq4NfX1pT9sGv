-- extra.lua

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Extra, "extra.lua: missing context or Extra tab")

    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ProximityPromptService = game:GetService("ProximityPromptService")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")

    local lp = C.LocalPlayer or Players.LocalPlayer
    local ExtraTab = UI.Tabs.Extra

    C.State = C.State or { Toggles = {} }
    C.State.Toggles = C.State.Toggles or {}

    --========================
    -- Zero ReloadTime Toggle
    --========================
    if C.State.Toggles.RifleZeroReload == nil then
        C.State.Toggles.RifleZeroReload = true
    end

    local running = false
    local invChildConn
    local lpChildConn
    local attrConns = setmetatable({}, { __mode = "k" })
    local nvConns   = setmetatable({}, { __mode = "k" })

    local function disconnectSignal(conn)
        if conn then
            pcall(function() conn:Disconnect() end)
        end
    end

    local function clearItemSignals(item)
        local a = attrConns[item]
        if a then
            disconnectSignal(a)
            attrConns[item] = nil
        end
        local n = nvConns[item]
        if n then
            disconnectSignal(n)
            nvConns[item] = nil
        end
    end

    local function hasReloadTimeAttribute(item)
        if not (item and item:IsA("Instance")) then return false end
        local ok, v = pcall(function()
            return item:GetAttribute("ReloadTime")
        end)
        return ok and v ~= nil
    end

    local function forceZero(item)
        if not (running and item and item.Parent) then return end

        local ok, attr = pcall(function()
            return item:GetAttribute("ReloadTime")
        end)

        if ok and attr ~= nil then
            if attr ~= 0 then
                pcall(function()
                    item:SetAttribute("ReloadTime", 0)
                end)
            end
            return
        end

        local nv = item:FindFirstChild("ReloadTime")
        if nv and nv:IsA("NumberValue") and nv.Value ~= 0 then
            nv.Value = 0
        end
    end

    local function setupItem(item)
        if not (running and item and item:IsA("Instance")) then return end

        clearItemSignals(item)

        local hasAttr = hasReloadTimeAttribute(item)
        local nv = item:FindFirstChild("ReloadTime")
        local hasNv = (nv and nv:IsA("NumberValue")) and true or false

        if not hasAttr and not hasNv then
            return
        end

        forceZero(item)

        if hasAttr then
            local ok, sig = pcall(function()
                return item:GetAttributeChangedSignal("ReloadTime")
            end)
            if ok and sig then
                attrConns[item] = sig:Connect(function()
                    if running then
                        forceZero(item)
                    end
                end)
            end
        end

        if hasNv then
            nvConns[item] = nv.Changed:Connect(function()
                if running and nv.Value ~= 0 then
                    nv.Value = 0
                end
            end)
        end
    end

    local function hookInventory(inv)
        if not inv then return end

        for _, child in ipairs(inv:GetChildren()) do
            setupItem(child)
        end

        disconnectSignal(invChildConn)
        invChildConn = inv.ChildAdded:Connect(function(child)
            if not running then return end
            setupItem(child)
        end)
    end

    local function startRifleZeroReload()
        if running then return end
        running = true

        local inv = lp:FindFirstChild("Inventory") or lp:WaitForChild("Inventory", 10)
        if inv then
            hookInventory(inv)
        end

        disconnectSignal(lpChildConn)
        lpChildConn = lp.ChildAdded:Connect(function(child)
            if not running then return end
            if child.Name == "Inventory" then
                hookInventory(child)
            else
                setupItem(child)
            end
        end)
    end

    local function stopRifleZeroReload()
        if not running then return end
        running = false

        disconnectSignal(invChildConn)
        invChildConn = nil
        disconnectSignal(lpChildConn)
        lpChildConn = nil

        for item, conn in pairs(attrConns) do
            disconnectSignal(conn)
            attrConns[item] = nil
        end
        for item, conn in pairs(nvConns) do
            disconnectSignal(conn)
            nvConns[item] = nil
        end
    end

    ExtraTab:Toggle({
        Title = "Zero ReloadTime",
        Value = C.State.Toggles.RifleZeroReload,
        Callback = function(on)
            C.State.Toggles.RifleZeroReload = on
            if on then
                startRifleZeroReload()
            else
                stopRifleZeroReload()
            end
        end
    })

    if C.State.Toggles.RifleZeroReload then
        startRifleZeroReload()
    end

    --========================
    -- AutoChest (WindUI)
    --========================
    if _G.__ExtraAutoChest and type(_G.__ExtraAutoChest.Destroy) == "function" then
        pcall(function() _G.__ExtraAutoChest.Destroy() end)
    end

    if C.State.Toggles.AutoChest == nil then
        C.State.Toggles.AutoChest = false
    end
    if C.State.Toggles.AutoChestCaptureDropsOnly == nil then
        C.State.Toggles.AutoChestCaptureDropsOnly = true
    end

    local UID_OPEN_KEY = tostring(lp.UserId) .. "Opened"

    local AUTO_DELAY = 0.12
    local FAIL_RETRY_DELAY = 0.20
    local CHEST_COOLDOWN = 0.35

    local CAPTURE_WINDOW = 2.75
    local CAPTURE_RADIUS_CHEST = 12
    local START_CAPTURE_YIELD = 0.10

    local DRAG_TTL = 60.0
    local FRONT_DIST = 4.0
    local STAND_UP = 2.5
    local CHEST_FLOOR_RAY_DEPTH = 80.0

    local EXCLUDE_NAMES = { ["Stronghold Diamond Chest"] = true }
    local STRONGHOLD_EXCLUDE_RADIUS = 15.0

    local QUICKFIRE_HOLD_OVERRIDE = 0.12
    local FORCE_LOS_FALSE = true

    local alive = true
    local conns = {}
    local function bind(conn)
        conns[#conns+1] = conn
        return conn
    end

    local function hrp()
        local ch = lp.Character
        return ch and ch:FindFirstChild("HumanoidRootPart") or nil
    end

    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Tool") then
            local h = obj:FindFirstChild("Handle")
            if h and h:IsA("BasePart") then return h end
            return obj:FindFirstChildWhichIsA("BasePart", true)
        end
        if obj:IsA("Model") then
            if obj.PrimaryPart then return obj.PrimaryPart end
            return obj:FindFirstChildWhichIsA("BasePart", true)
        end
        return nil
    end

    local function itemsFolder()
        return Workspace:FindFirstChild("Items")
    end

    local function modelWorldPos(m)
        if not m or not m.Parent then return nil end
        local mp = mainPart(m)
        if mp then return mp.Position end
        local ok, cf = pcall(function() return m:GetPivot() end)
        return ok and cf.Position or nil
    end

    local function pivotModel(m, cf)
        if not (m and m.Parent) then return end
        if m:IsA("Model") then
            pcall(function() m:PivotTo(cf) end)
        else
            local p = mainPart(m)
            if p then pcall(function() p.CFrame = cf end) end
        end
    end

    local function isChestName(n)
        if type(n) ~= "string" then return false end
        if n:match("^Item Chest%d*$") then return true end
        if n:match("^Item Chest$") then return true end
        if n:match("Chest%d*$") then return true end
        if n:match("Chest$") then return true end
        return false
    end

    local function isSnowChestName(n)
        if type(n) ~= "string" then return false end
        return (n == "Snow Chest") or (n:match("^Snow Chest%d+$") ~= nil)
    end

    local function isHalloweenChestName(n)
        if type(n) ~= "string" then return false end
        return (n == "Halloween Chest") or (n:match("^Halloween Chest%d+$") ~= nil)
    end

    local function chestOpened(m)
        if not m then return false end
        local ok, v = pcall(function() return m:GetAttribute(UID_OPEN_KEY) end)
        return ok and v == true
    end

    local function markChestOpened(m, on)
        if not m then return end
        pcall(function()
            if on then
                m:SetAttribute(UID_OPEN_KEY, true)
            else
                m:SetAttribute(UID_OPEN_KEY, nil)
            end
        end)
    end

    local function getRemote(...)
        local f = ReplicatedStorage:FindFirstChild("RemoteEvents")
        if not f then return nil end
        for i = 1, select("#", ...) do
            local n = select(i, ...)
            local x = f:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local RF_Start, RF_Stop = nil, nil
    local function refreshDragRemotes()
        RF_Start = getRemote("RequestStartDraggingItem","StartDraggingItem")
        RF_Stop  = getRemote("RequestStopDraggingItem","StopDraggingItem","StopDraggingItemRemote")
    end
    refreshDragRemotes()

    local DragActive = {}
    local function safeStopDrag(m)
        if not (m and RF_Stop) then return false end
        return pcall(function() RF_Stop:FireServer(m) end)
    end

    local function finallyStopDrag(m)
        task.delay(0.05, function() pcall(safeStopDrag, m) end)
        task.delay(0.20, function() pcall(safeStopDrag, m) end)
    end

    local function dragUntrack(m)
        local rec = DragActive[m]
        if not rec then return end
        DragActive[m] = nil
        for _,c in ipairs(rec.conns) do pcall(function() c:Disconnect() end) end
    end

    local function dragTrackRelease(m)
        local rec = DragActive[m]
        if not rec then return end
        DragActive[m] = nil
        for _,c in ipairs(rec.conns) do pcall(function() c:Disconnect() end) end
        safeStopDrag(m)
    end

    local function dragStart(m)
        if not (m and m.Parent and RF_Start) then return false end
        if DragActive[m] then
            DragActive[m].t0 = os.clock()
            return true
        end
        local ok = pcall(function() RF_Start:FireServer(m) end)
        if not ok then return false end
        local c = {}
        c[#c+1] = m.AncestryChanged:Connect(function(_, parent)
            if not parent then dragTrackRelease(m) end
        end)
        c[#c+1] = m:GetPropertyChangedSignal("Parent"):Connect(function()
            if not m.Parent then dragTrackRelease(m) end
        end)
        DragActive[m] = { t0 = os.clock(), conns = c }
        return true
    end

    local function dragKeepAlive(m)
        local rec = DragActive[m]
        if rec then rec.t0 = os.clock() end
    end

    bind(RunService.Heartbeat:Connect(function()
        local now = os.clock()
        for m, rec in pairs(DragActive) do
            if (not m) or (not m.Parent) or (now - rec.t0) > DRAG_TTL then
                dragTrackRelease(m)
            end
        end
    end))

    local function setNoCollideModel(m, on)
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                d.CanCollide = not on
                d.CanQuery = not on
                d.CanTouch = not on
                d.Massless = on and true or false
                d.AssemblyLinearVelocity = Vector3.new()
                d.AssemblyAngularVelocity = Vector3.new()
            end
        end
    end

    local function setAnchoredModel(m, on)
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored = on end
        end
    end

    local CapturedSet = {}
    local CapturedList = {}

    local function addCaptured(m)
        if CapturedSet[m] then return end
        CapturedSet[m] = true
        CapturedList[#CapturedList+1] = m
    end

    local function removeCaptured(m)
        if not CapturedSet[m] then return end
        CapturedSet[m] = nil
        for i = #CapturedList, 1, -1 do
            if CapturedList[i] == m then
                table.remove(CapturedList, i)
                break
            end
        end
    end

    local hoverConn = nil
    local function hoverFollow()
        local root = hrp()
        if not root then return end
        local forward = root.CFrame.LookVector
        local basePos = root.Position + Vector3.new(0, 10, 0) + forward * 1.5
        local baseCF = CFrame.lookAt(basePos, basePos + forward)
        for i = #CapturedList, 1, -1 do
            local m = CapturedList[i]
            if m and m.Parent then
                dragKeepAlive(m)
                setAnchoredModel(m, true)
                pivotModel(m, baseCF)
            else
                removeCaptured(m)
            end
        end
    end

    local function ensureHoverOn()
        if hoverConn then return end
        hoverConn = RunService.RenderStepped:Connect(hoverFollow)
    end

    local function ensureHoverOff()
        if hoverConn then pcall(function() hoverConn:Disconnect() end) end
        hoverConn = nil
    end

    local function isValidCaptureTarget(t)
        if not (t and t.Parent) then return false end
        if t:IsA("Model") or t:IsA("Tool") or t:IsA("BasePart") then
            local n = t.Name
            if isChestName(n) then return false end
            if isSnowChestName(n) or isHalloweenChestName(n) then return false end
            return true
        end
        return false
    end

    local function findCaptureTarget(inst)
        if not (inst and inst.Parent) then return nil end
        if inst:IsA("Model") or inst:IsA("Tool") or inst:IsA("BasePart") then
            return inst
        end
        local m = inst:FindFirstAncestorOfClass("Model")
        if m then return m end
        local t = inst:FindFirstAncestorOfClass("Tool")
        if t then return t end
        local p = inst:FindFirstAncestorWhichIsA("BasePart")
        if p then return p end
        return nil
    end

    local function captureTarget(t)
        if not isValidCaptureTarget(t) then return false end
        if CapturedSet[t] then return false end
        refreshDragRemotes()
        if not dragStart(t) then return false end
        task.wait(0.06)
        setNoCollideModel(t, true)
        setAnchoredModel(t, true)
        addCaptured(t)
        ensureHoverOn()
        return true
    end

    local function releaseAllCaptured()
        ensureHoverOff()
        for i = #CapturedList, 1, -1 do
            local m = CapturedList[i]
            if m and m.Parent then
                setAnchoredModel(m, false)
                setNoCollideModel(m, false)
                finallyStopDrag(m)
                dragUntrack(m)
            end
        end
        table.clear(CapturedList)
        for k,_ in pairs(CapturedSet) do CapturedSet[k] = nil end
    end

    local function makeChestRayParams(extras)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        local ex = { lp.Character }
        local items = Workspace:FindFirstChild("Items")
        if items then table.insert(ex, items) end
        local map = Workspace:FindFirstChild("Map")
        if map then
            local fol = map:FindFirstChild("Foliage")
            if fol then table.insert(ex, fol) end
        end
        if extras then
            for i=1,#extras do
                local v = extras[i]
                if v then table.insert(ex, v) end
            end
        end
        params.FilterDescendantsInstances = ex
        return params
    end

    local function floorAtFromChestTop(chestModel, chestTopY, xz)
        local params = makeChestRayParams({ chestModel })
        local start = Vector3.new(xz.X, chestTopY + 2.0, xz.Z)
        local hit = Workspace:Raycast(start, Vector3.new(0, -CHEST_FLOOR_RAY_DEPTH, 0), params)
        return hit and hit.Position or nil
    end

    local function hasLineOfSightToChest(standPos, chestModel, chestCenter)
        local params = makeChestRayParams({ chestModel })
        local from = standPos + Vector3.new(0, 1.0, 0)
        local to   = chestCenter + Vector3.new(0, 0.8, 0)
        local dir = (to - from)
        if dir.Magnitude < 0.05 then return true end
        local hit = Workspace:Raycast(from, dir, params)
        if not hit then return true end
        if hit.Instance and hit.Instance:IsDescendantOf(chestModel) then return true end
        return false
    end

    local function teleportToCF(cf)
        local root = hrp()
        if not root then return false end
        local ch = lp.Character
        if ch then pcall(function() ch:PivotTo(cf) end) end
        return pcall(function() root.CFrame = cf end)
    end

    local function teleportNearChest(m)
        if not (m and m.Parent and m:IsA("Model")) then return false end
        if EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name) or isHalloweenChestName(m.Name) then
            markChestOpened(m, true)
            return false
        end
        local mp = mainPart(m)
        if not mp then
            markChestOpened(m, true)
            return false
        end

        local chestCenter = mp.Position
        local chestTopY = mp.Position.Y + (mp.Size.Y * 0.5)
        local root = hrp()

        local dirs = {}
        local function addDir(v)
            if not v then return end
            if v.Magnitude < 1e-3 then return end
            dirs[#dirs+1] = v.Unit
        end

        if root then addDir(root.Position - chestCenter) end
        addDir(mp.CFrame.LookVector)
        addDir(-mp.CFrame.LookVector)
        addDir(mp.CFrame.RightVector)
        addDir(-mp.CFrame.RightVector)
        addDir((mp.CFrame.LookVector + mp.CFrame.RightVector))
        addDir((mp.CFrame.LookVector - mp.CFrame.RightVector))
        addDir((-mp.CFrame.LookVector + mp.CFrame.RightVector))
        addDir((-mp.CFrame.LookVector - mp.CFrame.RightVector))

        local bestCF = nil
        for i=1,#dirs do
            local dir = dirs[i]
            local desired = chestCenter + dir * FRONT_DIST
            local floorPos = floorAtFromChestTop(m, chestTopY, desired)
            local standY = floorPos and (floorPos.Y + STAND_UP) or (chestCenter.Y + STAND_UP)
            local standPos = Vector3.new(desired.X, standY, desired.Z)
            if hasLineOfSightToChest(standPos, m, chestCenter) then
                bestCF = CFrame.new(standPos, chestCenter)
                break
            end
        end

        if not bestCF then
            local fallbackPos = chestCenter + (-mp.CFrame.LookVector) * FRONT_DIST
            local floorPos = floorAtFromChestTop(m, chestTopY, fallbackPos) or Vector3.new(fallbackPos.X, chestCenter.Y, fallbackPos.Z)
            local standPos = Vector3.new(fallbackPos.X, floorPos.Y + STAND_UP, fallbackPos.Z)
            bestCF = CFrame.new(standPos, chestCenter)
        end

        return teleportToCF(bestCF)
    end

    local function chestPrompt(m)
        if not (m and m.Parent) then return nil end
        return m:FindFirstChildWhichIsA("ProximityPrompt", true)
    end

    local function triggerPrompt(prompt)
        if not (prompt and prompt.Parent) then return false end
        if FORCE_LOS_FALSE then
            pcall(function() prompt.RequiresLineOfSight = false end)
        end
        if QUICKFIRE_HOLD_OVERRIDE and type(QUICKFIRE_HOLD_OVERRIDE) == "number" then
            pcall(function()
                if prompt.HoldDuration > QUICKFIRE_HOLD_OVERRIDE then
                    prompt.HoldDuration = QUICKFIRE_HOLD_OVERRIDE
                end
            end)
        end
        local ok = pcall(function()
            ProximityPromptService:TriggerPrompt(prompt)
        end)
        if ok then return true end
        local ok2 = pcall(function()
            prompt:InputHoldBegin()
        end)
        if not ok2 then return false end
        local hold = tonumber(prompt.HoldDuration) or 0
        local waitTime = (hold > 0) and (hold + 0.05) or 0.05
        task.delay(waitTime, function()
            if prompt and prompt.Parent then
                pcall(function() prompt:InputHoldEnd() end)
            end
        end)
        return true
    end

    local function chestPos(m)
        return modelWorldPos(m)
    end

    local function collectChestsSnapshot()
        local items = itemsFolder()
        if not items then return {} end
        local list = {}
        for _,m in ipairs(items:GetChildren()) do
            if m:IsA("Model") and isChestName(m.Name) then
                if not (EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name) or isHalloweenChestName(m.Name)) then
                    local p = chestPos(m)
                    if p then
                        list[#list+1] = m
                    end
                end
            end
        end
        return list
    end

    local function applyStrongholdExclusion(chests)
        local diamond = nil
        local dpos = nil
        for i=1,#chests do
            if chests[i] and chests[i].Parent and chests[i].Name == "Stronghold Diamond Chest" then
                diamond = chests[i]
                dpos = chestPos(diamond)
                break
            end
        end
        if not (diamond and dpos) then return end
        markChestOpened(diamond, true)
        for i=1,#chests do
            local m = chests[i]
            if m and m.Parent and m ~= diamond then
                local p = chestPos(m)
                if p and (p - dpos).Magnitude <= STRONGHOLD_EXCLUDE_RADIUS then
                    markChestOpened(m, true)
                end
            end
        end
    end

    local function nearestUnopenedChest()
        local root = hrp()
        if not root then return nil end
        local chests = collectChestsSnapshot()
        if #chests == 0 then return nil end
        applyStrongholdExclusion(chests)
        local best, bestD = nil, math.huge
        for i=1,#chests do
            local m = chests[i]
            if m and m.Parent and not chestOpened(m) then
                local p = chestPos(m)
                if p then
                    local d = (p - root.Position).Magnitude
                    if d < bestD then
                        bestD = d
                        best = m
                    end
                end
            end
        end
        return best
    end

    local function snapshotItems(items)
        local set = {}
        if not items then return set end
        for _,ch in ipairs(items:GetChildren()) do
            set[ch] = true
        end
        return set
    end

    local function beginCaptureWindowForChest(chestModel)
        local items = itemsFolder()
        if not items then return end
        local cpos = chestPos(chestModel)
        if not cpos then return end

        local pre = snapshotItems(items)
        local tEnd = os.clock() + CAPTURE_WINDOW
        local useDiff = (C.State.Toggles.AutoChestCaptureDropsOnly == true)

        local function withinChestRadius(t)
            local p = modelWorldPos(t)
            if not p then return false end
            return (p - cpos).Magnitude <= CAPTURE_RADIUS_CHEST
        end

        local function tryCaptureFromInst(inst)
            if not alive then return end
            if os.clock() > tEnd then return end
            if not (inst and inst.Parent) then return end

            local t = findCaptureTarget(inst)
            if not t or not t.Parent then return end
            if isChestName(t.Name) then return end

            if useDiff and pre[t] then return end
            if not withinChestRadius(t) then return end

            captureTarget(t)
        end

        local dc = items.DescendantAdded:Connect(tryCaptureFromInst)

        task.spawn(function()
            while alive and os.clock() <= tEnd do
                local kids = items:GetChildren()
                for i=1,#kids do
                    local inst = kids[i]
                    local t = findCaptureTarget(inst)
                    if t and t.Parent then
                        if not (useDiff and pre[t]) then
                            if not isChestName(t.Name) and withinChestRadius(t) then
                                captureTarget(t)
                            end
                        end
                    end
                end
                task.wait(0.08)
            end
            pcall(function() dc:Disconnect() end)
        end)
    end

    local autoOn = false
    local runner = nil

    local function startAuto()
        if autoOn then return end
        autoOn = true
        if runner then return end
        runner = task.spawn(function()
            while alive and autoOn do
                local root = hrp()
                if not root then task.wait(0.25) continue end

                local chest = nearestUnopenedChest()
                if not chest then task.wait(0.35) continue end

                local okTp = teleportNearChest(chest)
                if not okTp then
                    markChestOpened(chest, true)
                    task.wait(FAIL_RETRY_DELAY)
                    continue
                end

                task.wait(AUTO_DELAY)

                local p = chestPrompt(chest)
                if not p then
                    markChestOpened(chest, true)
                    task.wait(FAIL_RETRY_DELAY)
                    continue
                end

                local okTrig = triggerPrompt(p)
                if okTrig then
                    task.wait(START_CAPTURE_YIELD)
                    beginCaptureWindowForChest(chest)
                    task.wait(CHEST_COOLDOWN)
                    markChestOpened(chest, true)
                else
                    task.wait(FAIL_RETRY_DELAY)
                end
            end
            runner = nil
        end)
    end

    local function stopAuto()
        if not autoOn then return end
        autoOn = false
    end

    local function resetOpenedMarks()
        local items = itemsFolder()
        if not items then return end
        for _,m in ipairs(items:GetChildren()) do
            if m and m.Parent and m:IsA("Model") and isChestName(m.Name) then
                markChestOpened(m, false)
            end
        end
    end

    ExtraTab:Toggle({
        Title = "Auto Chest",
        Value = C.State.Toggles.AutoChest,
        Callback = function(on)
            C.State.Toggles.AutoChest = on
            if on then startAuto() else stopAuto() end
        end
    })

    ExtraTab:Toggle({
        Title = "Capture Drops Only (ignore existing nearby)",
        Value = C.State.Toggles.AutoChestCaptureDropsOnly,
        Callback = function(on)
            C.State.Toggles.AutoChestCaptureDropsOnly = on
        end
    })

    ExtraTab:Button({
        Title = "Place Captured Items",
        Callback = function()
            releaseAllCaptured()
        end
    })

    ExtraTab:Button({
        Title = "Reset Opened Marks (Items)",
        Callback = function()
            resetOpenedMarks()
        end
    })

    bind(lp.CharacterAdded:Connect(function()
        task.wait(0.15)
        releaseAllCaptured()
    end))

    if C.State.Toggles.AutoChest then
        startAuto()
    end

    local api = {}
    function api.Destroy()
        alive = false
        stopAuto()
        releaseAllCaptured()
        for i=1,#conns do
            local c = conns[i]
            if c and c.Disconnect then pcall(function() c:Disconnect() end) end
        end
        conns = {}
    end
    _G.__ExtraAutoChest = api
end
