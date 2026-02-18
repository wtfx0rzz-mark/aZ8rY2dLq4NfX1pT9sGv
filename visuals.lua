return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Visuals, "visuals.lua: Visuals tab missing")

    local Services = C.Services or {}
    local Players  = Services.Players or game:GetService("Players")
    local WS       = Services.WS      or game:GetService("Workspace")
    local RS       = Services.RS      or game:GetService("ReplicatedStorage")
    local lp       = C.LocalPlayer    or Players.LocalPlayer
    local VisualsTab = UI.Tabs.Visuals

    local Lighting   = game:GetService("Lighting")
    local RunService = game:GetService("RunService")

    --------------------------------------------------------------------
    -- MODULE LIFECYCLE GUARD (PREVENT STACKING ON RELOAD)
    --------------------------------------------------------------------
    local __VISUALS_KEY = "__VisualsLua_VisualsModule_v1"
    if _G[__VISUALS_KEY] and type(_G[__VISUALS_KEY].Destroy) == "function" then
        pcall(function() _G[__VISUALS_KEY].Destroy() end)
    end
    local __VISUALS = { _alive = true }
    _G[__VISUALS_KEY] = __VISUALS

    local function alive()
        return (__VISUALS._alive == true) and (_G[__VISUALS_KEY] == __VISUALS)
    end

    --------------------------------------------------------------------
    -- STATE DEFAULTS
    --------------------------------------------------------------------
    C.State = C.State or { AuraRadius = 150, Toggles = {} }
    C.State.Toggles = C.State.Toggles or {}
    if C.State.Toggles.PlayerTracker == nil then C.State.Toggles.PlayerTracker = true end
    if C.State.Toggles.RemoveFog     == nil then C.State.Toggles.RemoveFog     = true end

    local function auraRadius()
        return math.clamp(tonumber(C.State.AuraRadius) or 150, 0, 1_000_000)
    end

    local TREE_NAMES = { ["Small Tree"]=true, ["Snowy Small Tree"]=true, ["Small Webbed Tree"]=true }

    local function bestPart(model)
        if not model or not model:IsA("Model") then return nil end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
        local trunk = model:FindFirstChild("Trunk")
        if trunk and trunk:IsA("BasePart") then return trunk end
        if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart")
    end

    local function ensureHighlight(parent, name)
        local hl = parent:FindFirstChild(name)
        if hl and hl:IsA("Highlight") then return hl end
        hl = Instance.new("Highlight")
        hl.Name = name
        hl.Adornee = parent
        hl.FillTransparency = 1
        hl.OutlineTransparency = 0
        hl.OutlineColor = Color3.fromRGB(255, 255, 0)
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = parent
        return hl
    end

    local function clearHighlight(parent, name)
        local hl = parent and parent:FindFirstChild(name)
        if hl and hl:IsA("Highlight") then hl:Destroy() end
    end

    --------------------------------------------------------------------
    -- REMOVE FOG (CLEAN LIFECYCLE)
    --------------------------------------------------------------------
    local fogRunning = false
    local fogConns = {}
    local fogOriginal
    local atmoOriginal = setmetatable({}, { __mode = "k" })
    local lastFogApply = 0
    local fogLoopId = 0

    local function captureFogOriginal()
        if fogOriginal then return end
        fogOriginal = {
            FogStart = Lighting.FogStart,
            FogEnd   = Lighting.FogEnd,
            FogColor = Lighting.FogColor,
        }
    end

    local function touchAtmosphere(inst)
        if not inst or not inst:IsA("Atmosphere") then return end
        if not atmoOriginal[inst] then
            atmoOriginal[inst] = { Density = inst.Density, Haze = inst.Haze, Glare = inst.Glare }
        end
        inst.Density = 0
        inst.Haze = 0
        inst.Glare = 0
    end

    local function applyNoFog()
        Lighting.FogStart = 1e6
        Lighting.FogEnd = 1e6 + 1
        for _, d in ipairs(Lighting:GetDescendants()) do
            touchAtmosphere(d)
        end
    end

    local function startRemoveFog()
        if fogRunning then return end
        fogRunning = true
        fogLoopId += 1
        local myId = fogLoopId

        captureFogOriginal()
        applyNoFog()

        fogConns[#fogConns+1] = Lighting.DescendantAdded:Connect(function(inst)
            if not (alive() and fogRunning and fogLoopId == myId) then return end
            touchAtmosphere(inst)
        end)

        fogConns[#fogConns+1] = RunService.Heartbeat:Connect(function()
            if not (alive() and fogRunning and fogLoopId == myId) then return end
            local t = os.clock()
            if (t - lastFogApply) < 0.25 then return end
            lastFogApply = t
            applyNoFog()
        end)
    end

    local function stopRemoveFog()
        if not fogRunning and #fogConns == 0 then
            -- Still restore if needed (e.g., unload happened mid-run)
        end
        fogRunning = false
        fogLoopId += 1

        for _, c in ipairs(fogConns) do pcall(function() c:Disconnect() end) end
        fogConns = {}

        if fogOriginal then
            Lighting.FogStart = fogOriginal.FogStart
            Lighting.FogEnd   = fogOriginal.FogEnd
            Lighting.FogColor = fogOriginal.FogColor
        end

        for inst, orig in pairs(atmoOriginal) do
            if inst and inst.Parent then
                pcall(function()
                    inst.Density = orig.Density
                    inst.Haze = orig.Haze
                    inst.Glare = orig.Glare
                end)
            end
        end
    end

    --------------------------------------------------------------------
    -- PLAYER TRACKER (FIX: DISCONNECT ALL CONNECTIONS + RELOAD SAFE)
    --------------------------------------------------------------------
    local runningPlayers = false
    local PLAYER_HL_NAME = "__PlayerTrackerHL__"
    local trackerConns = {}
    local trackerCharConns = setmetatable({}, { __mode = "k" })
    local trackerLoopId = 0

    local function trackConn(list, c)
        if c then list[#list+1] = c end
        return c
    end

    local function untrackAll(list)
        for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end
        for i = #list, 1, -1 do list[i] = nil end
    end

    local function cleanupPlayer(plr)
        local cc = trackerCharConns[plr]
        if cc then
            trackerCharConns[plr] = nil
            pcall(function() cc:Disconnect() end)
        end
        if plr and plr.Character then
            clearHighlight(plr.Character, PLAYER_HL_NAME)
        end
    end

    local function attachPlayer(plr, ch)
        if not ch then return end
        local h = ensureHighlight(ch, PLAYER_HL_NAME)
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Enabled = true
    end

    local function trackPlayer(plr)
        if plr == lp then return end
        if plr.Character then attachPlayer(plr, plr.Character) end
        if not trackerCharConns[plr] then
            trackerCharConns[plr] = plr.CharacterAdded:Connect(function(ch)
                if not (alive() and runningPlayers) then return end
                attachPlayer(plr, ch)
            end)
        end
    end

    local function startPlayerTracker()
        if runningPlayers then return end
        runningPlayers = true
        trackerLoopId += 1
        local myId = trackerLoopId

        for _, p in ipairs(Players:GetPlayers()) do trackPlayer(p) end

        trackConn(trackerConns, Players.PlayerAdded:Connect(function(p)
            if not (alive() and runningPlayers and trackerLoopId == myId) then return end
            trackPlayer(p)
        end))

        trackConn(trackerConns, Players.PlayerRemoving:Connect(function(p)
            cleanupPlayer(p)
        end))

        task.spawn(function()
            while alive() and runningPlayers and trackerLoopId == myId do
                local lch = lp.Character
                local lhrp = lch and lch:FindFirstChild("HumanoidRootPart")
                local R = auraRadius()

                for _, plr2 in ipairs(Players:GetPlayers()) do
                    if plr2 ~= lp then
                        local ch = plr2.Character
                        if ch then
                            local h = ensureHighlight(ch, PLAYER_HL_NAME)
                            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            h.Enabled = true

                            if lhrp then
                                local phrp = ch:FindFirstChild("HumanoidRootPart")
                                local bp = bestPart(ch)
                                local p0 = (phrp and phrp.Position) or (bp and bp.Position)
                                if p0 then
                                    local d = (p0 - lhrp.Position).Magnitude
                                    local t = math.clamp(d / math.max(R, 1), 0, 1)
                                    h.FillTransparency = 1 - (0.85 * t)
                                    h.OutlineTransparency = 0.2 * (1 - t)
                                end
                            end
                        end
                    end
                end

                task.wait(0.25)
            end

            -- Cleanup highlights when loop exits
            for _, plr2 in ipairs(Players:GetPlayers()) do
                if plr2 ~= lp and plr2.Character then
                    clearHighlight(plr2.Character, PLAYER_HL_NAME)
                end
            end
        end)
    end

    local function stopPlayerTracker()
        if not runningPlayers then return end
        runningPlayers = false
        trackerLoopId += 1

        untrackAll(trackerConns)

        for plr2, cc in pairs(trackerCharConns) do
            trackerCharConns[plr2] = nil
            pcall(function() cc:Disconnect() end)
        end

        for _, plr2 in ipairs(Players:GetPlayers()) do
            if plr2 ~= lp and plr2.Character then
                clearHighlight(plr2.Character, PLAYER_HL_NAME)
            end
        end
    end

    --------------------------------------------------------------------
    -- LOCAL INVISIBILITY
    --------------------------------------------------------------------
    local function setLocalInvisible(state)
        local ch = lp and lp.Character
        if not ch then return end
        for _, d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then
                d.LocalTransparencyModifier = state and 1 or 0
            elseif d:IsA("Decal") then
                d.Transparency = state and 1 or 0
            end
        end
    end

    --------------------------------------------------------------------
    -- TREE HIGHLIGHT (RELOAD SAFE)
    --------------------------------------------------------------------
    local runningTrees = false
    local TREE_HL_NAME = "__TreeAuraHL__"
    local treeLoopId = 0

    local function collectTreesInRadius(origin, radius, maxCount)
        local out, n = {}, 0
        local roots = {
            WS,
            (RS and RS:FindFirstChild("Assets")) or nil,
            (RS and RS:FindFirstChild("CutsceneSets")) or nil,
        }

        local function walk(node)
            if not node or n >= maxCount then return end
            if node:IsA("Model") and TREE_NAMES[node.Name] then
                local p = bestPart(node)
                if p and (p.Position - origin).Magnitude <= radius then
                    n += 1
                    out[n] = node
                end
            end
            local ok, children = pcall(node.GetChildren, node)
            if not ok then return end
            for _, ch in ipairs(children) do
                if n >= maxCount then break end
                walk(ch)
            end
        end

        for _, r in ipairs(roots) do
            if r then walk(r) end
        end
        return out
    end

    local function startTreeHighlight()
        if runningTrees then return end
        runningTrees = true
        treeLoopId += 1
        local myId = treeLoopId

        task.spawn(function()
            while alive() and runningTrees and treeLoopId == myId do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    task.wait(0.2)
                    break
                end

                local r = auraRadius()
                local trees = collectTreesInRadius(hrp.Position, r, 256)
                local seen = {}

                for _, m in ipairs(trees) do
                    seen[m] = true
                    ensureHighlight(m, TREE_HL_NAME).Enabled = true
                end

                for _, model in ipairs(WS:GetDescendants()) do
                    if model:IsA("Model") and TREE_NAMES[model.Name] then
                        local hl = model:FindFirstChild(TREE_HL_NAME)
                        if hl and not seen[model] then
                            hl.Enabled = false
                            hl:Destroy()
                        end
                    end
                end

                task.wait(0.35)
            end

            for _, model in ipairs(WS:GetDescendants()) do
                if model:IsA("Model") and TREE_NAMES[model.Name] then
                    clearHighlight(model, TREE_HL_NAME)
                end
            end
        end)
    end

    local function stopTreeHighlight()
        runningTrees = false
        treeLoopId += 1
    end

    --------------------------------------------------------------------
    -- CHARACTER HIGHLIGHT (RELOAD SAFE)
    --------------------------------------------------------------------
    local runningChars = false
    local CHAR_HL_NAME = "__CharAuraHL__"
    local charLoopId = 0

    local function collectCharactersInRadius(origin, radius, maxCount)
        local out, n = {}, 0
        local chars = WS:FindFirstChild("Characters")
        if not chars then return out end
        for _, mdl in ipairs(chars:GetChildren()) do
            if n >= maxCount then break end
            repeat
                if not mdl:IsA("Model") then break end
                local nameLower = string.lower(mdl.Name or "")
                if string.find(nameLower, "horse", 1, true) then break end
                local p = bestPart(mdl)
                if not p then break end
                if (p.Position - origin).Magnitude > radius then break end
                n += 1
                out[n] = mdl
            until true
        end
        return out
    end

    local function startCharHighlight()
        if runningChars then return end
        runningChars = true
        charLoopId += 1
        local myId = charLoopId

        task.spawn(function()
            while alive() and runningChars and charLoopId == myId do
                local ch = lp.Character or lp.CharacterAdded:Wait()
                local hrp = ch:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    task.wait(0.2)
                    break
                end

                local r = auraRadius()
                local targets = collectCharactersInRadius(hrp.Position, r, 256)
                local seen = {}

                for _, m in ipairs(targets) do
                    seen[m] = true
                    ensureHighlight(m, CHAR_HL_NAME).Enabled = true
                end

                local chars = WS:FindFirstChild("Characters")
                if chars then
                    for _, mdl in ipairs(chars:GetChildren()) do
                        local hl = mdl:FindFirstChild(CHAR_HL_NAME)
                        if hl and not seen[mdl] then
                            hl.Enabled = false
                            hl:Destroy()
                        end
                    end
                end

                task.wait(0.35)
            end

            local chars = WS:FindFirstChild("Characters")
            if chars then
                for _, mdl in ipairs(chars:GetChildren()) do
                    clearHighlight(mdl, CHAR_HL_NAME)
                end
            end
        end)
    end

    local function stopCharHighlight()
        runningChars = false
        charLoopId += 1
    end

    --------------------------------------------------------------------
    -- UI WIRING
    --------------------------------------------------------------------
    VisualsTab:Toggle({
        Title = "Player Tracker",
        Value = C.State.Toggles.PlayerTracker or false,
        Callback = function(on)
            if not alive() then return end
            C.State.Toggles.PlayerTracker = on
            if on then startPlayerTracker() else stopPlayerTracker() end
        end
    })

    VisualsTab:Toggle({
        Title = "Invisible",
        Value = C.State.Toggles.Invisible or false,
        Callback = function(on)
            if not alive() then return end
            C.State.Toggles.Invisible = on
            setLocalInvisible(on)
        end
    })

    VisualsTab:Toggle({
        Title = "Remove Fog",
        Value = C.State.Toggles.RemoveFog or false,
        Callback = function(on)
            if not alive() then return end
            C.State.Toggles.RemoveFog = on
            if on then startRemoveFog() else stopRemoveFog() end
        end
    })

    VisualsTab:Toggle({
        Title = "Highlight Trees In Aura",
        Value = C.State.Toggles.HighlightTrees or false,
        Callback = function(on)
            if not alive() then return end
            C.State.Toggles.HighlightTrees = on
            if on then startTreeHighlight() else stopTreeHighlight() end
        end
    })

    VisualsTab:Toggle({
        Title = "Highlight Characters In Aura",
        Value = C.State.Toggles.HighlightChars or false,
        Callback = function(on)
            if not alive() then return end
            C.State.Toggles.HighlightChars = on
            if on then startCharHighlight() else stopCharHighlight() end
        end
    })

    --------------------------------------------------------------------
    -- DESTROY (TEARDOWN FOR RELOADS)
    --------------------------------------------------------------------
    __VISUALS.Destroy = function()
        __VISUALS._alive = false

        pcall(function() stopPlayerTracker() end)
        pcall(function() stopRemoveFog() end)
        pcall(function() stopTreeHighlight() end)
        pcall(function() stopCharHighlight() end)

        pcall(function()
            C.State.Toggles.Invisible = false
            setLocalInvisible(false)
        end)
    end

    --------------------------------------------------------------------
    -- AUTO-START (FROM TOGGLES)
    --------------------------------------------------------------------
    if C.State.Toggles.PlayerTracker then startPlayerTracker() end
    if C.State.Toggles.RemoveFog then startRemoveFog() end
    if C.State.Toggles.HighlightTrees then startTreeHighlight() end
    if C.State.Toggles.HighlightChars then startCharHighlight() end
    if C.State.Toggles.Invisible then setLocalInvisible(true) end
end
