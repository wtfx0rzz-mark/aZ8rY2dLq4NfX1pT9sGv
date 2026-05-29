return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local Run     = C.Services.Run or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab = Tabs.AutoFeed
    if not tab then return end

    C.State = C.State or {}

    local REFILL_INTERVAL = 1.5
    local FEED_THRESHOLD  = 200
    local FEED_TARGET     = 350
    local FUEL_MAX        = 674
    local BAR2_MIN = 0.484
    local BAR2_MAX = 7.100

    local PILE_SCAN_RADIUS = 50
    local FEED_SPEED = 80

    local ORB_OFFSET_Y = 30
    local VERTICAL_MULT = 1.35
    local STEP_WAIT = 0.03
    local CONSUME_WAIT = 2.5
    local JOB_TIMEOUT = 45
    local DEST_RADIUS = 1.0
    local FINAL_DROP_HEIGHT = 4.0

    local PER_ITEM_ACTIVE_LIMIT = {
        ["Log"] = 8,
        ["Biofuel"] = 8,
        ["Coal"] = 4,
        ["Fuel Canister"] = 2,
        ["Oil Barrel"] = 1
    }

    local FUEL_PRIORITY = {
        "Biofuel",
        "Coal",
        "Fuel Canister",
        "Oil Barrel",
        "Log"
    }

    local FUEL_ITEMS = {
        ["Biofuel"] = true,
        ["Coal"] = true,
        ["Fuel Canister"] = true,
        ["Oil Barrel"] = true,
        ["Log"] = true
    }

    local running = false
    local feedThread = nil
    local pilePos = nil

    local ActiveDrags = {}
    local ReservedItems = setmetatable({}, { __mode = "k" })

    local function now()
        return os.clock()
    end

    local function hrp()
        local ch = lp.Character
        return ch and ch:FindFirstChild("HumanoidRootPart")
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

    local function physicalRootPart(model)
        if not model or not model.Parent then return nil end
        if model:IsA("BasePart") then return model end
        if not model:IsA("Model") then return mainPart(model) end
        local main = model:FindFirstChild("Main", true)
        if main and main:IsA("BasePart") then return main end
        if model.PrimaryPart then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function getAllParts(target)
        local t = {}
        if not target then return t end
        if target:IsA("BasePart") then
            t[1] = target
        elseif target:IsA("Model") then
            for _, d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then
                    t[#t + 1] = d
                end
            end
        end
        return t
    end

    local function zeroAssembly(model)
        for _, p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function setCollide(model, on, snapshot)
        local parts = getAllParts(model)
        if on and snapshot then
            for part, can in pairs(snapshot) do
                if part and part.Parent then
                    part.CanCollide = can
                end
            end
            return
        end
        local snap = {}
        for _, p in ipairs(parts) do
            snap[p] = p.CanCollide
            p.CanCollide = false
        end
        return snap
    end

    local function severeExternalWelds(model)
        if not model or not model.Parent then return end
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                local p0 = d.Part0
                local p1 = d.Part1
                if (p0 and not p0:IsDescendantOf(model)) or (p1 and not p1:IsDescendantOf(model)) then
                    pcall(function() d:Destroy() end)
                end
            end
            if d:IsA("BasePart") and d.Anchored then
                pcall(function() d.Anchored = false end)
            end
        end
        if model:IsA("BasePart") and model.Anchored then
            pcall(function() model.Anchored = false end)
        end
    end

    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents")
        if not re then return nil end
        for _, n in ipairs({...}) do
            local x = re:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local function getRemotes()
        return {
            StartDrag = getRemote("RequestStartDraggingItem", "StartDraggingItem"),
            StopDrag  = getRemote("StopDraggingItem", "RequestStopDraggingItem"),
            BurnItem  = getRemote("RequestAmmoFurnaceBurnItem")
        }
    end

    local function safeStartDrag(r, model)
        if r and r.StartDrag and model and model.Parent then
            local ok = pcall(function() r.StartDrag:FireServer(model) end)
            return ok
        end
        return false
    end

    local function safeStopDrag(r, model)
        if r and r.StopDrag and model then
            local ok = pcall(function() r.StopDrag:FireServer(model) end)
            return ok
        end
        return false
    end

    local function stopDragHard(r, model)
        pcall(safeStopDrag, r, model)
        Run.Heartbeat:Wait()
        pcall(safeStopDrag, r, model)
        task.delay(0.05, function() pcall(safeStopDrag, r, model) end)
        task.delay(0.20, function() pcall(safeStopDrag, r, model) end)
    end

    local function setNetworkOwnerLocal(model)
        for _, p in ipairs(getAllParts(model)) do
            pcall(function() p:SetNetworkOwner(lp) end)
        end
    end

    local function restoreNetworkOwner(model)
        for _, p in ipairs(getAllParts(model)) do
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function()
                if p.SetNetworkOwnershipAuto then
                    p:SetNetworkOwnershipAuto()
                end
            end)
        end
    end

    local function refreshPrompts(model)
        if not model then return end
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local was = d.Enabled
                d.Enabled = false
                task.defer(function()
                    if d and d.Parent then d.Enabled = was ~= false end
                end)
            end
        end
    end

    local function isConsumed(model)
        if not model then return true end
        if not model.Parent then return true end
        if not model:IsDescendantOf(WS) then return true end
        if not mainPart(model) then return true end
        if model:GetAttribute("Consumed") == true then return true end
        return false
    end

    local function setPivot(model, cf)
        if not model or not model.Parent then return end
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model)
            if p then p.CFrame = cf end
        end
    end

    local function getPivot(model)
        if not model or not model.Parent then return nil end
        if model:IsA("Model") then return model:GetPivot() end
        local p = mainPart(model)
        return p and p.CFrame or nil
    end

    local function bboxHeight(model)
        local rp = physicalRootPart(model)
        if rp then return math.max(0.5, rp.Size.Y) end
        local minY, maxY = nil, nil
        for _, p in ipairs(getAllParts(model)) do
            local y0 = p.Position.Y - p.Size.Y * 0.5
            local y1 = p.Position.Y + p.Size.Y * 0.5
            if not minY or y0 < minY then minY = y0 end
            if not maxY or y1 > maxY then maxY = y1 end
        end
        if minY and maxY then return math.max(0.5, maxY - minY) end
        return 2
    end

    local function findGenerator()
        local map = WS:FindFirstChild("Map")
        local landmarks = map and map:FindFirstChild("Landmarks")
        if not landmarks then return nil end
        for _, child in ipairs(landmarks:GetChildren()) do
            local nl = child.Name:lower()
            if nl:find("cultist", 1, true) and (nl:find("generator", 1, true) or nl:find("base", 1, true)) then
                local ext = child:FindFirstChild("GeneratorExtension", true)
                if ext then return ext end
            end
        end
        return nil
    end

    local function findFurnace2(ext)
        local extraBits = ext and ext:FindFirstChild("ExtraBits")
        local furnace = extraBits and extraBits:FindFirstChild("Furnace")
        return furnace and furnace:FindFirstChild("Furnace2")
    end

    local function findBar2(ext)
        local extraBits = ext and ext:FindFirstChild("ExtraBits")
        local bars = extraBits and extraBits:FindFirstChild("Bars")
        return bars and bars:FindFirstChild("Bar2")
    end

    local function readFuel(ext, bar2)
        local attr = ext and ext:GetAttribute("FuelRemaining")
        if attr ~= nil and attr > 0 then return attr end
        if bar2 and bar2.Parent then
            local x = bar2.Size.X
            local pct = math.clamp((x - BAR2_MIN) / (BAR2_MAX - BAR2_MIN), 0, 1)
            return math.floor(pct * FUEL_MAX)
        end
        return 0
    end

    local function currentFuel()
        local ext = findGenerator()
        if not ext then return nil, nil, nil, nil end
        local furnace2 = findFurnace2(ext)
        if not furnace2 then return nil, ext, nil, nil end
        local bar2 = findBar2(ext)
        return readFuel(ext, bar2), ext, furnace2, bar2
    end

    local function requestMoreStreamingAround(posList)
        if not WS.StreamingEnabled then return end
        local seen = {}
        for _, pos in ipairs(posList) do
            if typeof(pos) == "Vector3" then
                local key = math.floor(pos.X / 64) .. "|" .. math.floor(pos.Z / 64)
                if not seen[key] then
                    seen[key] = true
                    pcall(function() WS:RequestStreamAroundAsync(pos) end)
                end
            end
        end
        task.wait(0.12)
    end

    local function isFuelItem(m)
        return m and m:IsA("Model") and FUEL_ITEMS[m.Name] and mainPart(m) ~= nil
    end

    local function isNearPile(item)
        if not pilePos then return false end
        local mp = mainPart(item)
        if not mp then return false end
        return (mp.Position - pilePos).Magnitude <= PILE_SCAN_RADIUS
    end

    local function getPileItemsByPriority()
        local foundByName = {}
        for _, name in ipairs(FUEL_PRIORITY) do
            foundByName[name] = {}
        end
        local seen = {}
        for _, d in ipairs(WS:GetDescendants()) do
            if isFuelItem(d) and not seen[d] and not ActiveDrags[d] and not ReservedItems[d] and isNearPile(d) then
                seen[d] = true
                foundByName[d.Name][#foundByName[d.Name] + 1] = d
            end
        end
        if pilePos then
            for _, name in ipairs(FUEL_PRIORITY) do
                table.sort(foundByName[name], function(a, b)
                    local ap = mainPart(a)
                    local bp = mainPart(b)
                    local ad = ap and (ap.Position - pilePos).Magnitude or math.huge
                    local bd = bp and (bp.Position - pilePos).Magnitude or math.huge
                    return ad < bd
                end)
            end
        end
        local out = {}
        for _, name in ipairs(FUEL_PRIORITY) do
            for _, item in ipairs(foundByName[name]) do
                out[#out + 1] = item
            end
        end
        return out
    end

    local function getAmmoOrbCF(furnacePart)
        return furnacePart.CFrame + Vector3.new(0, ORB_OFFSET_Y, 0)
    end

    local function getFinalTargetPos(furnacePart)
        return furnacePart.Position + Vector3.new(0, FINAL_DROP_HEIGHT, 0)
    end

    local function fireAmmoBurnRemote(r, ext)
        if r and r.BurnItem and ext then
            pcall(function() r.BurnItem:FireServer(ext, Instance.new("Model")) end)
        end
    end

    local function markActive(model, r, snap, started)
        ActiveDrags[model] = { r = r, snap = snap, started = started }
    end

    local function clearActive(model)
        ActiveDrags[model] = nil
    end

    local function stopActiveItem(model, rec)
        if not model then return end
        local r = rec and rec.r or getRemotes()
        pcall(function() stopDragHard(r, model) end)
        if model and model.Parent then
            if rec and rec.snap then
                pcall(function() setCollide(model, true, rec.snap) end)
            end
            for _, p in ipairs(getAllParts(model)) do
                pcall(function() p.Anchored = false end)
            end
            pcall(function() restoreNetworkOwner(model) end)
            pcall(function() refreshPrompts(model) end)
        end
    end

    local function moveVisibleConveyor(model, orbPos, finalPos, speed, r, ext)
        if not running then return false end
        if not model or not model.Parent then return false end

        severeExternalWelds(model)

        local mp = mainPart(model)
        if not mp then return false end

        local started = safeStartDrag(r, model)
        local H = bboxHeight(model)
        local riserY = orbPos.Y - 1.0 + math.clamp(H * 0.45, 0.8, 3.0)
        local lookDir = Vector3.new(orbPos.X, mp.Position.Y, orbPos.Z) - mp.Position
        lookDir = lookDir.Magnitude > 0.001 and lookDir.Unit or Vector3.zAxis

        local snapOrig = setCollide(model, false)
        markActive(model, r, snapOrig, started)
        zeroAssembly(model)
        setNetworkOwnerLocal(model)

        local t0 = now()

        while running and model and model.Parent do
            if now() - t0 > JOB_TIMEOUT then break end
            if isConsumed(model) then
                if started then stopDragHard(r, model) end
                clearActive(model)
                restoreNetworkOwner(model)
                return true
            end
            local pivot = getPivot(model)
            if not pivot then break end
            local pos = pivot.Position
            local dy = riserY - pos.Y
            if math.abs(dy) <= 0.4 then break end
            local stepY = math.sign(dy) * math.min(speed * VERTICAL_MULT * STEP_WAIT, math.abs(dy))
            local newPos = Vector3.new(pos.X, pos.Y + stepY, pos.Z)
            setPivot(model, CFrame.new(newPos, newPos + lookDir))
            zeroAssembly(model)
            Run.Heartbeat:Wait()
            task.wait(STEP_WAIT)
        end

        while running and model and model.Parent do
            if now() - t0 > JOB_TIMEOUT then break end
            if isConsumed(model) then
                if started then stopDragHard(r, model) end
                clearActive(model)
                restoreNetworkOwner(model)
                return true
            end
            local pivot = getPivot(model)
            if not pivot then break end
            local pos = pivot.Position
            local delta = Vector3.new(orbPos.X - pos.X, 0, orbPos.Z - pos.Z)
            local dist = delta.Magnitude
            if dist <= DEST_RADIUS then break end
            local step = math.min(speed * STEP_WAIT, dist)
            local dir = delta.Unit
            local newPos = Vector3.new(pos.X, riserY, pos.Z) + dir * step
            setPivot(model, CFrame.new(newPos, newPos + dir))
            zeroAssembly(model)
            Run.Heartbeat:Wait()
            task.wait(STEP_WAIT)
        end

        while running and model and model.Parent do
            if now() - t0 > JOB_TIMEOUT then break end
            if isConsumed(model) then
                if started then stopDragHard(r, model) end
                clearActive(model)
                restoreNetworkOwner(model)
                return true
            end
            local pivot = getPivot(model)
            if not pivot then break end
            local pos = pivot.Position
            local delta = finalPos - pos
            local dist = delta.Magnitude
            if dist <= 0.55 then break end
            local step = math.min(speed * VERTICAL_MULT * STEP_WAIT, dist)
            local dir = delta.Unit
            local newPos = pos + dir * step
            setPivot(model, CFrame.new(newPos, finalPos))
            zeroAssembly(model)
            Run.Heartbeat:Wait()
            task.wait(STEP_WAIT)
        end

        if model and model.Parent then
            setCollide(model, true, snapOrig)
            setPivot(model, CFrame.new(finalPos))
            for _, p in ipairs(getAllParts(model)) do
                p.Anchored = false
                p.AssemblyLinearVelocity = Vector3.new(0, -18, 0)
                p.AssemblyAngularVelocity = Vector3.new()
            end
        end

        fireAmmoBurnRemote(r, ext)

        local waitStart = now()
        while running and model and model.Parent and now() - waitStart < CONSUME_WAIT do
            if isConsumed(model) then
                if started then stopDragHard(r, model) end
                clearActive(model)
                restoreNetworkOwner(model)
                return true
            end
            Run.Heartbeat:Wait()
            task.wait(STEP_WAIT)
        end

        if started then stopDragHard(r, model) end
        if model and model.Parent then
            restoreNetworkOwner(model)
            refreshPrompts(model)
            pcall(function()
                model:SetAttribute("AmmoFeedInFlightAt", nil)
                model:SetAttribute("AmmoFeedJob", nil)
            end)
        end
        clearActive(model)
        return true
    end

    local function shouldMoveItems()
        local fuel = currentFuel()
        return fuel ~= nil and fuel <= FEED_THRESHOLD
    end

    local function getActiveLimitForItem(item)
        if item and PER_ITEM_ACTIVE_LIMIT[item.Name] then
            return PER_ITEM_ACTIVE_LIMIT[item.Name]
        end
        return 1
    end

    local function feedWorker()
        while running do
            if pilePos and shouldMoveItems() then
                local fuel, ext, furnace2, bar2 = currentFuel()
                if fuel and ext and furnace2 and bar2 and fuel < FEED_TARGET then
                    local furnacePart = mainPart(furnace2)
                    local r = getRemotes()
                    if furnacePart and r.StartDrag and r.StopDrag then
                        requestMoreStreamingAround({ pilePos, furnacePart.Position })
                        local orbPos = getAmmoOrbCF(furnacePart).Position
                        local finalPos = getFinalTargetPos(furnacePart)
                        local pileItems = getPileItemsByPriority()

                        for _, priorityName in ipairs(FUEL_PRIORITY) do
                            if not running then break end
                            if not shouldMoveItems() then break end
                            local latestFuel = readFuel(ext, bar2)
                            if latestFuel >= FEED_TARGET then break end

                            local active = 0

                            for _, item in ipairs(pileItems) do
                                if not running then break end
                                if not shouldMoveItems() then break end
                                latestFuel = readFuel(ext, bar2)
                                if latestFuel >= FEED_TARGET then break end

                                if item and item.Parent and item.Name == priorityName and isFuelItem(item) and isNearPile(item) and not ActiveDrags[item] and not ReservedItems[item] then
                                    local activeLimit = getActiveLimitForItem(item)
                                    while active >= activeLimit and running do
                                        Run.Heartbeat:Wait()
                                    end
                                    ReservedItems[item] = true
                                    active = active + 1
                                    task.spawn(function()
                                        moveVisibleConveyor(item, orbPos, finalPos, FEED_SPEED, r, ext)
                                        ReservedItems[item] = nil
                                        active = active - 1
                                    end)
                                    task.wait(0.35)
                                end
                            end

                            local deadline = now() + 20
                            while active > 0 and running and now() < deadline do
                                task.wait(0.05)
                            end

                            latestFuel = readFuel(ext, bar2)
                            if latestFuel >= FEED_TARGET then break end
                        end
                    end
                end
            end
            task.wait(REFILL_INTERVAL)
        end
    end

    local function stopAllOutstandingDrags()
        local copy = {}
        for model, rec in pairs(ActiveDrags) do
            copy[model] = rec
        end
        ActiveDrags = {}
        for model, rec in pairs(copy) do
            stopActiveItem(model, rec)
        end
        ReservedItems = setmetatable({}, { __mode = "k" })
    end

    local function stopLoop()
        running = false
        if feedThread then
            pcall(function() task.cancel(feedThread) end)
            feedThread = nil
        end
        stopAllOutstandingDrags()
    end

    local function startLoop()
        if running then return end
        local root = hrp()
        if not root then
            warn("[AutoFeed] HumanoidRootPart not found")
            return
        end
        local ext = findGenerator()
        if not ext then
            warn("[AutoFeed] GeneratorExtension not found")
            return
        end
        local furnace2 = findFurnace2(ext)
        if not furnace2 then
            warn("[AutoFeed] Furnace2 not found")
            return
        end
        pilePos = root.Position
        ActiveDrags = {}
        ReservedItems = setmetatable({}, { __mode = "k" })
        running = true
        local furnacePart = mainPart(furnace2)
        requestMoreStreamingAround({ pilePos, furnacePart and furnacePart.Position or nil })
        feedThread = task.spawn(feedWorker)
    end

    tab:Section({ Title = "Generator Auto Feed" })

    tab:Toggle({
        Title   = "Auto Feed For Ammo",
        Default = C.State.AutoFeedEnabled and true or false,
        Callback = function(state)
            C.State.AutoFeedEnabled = state and true or false
            if state then startLoop() else stopLoop() end
        end
    })

    tab:Button({
        Title = "Feed Now",
        Callback = function()
            if running then return end
            local root = hrp()
            if not root then return end
            pilePos = root.Position
            ActiveDrags = {}
            ReservedItems = setmetatable({}, { __mode = "k" })
            running = true
            feedThread = task.spawn(feedWorker)
            task.delay(20, function()
                if running and not C.State.AutoFeedEnabled then
                    stopLoop()
                end
            end)
        end
    })

    if C.State.AutoFeedEnabled then
        startLoop()
    end

    -- ============================================================
    -- CAMPFIRE FEED
    -- ============================================================

    local CF_FUEL_MAX        = 3500
    local CF_FEED_THRESHOLD  = CF_FUEL_MAX * 0.50
    local CF_FEED_TARGET     = CF_FUEL_MAX * 0.90

    local CF_REFILL_INTERVAL      = 1.5
    local CF_FEED_SPEED           = 80
    local CF_ORB_OFFSET_Y         = 20
    local CF_VERTICAL_MULT        = 1.35
    local CF_STEP_WAIT            = 0.03
    local CF_CONSUME_WAIT         = 2.5
    local CF_JOB_TIMEOUT          = 45
    local CF_DEST_RADIUS          = 1.0
    local CF_FINAL_DROP_HEIGHT    = 6.0
    local CF_SPAWN_STAGGER        = 0.15
    local CF_FEED_NOW_LIMIT       = 50

    local CF_PROCESSOR_BATCH      = 50
    local CF_BIOFUEL_BATCH        = 50

    local CF_PER_ITEM_LIMIT = {
        ["Coal"]          = 8,
        ["Biofuel"]       = CF_BIOFUEL_BATCH,
        ["Fuel Canister"] = 3,
        ["Oil Barrel"]    = 1,
        ["Log"]           = CF_PROCESSOR_BATCH,
        ["Morsel"]        = CF_PROCESSOR_BATCH,
        ["Cooked Morsel"] = CF_PROCESSOR_BATCH,
        ["Steak"]         = CF_PROCESSOR_BATCH,
        ["Cooked Steak"]  = CF_PROCESSOR_BATCH,
        ["Carrot"]        = CF_PROCESSOR_BATCH,
        ["Corn"]          = CF_PROCESSOR_BATCH,
        ["Pumpkin"]       = CF_PROCESSOR_BATCH,
        ["Strawberry"]    = CF_PROCESSOR_BATCH,
        ["Apple"]         = CF_PROCESSOR_BATCH,
    }

    local CF_DIRECT_FIRE_ITEMS = {
        ["Coal"]          = true,
        ["Biofuel"]       = true,
        ["Fuel Canister"] = true,
        ["Oil Barrel"]    = true,
    }

    local CF_PROCESSOR_ITEMS = {
        ["Log"]           = true,
        ["Morsel"]        = true,
        ["Cooked Morsel"] = true,
        ["Steak"]         = true,
        ["Cooked Steak"]  = true,
        ["Carrot"]        = true,
        ["Corn"]          = true,
        ["Pumpkin"]       = true,
        ["Strawberry"]    = true,
        ["Apple"]         = true,
    }

    local CF_ALL_ITEMS = {}
    for k in pairs(CF_DIRECT_FIRE_ITEMS) do CF_ALL_ITEMS[k] = true end
    for k in pairs(CF_PROCESSOR_ITEMS)  do CF_ALL_ITEMS[k] = true end

    local CF_PRIORITY = {
        "Biofuel",
        "Log", "Morsel", "Cooked Morsel", "Steak", "Cooked Steak",
        "Carrot", "Corn", "Pumpkin", "Strawberry", "Apple",
        "Coal", "Fuel Canister", "Oil Barrel",
    }

    local cfRunning      = false
    local cfThread       = nil
    local cfFireCenter   = nil
    local cfScanRadius   = nil
    local cfIgnoreRadius = nil
    local cfActiveDrags  = {}
    local cfReserved     = setmetatable({}, { __mode = "k" })
    local cfWhitelist    = {}

    local function cfNow()
        return os.clock()
    end

    local function findCampfire()
        local map = WS:FindFirstChild("Map")
        local campground = map and map:FindFirstChild("Campground")
        if not campground then return nil end
        return campground:FindFirstChild("MainFire")
    end

    local function findBiofuelProcessor()
        local structures = WS:FindFirstChild("Structures")
        if not structures then return nil end
        return structures:FindFirstChild("Biofuel Processor")
    end

    local function getCampfireCenter(fire)
        local center = fire:FindFirstChild("Center")
        return center and center.Position or nil
    end

    local function getCampfireTouchRadii(fire)
        local inner = fire:FindFirstChild("InnerTouchZone")
        local outer = fire:FindFirstChild("OuterTouchZone")
        local ignoreR = inner and (inner.Size.X / 2) or 9.1
        local scanR   = outer and (outer.Size.X / 2) or 65
        return ignoreR, scanR
    end

    local function readCampfireFuel(fire)
        if not fire or not fire.Parent then return nil end
        return fire:GetAttribute("FuelRemaining")
    end

    local function cfShouldFeed(fire)
        local fuel = readCampfireFuel(fire)
        return fuel ~= nil and fuel <= CF_FEED_THRESHOLD
    end

    local function cfIsItem(m)
        return m and m:IsA("Model") and CF_ALL_ITEMS[m.Name] and mainPart(m) ~= nil
    end

    local function cfIsWhitelisted(m)
        return m and cfWhitelist[m.Name] == true
    end

    local function cfIsNearFire(item)
        if not cfFireCenter then return false end
        local mp = mainPart(item)
        if not mp then return false end
        return (mp.Position - cfFireCenter).Magnitude <= cfScanRadius
    end

    local function cfIsInsideIgnore(item)
        if not cfFireCenter or not cfIgnoreRadius then return false end
        local mp = mainPart(item)
        if not mp then return false end
        return (mp.Position - cfFireCenter).Magnitude <= cfIgnoreRadius
    end

    local function cfGetItemsByPriority()
        local foundByName = {}
        for _, name in ipairs(CF_PRIORITY) do
            foundByName[name] = {}
        end
        local seen = {}
        for _, d in ipairs(WS:GetDescendants()) do
            if cfIsItem(d) and cfIsWhitelisted(d) and not seen[d] and not cfActiveDrags[d] and not cfReserved[d] and cfIsNearFire(d) then
                if d.Name == "Biofuel" and cfIsInsideIgnore(d) then
                else
                    seen[d] = true
                    if foundByName[d.Name] then
                        foundByName[d.Name][#foundByName[d.Name] + 1] = d
                    end
                end
            end
        end
        if cfFireCenter then
            for _, name in ipairs(CF_PRIORITY) do
                table.sort(foundByName[name], function(a, b)
                    local ap = mainPart(a)
                    local bp = mainPart(b)
                    local ad = ap and (ap.Position - cfFireCenter).Magnitude or math.huge
                    local bd = bp and (bp.Position - cfFireCenter).Magnitude or math.huge
                    return ad < bd
                end)
            end
        end
        local out = {}
        for _, name in ipairs(CF_PRIORITY) do
            for _, item in ipairs(foundByName[name]) do
                out[#out + 1] = item
            end
        end
        return out
    end

    local function cfMarkActive(model, r, snap, started)
        cfActiveDrags[model] = { r = r, snap = snap, started = started }
    end

    local function cfClearActive(model)
        cfActiveDrags[model] = nil
    end

    local function cfDropInPlace(model, rec)
        if not model or not model.Parent then return end
        local r = rec and rec.r or getRemotes()
        pcall(function() stopDragHard(r, model) end)
        if rec and rec.snap then
            pcall(function() setCollide(model, true, rec.snap) end)
        end
        for _, p in ipairs(getAllParts(model)) do
            pcall(function()
                p.Anchored = false
                p.AssemblyLinearVelocity  = Vector3.new(0, -18, 0)
                p.AssemblyAngularVelocity = Vector3.new()
            end)
        end
        pcall(function() restoreNetworkOwner(model) end)
        pcall(function() refreshPrompts(model) end)
    end

    local function cfStopAllDrags()
        local copy = {}
        for model, rec in pairs(cfActiveDrags) do
            copy[model] = rec
        end
        cfActiveDrags = {}
        for model, rec in pairs(copy) do
            cfDropInPlace(model, rec)
        end
        cfReserved = setmetatable({}, { __mode = "k" })
    end

    local function cfMoveToTarget(model, targetPos, speed, r)
        if not cfRunning then return false end
        if not model or not model.Parent then return false end

        severeExternalWelds(model)

        local mp = mainPart(model)
        if not mp then return false end

        local started  = safeStartDrag(r, model)
        local riseY    = targetPos.Y + CF_ORB_OFFSET_Y
        local H        = bboxHeight(model)
        local riserY   = riseY - 1.0 + math.clamp(H * 0.45, 0.8, 3.0)

        local lookDir = Vector3.new(targetPos.X, mp.Position.Y, targetPos.Z) - mp.Position
        lookDir = lookDir.Magnitude > 0.001 and lookDir.Unit or Vector3.zAxis

        local snapOrig = setCollide(model, false)
        cfMarkActive(model, r, snapOrig, started)
        zeroAssembly(model)
        setNetworkOwnerLocal(model)

        local t0 = cfNow()

        while cfRunning and model and model.Parent do
            if cfNow() - t0 > CF_JOB_TIMEOUT then break end
            if isConsumed(model) then
                if started then stopDragHard(r, model) end
                cfClearActive(model)
                restoreNetworkOwner(model)
                return true
            end
            local pivot = getPivot(model)
            if not pivot then break end
            local pos = pivot.Position
            local dy = riserY - pos.Y
            if math.abs(dy) <= 0.4 then break end
            local stepY = math.sign(dy) * math.min(speed * CF_VERTICAL_MULT * CF_STEP_WAIT, math.abs(dy))
            local np = Vector3.new(pos.X, pos.Y + stepY, pos.Z)
            setPivot(model, CFrame.new(np, np + lookDir))
            zeroAssembly(model)
            Run.Heartbeat:Wait()
            task.wait(CF_STEP_WAIT)
        end

        if not cfRunning then
            cfDropInPlace(model, cfActiveDrags[model])
            cfClearActive(model)
            return false
        end

        while cfRunning and model and model.Parent do
            if cfNow() - t0 > CF_JOB_TIMEOUT then break end
            if isConsumed(model) then
                if started then stopDragHard(r, model) end
                cfClearActive(model)
                restoreNetworkOwner(model)
                return true
            end
            local pivot = getPivot(model)
            if not pivot then break end
            local pos = pivot.Position
            local delta = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
            local dist = delta.Magnitude
            if dist <= CF_DEST_RADIUS then break end
            local step = math.min(speed * CF_STEP_WAIT, dist)
            local dir = delta.Unit
            local np = Vector3.new(pos.X, riserY, pos.Z) + dir * step
            setPivot(model, CFrame.new(np, np + dir))
            zeroAssembly(model)
            Run.Heartbeat:Wait()
            task.wait(CF_STEP_WAIT)
        end

        if not cfRunning then
            cfDropInPlace(model, cfActiveDrags[model])
            cfClearActive(model)
            return false
        end

        local finalPos = targetPos + Vector3.new(0, CF_FINAL_DROP_HEIGHT, 0)

        while cfRunning and model and model.Parent do
            if cfNow() - t0 > CF_JOB_TIMEOUT then break end
            if isConsumed(model) then
                if started then stopDragHard(r, model) end
                cfClearActive(model)
                restoreNetworkOwner(model)
                return true
            end
            local pivot = getPivot(model)
            if not pivot then break end
            local pos = pivot.Position
            local delta = finalPos - pos
            local dist = delta.Magnitude
            if dist <= 0.55 then break end
            local step = math.min(speed * CF_VERTICAL_MULT * CF_STEP_WAIT, dist)
            local dir = delta.Unit
            setPivot(model, CFrame.new(pos + dir * step, finalPos))
            zeroAssembly(model)
            Run.Heartbeat:Wait()
            task.wait(CF_STEP_WAIT)
        end

        if not cfRunning then
            cfDropInPlace(model, cfActiveDrags[model])
            cfClearActive(model)
            return false
        end

        if model and model.Parent then
            setCollide(model, true, snapOrig)
            setPivot(model, CFrame.new(finalPos))
            for _, p in ipairs(getAllParts(model)) do
                p.Anchored = false
                p.AssemblyLinearVelocity  = Vector3.new(0, -18, 0)
                p.AssemblyAngularVelocity = Vector3.new()
            end
        end

        local waitStart = cfNow()
        while cfRunning and model and model.Parent and cfNow() - waitStart < CF_CONSUME_WAIT do
            if isConsumed(model) then
                if started then stopDragHard(r, model) end
                cfClearActive(model)
                restoreNetworkOwner(model)
                return true
            end
            Run.Heartbeat:Wait()
            task.wait(CF_STEP_WAIT)
        end

        if started then stopDragHard(r, model) end
        if model and model.Parent then
            restoreNetworkOwner(model)
            refreshPrompts(model)
        end
        cfClearActive(model)
        return true
    end

    -- ignoreFuel = true bypasses all fuel threshold checks (used by Feed Now)
    local function cfRunOneCycle(feedNowCap, ignoreFuel)
        local fire = findCampfire()
        if not fire then return end

        local processor     = findBiofuelProcessor()
        local processorPart = processor and mainPart(processor)
        local r             = getRemotes()

        if not r.StartDrag or not r.StopDrag then return end

        requestMoreStreamingAround({
            cfFireCenter,
            processorPart and processorPart.Position or nil
        })

        local totalDispatched = 0
        local cap = feedNowCap or math.huge

        for _, priorityName in ipairs(CF_PRIORITY) do
            if not cfRunning then break end
            if totalDispatched >= cap then break end

            if not ignoreFuel then
                local fireMidCheck = findCampfire()
                local fuelMid = fireMidCheck and readCampfireFuel(fireMidCheck)
                if fuelMid and fuelMid >= CF_FEED_TARGET then break end
            end

            local isProcessorItem = CF_PROCESSOR_ITEMS[priorityName] == true
            local targetPos

            if isProcessorItem then
                if processorPart then
                    targetPos = processorPart.Position
                end
            else
                targetPos = cfFireCenter
            end

            if targetPos then
                local items = cfGetItemsByPriority()
                local active      = 0
                local activeLimit = math.min(CF_PER_ITEM_LIMIT[priorityName] or 1, cap - totalDispatched)

                for _, item in ipairs(items) do
                    if not cfRunning then break end
                    if totalDispatched >= cap then break end

                    if not ignoreFuel then
                        local fireInnerCheck = findCampfire()
                        local fuelInner = fireInnerCheck and readCampfireFuel(fireInnerCheck)
                        if fuelInner and fuelInner >= CF_FEED_TARGET then break end
                    end

                    if item and item.Parent and item.Name == priorityName and cfIsWhitelisted(item) and cfIsNearFire(item) and not cfActiveDrags[item] and not cfReserved[item] then
                        if not (item.Name == "Biofuel" and cfIsInsideIgnore(item)) then
                            while active >= activeLimit and cfRunning do
                                task.wait(0.05)
                            end

                            cfReserved[item] = true
                            active = active + 1
                            totalDispatched = totalDispatched + 1

                            task.spawn(function()
                                cfMoveToTarget(item, targetPos, CF_FEED_SPEED, r)
                                cfReserved[item] = nil
                                active = active - 1
                            end)

                            task.wait(CF_SPAWN_STAGGER)
                        end
                    end
                end

                local deadline = cfNow() + 30
                while active > 0 and cfRunning and cfNow() < deadline do
                    task.wait(0.05)
                end
            end
        end
    end

    local function cfFeedWorker()
        while cfRunning do
            local fire = findCampfire()
            if fire and cfShouldFeed(fire) then
                local fuel = readCampfireFuel(fire)
                if fuel and fuel < CF_FEED_TARGET then
                    cfRunOneCycle(nil, false)
                end
            end
            task.wait(CF_REFILL_INTERVAL)
        end
    end

    local function cfStopLoop()
        cfRunning = false
        if cfThread then
            pcall(function() task.cancel(cfThread) end)
            cfThread = nil
        end
        cfStopAllDrags()
    end

    local function cfStartLoop()
        if cfRunning then return end
        local fire = findCampfire()
        if not fire then
            warn("[CampfireFeed] MainFire not found")
            return
        end
        local center = getCampfireCenter(fire)
        if not center then
            warn("[CampfireFeed] Center part not found")
            return
        end
        local ignoreR, scanR = getCampfireTouchRadii(fire)
        cfFireCenter   = center
        cfIgnoreRadius = ignoreR
        cfScanRadius   = scanR
        cfActiveDrags  = {}
        cfReserved     = setmetatable({}, { __mode = "k" })
        cfRunning      = true
        local processor     = findBiofuelProcessor()
        local processorPart = processor and mainPart(processor)
        requestMoreStreamingAround({
            cfFireCenter,
            processorPart and processorPart.Position or nil
        })
        cfThread = task.spawn(cfFeedWorker)
    end

    tab:Section({ Title = "Campfire Feed" })

    tab:Dropdown({
        Title    = "Feed Items",
        Values   = {
            "Log", "Coal", "Fuel Canister", "Oil Barrel", "Biofuel",
            "Morsel", "Cooked Morsel", "Steak", "Cooked Steak",
            "Carrot", "Corn", "Pumpkin", "Strawberry", "Apple",
        },
        Multi    = true,
        Default  = {
            "Log", "Coal", "Fuel Canister", "Oil Barrel", "Biofuel",
            "Morsel", "Cooked Morsel", "Steak", "Cooked Steak",
            "Carrot", "Corn", "Pumpkin", "Strawberry", "Apple",
        },
        Callback = function(selection)
            cfWhitelist = {}
            if type(selection) == "table" then
                for _, v in pairs(selection) do
                    cfWhitelist[v] = true
                end
            end
        end
    })

    tab:Toggle({
        Title    = "Auto Feed Campfire",
        Default  = C.State.CampfireFeedEnabled and true or false,
        Callback = function(state)
            C.State.CampfireFeedEnabled = state and true or false
            if state then cfStartLoop() else cfStopLoop() end
        end
    })

    tab:Button({
        Title    = "Feed Now (50)",
        Callback = function()
            local fire = findCampfire()
            if not fire then
                warn("[CampfireFeed] MainFire not found")
                return
            end
            local center = getCampfireCenter(fire)
            if not center then
                warn("[CampfireFeed] Center part not found")
                return
            end
            local ignoreR, scanR = getCampfireTouchRadii(fire)
            cfFireCenter   = center
            cfIgnoreRadius = ignoreR
            cfScanRadius   = scanR
            if cfRunning then return end
            cfActiveDrags = {}
            cfReserved    = setmetatable({}, { __mode = "k" })
            cfRunning     = true
            task.spawn(function()
                cfRunOneCycle(CF_FEED_NOW_LIMIT, true)
                if not C.State.CampfireFeedEnabled then
                    cfRunning = false
                end
            end)
        end
    })

    if C.State.CampfireFeedEnabled then
        cfStartLoop()
    end

    if type(C.RegisterCleanup) == "function" then
        C.RegisterCleanup(function()
            stopLoop()
            cfStopLoop()
        end)
    end
end
