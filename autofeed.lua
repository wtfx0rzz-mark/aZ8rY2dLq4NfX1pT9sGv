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

    local ABOVE_HEIGHT    = 6
    local SPACING         = 0.4
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
    local FUEL_ITEMS = {}
    for k in pairs(SMALL_FUEL) do FUEL_ITEMS[k] = true end
    for k in pairs(LARGE_FUEL) do FUEL_ITEMS[k] = true end

    local running    = false
    local loopThread = nil
    local slotIndex  = 1

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

    local function findPartPar
