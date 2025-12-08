-- memory.lua – 1337 Nights Map/Memory Cleanup Controls

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI

    assert(C and UI and UI.Tabs and UI.Tabs.Memory, "memory.lua: Memory tab missing")
    local MemoryTab = UI.Tabs.Memory

    local Services = C.Services or {}
    local Players  = Services.Players or game:GetService("Players")
    local WS       = Services.WS      or game:GetService("Workspace")

    local lp = C.LocalPlayer or Players.LocalPlayer

    C.State         = C.State or {}
    C.State.Memory  = C.State.Memory or {}
    local state     = C.State.Memory
    state.EnabledByGroup = state.EnabledByGroup or {}

    local EXCLUDED_ROOT_NAME = "1337b00g"
    local descAddedConn

    ------------------------------------------------------------------------
    -- Helpers
    ------------------------------------------------------------------------

    local function getRootContainer(inst)
        local root = inst
        while root.Parent and root.Parent ~= WS do
            root = root.Parent
        end
        return root
    end

    local function isExcludedRoot(root)
        if not root then return false end
        if root.Name == EXCLUDED_ROOT_NAME then
            return true
        end
        if root:FindFirstAncestor(EXCLUDED_ROOT_NAME) then
            return true
        end
        return false
    end

    local function namesMatchWithDigits(actualName, sigName)
        if actualName == sigName then
            return true
        end
        local base, digit = sigName:match("^(.-)(%d)$")
        if not base or not digit then
            return false
        end
        if actualName == base then
            return true
        end
        local aBase, aDigits = actualName:match("^(.-)(%d+)$")
        if aBase and #aDigits == 1 and aBase == base then
            return true
        end
        return false
    end

    local function rootsMatch(root, sig)
        if not root or not root.Parent then
            return false
        end
        local container = getRootContainer(root)
        if container.Name ~= sig.containerName then
            return false
        end
        if root.ClassName ~= sig.className then
            return false
        end
        if root.Name == sig.rootName then
            return true
        end
        return namesMatchWithDigits(root.Name, sig.rootName)
    end

    local function safeDeleteRoot(root)
        if not root or not root.Parent then
            return
        end
        if isExcludedRoot(root) then
            return
        end
        root:Destroy()
    end

    ------------------------------------------------------------------------
    -- Groups / Seeds
    ------------------------------------------------------------------------

    -- Each group corresponds to one toggle.
    local GROUPS = {
        { -- whole caves tree
            id    = "caves",
            label = "Delete Caves (Map.Caves)",
            mode  = "special_caves",
        },
        { -- fog wall / boundary
            id    = "fog",
            label = "Delete Boundary Fog Wall",
            mode  = "special_fog",
        },

        { -- Workspace.Map.Foliage.Bush
            id    = "bush",
            label = "Bush (Foliage.Bush)",
            seeds = {
                {containerName = "Map", rootName = "Bush", className = "Model"},
            },
        },
        { -- Workspace.Map.Foliage.StoneSmall
            id    = "stonesmall",
            label = "StoneSmall",
            seeds = {
                {containerName = "Map", rootName = "StoneSmall", className = "Model"},
            },
        },
        { -- Workspace.Items.Berry
            id    = "berry_items",
            label = "Berries (Items.Berry)",
            seeds = {
                {containerName = "Items", rootName = "Berry", className = "Model"},
            },
        },
        { -- Workspace.Map.Landmarks.Berry Bush
            id    = "berry_bush",
            label = "Berry Bush (Landmarks)",
            seeds = {
                {containerName = "Map", rootName = "Berry Bush", className = "Model"},
            },
        },
        { -- Workspace.Map.Foliage.Basalt Pile1 (+ digits)
            id    = "basalt_pile",
            label = "Basalt Piles",
            seeds = {
                {containerName = "Map", rootName = "Basalt Pile1", className = "Model"},
            },
        },
        { -- Workspace.Map.Foliage.Basalt Pillar2/3 (+ digits)
            id    = "basalt_pillar",
            label = "Basalt Pillars",
            seeds = {
                {containerName = "Map", rootName = "Basalt Pillar2", className = "Model"},
            },
        },
        { -- Workspace.Map.Foliage.Dead Tree1/2/3 (+ digits)
            id    = "dead_tree",
            label = "Dead Trees",
            seeds = {
                {containerName = "Map", rootName = "Dead Tree3", className = "Model"},
            },
        },
        { -- Workspace.Map.Foliage.StoneTall
            id    = "stonetall",
            label = "StoneTall",
            seeds = {
                {containerName = "Map", rootName = "StoneTall", className = "Model"},
            },
        },
        { -- Workspace.Map.Landmarks.FlowerRing1.Flower -> Flower
            id    = "flower",
            label = "Flowers (Landmarks)",
            seeds = {
                {containerName = "Map", rootName = "Flower", className = "Model"},
            },
        },
        { -- Workspace.Map.Landmarks.Military Base.Decor.Satellite Dish
            id    = "satellite_dish",
            label = "Satellite Dishes",
            seeds = {
                {containerName = "Map", rootName = "Satellite Dish", className = "Model"},
            },
        },
        { -- Workspace.Map.Landmarks.Military Base.Radar Tower
            id    = "radar_tower",
            label = "Radar Towers",
            seeds = {
                {containerName = "Map", rootName = "Radar Tower", className = "Model"},
            },
        },
        { -- Workspace.Map.Landmarks.Military Base.Decor.Crate
            id    = "crate",
            label = "Crates (Landmarks/Military)",
            seeds = {
                {containerName = "Map", rootName = "Crate", className = "Model"},
            },
        },
        { -- Workspace.Map.Foliage.Icicle2
            id    = "icicle2",
            label = "Icicle2",
            seeds = {
                {containerName = "Map", rootName = "Icicle2", className = "Model"},
            },
        },
        { -- Workspace.Map.Foliage.SnowStoneTall
            id    = "snowstone_tall",
            label = "SnowStoneTall",
            seeds = {
                {containerName = "Map", rootName = "SnowStoneTall", className = "Model"},
            },
        },
        { -- Workspace.Map.Foliage.SnowStoneSmall
            id    = "snowstone_small",
            label = "SnowStoneSmall",
            seeds = {
                {containerName = "Map", rootName = "SnowStoneSmall", className = "Model"},
            },
        },
        { -- Workspace.Map.Landmarks.Abandoned Playground.Roundabout
            id    = "roundabout",
            label = "Roundabout (Playground)",
            seeds = {
                {containerName = "Map", rootName = "Roundabout", className = "Model"},
            },
        },
        { -- Workspace.Map.Landmarks.Abandoned Playground.Swings
            id    = "swings",
            label = "Swings (Playground)",
            seeds = {
                {containerName = "Map", rootName = "Swings", className = "Model"},
            },
        },
    }

    local function getGroupById(id)
        for _, g in ipairs(GROUPS) do
            if g.id == id then
                return g
            end
        end
        return nil
    end

    local function isGroupEnabled(id)
        return state.EnabledByGroup[id] == true
    end

    ------------------------------------------------------------------------
    -- Deletion routines per group
    ------------------------------------------------------------------------

    local function deleteFogWall()
        local map = WS:FindFirstChild("Map")
        if not map then return end
        local boundaries = map:FindFirstChild("Boundaries")
        if not boundaries then return end
        local fog = boundaries:FindFirstChild("Fog")
        if fog then
            fog:Destroy()
        end
    end

    local function deleteCavesTree()
        local map = WS:FindFirstChild("Map")
        if not map then return end
        local caves = map:FindFirstChild("Caves")
        if caves then
            caves:Destroy()
        end
    end

    local function deleteAllBySignature(sig)
        local container = WS:FindFirstChild(sig.containerName) or WS
        for _, inst in ipairs(container:GetDescendants()) do
            if inst:IsA("BasePart") or inst:IsA("Model") then
                local root = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model") or inst
                if root and rootsMatch(root, sig) then
                    safeDeleteRoot(root)
                end
            end
        end
    end

    local function deleteExistingForGroup(group)
        if group.mode == "special_caves" then
            deleteCavesTree()
            return
        elseif group.mode == "special_fog" then
            deleteFogWall()
            return
        end

        if group.seeds then
            for _, sig in ipairs(group.seeds) do
                deleteAllBySignature(sig)
            end
        end
    end

    ------------------------------------------------------------------------
    -- Streaming hook
    ------------------------------------------------------------------------

    local function ensureDescendantHook()
        if descAddedConn then return end

        descAddedConn = WS.DescendantAdded:Connect(function(inst)
            if not (inst:IsA("BasePart") or inst:IsA("Model")) then
                return
            end

            local map = WS:FindFirstChild("Map")
            local parent = inst.Parent

            -- Fog wall: if enabled, keep killing Fog under Boundaries
            if isGroupEnabled("fog") and map then
                local function isFogNode(node)
                    if not node or not node.Parent then
                        return false
                    end
                    local p = node.Parent
                    return node.Name == "Fog"
                        and p.Name == "Boundaries"
                        and p.Parent == map
                end

                if isFogNode(inst) then
                    inst:Destroy()
                    return
                end
                if parent and isFogNode(parent) then
                    parent:Destroy()
                    return
                end
            end

            -- Caves subtree: if enabled, keep nuking Map.Caves
            if isGroupEnabled("caves") and map then
                local caves = map:FindFirstChild("Caves")
                if caves and inst:IsDescendantOf(caves) then
                    caves:Destroy()
                    return
                end
            end

            local root = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model") or inst
            if not root or isExcludedRoot(root) then
                return
            end

            -- Generic seed-based groups
            for _, group in ipairs(GROUPS) do
                if group.seeds and isGroupEnabled(group.id) then
                    for _, sig in ipairs(group.seeds) do
                        if rootsMatch(root, sig) then
                            safeDeleteRoot(root)
                            return
                        end
                    end
                end
            end
        end)
    end

    ------------------------------------------------------------------------
    -- Group enable/disable
    ------------------------------------------------------------------------

    local function setGroupEnabled(id, on)
        local group = getGroupById(id)
        if not group then return end
        state.EnabledByGroup[id] = on and true or false

        if on then
            ensureDescendantHook()
            deleteExistingForGroup(group)
        end
    end

    local function setAllGroups(on)
        for _, g in ipairs(GROUPS) do
            setGroupEnabled(g.id, on)
            if g._toggle and typeof(g._toggle.SetValue) == "function" then
                g._toggle:SetValue(on)
            end
        end
    end

    ------------------------------------------------------------------------
    -- UI Wiring
    ------------------------------------------------------------------------

    -- Master "All" toggle
    MemoryTab:CreateToggle({
        Name = "All (apply to every group below)",
        CurrentValue = false,
        Flag = "Memory_All",
        Callback = function(value)
            setAllGroups(value)
        end,
    })

    -- Individual toggles for each group
    for _, group in ipairs(GROUPS) do
        local defaultOn = state.EnabledByGroup[group.id] == true

        local toggle = MemoryTab:CreateToggle({
            Name = group.label,
            CurrentValue = defaultOn,
            Flag = "Memory_" .. group.id,
            Callback = function(value)
                setGroupEnabled(group.id, value)
            end,
        })

        group._toggle = toggle
        if defaultOn then
            ensureDescendantHook()
            deleteExistingForGroup(group)
        end
    end
end
