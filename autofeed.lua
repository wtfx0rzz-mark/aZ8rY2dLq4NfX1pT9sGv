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

    local QUEUE_SIZE      = 20
    local HOLD_HEIGHT     = 2.0
    local HOLD_FRAMES     = 8
    local REFILL_INTERVAL = 2
    local DRAG_SETTLE     = 0.04
    local FEED_THRESHOLD  = 200
    local FEED_TARGET     = 350
    local FUEL_MAX        = 674

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

    local function findBar2(ext)
        local extraBits = ext:FindFirstChild("ExtraBits")
        local bars = extraBits and extraBits:FindFirstChild("Bars")
        return bars and bars:FindFirstChild("Bar2")
    end

    local function getFuelRemaining(ext)
        return ext:GetAttribute("FuelRemaining")
    end

    local function getFuelFromBar(bar2)
        if not (bar2 and bar2.Parent) then return nil end
        local BAR_MIN = 0.484
        local BAR_MAX = 7.100
        local x = bar2.Size.X
        local pct = math.clamp((x - BAR_MIN) / (BAR_MAX - BAR_MIN), 0, 1)
        return math.floor(pct * FUEL_MAX)
    end

    local function readFuel(ext, bar2)
        local attr = getFuelRemaining(ext)
        if attr and attr > 0 then return attr end
        return getFuelFromBar(bar2) or 0
    end

    local function findFuelItem()
        local itemsFolder = WS:FindFirstChild("Items")
        if itemsFolder then
            for _, d in ipairs(itemsFolder:GetChildren()) do
                if d:IsA("Model") and FUEL_ITEMS[d.Name] and mainPart(d) then
                    return d
                end
            end
        end
        for _, d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") and FUEL_ITEMS[d.Name] and mainPart(d) then
                return d
            end
        end
        return nil
    end

    local function dropIntoBowl(model, dropPos, r)
        if not (model and model.Parent) then return false end
        severeExternalWelds(model)

        local started = false
        if r.StartDrag then
            started = pcall(function() r.StartDrag:FireServer(model) end)
        end

        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)

        local snap = setCollide(model, false)
        zeroAssembly(model)

        local holdPos = dropPos + Vector3.new(0, HOLD_HEIGHT, 0)
        if model:IsA("Model") then
            model:PivotTo(CFrame.new(holdPos))
        else
            local mp = mainPart(model)
            if mp then mp.CFrame = CFrame.new(holdPos) end
        end

        for _ = 1, HOLD_FRAMES do
            if not (model and model.Parent) then break end
            if model:IsA("Model") then
                model:PivotTo(CFrame.new(holdPos))
            else
                local mp = mainPart(model)
                if mp then mp.CFrame = CFrame.new(holdPos) end
            end
            zeroAssembly(model)
            Run.Heartbeat:Wait()
        end

        if model:IsA("Model") then
            model:PivotTo(CFrame.new(dropPos))
        else
            local mp = mainPart(model)
            if mp then mp.CFrame = CFrame.new(dropPos) end
        end
        zeroAssembly(model)

        setCollide(model, true, snap)

        for _, p in ipairs(getAllParts(model)) do
            p.Anchored = false
            p.AssemblyLinearVelocity  = Vector3.new(0, -10, 0)
            p.AssemblyAngularVelocity = Vector3.new()
        end

        task.wait(0.3)

        if started and r.StopDrag then
            pcall(function() r.StopDrag:FireServer(model) end)
            task.wait(0.05)
            pcall(function() r.StopDrag:FireServer(model) end)
        end

        return true
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

        local bar2 = findBar2(ext)

        running = true

        loopThread = task.spawn(function()
            local r = getRemotes()

            while running do
                local fuel = readFuel(ext, bar2)
                local pct  = math.floor((fuel / FUEL_MAX) * 100)

                if fuel <= FEED_THRESHOLD then
                    local fed = 0
                    while running do
                        local currentFuel = readFuel(ext, bar2)
                        if currentFuel >= FEED_TARGET then break end

                        local dropPos = furnace2.Position
                        local m = findFuelItem()
                        if not m then
                            task.wait(1)
                            break
                        end

                        dropIntoBowl(m, dropPos, r)
                        fed += 1
                        task.wait(0.5)
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
            local bar2 = findBar2(ext)
            local fuel = readFuel(ext, bar2)
            local needed = FEED_TARGET - fuel
            if needed <= 0 then return end
            local r = getRemotes()
            local count = 0
            while count < QUEUE_SIZE do
                local currentFuel = readFuel(ext, bar2)
                if currentFuel >= FEED_TARGET then break end
                local m = findFuelItem()
                if not m then break end
                dropIntoBowl(m, furnace2.Position, r)
                count += 1
                task.wait(0.5)
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
