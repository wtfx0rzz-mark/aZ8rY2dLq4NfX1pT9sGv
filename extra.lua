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

    if C.State.Toggles.RifleZeroReload == nil then
        C.State.Toggles.RifleZeroReload = true
    end
    if C.State.Toggles.AutoChest == nil then
        C.State.Toggles.AutoChest = false
    end

    local rifleRunning = false
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
        if not (rifleRunning and item and item.Parent) then return end

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
        if not (rifleRunning and item and item:IsA("Instance")) then return end

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
                    if rifleRunning then
                        forceZero(item)
                    end
                end)
            end
        end

        if hasNv then
            nvConns[item] = nv.Changed:Connect(function()
                if rifleRunning and nv.Value ~= 0 then
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
            if not rifleRunning then return end
            setupItem(child)
        end)
    end

    local function startRifleZeroReload()
        if rifleRunning then return end
        rifleRunning = true

        local inv = lp:FindFirstChild("Inventory") or lp:WaitForChild("Inventory", 10)
        if inv then
            hookInventory(inv)
        end

        disconnectSignal(lpChildConn)
        lpChildConn = lp.ChildAdded:Connect(function(child)
            if not rifleRunning then return end
            if child.Name == "Inventory" then
                hookInventory(child)
            else
                setupItem(child)
            end
        end)
    end

    local function stopRifleZeroReload()
        if not rifleRunning then return end
        rifleRunning = false

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

    local function setupAutoChestFeature()
        local UID_OPEN_KEY = tostring(lp.UserId) .. "Opened"

        local AUTO_DELAY = 0.10
        local AFTER_OPEN_DELAY = 0.50
        local NOT_OPEN_WAIT = 5.00
        local WATCH_TICK = 0.05

        local CAPTURE_RADIUS = 12
        local SPAWN_RADIUS = 8

        local DRAG_TTL = 60.0
        local FRONT_DIST = 4.0
        local STAND_UP = 2.5
        local CHEST_FLOOR_RAY_DEPTH = 80.0

        local EXCLUDE_NAMES = { ["Stronghold Diamond Chest"] = true }
        local STRONGHOLD_EXCLUDE_RADIUS = 15.0

        local QUICKFIRE_HOLD_OVERRIDE = 0.12
        local FORCE_LOS_FALSE = true
        local START_YIELD = 0.06

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
            return n:match("Chest%d*$") ~= nil or n:match("Chest$") ~= nil
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
            return m:GetAttribute(UID_OPEN_KEY) == true
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
                    CapturedSet[m] = nil
                    table.remove(CapturedList, i)
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

        local function addCaptured(m)
            if CapturedSet[m] then return end
            CapturedSet[m] = true
            CapturedList[#CapturedList+1] = m
            ensureHoverOn()
        end

        local function captureModel(m)
            if not (m and m.Parent) then return false end
            if CapturedSet[m] then return false end
            if m:IsA("Model") and isChestName(m.Name) then return false end

            local root = hrp()
            if not root then return false end
            local pos = modelWorldPos(m)
            if not pos then return false end
            if (pos - root.Position).Magnitude > CAPTURE_RADIUS then return false end

            refreshDragRemotes()
            if not dragStart(m) then return false end
            task.wait(START_YIELD)
            setNoCollideModel(m, true)
            setAnchoredModel(m, true)
            addCaptured(m)
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

        local function hingeBackCenter(m)
            local pts = {}
            for _,d in ipairs(m:GetDescendants()) do
                if d.Name == "Hinge" then
                    if d:IsA("BasePart") then
                        pts[#pts+1] = d.Position
                    elseif d:IsA("Model") then
                        local mp = mainPart(d)
                        if mp then pts[#pts+1] = mp.Position end
                    end
                end
            end
            if #pts == 0 then return nil end
            local sum = Vector3.new(0,0,0)
            for _,p in ipairs(pts) do sum += p end
            return sum / #pts
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
                pcall(function() m:SetAttribute(UID_OPEN_KEY, true) end)
                return false
            end

            local mp = mainPart(m)
            if not mp then return false end

            local chestCenter = mp.Position
            local chestTopY = mp.Position.Y + (mp.Size.Y * 0.5)
            local root = hrp()
            local hingePos = hingeBackCenter(m)

            local dirs = {}
            local function addDir(v)
                if not v then return end
                if v.Magnitude < 1e-3 then return end
                dirs[#dirs+1] = v.Unit
            end

            if root then addDir(root.Position - chestCenter) end
            if hingePos then
                local v = (chestCenter - hingePos)
                if v.Magnitude < 1e-3 then v = -mp.CFrame.LookVector end
                addDir(v)
            end

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

        local function collectChestsSnapshot()
            local items = itemsFolder()
            if not items then return {} end
            local list = {}
            for _,m in ipairs(items:GetChildren()) do
                if m:IsA("Model") and isChestName(m.Name) then
                    if not (EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name) or isHalloweenChestName(m.Name)) then
                        list[#list+1] = m
                    end
                end
            end
            return list
        end

        local function applyStrongholdExclusion(chests)
            local diamond = nil
            local dpos = nil
            for i=1,#chests do
                local m = chests[i]
                if m and m.Parent and m.Name == "Stronghold Diamond Chest" then
                    diamond = m
                    dpos = modelWorldPos(m)
                    break
                end
            end
            if not (diamond and dpos) then return end
            pcall(function() diamond:SetAttribute(UID_OPEN_KEY, true) end)
            for i=1,#chests do
                local m = chests[i]
                if m and m.Parent and m ~= diamond then
                    local p = modelWorldPos(m)
                    if p and (p - dpos).Magnitude <= STRONGHOLD_EXCLUDE_RADIUS then
                        pcall(function() m:SetAttribute(UID_OPEN_KEY, true) end)
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
                    if not (EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name) or isHalloweenChestName(m.Name)) then
                        local p = modelWorldPos(m)
                        if p then
                            local d = (p - root.Position).Magnitude
                            if d < bestD then
                                bestD = d
                                best = m
                            end
                        end
                    end
                end
            end
            return best
        end

        local function snapshotNonChestItems(items)
            local set = {}
            if not items then return set end
            for _,m in ipairs(items:GetChildren()) do
                if m:IsA("Model") and m.Parent and not isChestName(m.Name) then
                    set[m] = true
                end
            end
            return set
        end

        local function scanNewDropsNearChest(items, beforeSet, chestPos)
            if not (items and beforeSet and chestPos) then return 0 end
            local picked = 0
            for _,m in ipairs(items:GetChildren()) do
                if m:IsA("Model") and m.Parent and not isChestName(m.Name) and not beforeSet[m] then
                    local p = modelWorldPos(m)
                    if p and (p - chestPos).Magnitude <= SPAWN_RADIUS then
                        if captureModel(m) then
                            picked += 1
                        end
                    end
                end
            end
            return picked
        end

        local function confirmChestOpened(chest, prompt, beforeSet, capturedBefore)
            local items = itemsFolder()
            local chestPos = modelWorldPos(chest)
            local tEnd = os.clock() + NOT_OPEN_WAIT

            while alive and os.clock() <= tEnd do
                local nowPrompt = chestPrompt(chest)
                if not nowPrompt then
                    return true
                end

                local pickedNow = 0
                if items and chestPos then
                    pickedNow = scanNewDropsNearChest(items, beforeSet, chestPos)
                end

                if #CapturedList > capturedBefore then
                    return true
                end
                if pickedNow > 0 then
                    return true
                end

                task.wait(WATCH_TICK)
            end

            return false
        end

        local autoOn = false
        local runner = nil

        local function setAuto(state)
            autoOn = (state == true)
            if not autoOn then return end
            if runner then return end
            runner = task.spawn(function()
                while alive and autoOn do
                    local root = hrp()
                    if not root then task.wait(0.25) continue end

                    local chest = nearestUnopenedChest()
                    if not chest then task.wait(0.35) continue end

                    local okTp = teleportNearChest(chest)
                    if not okTp then
                        task.wait(0.25)
                        continue
                    end

                    task.wait(AUTO_DELAY)

                    local p = chestPrompt(chest)
                    if not p then
                        task.wait(0.25)
                        continue
                    end

                    local items = itemsFolder()
                    local beforeSet = snapshotNonChestItems(items)
                    local capturedBefore = #CapturedList

                    local okTrig = triggerPrompt(p)

                    local opened = false
                    if okTrig then
                        opened = confirmChestOpened(chest, p, beforeSet, capturedBefore)
                    else
                        opened = confirmChestOpened(chest, p, beforeSet, capturedBefore)
                    end

                    if opened then
                        pcall(function() chest:SetAttribute(UID_OPEN_KEY, true) end)
                        task.wait(AFTER_OPEN_DELAY)
                    else
                        task.wait(0.05)
                    end
                end
                runner = nil
            end)
        end

        local api = {}
        function api.SetAuto(on)
            setAuto(on == true)
        end
        function api.PlaceCaptured()
            releaseAllCaptured()
        end
        function api.Destroy()
            alive = false
            autoOn = false
            releaseAllCaptured()
            for i=1,#conns do
                local c = conns[i]
                if c and c.Disconnect then pcall(function() c:Disconnect() end) end
            end
            conns = {}
        end

        bind(lp.CharacterAdded:Connect(function()
            task.wait(0.15)
            releaseAllCaptured()
        end))

        return api
    end

    if _G.__ExtraAutoChest and type(_G.__ExtraAutoChest.Destroy) == "function" then
        pcall(function() _G.__ExtraAutoChest.Destroy() end)
    end
    _G.__ExtraAutoChest = setupAutoChestFeature()

    ExtraTab:Toggle({
        Title = "Auto Chest",
        Value = C.State.Toggles.AutoChest,
        Callback = function(on)
            C.State.Toggles.AutoChest = on
            if _G.__ExtraAutoChest and _G.__ExtraAutoChest.SetAuto then
                _G.__ExtraAutoChest.SetAuto(on)
            end
        end
    })

    ExtraTab:Button({
        Title = "Place Captured Items",
        Callback = function()
            if _G.__ExtraAutoChest and _G.__ExtraAutoChest.PlaceCaptured then
                _G.__ExtraAutoChest.PlaceCaptured()
            end
        end
    })

    if C.State.Toggles.AutoChest and _G.__ExtraAutoChest and _G.__ExtraAutoChest.SetAuto then
        _G.__ExtraAutoChest.SetAuto(true)
    end
end
