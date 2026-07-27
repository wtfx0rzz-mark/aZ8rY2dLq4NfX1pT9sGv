return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Extra, "extra.lua: missing context or Extra tab")

    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local WS = game:GetService("Workspace")
    local RunService = game:GetService("RunService")

    local lp = C.LocalPlayer or Players.LocalPlayer
    local ExtraTab = UI.Tabs.Extra

    local Tuning = {
        OPEN_CHEST_MAX_DISTANCE = 20.0,
        CHEST_RETRY_WAIT_SECONDS = 2.0,
        CHEST_CAPTURE_MAX_PER_POLL = 180,
        AUTO_STOP_IF_EMPTY_SECONDS = 8.0,
        STAND_UP = 2.5,
        CHEST_LOOT_RAY_OFF = 1.05,
        QuickOpenSettleWait = 0.05,
        QuickOpenStepDelay = 0.04,
        QuickCollectTeleportSettle = 0.05,
        QuickCollectStepDelay = 0.04,
        QuickPassGapDelay = 0.10,
        QuickEmptyWait = 1.0,
        QuickLastChestExtraWait = 0.60,
        QuickCollectPollInterval = 0.08,
        QuickCollectPollDuration = 0.35,
        MAX_CHEST_FAILED_ATTEMPTS = 3,
    }

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
        local items = WS:FindFirstChild("Items")
        if items then return items end

        local ugc = game:FindFirstChild("Ugc") or WS:FindFirstChild("Ugc")
        if ugc and ugc.Parent then
            local wroot = ugc:FindFirstChild("Workspace")
            if wroot and wroot.Parent then
                local it = wroot:FindFirstChild("Items")
                if it then return it end
            end
            local it2 = ugc:FindFirstChild("Items")
            if it2 then return it2 end
        end

        return nil
    end

    local function isUnderItems(inst, itemsRoot)
        if not (inst and inst.Parent and itemsRoot and itemsRoot.Parent) then return false end
        return inst == itemsRoot or inst:IsDescendantOf(itemsRoot)
    end

    local function isChestName(n)
        if type(n) ~= "string" then return false end
        return n:match("Chest%d*$") ~= nil or n:match("Chest$") ~= nil
    end

    local function isSnowChestName(n)
        if type(n) ~= "string" then return false end
        return (n == "Snow Chest") or (n:match("^Snow Chest%d+$") ~= nil)
    end

    local function snapshotInst(inst)
        local snap = {}
        if inst:IsA("BasePart") then
            snap[inst] = {
                CanCollide = inst.CanCollide,
                CanQuery   = inst.CanQuery,
                CanTouch   = inst.CanTouch,
                Massless   = inst.Massless,
            }
        else
            for _, d in ipairs(inst:GetDescendants()) do
                if d:IsA("BasePart") then
                    snap[d] = {
                        CanCollide = d.CanCollide,
                        CanQuery   = d.CanQuery,
                        CanTouch   = d.CanTouch,
                        Massless   = d.Massless,
                    }
                end
            end
        end
        return snap
    end

    local function setNoCollideAny(inst, on, snap)
        if not (inst and inst.Parent) then return end
        if inst:IsA("BasePart") then
            if on then
                inst.CanCollide = false
                inst.CanQuery   = false
                inst.CanTouch   = false
                inst.Massless   = true
                inst.AssemblyLinearVelocity  = Vector3.new()
                inst.AssemblyAngularVelocity = Vector3.new()
            else
                if snap and snap[inst] then
                    inst.CanCollide = snap[inst].CanCollide
                    inst.CanQuery   = snap[inst].CanQuery
                    inst.CanTouch   = snap[inst].CanTouch
                    inst.Massless   = snap[inst].Massless
                else
                    inst.CanCollide = true
                    inst.CanQuery   = true
                    inst.CanTouch   = true
                    inst.Massless   = false
                end
                inst.AssemblyLinearVelocity  = Vector3.new()
                inst.AssemblyAngularVelocity = Vector3.new()
            end
            return
        end
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then
                if on then
                    d.CanCollide = false
                    d.CanQuery   = false
                    d.CanTouch   = false
                    d.Massless   = true
                    d.AssemblyLinearVelocity  = Vector3.new()
                    d.AssemblyAngularVelocity = Vector3.new()
                else
                    if snap and snap[d] then
                        d.CanCollide = snap[d].CanCollide
                        d.CanQuery   = snap[d].CanQuery
                        d.CanTouch   = snap[d].CanTouch
                        d.Massless   = snap[d].Massless
                    else
                        d.CanCollide = true
                        d.CanQuery   = true
                        d.CanTouch   = true
                        d.Massless   = false
                    end
                    d.AssemblyLinearVelocity  = Vector3.new()
                    d.AssemblyAngularVelocity = Vector3.new()
                end
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

    local function resolveStopDragRemote()
        return getRemote("StopDraggingItem", "RequestStopDraggingItem", "StopDraggingItemRemote")
    end

    local function resolveStartDragRemote()
        return getRemote("RequestStartDraggingItem", "StartDraggingItem")
    end

    local function resolveOpenChestRemote()
        return getRemote("RequestOpenItemChest")
    end

    if _G.__AutoChestExtra and type(_G.__AutoChestExtra.Destroy) == "function" then
        pcall(function() _G.__AutoChestExtra.Destroy() end)
    end

    if C.State.Toggles.ChestTrack == nil then
        C.State.Toggles.ChestTrack = true
    end
    if C.State.Toggles.ChestRun == nil then
        C.State.Toggles.ChestRun = false
    end
    if C.State.Toggles.QuickChests == nil then
        C.State.Toggles.QuickChests = false
    end
    if C.State.Toggles.GrabNearby == nil then
        C.State.Toggles.GrabNearby = false
    end
    if C.State.Toggles.ItemSearch == nil then
        C.State.Toggles.ItemSearch = false
    end





    -- Quick Chests timing. Tweak these to change how fast the open pass and
    -- the revisit/collect pass move between chests.

    C.State.ChestWaitAfterTeleportBeforeOpen = 0.2
    C.State.ChestCollectWindowSeconds = 1.0
    C.State.ChestDelayAfterCollectionBeforeNext = 0.05
    C.State.ChestRetryWaitSeconds = Tuning.CHEST_RETRY_WAIT_SECONDS

    if not tonumber(C.State.ChestCaptureRadius) then
        C.State.ChestCaptureRadius = 22.00
    end
    if not tonumber(C.State.ChestSpawnRadius) then
        C.State.ChestSpawnRadius = 10.00
    end

    local UID_OPEN_KEY = tostring(lp.UserId) .. "Opened"

    local RF_Start = nil
    local RF_Stop = nil
    local function refreshDragRemotes()
        RF_Start = resolveStartDragRemote()
        RF_Stop  = resolveStopDragRemote()
    end
    refreshDragRemotes()

    local RF_OpenChest = nil
    local function refreshOpenChestRemote()
        RF_OpenChest = resolveOpenChestRemote()
    end
    refreshOpenChestRemote()

    local function fireOpenChest(chestModel)
        refreshOpenChestRemote()
        if not (RF_OpenChest and chestModel and chestModel.Parent) then return false end
        return pcall(function()
            RF_OpenChest:FireServer(chestModel)
        end)
    end

    local function getTakeRoots()
        local ugc = game:FindFirstChild("Ugc")
        if ugc and ugc:FindFirstChild("ReplicatedStorage") and ugc:FindFirstChild("Workspace") then
            return ugc.ReplicatedStorage, ugc.Workspace
        end
        return RS, WS
    end

    local ALWAYS_TAKE_NAMES = {
        ["Bandage"] = true,
        ["MedKit"] = true,
        ["Impact Grenade"] = true,
        ["Wildfire"] = true,
        ["Rifle Ammo"] = true,
    }

    local CONSUME_ITEM_NAMES = {
        ["Rifle Ammo"] = true,
    }

    local SPECIAL_TAKE_NAMES = {
        ["Strong Axe"] = true,
        ["Strong Flashlight"] = true,
        ["Giant Sack"] = true,
        ["Tactical Shotgun"] = true,
        ["Laser Cannon"] = true,
        ["Scythe"] = true,
        ["Rifle"] = true,
    }

    local function isSwordName(n)
        return type(n) == "string" and (n:find("Sword", 1, true) ~= nil)
    end


    local function invFolder()
        return lp:FindFirstChild("Inventory")
    end

    local function countInInventoryByName(itemName)
        local inv = invFolder()
        if not inv then return 0 end
        local n = 0
        for _,ch in ipairs(inv:GetChildren()) do
            if ch and ch.Name == itemName then
                n += 1
            end
        end
        return n
    end

    local function armourFolder()
        return lp:FindFirstChild("Armour")
    end

    local function getArmourValue()
        local okA, av = pcall(function() return lp:GetAttribute("Armour") end)
        if okA and type(av) == "number" then return av end
        local stats = lp:FindFirstChild("Stats")
        if stats then
            local nv = stats:FindFirstChild("Armour")
            if nv and nv:IsA("NumberValue") then return nv.Value end
        end
        local nv2 = lp:FindFirstChild("ArmourValue")
        if nv2 and nv2:IsA("NumberValue") then return nv2.Value end
        return nil
    end

    local function hasSpecialInInventory(itemName)
        local inv = invFolder()
        if not inv then return false end
        if isSwordName(itemName) then
            for _,ch in ipairs(inv:GetChildren()) do
                if ch and ch.Name and isSwordName(ch.Name) then
                    return true
                end
            end
            return false
        end
        for _,ch in ipairs(inv:GetChildren()) do
            if ch and ch.Name == itemName then
                return true
            end
        end
        return false
    end

    local function hasThornBodyOwned()
        local af = armourFolder()
        if af and af.Parent then
            local t = af:FindFirstChild("Thorn Body")
            if t and t.Parent then return true end
        end
        local inv = invFolder()
        if inv and inv.Parent then
            local t2 = inv:FindFirstChild("Thorn Body")
            if t2 and t2.Parent then return true end
        end
        return false
    end

    local function consumeItem(itemInst)
        if not (itemInst and itemInst.Parent) then return false end

        local itemsRoot = itemsFolder()
        if not (itemsRoot and isUnderItems(itemInst, itemsRoot)) then return false end

        local takeRS, _ = getTakeRoots()
        local rf = takeRS:FindFirstChild("RemoteEvents")
        if not rf then return false end
        local consumeRF = rf:FindFirstChild("RequestConsumeItem")
        if not consumeRF then return false end

        local ok = pcall(function()
            if consumeRF:IsA("RemoteFunction") then
                consumeRF:InvokeServer(itemInst)
            else
                consumeRF:FireServer(itemInst)
            end
        end)
        return ok
    end

    local function takeItemToInventory(itemInst)
        if not (itemInst and itemInst.Parent) then return false end

        if CONSUME_ITEM_NAMES[itemInst.Name] then
            if consumeItem(itemInst) then
                return true
            end
        end

        local itemsRoot = itemsFolder()
        if not (itemsRoot and isUnderItems(itemInst, itemsRoot)) then return false end

        local takeRS, _ = getTakeRoots()
        local rf = takeRS:FindFirstChild("RemoteEvents")
        if not rf then return false end
        local hotbarX = rf:FindFirstChild("RequestHotbarItem")
        local stopDragRE = rf:FindFirstChild("StopDraggingItem")
        if not hotbarX then return false end
        if not (stopDragRE and stopDragRE:IsA("RemoteEvent")) then return false end

        local okHotbar = pcall(function()
            if hotbarX:IsA("RemoteFunction") then
                hotbarX:InvokeServer(itemInst)
            else
                hotbarX:FireServer(itemInst)
            end
        end)
        if not okHotbar then return false end

        pcall(function() stopDragRE:FireServer(itemInst) end)
        RunService.Heartbeat:Wait()
        pcall(function() stopDragRE:FireServer(itemInst) end)
        return true
    end


    local function ensureArmourFolder()
        return lp:FindFirstChild("Armour") or lp:WaitForChild("Armour", 5)
    end

    local function waitForArmourChild(armourFolderInst, targetName, timeout)
        local got = armourFolderInst:FindFirstChild(targetName)
        if got then return got end

        local found = nil
        local conn
        conn = armourFolderInst.ChildAdded:Connect(function(ch)
            if ch and ch.Name == targetName then
                found = ch
            end
        end)

        local t0 = os.clock()
        while armourFolderInst.Parent and (not found) and (os.clock() - t0) < timeout do
            RunService.Heartbeat:Wait()
            local now = armourFolderInst:FindFirstChild(targetName)
            if now then
                found = now
                break
            end
        end

        pcall(function() conn:Disconnect() end)
        return found
    end

    local function getEquipArmourRemotes()
        local takeRS, _ = getTakeRoots()

        local function fromRoot(r)
            if not r then return nil, nil, nil end
            local re = r:FindFirstChild("RemoteEvents")
            if not re then return nil, nil, nil end
            local startRE = re:FindFirstChild("RequestStartDraggingItem") or re:FindFirstChild("StartDraggingItem")
            local stopRE  = re:FindFirstChild("StopDraggingItem") or re:FindFirstChild("RequestStopDraggingItem")
            local equipRF = re:FindFirstChild("RequestEquipArmour")
            return startRE, stopRE, equipRF
        end

        local startRE, stopRE, equipRF = fromRoot(takeRS)
        if not (startRE and stopRE and equipRF) then
            local s2, t2, e2 = fromRoot(RS)
            if not startRE then startRE = s2 end
            if not stopRE  then stopRE  = t2 end
            if not equipRF then equipRF = e2 end
        end

        if not startRE then startRE = RF_Start end
        if not stopRE  then stopRE  = RF_Stop  end

        return startRE, stopRE, equipRF
    end

    local lastThornEquipAt = 0

    local function tryEquipThornBody(worldInst)
        local targetName = "Thorn Body"

        local itemsRoot = itemsFolder()
        if worldInst and worldInst.Parent and itemsRoot and (not isUnderItems(worldInst, itemsRoot)) then
            worldInst = nil
        end

        local armourFolderInst = ensureArmourFolder()
        if not armourFolderInst then return false end

        local armourVal = getArmourValue()
        if type(armourVal) ~= "number" then armourVal = 0 end
        if armourVal > 0.4 then return true end

        local now = os.clock()
        if (now - lastThornEquipAt) < 1.5 then return false end

        local _, _, equipRF = getEquipArmourRemotes()
        if not equipRF then return false end

        local function callEquip(inst)
            return pcall(function()
                if equipRF:IsA("RemoteFunction") then
                    return equipRF:InvokeServer(inst)
                else
                    equipRF:FireServer(inst)
                    return true
                end
            end)
        end

        local function armourNowOk()
            local av = getArmourValue()
            if type(av) ~= "number" then av = 0 end
            return av > 0.4
        end

        if worldInst and worldInst.Parent then
            for i = 1, 3 do
                if not (worldInst and worldInst.Parent) then break end
                local ok, ret = callEquip(worldInst)
                RunService.Heartbeat:Wait()
                if ok and ret ~= false and (ret == true or armourNowOk()) then
                    lastThornEquipAt = os.clock()
                    return true
                end
                task.wait(0.10)
            end
        end

        local target = armourFolderInst:FindFirstChild(targetName) or waitForArmourChild(armourFolderInst, targetName, 2.0)
        if not (target and target.Parent) then return false end

        for i = 1, 3 do
            target = armourFolderInst:FindFirstChild(targetName) or target
            if not (target and target.Parent) then break end
            local ok, ret = callEquip(target)
            RunService.Heartbeat:Wait()
            if ok and ret ~= false and (ret == true or armourNowOk()) then
                lastThornEquipAt = os.clock()
                return true
            end
            task.wait(0.10)
        end

        return false
    end

    local alive = true
    local conns = {}
    local function bind(conn)
        conns[#conns+1] = conn
        return conn
    end

    local DragActive = {}

    local function safeStopDrag(m)
        refreshDragRemotes()
        if not (m and RF_Stop) then return false end
        return pcall(function() RF_Stop:FireServer(m) end)
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
            if (not m) or (not m.Parent) or (now - rec.t0) > 60.0 then
                dragTrackRelease(m)
            end
        end
    end))

    local overlapParams = OverlapParams.new()
    overlapParams.MaxParts = 1000

    local function refreshOverlapFilter()
        local items = itemsFolder()
        if items and items.Parent then
            overlapParams.FilterType = Enum.RaycastFilterType.Include
            overlapParams.FilterDescendantsInstances = { items }
        else
            overlapParams.FilterType = Enum.RaycastFilterType.Include
            overlapParams.FilterDescendantsInstances = {}
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
    local CapturedSnaps = {}


    local hoverConn = nil
    local function hoverFollow()
        local root = hrp()
        if not root then return end
        local forward = root.CFrame.LookVector
        local right = root.CFrame.RightVector
        local basePos = root.Position + Vector3.new(0, 10, 0) + forward * 1.5

        for i = #CapturedList, 1, -1 do
            local m = CapturedList[i]
            if m and m.Parent then
                dragKeepAlive(m)
                setAnchoredAny(m, true)

                local idx = i
                local a = idx * 2.399963229728653
                local r = math.min(0.75 + 0.08 * (idx - 1), 2.35)
                local waveY = math.sin((os.clock() * 1.35) + idx) * 0.25
                local off = (right * math.cos(a) + forward * math.sin(a)) * r + Vector3.new(0, waveY, 0)

                local pos = basePos + off
                local cf = CFrame.lookAt(pos, pos + forward)
                pivotAny(m, cf)
            else
                CapturedSet[m] = nil
                CapturedSnaps[m] = nil
                table.remove(CapturedList, i)
            end
        end

        if #CapturedList == 0 then
            if hoverConn then pcall(function() hoverConn:Disconnect() end) end
            hoverConn = nil
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

    local function addCaptured(m, snap)
        if CapturedSet[m] then return end
        CapturedSet[m] = true
        CapturedSnaps[m] = snap or {}
        CapturedList[#CapturedList+1] = m
        ensureHoverOn()
    end

    local function releaseAllCaptured()
        ensureHoverOff()
        refreshDragRemotes()
        for i = #CapturedList, 1, -1 do
            local m = CapturedList[i]
            if m and m.Parent then
                local snap = CapturedSnaps[m]
                setAnchoredAny(m, false)
                setNoCollideAny(m, false, snap)
                if RF_Stop then
                    pcall(function() RF_Stop:FireServer(m) end)
                end
                RunService.Heartbeat:Wait()
                if RF_Stop then
                    pcall(function() RF_Stop:FireServer(m) end)
                end
                task.delay(0.05, function() pcall(safeStopDrag, m) end)
                task.delay(0.20, function() pcall(safeStopDrag, m) end)
                task.delay(0.45, function() pcall(safeStopDrag, m) end)
                dragUntrack(m)
            end
            CapturedSet[m] = nil
            CapturedSnaps[m] = nil
            table.remove(CapturedList, i)
        end
        table.clear(CapturedList)
        for k,_ in pairs(CapturedSet) do CapturedSet[k] = nil end
        for k,_ in pairs(CapturedSnaps) do CapturedSnaps[k] = nil end
    end

    local function chestOpened(chestModel)
        if not chestModel then return false end
        local ok, v = pcall(function() return chestModel:GetAttribute(UID_OPEN_KEY) end)
        return ok and v == true
    end

    local EXCLUDE_NAMES = {
        ["Stronghold Diamond Chest"] = true,
        ["Mossy Chest"] = true,
    }

    local CHEST_LOOT_RAY_OFFSETS = {
        Vector3.new(0, 0, 0),
        Vector3.new( Tuning.CHEST_LOOT_RAY_OFF, 0, 0),
        Vector3.new(-Tuning.CHEST_LOOT_RAY_OFF, 0, 0),
        Vector3.new(0, 0,  Tuning.CHEST_LOOT_RAY_OFF),
        Vector3.new(0, 0, -Tuning.CHEST_LOOT_RAY_OFF),
        Vector3.new( Tuning.CHEST_LOOT_RAY_OFF, 0,  Tuning.CHEST_LOOT_RAY_OFF),
        Vector3.new( Tuning.CHEST_LOOT_RAY_OFF, 0, -Tuning.CHEST_LOOT_RAY_OFF),
        Vector3.new(-Tuning.CHEST_LOOT_RAY_OFF, 0,  Tuning.CHEST_LOOT_RAY_OFF),
        Vector3.new(-Tuning.CHEST_LOOT_RAY_OFF, 0, -Tuning.CHEST_LOOT_RAY_OFF),
    }


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

    local function makeLootRayParams(extras)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        local ex = { lp.Character }
        local map = WS:FindFirstChild("Map")
        if map then table.insert(ex, map) end
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
        local hit = WS:Raycast(start, Vector3.new(0, -80.0, 0), params)
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
        if EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name) then
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

        if hingePos then
            local v = (chestCenter - hingePos)
            if v.Magnitude < 1e-3 then v = -mp.CFrame.LookVector end
            addDir(v)
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
            local desired = chestCenter + dir * 4.0
            local floorPos = floorAtFromChestTop(m, chestTopY, desired)
            local standY = floorPos and (floorPos.Y + Tuning.STAND_UP) or (chestCenter.Y + Tuning.STAND_UP)
            local standPos = Vector3.new(desired.X, standY, desired.Z)
            if hasLineOfSightToChest(standPos, m, chestCenter) then
                bestCF = CFrame.new(standPos, chestCenter)
                break
            end
        end

        if not bestCF then
            local fallbackPos = chestCenter + (-mp.CFrame.LookVector) * 4.0
            local floorPos = floorAtFromChestTop(m, chestTopY, fallbackPos) or Vector3.new(fallbackPos.X, chestCenter.Y, fallbackPos.Z)
            local standPos = Vector3.new(fallbackPos.X, floorPos.Y + Tuning.STAND_UP, fallbackPos.Z)
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
                if not (EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name)) then
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
                if p and (p - dpos).Magnitude <= 15.0 then
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

    local failedAttempts = setmetatable({}, { __mode = "k" })
    local function giveUpOnChest(chest)
        if not chest then return end
        pcall(function() chest:SetAttribute(UID_OPEN_KEY, true) end)
        failedAttempts[chest] = nil
    end

    local function noteChestAttemptResult(chest, succeeded)
        if not chest then return end
        if succeeded then
            failedAttempts[chest] = nil
            return
        end
        local n = (failedAttempts[chest] or 0) + 1
        failedAttempts[chest] = n
        if n >= Tuning.MAX_CHEST_FAILED_ATTEMPTS then
            giveUpOnChest(chest)
        end
    end

    local function captureInst(inst, forceHover)
        if not (inst and inst.Parent) then return false end

        local itemsRoot = itemsFolder()
        if not (itemsRoot and isUnderItems(inst, itemsRoot)) then return false end

        if CapturedSet[inst] then return false end
        if isChestInst(inst) then return false end

        local n = inst.Name

        if not forceHover then
            if n == "Thorn Body" then
                if tryEquipThornBody(inst) then
                    return true
                end
            end

            if ALWAYS_TAKE_NAMES[n] then
                if takeItemToInventory(inst) then
                    return true
                end
            end

            local wantsTake = (SPECIAL_TAKE_NAMES[n] == true) or isSwordName(n)
            if wantsTake and (not hasSpecialInInventory(n)) then
                if takeItemToInventory(inst) then
                    return true
                end
            end
        end

        refreshDragRemotes()
        if not dragStart(inst) then return false end
        task.wait(0.06)
        local snap = snapshotInst(inst)
        setNoCollideAny(inst, true, nil)
        setAnchoredAny(inst, true)
        addCaptured(inst, snap)
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
            if not isUnderItems(inst, items) then return end
            if isChestInst(inst) then return end
            if isSnowChestName(inst.Name) then return end
            if seen[inst] then return end
            seen[inst] = true
            out[#out+1] = inst
        end
        if ok and type(parts) == "table" then
            for _,p in ipairs(parts) do
                if p and p.Parent and p:IsDescendantOf(items) then
                    local m = topModelUnderItems(p, items) or p
                    if m and m.Parent and (m:IsA("Model") or m:IsA("BasePart")) then
                        push(m)
                    end
                end
            end
        end
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

    local function lootRaycastCandidates(chest)
        if not (chest and chest.Parent and chest:IsA("Model")) then return {} end
        local mp = mainPart(chest)
        if not mp then return {} end

        local itemsRoot = itemsFolder()
        if not (itemsRoot and itemsRoot.Parent) then return {} end

        local chestCenter = mp.Position
        local chestTopY = mp.Position.Y + (mp.Size.Y * 0.5)
        local params = makeLootRayParams({ chest })
        local out = {}
        local seen = {}

        for i=1,#CHEST_LOOT_RAY_OFFSETS do
            local off = CHEST_LOOT_RAY_OFFSETS[i]
            local start = Vector3.new(chestCenter.X + off.X, chestTopY + 0.40, chestCenter.Z + off.Z)
            local hit = WS:Raycast(start, Vector3.new(0, 38.0, 0), params)
            if hit and hit.Instance and hit.Instance.Parent and hit.Instance:IsDescendantOf(itemsRoot) then
                local part = hit.Instance
                local cand = topModelUnderItems(part, itemsRoot) or part
                if cand and cand.Parent and (not seen[cand]) and isUnderItems(cand, itemsRoot) then
                    if not isChestInst(cand) then
                        seen[cand] = true
                        out[#out+1] = cand
                    end
                end
            end
        end

        return out
    end

    local function forwardWallRaycastCandidates(chest)
        local root = hrp()
        if not root then return {} end

        local itemsRoot = itemsFolder()
        if not (itemsRoot and itemsRoot.Parent) then return {} end

        local params = makeLootRayParams({ chest })
        local out = {}
        local seen = {}

        local chestPos = (chest and chest.Parent) and modelWorldPos(chest) or nil
        local capRad = math.max(tonumber(C.State.ChestCaptureRadius) or 22.0, (tonumber(C.State.ChestSpawnRadius) or 10.0) + 12.0)

        local forward = root.CFrame.LookVector
        local right = root.CFrame.RightVector
        local up = root.CFrame.UpVector
        local base = root.Position + forward * 1.25 + Vector3.new(0, 2.0, 0)

        local cols = math.max(1, tonumber(9) or 1)
        local rows = math.max(1, tonumber(7) or 1)
        local dx = (cols > 1) and ((8.0 * 2) / (cols - 1)) or 0
        local dy = (rows > 1) and ((5.0 * 2) / (rows - 1)) or 0

        local rayCount = 0
        for r = 0, rows - 1 do
            local y = -5.0 + (dy * r)
            for c = 0, cols - 1 do
                rayCount += 1
                if rayCount > 90 then break end

                local x = -8.0 + (dx * c)
                local start = base + right * x + up * y
                local hit = WS:Raycast(start, forward * 42.0, params)

                if hit and hit.Instance and hit.Instance.Parent and hit.Instance:IsDescendantOf(itemsRoot) then
                    local part = hit.Instance
                    local cand = topModelUnderItems(part, itemsRoot) or part

                    if cand and cand.Parent and (not seen[cand]) and isUnderItems(cand, itemsRoot) and (not isChestInst(cand)) then
                        local candPos = nil
                        if cand:IsA("BasePart") then
                            candPos = cand.Position
                        else
                            candPos = modelWorldPos(cand)
                        end

                        local okNear = true
                        if candPos and chestPos then
                            okNear = ((candPos - chestPos).Magnitude <= capRad)
                        elseif candPos then
                            okNear = ((candPos - root.Position).Magnitude <= capRad)
                        end

                        if okNear then
                            seen[cand] = true
                            out[#out+1] = cand
                        end
                    end
                end
            end
            if rayCount > 90 then break end
        end

        return out
    end

    local function processRaycastNewLoot(chest, preSet, maxCount)
        local cands = lootRaycastCandidates(chest)

        local wall = forwardWallRaycastCandidates(chest)
        if #wall > 0 then
            local seen = {}
            for i=1,#cands do
                local v = cands[i]
                if v then seen[v] = true end
            end
            for i=1,#wall do
                local inst = wall[i]
                if inst and (not seen[inst]) then
                    cands[#cands+1] = inst
                    seen[inst] = true
                end
            end
        end

        local didAny = 0
        for i=1,#cands do
            local inst = cands[i]
            if inst and inst.Parent and (not isChestInst(inst)) then
                local k = itemKey(inst)
                if not (preSet and preSet[k]) then
                    local did = false
                    local n = inst.Name

                    if n == "Thorn Body" then
                        did = (tryEquipThornBody(inst) and true or false)
                    elseif ALWAYS_TAKE_NAMES[n] then
                        did = takeItemToInventory(inst) and true or false
                    else
                        local wantsTake = (SPECIAL_TAKE_NAMES[n] == true) or isSwordName(n)
                        if wantsTake and (not hasSpecialInInventory(n)) then
                            did = takeItemToInventory(inst) and true or false
                        end
                    end

                    if (not did) and (not CapturedSet[inst]) then
                        if captureInst(inst) then
                            did = true
                        end
                    end

                    if did then
                        if preSet then preSet[k] = true end
                        didAny += 1
                        if maxCount and didAny >= maxCount then break end
                    end
                end
            end
        end
        return didAny
    end

    local function processAllNear(pos, rad, maxCount, forceHover)
        local cands = getCandidatesNear(pos, rad)
        local didAny = 0
        for i=1,#cands do
            local inst = cands[i]
            if inst and inst.Parent and (not isChestInst(inst)) then
                local n = inst.Name
                local did = false

                if not forceHover then
                    if n == "Thorn Body" then
                        did = (tryEquipThornBody(inst) and true or false)
                    elseif ALWAYS_TAKE_NAMES[n] then
                        did = takeItemToInventory(inst) and true or false
                    else
                        local wantsTake = (SPECIAL_TAKE_NAMES[n] == true) or isSwordName(n)
                        if wantsTake and (not hasSpecialInInventory(n)) then
                            did = takeItemToInventory(inst) and true or false
                        end
                    end
                end

                if (not did) and (not CapturedSet[inst]) then
                    if captureInst(inst, forceHover) then
                        did = true
                    end
                end

                if did then
                    didAny += 1
                    if maxCount and didAny >= maxCount then break end
                end
            end
        end
        return didAny
    end

    local function processNewSinceSnapshot(pos, rad, preSet, maxCount)
        local cands = getCandidatesNear(pos, rad)
        local didAny = 0
        for i=1,#cands do
            local inst = cands[i]
            if inst and inst.Parent and (not isChestInst(inst)) then
                local k = itemKey(inst)
                if not preSet[k] then
                    local n = inst.Name
                    local did = false

                    if n == "Thorn Body" then
                        did = (tryEquipThornBody(inst) and true or false)
                    elseif ALWAYS_TAKE_NAMES[n] then
                        did = takeItemToInventory(inst) and true or false
                    else
                        local wantsTake = (SPECIAL_TAKE_NAMES[n] == true) or isSwordName(n)
                        if wantsTake and (not hasSpecialInInventory(n)) then
                            did = takeItemToInventory(inst) and true or false
                        end
                    end

                    if (not did) and (not CapturedSet[inst]) then
                        if captureInst(inst) then
                            did = true
                        end
                    end

                    if did then
                        preSet[k] = true
                        didAny += 1
                        if maxCount and didAny >= maxCount then break end
                    end
                end
            end
        end
        return didAny
    end

    local function collectDropsForChest(chest, preSet)
        local gotAny = false

        local spawnRadius = math.max(tonumber(C.State.ChestSpawnRadius) or 10.0, 2.0)
        local captureRadius = math.max(tonumber(C.State.ChestCaptureRadius) or 22.0, spawnRadius + 12.0)
        local captureWindowMin = math.max(tonumber(C.State.ChestCollectWindowSeconds) or 1.0, 0.05)
        local captureWindowMax = math.max(3.0, captureWindowMin)

        local tOpen = os.clock()
        local tMinEnd = tOpen + captureWindowMin
        local tMaxEnd = tOpen + captureWindowMax
        local lastNewAt = tOpen

        while alive and chest and chest.Parent and os.clock() <= tMaxEnd do
            local pos = modelWorldPos(chest)
            local cap = 0
            if pos then
                cap = processNewSinceSnapshot(pos, captureRadius, preSet, Tuning.CHEST_CAPTURE_MAX_PER_POLL)
                if cap > 0 then
                    gotAny = true
                    lastNewAt = os.clock()
                end
            end

            local rayCap = processRaycastNewLoot(chest, preSet, Tuning.CHEST_CAPTURE_MAX_PER_POLL)
            if rayCap > 0 then
                gotAny = true
                lastNewAt = os.clock()
            end

            local now = os.clock()
            if now >= tMinEnd and (now - lastNewAt) >= 0.35 then
                break
            end

            local dt = now - tOpen
            local waitT = (dt <= 0.60) and 0.03 or 0.08
            task.wait(waitT)
        end

        local pos = modelWorldPos(chest)
        if pos then
            local cap = processNewSinceSnapshot(pos, captureRadius, preSet, Tuning.CHEST_CAPTURE_MAX_PER_POLL)
            if cap > 0 then gotAny = true end
        end
        local rayCapFinal = processRaycastNewLoot(chest, preSet, Tuning.CHEST_CAPTURE_MAX_PER_POLL)
        if rayCapFinal > 0 then gotAny = true end
        task.wait(0.05)

        return gotAny
    end

    local function chestsWithinDistance(centerPos, radius)
        local items = itemsFolder()
        if not items then return {} end
        local out = {}
        for _,m in ipairs(items:GetChildren()) do
            if m:IsA("Model") and isChestName(m.Name) then
                if not (EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name)) then
                    if not chestOpened(m) then
                        local p = modelWorldPos(m)
                        if p and (p - centerPos).Magnitude <= radius then
                            out[#out+1] = m
                        end
                    end
                end
            end
        end
        return out
    end

    local function openChestOnce(chest)
        if not (chest and chest.Parent) then return false end
        if EXCLUDE_NAMES[chest.Name] or isSnowChestName(chest.Name) then
            pcall(function() chest:SetAttribute(UID_OPEN_KEY, true) end)
            return false
        end

        attemptedAt[chest] = os.clock()

        local pos = modelWorldPos(chest)
        if not pos then
            pcall(function() chest:SetAttribute(UID_OPEN_KEY, true) end)
            return false
        end

        local root = hrp()
        if not root then return false end
        if (root.Position - pos).Magnitude > Tuning.OPEN_CHEST_MAX_DISTANCE then
            return false
        end

        local snapRad = math.max(math.max(tonumber(C.State.ChestCaptureRadius) or 22.0, tonumber(C.State.ChestSpawnRadius) or 10.0) + 16.0, 18.0)
        local preSet = snapshotNearChest(pos, snapRad)

        local nearbyChests = chestsWithinDistance(root.Position, Tuning.OPEN_CHEST_MAX_DISTANCE)
        if #nearbyChests == 0 then
            nearbyChests = { chest }
        end

        local firedAny = false
        for i=1,#nearbyChests do
            local c = nearbyChests[i]
            if fireOpenChest(c) then
                firedAny = true
                attemptedAt[c] = os.clock()
            end
        end

        if not firedAny then
            return false
        end

        local gotAny = collectDropsForChest(chest, preSet)
        pcall(function() chest:SetAttribute(UID_OPEN_KEY, true) end)
        for i=1,#nearbyChests do
            local c = nearbyChests[i]
            if c ~= chest then
                pcall(function() c:SetAttribute(UID_OPEN_KEY, true) end)
            end
        end
        return true, gotAny
    end

    local Tracked = {}
    local TrackedSet = {}
    local trackOn = false
    local runOn = false
    local trackLoop = nil
    local runner = nil

    local currentRunChest = nil
    local emptySince = 0

    local chestRunToggleObj = nil
    local _settingChestRunToggle = false
    local function setChestRunToggleUI(v)
        if not chestRunToggleObj then return false end
        _settingChestRunToggle = true
        local ok = pcall(function()
            if chestRunToggleObj.Set then
                chestRunToggleObj:Set(v)
            elseif chestRunToggleObj.SetValue then
                chestRunToggleObj:SetValue(v)
            elseif chestRunToggleObj.SetState then
                chestRunToggleObj:SetState(v)
            elseif chestRunToggleObj.Update then
                chestRunToggleObj:Update(v)
            end
        end)
        _settingChestRunToggle = false
        return ok
    end

    local function clearTracked()
        table.clear(Tracked)
        for k,_ in pairs(TrackedSet) do TrackedSet[k] = nil end
    end

    local function pruneTracked()
        for i = #Tracked, 1, -1 do
            local rec = Tracked[i]
            local m = rec and rec.model or nil
            if (not m) or (not m.Parent) or chestOpened(m) then
                if m then TrackedSet[m] = nil end
                table.remove(Tracked, i)
            end
        end
    end

    local function trackOnce()
        local items = itemsFolder()
        if not items then return end

        local chests = collectChestsSnapshot()
        if #chests > 0 then
            applyStrongholdExclusion(chests)
        end

        for i=1,#chests do
            local m = chests[i]
            if m and m.Parent and (not chestOpened(m)) and (not TrackedSet[m]) then
                local pos = modelWorldPos(m)
                if pos then
                    TrackedSet[m] = true
                    Tracked[#Tracked+1] = { model = m, pos = pos }
                end
            end
        end

        for i=1,#Tracked do
            local rec = Tracked[i]
            local m = rec and rec.model or nil
            if m and m.Parent then
                local p = modelWorldPos(m)
                if p then rec.pos = p end
            end
        end

        pruneTracked()

        local root = hrp()
        if root then
            local rpos = root.Position
            table.sort(Tracked, function(a, b)
                local ap = a and a.pos
                local bp = b and b.pos
                if not ap then return false end
                if not bp then return true end
                return (ap - rpos).Magnitude < (bp - rpos).Magnitude
            end)
        end
    end

    local function startTracking()
        if trackOn then return end
        trackOn = true
        clearTracked()
        trackOnce()
        if trackLoop then return end
        trackLoop = task.spawn(function()
            while alive and trackOn do
                pcall(trackOnce)
                task.wait(0.60)
            end
            trackLoop = nil
        end)
    end

    local function stopTracking()
        trackOn = false
        runOn = false
        clearTracked()
    end

    local function nextChestFromTracked()
        local root = hrp()
        if not root then return nil end
        pruneTracked()
        if #Tracked == 0 then return nil end

        local best, bestD = nil, math.huge
        local skipWindow = math.max(Tuning.CHEST_RETRY_WAIT_SECONDS, 1.0)
        local rpos = root.Position

        for i=1,#Tracked do
            local rec = Tracked[i]
            local m = rec and rec.model or nil
            if m and m.Parent and (not chestOpened(m)) then
                if not recentlyAttempted(m, skipWindow) then
                    local p = rec.pos or modelWorldPos(m)
                    if p then
                        local d = (p - rpos).Magnitude
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

    local function removeTrackedChest(chest)
        if not chest then return end
        TrackedSet[chest] = nil
        for i = #Tracked, 1, -1 do
            local rec = Tracked[i]
            if rec and rec.model == chest then
                table.remove(Tracked, i)
                return
            end
        end
    end

    local skipGui = nil
    local skipBtn = nil
    local function ensureSkipGui()
        if skipGui and skipGui.Parent then return end
        local pg = lp:FindFirstChild("PlayerGui")
        if not pg then return end

        local sg = Instance.new("ScreenGui")
        sg.Name = "__SkipChestGui"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        sg.Parent = pg

        local btn = Instance.new("TextButton")
        btn.Name = "SkipChestButton"
        btn.Parent = sg
        btn.Size = UDim2.new(0, 160, 0, 44)
        btn.Position = UDim2.new(1, -180, 1, -110)
        btn.AnchorPoint = Vector2.new(0, 0)
        btn.Text = "Skip Chest"
        btn.TextScaled = true
        btn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        btn.BorderSizePixel = 1
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.AutoButtonColor = true
        btn.Visible = false

        skipGui = sg
        skipBtn = btn
    end

    local function setSkipGuiVisible(on)
        ensureSkipGui()
        if skipBtn and skipBtn.Parent then
            skipBtn.Visible = on and true or false
        end
    end

    local function skipActiveOrClosestChest()
        if not (alive and runOn and trackOn) then return false end

        local active = currentRunChest
        if active and active.Parent then
            pcall(function() active:SetAttribute(UID_OPEN_KEY, true) end)
            attemptedAt[active] = os.clock()
            removeTrackedChest(active)
            currentRunChest = nil
            if #Tracked == 0 then
                if Tuning.AUTO_STOP_IF_EMPTY_SECONDS and Tuning.AUTO_STOP_IF_EMPTY_SECONDS > 0 then
                    runOn = false
                    C.State.Toggles.ChestRun = false
                    setSkipGuiVisible(false)
                    setChestRunToggleUI(false)
                end
            end
            return true
        end

        local root = hrp()
        if not root then return false end

        local items = itemsFolder()
        if not (items and items.Parent) then return false end

        local best, bestD = nil, 20.0
        local rpos = root.Position

        for _,m in ipairs(items:GetChildren()) do
            if m and m.Parent and m:IsA("Model") and isChestName(m.Name) then
                if not (EXCLUDE_NAMES[m.Name] or isSnowChestName(m.Name)) then
                    if not chestOpened(m) then
                        local p = modelWorldPos(m)
                        if p then
                            local d = (p - rpos).Magnitude
                            if d <= bestD then
                                bestD = d
                                best = m
                            end
                        end
                    end
                end
            end
        end

        if not (best and best.Parent) then return false end

        pcall(function() best:SetAttribute(UID_OPEN_KEY, true) end)
        attemptedAt[best] = os.clock()
        removeTrackedChest(best)
        currentRunChest = nil
        return true
    end

    local function wireSkipButton()
        ensureSkipGui()
        if not (skipBtn and skipBtn.Parent) then return end
        skipBtn.MouseButton1Click:Connect(function()
            pcall(skipActiveOrClosestChest)
        end)
    end
    wireSkipButton()

    local function startRun()
        if runOn then return end
        if not trackOn then return end
        runOn = true
        C.State.Toggles.ChestRun = true
        setSkipGuiVisible(true)
        currentRunChest = nil
        emptySince = 0
        if runner then return end

        runner = task.spawn(function()
            while alive and trackOn and runOn do
                local root = hrp()
                if not root then task.wait(0.25) continue end

                if #Tracked == 0 then
                    if Tuning.AUTO_STOP_IF_EMPTY_SECONDS and Tuning.AUTO_STOP_IF_EMPTY_SECONDS > 0 then
                        if emptySince == 0 then emptySince = os.clock() end
                        if (os.clock() - emptySince) >= Tuning.AUTO_STOP_IF_EMPTY_SECONDS then
                            runOn = false
                            C.State.Toggles.ChestRun = false
                            setSkipGuiVisible(false)
                            setChestRunToggleUI(false)
                            break
                        end
                    end
                    task.wait(0.30)
                    continue
                end

                emptySince = 0

                local chest = nextChestFromTracked()
                if not chest then
                    task.wait(0.25)
                    continue
                end

                currentRunChest = chest
                attemptedAt[chest] = os.clock()

                local okTp = teleportNearChest(chest)
                if not okTp then
                    noteChestAttemptResult(chest, false)
                    task.wait(0.20)
                    continue
                end

                local waitBeforeOpen = tonumber(C.State.ChestWaitAfterTeleportBeforeOpen) or 0.2
                if waitBeforeOpen > 0 then task.wait(waitBeforeOpen) end

                local okOpen = openChestOnce(chest)
                noteChestAttemptResult(chest, okOpen)
                if okOpen then
                    removeTrackedChest(chest)
                    currentRunChest = nil
                    local postDelay = tonumber(C.State.ChestDelayAfterCollectionBeforeNext) or 0.05
                    if postDelay > 0 then task.wait(postDelay) end
                else
                    local retryWait = tonumber(C.State.ChestRetryWaitSeconds) or Tuning.CHEST_RETRY_WAIT_SECONDS
                    if retryWait > 0 then task.wait(retryWait) end
                end
            end
            runner = nil
            currentRunChest = nil
        end)
    end

    local function stopRun()
        runOn = false
        C.State.Toggles.ChestRun = false
        setSkipGuiVisible(false)
        currentRunChest = nil
        emptySince = 0
    end

    local quickOn = false
    local quickLoop = nil
    local QuickVisited = {}

    local function quickOpenPass()
        table.clear(QuickVisited)
        while alive and quickOn and trackOn do
            pruneTracked()
            local chest = nextChestFromTracked()
            if not chest then break end

            currentRunChest = chest
            attemptedAt[chest] = os.clock()

            local okTp = teleportNearChest(chest)
            if okTp then
                if Tuning.QuickOpenSettleWait > 0 then task.wait(Tuning.QuickOpenSettleWait) end

                local root = hrp()
                local pos = modelWorldPos(chest)
                if root and pos and (root.Position - pos).Magnitude <= Tuning.OPEN_CHEST_MAX_DISTANCE then
                    local nearbyChests = chestsWithinDistance(root.Position, Tuning.OPEN_CHEST_MAX_DISTANCE)
                    if #nearbyChests == 0 then nearbyChests = { chest } end
                    for i=1,#nearbyChests do
                        local c = nearbyChests[i]
                        if fireOpenChest(c) then
                            attemptedAt[c] = os.clock()
                            pcall(function() c:SetAttribute(UID_OPEN_KEY, true) end)
                            local cpos = modelWorldPos(c)
                            if cpos then
                                QuickVisited[#QuickVisited+1] = cpos
                            end
                        end
                    end
                end
            end

            local succeeded = chestOpened(chest)
            noteChestAttemptResult(chest, succeeded)

            removeTrackedChest(chest)
            currentRunChest = nil

            pruneTracked()
            if #Tracked == 0 then
                if Tuning.QuickLastChestExtraWait > 0 then task.wait(Tuning.QuickLastChestExtraWait) end
            elseif Tuning.QuickOpenStepDelay > 0 then
                task.wait(Tuning.QuickOpenStepDelay)
            end
        end
    end

    local function quickSweepVisited()
        local captureRadius = tonumber(C.State.ChestCaptureRadius) or 22.0
        for i=1,#QuickVisited do
            if not (alive and quickOn) then break end
            local pos = QuickVisited[i]
            if pos then
                local cf = CFrame.new(pos + Vector3.new(0, Tuning.STAND_UP, 0), pos)
                teleportToCF(cf)
                if Tuning.QuickCollectTeleportSettle > 0 then task.wait(Tuning.QuickCollectTeleportSettle) end

                local tEnd = os.clock() + Tuning.QuickCollectPollDuration
                repeat
                    processAllNear(pos, captureRadius, Tuning.CHEST_CAPTURE_MAX_PER_POLL)
                    if os.clock() >= tEnd then break end
                    task.wait(Tuning.QuickCollectPollInterval)
                until (not (alive and quickOn))

                if Tuning.QuickCollectStepDelay > 0 then task.wait(Tuning.QuickCollectStepDelay) end
            end
        end
    end

    local function quickCollectPass()
        quickSweepVisited()
        table.clear(QuickVisited)
    end

    local quickEmptySince = 0
    local quickChestsToggleObj = nil
    local _settingQuickChestsToggle = false
    local function setQuickChestsToggleUI(v)
        if not quickChestsToggleObj then return false end
        _settingQuickChestsToggle = true
        local ok = pcall(function()
            if quickChestsToggleObj.Set then
                quickChestsToggleObj:Set(v)
            elseif quickChestsToggleObj.SetValue then
                quickChestsToggleObj:SetValue(v)
            elseif quickChestsToggleObj.SetState then
                quickChestsToggleObj:SetState(v)
            elseif quickChestsToggleObj.Update then
                quickChestsToggleObj:Update(v)
            end
        end)
        _settingQuickChestsToggle = false
        return ok
    end

    local function startQuickChests()
        if quickOn then return end
        quickOn = true
        C.State.Toggles.QuickChests = true
        if not trackOn then
            startTracking()
        end
        quickEmptySince = 0
        if quickLoop then return end
        quickLoop = task.spawn(function()
            while alive and quickOn do
                quickOpenPass()
                if Tuning.QuickPassGapDelay > 0 then task.wait(Tuning.QuickPassGapDelay) end
                quickCollectPass()
                if Tuning.QuickPassGapDelay > 0 then task.wait(Tuning.QuickPassGapDelay) end
                if #Tracked == 0 then
                    if Tuning.AUTO_STOP_IF_EMPTY_SECONDS and Tuning.AUTO_STOP_IF_EMPTY_SECONDS > 0 then
                        if quickEmptySince == 0 then quickEmptySince = os.clock() end
                        if (os.clock() - quickEmptySince) >= Tuning.AUTO_STOP_IF_EMPTY_SECONDS then
                            quickOn = false
                            C.State.Toggles.QuickChests = false
                            setQuickChestsToggleUI(false)
                            break
                        end
                    end
                    task.wait(Tuning.QuickEmptyWait)
                else
                    quickEmptySince = 0
                end
            end
            quickLoop = nil
        end)
    end

    local function stopQuickChests()
        quickOn = false
        C.State.Toggles.QuickChests = false
        quickEmptySince = 0
    end

    local grabOn = false
    local grabLoop = nil

    local function startGrabNearby()
        if grabOn then return end
        grabOn = true
        C.State.Toggles.GrabNearby = true
        if grabLoop then return end
        grabLoop = task.spawn(function()
            while alive and grabOn do
                local root = hrp()
                if root then
                    processAllNear(root.Position, 10.0, 80, true)
                end
                task.wait(0.35)
            end
            grabLoop = nil
        end)
    end

    local function stopGrabNearby()
        grabOn = false
        C.State.Toggles.GrabNearby = false
    end

    local itemSearchOn = false
    local itemSearchLoop = nil

    local function isSearchTargetName(n)
        if n == "Thorn Body" then return true end
        if ALWAYS_TAKE_NAMES[n] then return true end
        if SPECIAL_TAKE_NAMES[n] == true then return true end
        if isSwordName(n) then return true end
        return false
    end

    local function needsSearchItem(n)
        if n == "Thorn Body" then
            return (not hasThornBodyOwned())
        end
        if n == "Bandage" then
            return countInInventoryByName("Bandage") < 10
        end
        if n == "MedKit" then
            return countInInventoryByName("MedKit") < 5
        end
        if ALWAYS_TAKE_NAMES[n] then
            return true
        end
        if isSwordName(n) then
            return (not hasSpecialInInventory(n))
        end
        return (not hasSpecialInInventory(n))
    end

    local function findNearestSearchTarget()
        local items = itemsFolder()
        local root = hrp()
        if not (items and root) then return nil end

        local best, bestD = nil, math.huge
        for _,m in ipairs(items:GetChildren()) do
            if (m:IsA("Model") or m:IsA("BasePart")) and m.Parent and (not isChestInst(m)) then
                local n = m.Name
                if isSearchTargetName(n) and needsSearchItem(n) then
                    local mp = mainPart(m)
                    if mp then
                        local d = (mp.Position - root.Position).Magnitude
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

    local function itemSearchTick()
        local target = findNearestSearchTarget()
        if not (target and target.Parent) then return end

        local n = target.Name

        if n == "Thorn Body" then
            pcall(function()
                tryEquipThornBody(target)
            end)
            return
        end

        if n == "Bandage" then
            if countInInventoryByName("Bandage") < 10 then
                pcall(function() takeItemToInventory(target) end)
            end
            return
        end

        if n == "MedKit" then
            if countInInventoryByName("MedKit") < 5 then
                pcall(function() takeItemToInventory(target) end)
            end
            return
        end

        if ALWAYS_TAKE_NAMES[n] then
            pcall(function() takeItemToInventory(target) end)
            return
        end

        local wantsTake = (SPECIAL_TAKE_NAMES[n] == true) or isSwordName(n)
        if wantsTake and (not hasSpecialInInventory(n)) then
            pcall(function() takeItemToInventory(target) end)
        end
    end

    local function startItemSearch()
        if itemSearchOn then return end
        itemSearchOn = true
        C.State.Toggles.ItemSearch = true
        if itemSearchLoop then return end
        itemSearchLoop = task.spawn(function()
            while alive and itemSearchOn do
                pcall(itemSearchTick)
                task.wait(0.75)
            end
            itemSearchLoop = nil
        end)
    end

    local function stopItemSearch()
        itemSearchOn = false
        C.State.Toggles.ItemSearch = false
    end

    ExtraTab:Section({ Title = "Chests" })

    ExtraTab:Toggle({
        Title = "Track Chests",
        Value = C.State.Toggles.ChestTrack,
        Callback = function(on)
            C.State.Toggles.ChestTrack = on
            if on then
                startTracking()
            else
                stopRun()
                stopQuickChests()
                stopTracking()
            end
        end
    })

    chestRunToggleObj = ExtraTab:Toggle({
        Title = "Chest Run",
        Value = C.State.Toggles.ChestRun,
        Callback = function(on)
            if _settingChestRunToggle then
                C.State.Toggles.ChestRun = on
                return
            end
            C.State.Toggles.ChestRun = on
            if on then
                startRun()
            else
                stopRun()
            end
        end
    })

    quickChestsToggleObj = ExtraTab:Toggle({
        Title = "Quick Chests",
        Value = C.State.Toggles.QuickChests,
        Callback = function(on)
            if _settingQuickChestsToggle then
                C.State.Toggles.QuickChests = on
                return
            end
            C.State.Toggles.QuickChests = on
            if on then
                startQuickChests()
            else
                stopQuickChests()
            end
        end
    })

    ExtraTab:Button({
        Title = "Open Chest",
        Callback = function()
            local root = hrp()
            if not root then return end
            local nearby = chestsWithinDistance(root.Position, Tuning.OPEN_CHEST_MAX_DISTANCE)
            for i=1,#nearby do
                local c = nearby[i]
                if fireOpenChest(c) then
                    attemptedAt[c] = os.clock()
                end
            end
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

    ExtraTab:Section({ Title = "Items" })

    ExtraTab:Toggle({
        Title = "Item Search",
        Value = C.State.Toggles.ItemSearch,
        Callback = function(on)
            C.State.Toggles.ItemSearch = on
            if on then
                startItemSearch()
            else
                stopItemSearch()
            end
        end
    })

    ExtraTab:Section({ Title = "Nearby Items" })

    ExtraTab:Button({
        Title = "Start Grab Nearby (10 studs)",
        Callback = function()
            startGrabNearby()
        end
    })

    ExtraTab:Button({
        Title = "Stop Grab Nearby",
        Callback = function()
            stopGrabNearby()
        end
    })

    ExtraTab:Button({
        Title = "Drop All Captured Items",
        Callback = function()
            stopGrabNearby()
            releaseAllCaptured()
        end
    })

    bind(lp.CharacterAdded:Connect(function()
        task.wait(0.25)
        refreshOverlapFilter()
        if #CapturedList > 0 then
            ensureHoverOn()
        else
            ensureHoverOff()
        end
        if runOn then
            setSkipGuiVisible(true)
        else
            setSkipGuiVisible(false)
        end
    end))

    local api = {}
    function api.Destroy()
        alive = false
        stopRun()
        stopQuickChests()
        stopTracking()
        stopGrabNearby()
        stopItemSearch()
        releaseAllCaptured()
        for i=1,#conns do
            local c = conns[i]
            if c and c.Disconnect then pcall(function() c:Disconnect() end) end
        end
        conns = {}
        ensureHoverOff()
        if skipGui and skipGui.Parent then pcall(function() skipGui:Destroy() end) end
        skipGui = nil
        skipBtn = nil
        currentRunChest = nil
        emptySince = 0
    end
    _G.__AutoChestExtra = api

    if C.State.Toggles.ChestTrack then
        startTracking()
        if C.State.Toggles.ChestRun then
            startRun()
        else
            setSkipGuiVisible(false)
        end
    else
        setSkipGuiVisible(false)
    end

    if C.State.Toggles.QuickChests then
        startQuickChests()
    end

    if C.State.Toggles.GrabNearby then
        startGrabNearby()
    end

    if C.State.Toggles.ItemSearch then
        startItemSearch()
    end
end
