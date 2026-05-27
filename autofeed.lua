return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local Run     = C.Services.Run or game:GetService("RunService")

    local lp = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}

    local tab  = Tabs.AutoFeed
    if not tab then return end

    C.State = C.State or {}

    local REFILL_INTERVAL = 2
    local FEED_THRESHOLD  = 200
    local FEED_TARGET     = 350
    local FUEL_MAX        = 674

    local BAR2_MIN = 0.484
    local BAR2_MAX = 7.100

    local FALLBACK_UP     = 4
    local DRAG_SETTLE     = 0.06
    local ACTION_HOLD     = 0.12
    local CONSUME_WAIT    = 1.0
    local COLLIDE_OFF_SEC = 0.22

    local SMALL_FUEL = {
        ["Coal"] = true,
        ["Biofuel"] = true
    }

    local FUEL_ITEMS = {
        ["Coal"] = true,
        ["Fuel Canister"] = true,
        ["Oil Barrel"] = true,
        ["Biofuel"] = true
    }

    local running    = false
    local loopThread = nil

    local DragStarted = setmetatable({}, { __mode = "k" })

    local function now()
        return os.clock()
    end

    local function getRemotes()
        local re = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
        return {
            StartDrag = re and re:FindFirstChild("RequestStartDraggingItem"),
            StopDrag  = re and (re:FindFirstChild("StopDraggingItem") or re:FindFirstChild("RequestStopDraggingItem")),
            BurnItem  = re and re:FindFirstChild("RequestAmmoFurnaceBurnItem"),
        }
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

    local function getAllParts(m)
        local t = {}
        if not m then return t end
        if m:IsA("BasePart") then
            t[1] = m
            return t
        end
        if m:IsA("Model") then
            for _, d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then
                    t[#t + 1] = d
                end
            end
        end
        return t
    end

    local function zeroAssembly(m)
        for _, p in ipairs(getAllParts(m)) do
            p.AssemblyLinearVelocity = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function setCollide(m, on, snapshot)
        local parts = getAllParts(m)

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

    local function severeExternalWelds(m)
        if not (m and m.Parent) then return end

        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                local p0 = d.Part0
                local p1 = d.Part1
                if (p0 and not p0:IsDescendantOf(m)) or (p1 and not p1:IsDescendantOf(m)) then
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

        if m:IsA("BasePart") and m.Anchored then
            pcall(function()
                m.Anchored = false
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
        if r and r.StopDrag and model and model.Parent then
            local ok = pcall(function()
                r.StopDrag:FireServer(model)
            end)
            return ok
        end
        return false
    end

    local function finallyStopDrag(r, model)
        task.delay(0.05, function()
            pcall(safeStopDrag, r, model)
        end)
        task.delay(0.20, function()
            pcall(safeStopDrag, r, model)
        end)
    end

    local function finallyStopDragTwice(r, model)
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

    local function markDragStarted(model)
        if not (model and model.Parent) then return end
        DragStarted[model] = true
        pcall(function()
            model:SetAttribute("AutoFeedDragStarted", true)
        end)
    end

    local function clearDragStarted(model)
        if not model then return end
        DragStarted[model] = nil
        pcall(function()
            if model and model.Parent then
                model:SetAttribute("AutoFeedDragStarted", nil)
            end
        end)
    end

    local function stopIfDragging(r, model)
        if not model then return end
        if DragStarted[model] then
            finallyStopDrag(r, model)
            clearDragStarted(model)
        end
    end

    local function stopAllOutstandingDrags()
        local r = getRemotes()
        for model, _ in pairs(DragStarted) do
            if model and model.Parent then
                finallyStopDragTwice(r, model)
                clearDragStarted(model)
            else
                DragStarted[model] = nil
            end
        end
    end

    local function awaitConsumedOrMoved(model, timeout)
        local t0 = now()
        local p0 = model and model.Parent or nil

        while now() - t0 < (timeout or 1) do
            if not model or not model.Parent then return true end
            if model.Parent ~= p0 then return true end
            if model:GetAttribute("Consumed") == true then return true end
            Run.Heartbeat:Wait()
        end

        return false
    end

    local function pivotOverTarget(model, target)
        local mp = mainPart(target)
        if not mp then return false end

        local above = mp.CFrame + Vector3.new(0, FALLBACK_UP, 0)
        local snap = setCollide(model, false)

        zeroAssembly(model)

        if model:IsA("Model") then
            model:PivotTo(above)
        else
            local p = mainPart(model)
            if p then
                p.CFrame = above
            end
        end

        for _, p in ipairs(getAllParts(model)) do
            p.Anchored = false
            p.AssemblyLinearVelocity = Vector3.new(0, -8, 0)
            p.AssemblyAngularVelocity = Vector3.new()
        end

        task.delay(COLLIDE_OFF_SEC, function()
            if model and model.Parent then
                setCollide(model, true, snap)
            end
        end)

        return true
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

    local function scanFuelItems()
        local found = {}
        local seen  = {}

        local itemsFolder = WS:FindFirstChild("Items")
        if itemsFolder then
            for _, d in ipairs(itemsFolder:GetChildren()) do
                if d:IsA("Model") and FUEL_ITEMS[d.Name] and mainPart(d) and not seen[d] then
                    seen[d] = true
                    found[#found + 1] = d
                end
            end
        end

        for _, d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") and FUEL_ITEMS[d.Name] and mainPart(d) and not seen[d] then
                seen[d] = true
                found[#found + 1] = d
            end
        end

        return found
    end

    local function buildBatches(items)
        local batches = {}
        local byType  = {}

        for _, m in ipairs(items) do
            local n = m.Name
            if not byType[n] then
                byType[n] = {}
            end
            byType[n][#byType[n] + 1] = m
        end

        for name, list in pairs(byType) do
            if SMALL_FUEL[name] then
                local i = 1
                while i <= #list do
                    local batch = {}
                    for j = i, math.min(i + 4, #list) do
                        batch[#batch + 1] = list[j]
                    end
                    batches[#batches + 1] = batch
                    i = i + 5
                end
            else
                for _, m in ipairs(list) do
                    batches[#batches + 1] = { m }
                end
            end
        end

        return batches
    end

    local function burnItem(item, ext, furnace2, r)
        if not (item and item.Parent and ext and furnace2 and r) then return false end

        severeExternalWelds(item)

        local started = safeStartDrag(r, item)
        if started then
            markDragStarted(item)
        end

        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)

        local moved = pivotOverTarget(item, furnace2)

        task.wait(ACTION_HOLD)

        local burned = false
        if r.BurnItem then
            burned = pcall(function()
                r.BurnItem:FireServer(ext, Instance.new("Model"))
            end)
        end

        awaitConsumedOrMoved(item, CONSUME_WAIT)

        if started then
            stopIfDragging(r, item)
        end

        refreshPrompts(item)

        return moved and burned
    end

    local function dropBatch(batch, ext, furnace2, r)
        for _, item in ipairs(batch) do
            if item and item.Parent then
                burnItem(item, ext, furnace2, r)
                task.wait(0.3)
            end
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

    local function startLoop()
        if running then return end

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

        running = true

        loopThread = task.spawn(function()
            local r = getRemotes()

            while running do
                local fuel = readFuel(ext, bar2)

                if fuel <= FEED_THRESHOLD then
                    local items = scanFuelItems()
                    local batches = buildBatches(items)

                    for _, batch in ipairs(batches) do
                        if not running then break end

                        local currentFuel = readFuel(ext, bar2)
                        if currentFuel >= FEED_TARGET then break end

                        dropBatch(batch, ext, furnace2, r)
                    end
                end

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
            local ext = findGenerator()
            if not ext then return end

            local furnace2 = findFurnace2(ext)
            if not furnace2 then return end

            local bar2 = findBar2(ext)
            local r = getRemotes()
            local items = scanFuelItems()
            local batches = buildBatches(items)

            for _, batch in ipairs(batches) do
                local currentFuel = readFuel(ext, bar2)
                if currentFuel >= FEED_TARGET then break end

                dropBatch(batch, ext, furnace2, r)
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
