-- diamonds.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Diamonds, "diamonds.lua: missing context or Diamonds tab")

    local Services = (C and C.Services) or {}
    local Players  = Services.Players or game:GetService("Players")
    local RS       = Services.RS      or game:GetService("ReplicatedStorage")
    local WS       = Services.WS      or game:GetService("Workspace")
    local Run      = Services.Run     or game:GetService("RunService")

    local lp = C.LocalPlayer or Players.LocalPlayer
    local tab = UI.Tabs.Diamonds

    local RADIUS            = 75
    local SCAN_INTERVAL     = 0.15
    local FIRE_COOLDOWN_S   = 0.35
    local MAX_FIRES_PER_SCAN = 8

    local function now() return os.clock() end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:WaitForChild("HumanoidRootPart", 10)
    end

    local function itemsFolder()
        return WS:FindFirstChild("Items") or WS
    end

    local function topModelUnderItems(part, items)
        local cur = part
        local lastModel = nil
        while cur and cur ~= WS and cur ~= items do
            if cur:IsA("Model") then lastModel = cur end
            cur = cur.Parent
        end
        return lastModel
    end

    local function resolveDiamondFromPart(part)
        if not (part and part.Parent) then return nil end
        local items = itemsFolder()
        local m = topModelUnderItems(part, items)
        if m and m.Parent and m.Name == "Diamond" and (not items or m:IsDescendantOf(items)) then
            return m
        end
        local anc = part:FindFirstAncestorOfClass("Model")
        if anc and anc.Parent and anc.Name == "Diamond" and (not items or anc:IsDescendantOf(items)) then
            return anc
        end
        if part.Name == "Diamond" then
            return part
        end
        return nil
    end

    local function getRemote()
        local re = RS:FindFirstChild("RemoteEvents")
        if not re then return nil end
        return re:FindFirstChild("RequestTakeDiamonds")
    end

    local takeRemote = getRemote()

    local lastFireAt = setmetatable({}, { __mode = "k" })

    local function fireTake(target)
        if not (takeRemote and takeRemote.Parent) then return false end
        if not (target and target.Parent) then return false end
        local ok = pcall(function()
            takeRemote:FireServer(target)
        end)
        return ok
    end

    local function scanOnce()
        local root = hrp()
        if not root then return end
        local center = root.Position

        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }

        local parts = WS:GetPartBoundsInRadius(center, RADIUS, params) or {}
        local uniq = {}
        local fired = 0

        for _,p in ipairs(parts) do
            if fired >= MAX_FIRES_PER_SCAN then break end
            if p:IsA("BasePart") then
                local d = resolveDiamondFromPart(p)
                if d and not uniq[d] then
                    uniq[d] = true
                    local lt = lastFireAt[d]
                    if (not lt) or (now() - lt >= FIRE_COOLDOWN_S) then
                        lastFireAt[d] = now()
                        if fireTake(d) then
                            fired += 1
                        end
                    end
                end
            end
        end
    end

    C.State = C.State or {}
    if C.State.DiamondsAutoTake == nil then
        C.State.DiamondsAutoTake = false
    end

    tab:Section({ Title = "Auto" })

    tab:Toggle({
        Title = "Auto-take Diamonds (75 studs)",
        Default = C.State.DiamondsAutoTake and true or false,
        Callback = function(on)
            C.State.DiamondsAutoTake = on and true or false
            if C.State.DiamondsAutoTake then
                if not takeRemote or not takeRemote.Parent then
                    takeRemote = getRemote()
                end
            end
        end
    })

    tab:Section({ Title = "Settings" })

    tab:Slider({
        Title = "Scan Radius",
        Value = { Min = 10, Max = 150, Default = RADIUS },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default
            end
            nv = tonumber(nv)
            if nv then
                RADIUS = math.clamp(nv, 10, 150)
            end
        end
    })

    tab:Slider({
        Title = "Scan Interval (sec)",
        Value = { Min = 0.05, Max = 1.0, Default = SCAN_INTERVAL },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default
            end
            nv = tonumber(nv)
            if nv then
                SCAN_INTERVAL = math.clamp(nv, 0.05, 1.0)
            end
        end
    })

    tab:Slider({
        Title = "Fire Cooldown (sec)",
        Value = { Min = 0.05, Max = 2.0, Default = FIRE_COOLDOWN_S },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default
            end
            nv = tonumber(nv)
            if nv then
                FIRE_COOLDOWN_S = math.clamp(nv, 0.05, 2.0)
            end
        end
    })

    tab:Slider({
        Title = "Max per Scan",
        Value = { Min = 1, Max = 25, Default = MAX_FIRES_PER_SCAN },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default
            end
            nv = tonumber(nv)
            if nv then
                MAX_FIRES_PER_SCAN = math.clamp(nv, 1, 25)
            end
        end
    })

    local loopStarted = false
    local function startLoopOnce()
        if loopStarted then return end
        loopStarted = true
        task.spawn(function()
            while true do
                if C.State and C.State.DiamondsAutoTake then
                    if not takeRemote or not takeRemote.Parent then
                        takeRemote = getRemote()
                    end
                    pcall(scanOnce)
                end
                task.wait(SCAN_INTERVAL)
            end
        end)
    end

    startLoopOnce()
end
