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

    local REFILL_INTERVAL = 2
    local FEED_THRESHOLD  = 200
    local FEED_TARGET     = 350
    local FUEL_MAX        = 674

    local BAR2_MIN = 0.484
    local BAR2_MAX = 7.100

    local PILE_TARGET_COUNT = 40
    local GATHER_SPEED = 420
    local FEED_SPEED = 80

    local ORB_OFFSET_Y = 30
    local VERTICAL_MULT = 1.35
    local STEP_WAIT = 0.03
    local CONSUME_WAIT = 2.5
    local JOB_TIMEOUT = 45
    local MAX_GATHER_ACTIVE = 8
    local MAX_FEED_ACTIVE = 4
    local DEST_RADIUS = 1.0
    local FINAL_DROP_HEIGHT = 4.0
    local PILE_DROP_HEIGHT = 5.0
    local PILE_RING_MIN = 0.75
    local PILE_RING_STEP = 0.12
    local PILE_RING_MAX = 6.0

    local FUEL_PRIORITY = {
        "Biofuel",
        "Coal",
        "Fuel Canister",
        "Oil Barrel"
    }

    local FUEL_ITEMS = {
        ["Biofuel"] = true,
        ["Coal"] = true,
        ["Fuel Canister"] = true,
        ["Oil Barrel"] = true
    }

    local running = false
    local loopThread = nil
    local pilePos = nil
    local pileCounter = 0

    local ActiveDrags = {}
    local PiledItems = {}

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
                    pcall(function()
                        d:Destroy()
                    end)
                end
            end

            if d:IsA("BasePart") and d.Anchored then
                pcall(function()
                    d.Anchored = false
                end)
            end
        end

        if model:IsA("BasePart") and model.Anchored then
            pcall(function()
                model.Anchored = false
            end)
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
            local ok = pcall(function()
                r.StartDrag:FireServer(model)
            end)
            return ok
        end
        return false
    end

    local function safeStopDrag(r, model)
        if r and r.StopDrag and model then
            local ok = pcall(function()
                r.StopDrag:FireServer(model)
            end)
            return ok
        end
        return false
    end

    local function stopDragHard(r, model)
        pcall(safeStopDrag, r, model)
        Run.Heartbeat:Wait()
        pcall(safeStopDrag, r, model)

        task.delay(0.05, function()
            pcall(safeStopDrag, r, model)
        end)

        task.delay(0.20, function()
            pcall(safeStopDrag, r, model)
        end)
    end

    local function setNetworkOwnerLocal(model)
        for _, p in ipairs(getAllParts(model)) do
            pcall(function()
                p:SetNetworkOwner(lp)
            end)
        end
    end

    local function restoreNetworkOwner(model)
        for _, p in ipairs(getAllParts(model)) do
            pcall(function()
                p:SetNetworkOwner(nil)
            end)

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
                    if d and d.Parent then
                        d.Enabled = was ~= false
                    end
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
            if p then
                p.CFrame = cf
            end
        end
    end

    local function getPivot(model)
        if not model or not model.Parent then return nil end

        if model:IsA("Model") then
            return model:GetPivot()
        end

        local p = mainPart(model)
        return p and p.CFrame or nil
    end

    local function bboxHeight(model)
        local rp = physicalRootPart(model)
        if rp then
            return math.max(0.5, rp.Size.Y)
        end

        local minY, maxY = nil, nil
        for _, p in ipairs(getAllParts(model)) do
            local y0 = p.Position.Y - p.Size.Y * 0.5
            local y1 = p.Position.Y + p.Size.Y * 0.5
            if not minY or y0 < minY then minY = y0 end
            if not maxY or y1 > maxY then maxY = y1 end
        end

        if minY and maxY then
            return math.max(0.5, maxY - minY)
        end

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
        if attr ~= nil and attr > 0 then
            return attr
        end

        if bar2 and bar2.Parent then
            local x = bar2.Size.X
            local pct = math.clamp((x - BAR2_MIN) / (BAR2_MAX - BAR2_MIN), 0, 1)
            return math.floor(pct * FUEL_MAX)
        end

        return 0
    end

    local function requestMoreStreamingAround(posList)
        if not WS.StreamingEnabled then return end

        local seen = {}
        for _, pos in ipairs(posList) do
            if typeof(pos) == "Vector3" then
                local key = math.floor(pos.X / 64) .. "|" .. math.floor(pos.Z / 64)
                if not seen[key] then
                    seen[key] = true
                    pcall(function()
                        WS:RequestStreamAroundAsync(pos)
                    end)
                end
            end
        end

        task.wait(0.12)
    end

    local function cleanupPiledItems()
        for item, _ in pairs(PiledItems) do
            if not item or not item.Parent or not item:IsDescendantOf(WS) or not FUEL_ITEMS[item.Name] or not mainPart(item) then
                PiledItems[item] = nil
            end
        end
    end

    local function pileCount()
        cleanupPiledItems()

        local n = 0
        for item, _ in pairs(PiledItems) do
            if item and item.Parent then
                n += 1
            end
        end

        return n
    end

    local function scanFuelItemsByPriority()
        local foundByName = {}
        local seen = {}

        for _, name in ipairs(FUEL_PRIORITY) do
            foundByName[name] = {}
        end

        local function scan(root)
            if not root then return end

            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("Model") and FUEL_ITEMS[d.Name] and mainPart(d) and not seen[d] and not ActiveDrags[d] and not PiledItems[d] then
                    seen[d] = true
                    foundByName[d.Name][#foundByName[d.Name] + 1] = d
                end
            end
        end

        scan(WS)

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

    local function getPiledItemsByPriority()
        cleanupPiledItems()

        local foundByName = {}
        for _, name in ipairs(FUEL_PRIORITY) do
            foundByName[name] = {}
        end

        for item, _ in pairs(PiledItems) do
            if item and item.Parent and FUEL_ITEMS[item.Name] and mainPart(item) then
                foundByName[item.Name][#foundByName[item.Name] + 1] = item
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

    local function nextPileOffset()
        pileCounter += 1

        local i = pileCounter
        local a = i * 2.399963229728653
        local r = math.min(PILE_RING_MIN + PILE_RING_STEP * (i - 1), PILE_RING_MAX)

        return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
    end

    local function getAmmoOrbCF(furnacePart)
        return furnacePart.CFrame + Vector3.new(0, ORB_OFFSET_Y, 0)
    end

    local function getFinalTargetPos(furnacePart)
        return furnacePart.Position + Vector3.new(0, FINAL_DROP_HEIGHT, 0)
    end

    local function getPileOrbPos()
        return pilePos + Vector3.new(0, ORB_OFFSET_Y, 0)
    end

    local function getPileTargetPos()
        return pilePos + nextPileOffset() + Vector3.new(0, PILE_DROP_HEIGHT, 0)
    end

    local function fireAmmoBurnRemote(r, ext)
        if r and r.BurnItem and ext then
            pcall(function()
                r.BurnItem:FireServer(ext, Instance.new("Model"))
            end)
        end
    end

    local function markActive(model, r, snap, started)
        ActiveDrags[model] = {
            r = r,
            snap = snap,
            started = started
        }
    end

    local function clearActive(model)
        ActiveDrags[model] = nil
    end

    local function stopActiveItem(model, rec)
        if not model then return end

        local r = rec and rec.r or getRemotes()

        pcall(function()
            stopDragHard(r, model)
        end)

        if model and model.Parent then
            if rec and rec.snap then
                pcall(function()
                    setCollide(model, true, rec.snap)
                end)
            end

            for _, p in ipairs(getAllParts(model)) do
                pcall(function()
                    p.Anchored = false
                end)
            end

            pcall(function()
                restoreNetworkOwner(model)
            end)

            pcall(function()
                refreshPrompts(model)
            end)
        end
    end

    local function moveConveyor(model, orbPos, finalPos, speed, r, ext, burnAtEnd, markPiledAtEnd)
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
                if started then
                    stopDragHard(r, model)
                end
                clearActive(model)
                PiledItems[model] = nil
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
                if started then
                    stopDragHard(r, model)
                end
                clearActive(model)
                PiledItems[model] = nil
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
                if started then
                    stopDragHard(r, model)
                end
                clearActive(model)
                PiledItems[model] = nil
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

        if not running then
            clearActive(model)
            if model and model.Parent then
                if snapOrig then
                    setCollide(model, true, snapOrig)
                end
                restoreNetworkOwner(model)
            end
            return false
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

        if burnAtEnd then
            fireAmmoBurnRemote(r, ext)

            local waitStart = now()
            while running and model and model.Parent and now() - waitStart < CONSUME_WAIT do
                if isConsumed(model) then
                    if started then
                        stopDragHard(r, model)
                    end
                    clearActive(model)
                    PiledItems[model] = nil
                    restoreNetworkOwner(model)
                    return true
                end

                Run.Heartbeat:Wait()
                task.wait(STEP_WAIT)
            end
        end

        if started then
            stopDragHard(r, model)
        end

        if model and model.Parent then
            restoreNetworkOwner(model)
            refreshPrompts(model)
        end

        clearActive(model)

        if markPiledAtEnd and model and model.Parent and FUEL_ITEMS[model.Name] then
            PiledItems[model] = true
        end

        return true
    end

    local function gatherPile()
        if not running then return 0 end
        if not pilePos then return 0 end

        cleanupPiledItems()

        local needed = PILE_TARGET_COUNT - pileCount()
        if needed <= 0 then return 0 end

        local r = getRemotes()
        if not r.StartDrag or not r.StopDrag then return 0 end

        local candidates = scanFuelItemsByPriority()
        if #candidates == 0 then return 0 end

        local orbPos = getPileOrbPos()
        local moved = 0
        local active = 0
        local index = 1

        while running and moved < needed and index <= #candidates do
            while active >= MAX_GATHER_ACTIVE and running do
                Run.Heartbeat:Wait()
            end

            local item = candidates[index]
            index += 1

            if item and item.Parent and FUEL_ITEMS[item.Name] and mainPart(item) and not PiledItems[item] and not ActiveDrags[item] then
                local finalPos = getPileTargetPos()

                active += 1

                task.spawn(function()
                    local ok = moveConveyor(item, orbPos, finalPos, GATHER_SPEED, r, nil, false, true)
                    if ok then
                        moved += 1
                    end
                    active -= 1
                end)

                task.wait(0.04)
            end
        end

        local deadline = now() + 15
        while active > 0 and running and now() < deadline do
            Run.Heartbeat:Wait()
        end

        return moved
    end

    local function feedFromPile(ext, furnace2, bar2)
        if not running then return 0 end

        local furnacePart = mainPart(furnace2)
        if not furnacePart then return 0 end

        local r = getRemotes()
        if not r.StartDrag or not r.StopDrag then return 0 end

        local orbPos = getAmmoOrbCF(furnacePart).Position
        local finalPos = getFinalTargetPos(furnacePart)
        local fed = 0

        while running do
            local currentFuel = readFuel(ext, bar2)
            if currentFuel >= FEED_TARGET then break end

            cleanupPiledItems()
            local pileItems = getPiledItemsByPriority()
            if #pileItems == 0 then break end

            local active = 0
            local movedThisPass = 0

            for _, item in ipairs(pileItems) do
                if not running then break end

                currentFuel = readFuel(ext, bar2)
                if currentFuel >= FEED_TARGET then break end

                while active >= MAX_FEED_ACTIVE and running do
                    Run.Heartbeat:Wait()
                end

                if item and item.Parent and FUEL_ITEMS[item.Name] and mainPart(item) and not ActiveDrags[item] then
                    PiledItems[item] = nil
                    active += 1

                    task.spawn(function()
                        local ok = moveConveyor(item, orbPos, finalPos, FEED_SPEED, r, ext, true, false)
                        if ok then
                            fed += 1
                            movedThisPass += 1
                        end
                        active -= 1
                    end)

                    task.wait(0.35)
                end
            end

            local deadline = now() + 20
            while active > 0 and running and now() < deadline do
                Run.Heartbeat:Wait()
            end

            if movedThisPass == 0 then
                break
            end

            task.wait(0.2)
        end

        return fed
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
    end

    local function stopLoop()
        running = false

        if loopThread then
            pcall(function()
                task.cancel(loopThread)
            end)
            loopThread = nil
        end

        stopAllOutstandingDrags()
    end

    local function runFeedCycle()
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

        local bar2 = findBar2(ext)
        local currentFuel = readFuel(ext, bar2)

        if currentFuel > FEED_THRESHOLD then
            return
        end

        local root = hrp()
        local furnacePart = mainPart(furnace2)
        requestMoreStreamingAround({
            root and root.Position or nil,
            pilePos,
            furnacePart and furnacePart.Position or nil
        })

        gatherPile()

        currentFuel = readFuel(ext, bar2)
        if currentFuel >= FEED_TARGET then
            return
        end

        feedFromPile(ext, furnace2, bar2)
    end

    local function startLoop()
        if running then return end

        local root = hrp()
        if not root then
            warn("[AutoFeed] HumanoidRootPart not found")
            return
        end

        pilePos = root.Position
        pileCounter = 0
        PiledItems = {}
        ActiveDrags = {}

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

        running = true

        loopThread = task.spawn(function()
            while running do
                runFeedCycle()
                task.wait(REFILL_INTERVAL)
            end
        end)
    end

    tab:Section({
        Title = "Generator Auto Feed"
    })

    tab:Toggle({
        Title   = "Auto Feed For Ammo",
        Default = C.State.AutoFeedEnabled and true or false,
        Callback = function(state)
            C.State.AutoFeedEnabled = state and true or false

            if state then
                startLoop()
            else
                stopLoop()
            end
        end
    })

    tab:Button({
        Title = "Feed Now",
        Callback = function()
            if not running then
                local root = hrp()
                if not root then return end
                pilePos = root.Position
                pileCounter = 0
                PiledItems = {}
                ActiveDrags = {}
                running = true
                runFeedCycle()
                running = false
                stopAllOutstandingDrags()
            else
                task.spawn(function()
                    runFeedCycle()
                end)
            end
        end
    })

    if C.State.AutoFeedEnabled then
        startLoop()
    end

    if type(C.RegisterCleanup) == "function" then
        C.RegisterCleanup(function()
            stopLoop()
        end)
    end
end
