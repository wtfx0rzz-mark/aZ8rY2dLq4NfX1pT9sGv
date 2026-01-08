return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Extra, "extra.lua: missing context or Extra tab")

    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local WS = game:GetService("Workspace")
    local PPS = game:GetService("ProximityPromptService")
    local RunService = game:GetService("RunService")

    local lp = C.LocalPlayer or Players.LocalPlayer
    local ExtraTab = UI.Tabs.Extra

    C.State = C.State or { Toggles = {} }
    C.State.Toggles = C.State.Toggles or {}

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

    local function pivotAny(inst, cf)
        if not (inst and inst.Parent) then return end
        if inst:IsA("Model") then
            pcall(function() inst:PivotTo(cf) end)
            return
        end
        local p = mainPart(inst)
        if p then
            pcall(function() p.CFrame = cf end)
        end
    end

    local function modelWorldPos(m)
        if not (m and m.Parent) then return nil end
        local mp = mainPart(m)
        if mp then return mp.Position end
        local ok, cf = pcall(function() return m:GetPivot() end)
        return ok and cf.Position or nil
    end

    local function itemsFolder()
        return WS:FindFirstChild("Items")
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

    local function setNoCollideAny(inst, on)
        if not (inst and inst.Parent) then return end
        if inst:IsA("BasePart") then
            inst.CanCollide = not on
            inst.CanQuery = not on
            inst.CanTouch = not on
            inst.Massless = on and true or false
            inst.AssemblyLinearVelocity = Vector3.new()
            inst.AssemblyAngularVelocity = Vector3.new()
            return
        end
        for _,d in ipairs(inst:GetDescendants()) do
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

    local function setAnchoredAny(inst, on)
        if not (inst and inst.Parent) then return end
        if inst:IsA("BasePart") then
            inst.Anchored = on
            return
        end
        for _,d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored = on end
        end
    end

    local function getRemote(...)
        local f = RS:FindFirstChild("RemoteEvents")
        if not f then return nil end
        for i = 1, select("#", ...) do
            local n = select(i, ...)
            local x = f:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    if _G.__AutoChestExtra and type(_G.__AutoChestExtra.Destroy) == "function" then
        pcall(function() _G.__AutoChestExtra.Destroy() end)
    end

    if C.State.Toggles.AutoChest == nil then
        C.State.Toggles.AutoChest = false
    end
    if not tonumber(C.State.ChestPostOpenDelay) then
        C.State.ChestPostOpenDelay = 0.50
    end
    if not tonumber(C.State.ChestNotOpenWait) then
        C.State.ChestNotOpenWait = 5.00
    end
    if not tonumber(C.State.ChestCaptureWindow) then
        C.State.ChestCaptureWindow = 4.50
    end
    if not tonumber(C.State.ChestCaptureRadius) then
        C.State.ChestCaptureRadius = 22.00
    end
    if not tonumber(C.State.ChestSpawnRadius) then
        C.State.ChestSpawnRadius = 10.00
    end
    if not tonumber(C.State.ChestOpenConfirmTimeout) then
        C.State.ChestOpenConfirmTimeout = 3.50
    end

    local UID_OPEN_KEY = tostring(lp.UserId) .. "Opened"

    local RF_Start = nil
    local RF_Stop = nil
    local function refreshDragRemotes()
        RF_Start = getRemote("RequestStartDraggingItem","StartDraggingItem")
        RF_Stop  = getRemote("RequestStopDraggingItem","StopDraggingItem","StopDraggingItemRemote")
    end
    refreshDragRemotes()

    local alive = true
    local conns = {}
    local function bind(conn)
        conns[#conns+1] = conn
        return conn
    end

    local DRAG_TTL = 60.0
    local DragActive = {}

    local function safeStopDrag(m)
        if not (m and RF_Stop) then return false end
        return pcall(function() RF_Stop:FireServer(m) end)
    end

    local function finallyStopDrag(m)
        task.delay(0.05, function() pcall(safeStopDrag, m) end)
        task.delay(0.20, function() pcall(safeStopDrag, m) end)
        task.delay(0.45, function() pcall(safeStopDrag, m) end)
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

    local overlapParams = OverlapParams.new()
    overlapParams.MaxParts = 1000

    local function refreshOverlapFilter()
        local items = itemsFolder()
        if items then
            overlapParams.FilterType = Enum.RaycastFilterType.Include
            overlapParams.FilterDescendantsInstances = { items }
        else
            overlapParams.FilterType = Enum.RaycastFilterType.Exclude
            overlapParams.FilterDescendantsInstances = { lp.Character }
        end
    end
    refreshOverlapFilter()

    local function topModelUnderItems(part, itemsRoot)
        local cur = part
        local lastModel = nil
        while cur and cur ~= WS and cur ~= itemsRoot do
            if cur:IsA("Model") then lastModel = cur end
            cur = cur.Parent
        end
        if lastModel and itemsRoot and lastModel.Parent == itemsRoot then return lastModel end
        return lastModel
    end

    local function itemKey(inst)
        return inst
    end

    local function isChestInst(inst)
        return inst and inst.Parent and inst:IsA("Model") and isChestName(inst.Name)
    end

    local CapturedSet = {}
    local CapturedList = {}

    local HOLD_OFFSET_Y = 10
    local HOLD_FORWARD = 1.5

    local hoverConn = nil
    local function hoverFollow()
        local root = hrp()
        if not root then return end
        local forward = root.CFrame.LookVector
        local basePos = root.Position + Vector3.new(0, HOLD_OFFSET_Y, 0) + forward * HOLD_FORWARD
        local baseCF = CFrame.lookAt(basePos, basePos + forward)
        for i = #CapturedList, 1, -1 do
            local m = CapturedList[i]
            if m and m.Parent then
                dragKeepAlive(m)
                setAnchoredAny(m, true)
                pivotAny(m, baseCF)
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

    local function releaseAllCaptured()
        ensureHoverOff()
        for i = #CapturedList, 1, -1 do
            local m = CapturedList[i]
            if m and m.Parent then
                setAnchoredAny(m, false)
                setNoCollideAny(m, false)
                finallyStopDrag(m)
                dragUntrack(m)
            end
            CapturedSet[m] = nil
            table.remove(CapturedList, i)
        end
        table.clear(CapturedList)
        for k,_ in pairs(CapturedSet) do CapturedSet[k] = nil end
    end

    local function captureInst(inst)
        if not (inst and inst.Parent) then return false end
        if CapturedSet[inst] then return false end
        if isChestInst(inst) then return false end
        refreshDragRemotes()
        if not dragStart(inst) then return false end
        task.wait(0.06)
        setNoCollideAny(inst, true)
        setAnchoredAny(inst, true)
        addCaptured(inst)
        return true
    end

    local function getCandidatesNear(pos, rad)
        local items = itemsFolder()
        if not (items and pos and rad) then return {} end
        refreshOverlapFilter()
        local ok, parts = pcall(function()
            return WS:GetPartBoundsInRadius(pos, rad, overlapParams)
        end)
        local out = {}
        local seen = {}
        local function push(inst)
            if not (inst and inst.Parent) then return end
            if isChestInst(inst) then return end
            if isSnowChestName(inst.Name) or isHalloweenChestName(inst.Name) then return end
            if seen[inst] then return end
            seen[inst] = true
            out[#out+1] = inst
        end
        if ok and type(parts) == "table" then
            for _,p in ipairs(parts) do
                if p and p.Parent then
                    local m = topModelUnderItems(p, items) or p
                    if m and m.Parent and (m:IsA("Model") or m:IsA("BasePart")) then
                        push(m)
                    end
                end
            end
        end
        if #out == 0 then
            for _,ch in ipairs(items:GetChildren()) do
                if (ch:IsA("Model") or ch:IsA("BasePart")) and ch.Parent then
                    local mp = mainPart(ch)
                    if mp then
                        if (mp.Position - pos).Magnitude <= rad then
                            push(ch)
                        end
                    end
                end
            end
        end
        return out
    end

    local function snapshotNearChest(chestPos, rad)
        local set = {}
        local list = getCandidatesNear(chestPos, rad)
        for i=1,#list do
            set[itemKey(list[i])] = true
        end
        return set
    end

    local function chestOpened(chestModel)
        if not chestModel then return false end
        local ok, v = pcall(function() return chestModel:GetAttribute(UID_OPEN_KEY) end)
        return ok and v == true
    end

    local function chestPrompt(chestModel)
        if not (chestModel and chestModel.Parent) then return nil end
        return chestModel:FindFirstChildWhichIsA("ProximityPrompt", true)
    end

    local function triggerPrompt(prompt)
        if not (prompt and prompt.Parent) then return false end
        pcall(function() prompt.RequiresLineOfSight = false end)
        pcall(function()
            if prompt.HoldDuration > 0.12 then
                prompt.HoldDuration = 0.12
            end
        end)
        local ok = pcall(function()
            PPS:TriggerPrompt(prompt)
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

    local CHEST_FLOOR_RAY_DEPTH = 80.0
    local FRONT_DIST = 4.0
    local STAND_UP = 2.5
    local STRONGHOLD_EXCLUDE_RADIUS = 15.0
    local EXCLUDE_NAMES = { ["Stronghold Diamond Chest"] = true }

    local function makeChestRayParams(extras)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        local ex = { lp.Character }
        local items = WS:FindFirstChild("Items")
        if items then table.insert(ex, items) end
        local map = WS:FindFirstChild("Map")
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
        local hit = WS:Raycast(start, Vector3.new(0, -CHEST_FLOOR_RAY_DEPTH, 0), params)
        return hit and hit.Position or nil
    end

    local function hasLineOfSightToChest(standPos, chestModel, chestCenter)
        local params = makeChestRayParams({ chestModel })
        local from = standPos + Vector3.new(0, 1.0, 0)
        local to   = chestCenter + Vector3.new(0, 0.8, 0)
        local dir = (to - from)
        if dir.Magnitude < 0.05 then return true end
        local hit = WS:Raycast(from, dir, params)
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
            if chests[i] and chests[i].Parent and chests[i].Name == "Stronghold Diamond Chest" then
                diamond = chests[i]
                dpos = modelWorldPos(diamond)
                break
            end
        end
        if not (diamond and dpos) then return end
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

    local attemptedAt = setmetatable({}, { __mode = "k" })
    local function recentlyAttempted(chest, windowSec)
        local t = attemptedAt[chest]
        if not t then return false end
        return (os.clock() - t) <= windowSec
    end

    local function nearestUnopenedChest()
        local root = hrp()
        if not root then return nil end
        local chests = collectChestsSnapshot()
        if #chests == 0 then return nil end
        applyStrongholdExclusion(chests)
        local best, bestD = nil, math.huge
        local skipWindow = math.max(tonumber(C.State.ChestNotOpenWait) or 5.0, 1.0)
        for i=1,#chests do
            local m = chests[i]
            if m and m.Parent and not chestOpened(m) then
                if not recentlyAttempted(m, skipWindow) then
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

    local function confirmAndCaptureDropsForChest(chest, preSet)
        local opened = false
        local gotAny = false
        local t0 = os.clock()
        local confirmTimeout = math.max(tonumber(C.State.ChestOpenConfirmTimeout) or 3.5, 0.5)
        local spawnRadius = math.max(tonumber(C.State.ChestSpawnRadius) or 10.0, 2.0)
        local captureRadius = math.max(tonumber(C.State.ChestCaptureRadius) or 22.0, spawnRadius)
        local captureWindow = math.max(tonumber(C.State.ChestCaptureWindow) or 4.5, 0.5)

        local function scanNewNear(chestPos, rad, doCapture)
            local cands = getCandidatesNear(chestPos, rad)
            local newFound = {}
            for i=1,#cands do
                local inst = cands[i]
                if inst and inst.Parent then
                    if not isChestInst(inst) then
                        local k = itemKey(inst)
                        if not preSet[k] then
                            newFound[#newFound+1] = inst
                        end
                    end
                end
            end
            if #newFound > 0 then
                if doCapture then
                    for i=1,#newFound do
                        local inst = newFound[i]
                        if inst and inst.Parent then
                            if captureInst(inst) then
                                preSet[itemKey(inst)] = true
                                gotAny = true
                            end
                        end
                    end
                end
                return true
            end
            return false
        end

        while alive and chest and chest.Parent and (os.clock() - t0) <= confirmTimeout do
            local pos = modelWorldPos(chest)
            if pos then
                if scanNewNear(pos, spawnRadius, true) then
                    opened = true
                    break
                end
            end
            local p = chestPrompt(chest)
            if not (p and p.Parent) then
                opened = true
                break
            end
            task.wait(0.10)
        end

        if opened and chest and chest.Parent then
            local tEnd = os.clock() + captureWindow
            while alive and chest and chest.Parent and os.clock() <= tEnd do
                local pos = modelWorldPos(chest)
                if pos then
                    scanNewNear(pos, captureRadius, true)
                end
                task.wait(0.08)
            end
        end

        return opened, gotAny
    end

    local CHEST_LIFT_Y = 30

    local function openChestOnce(chest)
        if not (chest and chest.Parent) then return false end
        if EXCLUDE_NAMES[chest.Name] or isSnowChestName(chest.Name) or isHalloweenChestName(chest.Name) then
            pcall(function() chest:SetAttribute(UID_OPEN_KEY, true) end)
            return false
        end

        attemptedAt[chest] = os.clock()

        local origPivot
        do
            local ok, cf = pcall(function() return chest:GetPivot() end)
            if not (ok and cf) then return false end
            origPivot = cf
        end

        local function restore()
            if chest and chest.Parent and origPivot then
                pcall(function() chest:PivotTo(origPivot) end)
            end
        end

        pcall(function()
            chest:PivotTo(origPivot * CFrame.new(0, CHEST_LIFT_Y, 0))
        end)
        task.wait(0.06)

        if not teleportNearChest(chest) then
            restore()
            local notOpenWait = math.max(tonumber(C.State.ChestNotOpenWait) or 5.0, 0.0)
            if notOpenWait > 0 then task.wait(notOpenWait) end
            return false
        end
        task.wait(0.08)

        local pos = modelWorldPos(chest)
        if not pos then
            restore()
            return false
        end

        local preSet = snapshotNearChest(pos, math.max(tonumber(C.State.ChestCaptureRadius) or 22.0, 10.0) + 8.0)

        local prompt = chestPrompt(chest)
        if not prompt then
            restore()
            return false
        end

        if not triggerPrompt(prompt) then
            restore()
            return false
        end

        local opened, gotAny = confirmAndCaptureDropsForChest(chest, preSet)
        restore()

        if opened then
            pcall(function() chest:SetAttribute(UID_OPEN_KEY, true) end)
            local postDelay = math.max(tonumber(C.State.ChestPostOpenDelay) or 0.5, 0.0)
            if postDelay > 0 then task.wait(postDelay) end
            return true, gotAny
        end

        local notOpenWait = math.max(tonumber(C.State.ChestNotOpenWait) or 5.0, 0.0)
        if notOpenWait > 0 then task.wait(notOpenWait) end
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
                local okOpen = openChestOnce(chest)
                if not okOpen then
                    task.wait(0.10)
                end
            end
            runner = nil
        end)
    end

    local function stopAuto()
        autoOn = false
    end

    ExtraTab:Section({ Title = "Chests" })

    ExtraTab:Toggle({
        Title = "Auto Open Chests",
        Value = C.State.Toggles.AutoChest,
        Callback = function(on)
            C.State.Toggles.AutoChest = on
            if on then
                setAuto(true)
            else
                stopAuto()
            end
        end
    })

    ExtraTab:Button({
        Title = "Drop Captured Items",
        Callback = function()
            releaseAllCaptured()
        end
    })

    ExtraTab:Slider({
        Title = "Post-open delay (sec)",
        Min = 0,
        Max = 3,
        Default = tonumber(C.State.ChestPostOpenDelay) or 0.5,
        Value = { Min = 0, Max = 3, Default = tonumber(C.State.ChestPostOpenDelay) or 0.5 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default end
            nv = tonumber(nv)
            if nv then C.State.ChestPostOpenDelay = math.clamp(nv, 0, 3) end
        end
    })

    ExtraTab:Slider({
        Title = "Not opening wait (sec)",
        Min = 0,
        Max = 15,
        Default = tonumber(C.State.ChestNotOpenWait) or 5.0,
        Value = { Min = 0, Max = 15, Default = tonumber(C.State.ChestNotOpenWait) or 5.0 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default end
            nv = tonumber(nv)
            if nv then C.State.ChestNotOpenWait = math.clamp(nv, 0, 15) end
        end
    })

    ExtraTab:Slider({
        Title = "Open confirm timeout (sec)",
        Min = 1,
        Max = 8,
        Default = tonumber(C.State.ChestOpenConfirmTimeout) or 3.5,
        Value = { Min = 1, Max = 8, Default = tonumber(C.State.ChestOpenConfirmTimeout) or 3.5 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default end
            nv = tonumber(nv)
            if nv then C.State.ChestOpenConfirmTimeout = math.clamp(nv, 1, 8) end
        end
    })

    ExtraTab:Slider({
        Title = "Capture window (sec)",
        Min = 1,
        Max = 10,
        Default = tonumber(C.State.ChestCaptureWindow) or 4.5,
        Value = { Min = 1, Max = 10, Default = tonumber(C.State.ChestCaptureWindow) or 4.5 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default end
            nv = tonumber(nv)
            if nv then C.State.ChestCaptureWindow = math.clamp(nv, 1, 10) end
        end
    })

    ExtraTab:Slider({
        Title = "Capture radius (studs)",
        Min = 6,
        Max = 40,
        Default = tonumber(C.State.ChestCaptureRadius) or 22.0,
        Value = { Min = 6, Max = 40, Default = tonumber(C.State.ChestCaptureRadius) or 22.0 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default end
            nv = tonumber(nv)
            if nv then C.State.ChestCaptureRadius = math.clamp(nv, 6, 40) end
        end
    })

    ExtraTab:Slider({
        Title = "Spawn detect radius (studs)",
        Min = 4,
        Max = 25,
        Default = tonumber(C.State.ChestSpawnRadius) or 10.0,
        Value = { Min = 4, Max = 25, Default = tonumber(C.State.ChestSpawnRadius) or 10.0 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default end
            nv = tonumber(nv)
            if nv then C.State.ChestSpawnRadius = math.clamp(nv, 4, 25) end
        end
    })

    bind(lp.CharacterAdded:Connect(function()
        task.wait(0.15)
        releaseAllCaptured()
    end))

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
        ensureHoverOff()
    end
    _G.__AutoChestExtra = api

    if C.State.Toggles.AutoChest then
        setAuto(true)
    end
end
