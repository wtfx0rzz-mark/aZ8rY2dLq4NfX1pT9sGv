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

    local ABOVE_HEIGHT    = 3.0
    local Y_STACK_SPACING = 0.8
    local REFILL_INTERVAL = 2
    local DRAG_SETTLE     = 0.04
    local FEED_THRESHOLD  = 200
    local FEED_TARGET     = 350
    local FUEL_MAX        = 674

    local BAR2_MIN = 0.484
    local BAR2_MAX = 7.100

    local SMALL_FUEL = {
        ["Log"] = true, ["Coal"] = true, ["Biofuel"] = true, ["Chair"] = true
    }
    local LARGE_FUEL = {
        ["Fuel Canister"] = true, ["Oil Barrel"] = true
    }
    local FUEL_ITEMS = {
        ["Log"] = true, ["Coal"] = true, ["Fuel Canister"] = true,
        ["Oil Barrel"] = true, ["Biofuel"] = true, ["Chair"] = true
    }

    local running    = false
    local loopThread = nil

    local function getRemotes()
        local re = RS:FindFirstChild("RemoteEvents")
        return {
            StartDrag = re and re:FindFirstChild("RequestStartDraggingItem"),
            StopDrag  = re and re:FindFirstChild("StopDraggingItem"),
        }
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

    local function getAllParts(m)
        local t = {}
        if not m then return t end
        if m:IsA("BasePart") then t[1] = m; return t end
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then t[#t+1] = d end
        end
        return t
    end

    local function zeroAssembly(m)
        for _, p in ipairs(getAllParts(m)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function setCollide(m, on, snapshot)
        if on and snapshot then
            for part, can in pairs(snapshot) do
                if part and part.Parent then part.CanCollide = can end
            end
            return
        end
        local snap = {}
        for _, p in ipairs(getAllParts(m)) do
            snap[p] = p.CanCollide
            p.CanCollide = false
        end
        return snap
    end

    local function severeExternalWelds(m)
        if not (m and m.Parent) then return end
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                local p0, p1 = d.Part0, d.Part1
                if (p0 and not p0:IsDescendantOf(m)) or (p1 and not p1:IsDescendantOf(m)) then
                    pcall(function() d:Destroy() end)
                end
            end
            if d:IsA("BasePart") and d.Anchored then
                pcall(function() d.Anchored = false end)
            end
        end
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
        local extraBits = ext:FindFirstChild("ExtraBits")
        local furnace = extraBits and extraBits:FindFirstChild("Furnace")
        return furnace and furnace:FindFirstChild("Furnace2")
    end

    local function findPartParticle(ext)
        local extraBits = ext:FindFirstChild("ExtraBits")
        local furnace = extraBits and extraBits:FindFirstChild("Furnace")
        return furnace and furnace:FindFirstChild("PartParticle")
    end

    local function findBar2(ext)
        local extraBits = ext:FindFirstChild("ExtraBits")
        local bars = extraBits and extraBits:FindFirstChild("Bars")
        return bars and bars:FindFirstChild("Bar2")
    end

    local function readFuel(ext, bar2)
        local attr = ext:GetAttribute("FuelRemaining")
        if attr ~= nil and attr > 0 then return attr end
        if bar2 and bar2.Parent then
            local x = bar2.Size.X
            local pct = math.clamp((x - BAR2_MIN) / (BAR2_MAX - BAR2_MIN), 0, 1)
            return math.floor(pct * FUEL_MAX)
        end
        return 0
    end

    local function getBowlPos(furnace2, partParticle)
        local f2 = furnace2.Position
        local pp = partParticle and partParticle.Position or f2
        return Vector3.new(
            (f2.X + pp.X) / 2,
            math.max(f2.Y, pp.Y),
            (f2.Z + pp.Z) / 2
        )
    end

    local function scanFuelItems()
        local found = {}
        local seen  = {}
        local itemsFolder = WS:FindFirstChild("Items")
        if itemsFolder then
            for _, d in ipairs(itemsFolder:GetChildren()) do
                if d:IsA("Model") and FUEL_ITEMS[d.Name] and mainPart(d) and not seen[d] then
                    seen[d] = true
                    found[#found+1] = d
                end
            end
        end
        for _, d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") and FUEL_ITEMS[d.Name] and mainPart(d) and not seen[d] then
                seen[d] = true
                found[#found+1] = d
            end
        end
        return found
    end

    local function buildBatches(items)
        local batches = {}
        local byType  = {}
        for _, m in ipairs(items) do
            local n = m.Name
            if not byType[n] then byType[n] = {} end
            byType[n][#byType[n]+1] = m
        end
        for name, list in pairs(byType) do
            if SMALL_FUEL[name] then
                local i = 1
                while i <= #list do
                    local batch = {}
                    for j = i, math.min(i + 4, #list) do
                        batch[#batch+1] = list[j]
                    end
                    batches[#batches+1] = batch
                    i = i + 5
                end
            else
                for _, m in ipairs(list) do
                    batches[#batches+1] = {m}
                end
            end
        end
        return batches
    end

    local function dropBatch(batch, bowlPos, r)
        local dropY = bowlPos.Y + ABOVE_HEIGHT
        for i, m in ipairs(batch) do
            if m and m.Parent then
                severeExternalWelds(m)
                local started = false
                if r.StartDrag then
                    started = pcall(function() r.StartDrag:FireServer(m) end)
                end
                Run.Heartbeat:Wait()
                task.wait(DRAG_SETTLE)
                local stackPos = Vector3.new(
                    bowlPos.X,
                    dropY + (i - 1) * Y_STACK_SPACING,
                    bowlPos.Z
                )
                local snap = setCollide(m, false)
                zeroAssembly(m)
                if m:IsA("Model") then
                    m:PivotTo(CFrame.new(stackPos))
                else
                    local mp = mainPart(m)
                    if mp then mp.CFrame = CFrame.new(stackPos) end
                end
                setCollide(m, true, snap)
                for _, p in ipairs(getAllParts(m)) do
                    p.Anchored = false
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                end
                if started and r.StopDrag then
                    pcall(function() r.StopDrag:FireServer(m) end)
                    task.wait(0.03)
                    pcall(function() r.StopDrag:FireServer(m) end)
                end
                task.wait(0.05)
            end
        end
    end

    local function stopLoop()
        running = false
        if loopThread then
            pcall(function() task.cancel(loopThread) end)
            loopThread = nil
        end
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

        local partParticle = findPartParticle(ext)
        local bar2         = findBar2(ext)

        running = true

        loopThread = task.spawn(function()
            local r = getRemotes()

            while running do
                local fuel = readFuel(ext, bar2)

                if fuel <= FEED_THRESHOLD then
                    local bowlPos = getBowlPos(furnace2, partParticle)
                    local items   = scanFuelItems()
                    local batches = buildBatches(items)

                    for _, batch in ipairs(batches) do
                        if not running then break end
                        local currentFuel = readFuel(ext, bar2)
                        if currentFuel >= FEED_TARGET then break end
                        dropBatch(batch, bowlPos, r)
                        task.wait(1.5)
                    end
                end

                task.wait(REFILL_INTERVAL)
            end
        end)
    end

    tab:Section({ Title = "Generator Auto Feed" })

    tab:Toggle({
        Title    = "Auto Feed For Ammo",
        Default  = C.State.AutoFeedEnabled and true or false,
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
        Title    = "Feed Now",
        Callback = function()
            local ext = findGenerator()
            if not ext then return end
            local furnace2 = findFurnace2(ext)
            if not furnace2 then return end
            local partParticle = findPartParticle(ext)
            local bar2 = findBar2(ext)
            local r = getRemotes()
            local bowlPos = getBowlPos(furnace2, partParticle)
            local items = scanFuelItems()
            local batches = buildBatches(items)
            for _, batch in ipairs(batches) do
                local currentFuel = readFuel(ext, bar2)
                if currentFuel >= FEED_TARGET then break end
                dropBatch(batch, bowlPos, r)
                task.wait(1.5)
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
