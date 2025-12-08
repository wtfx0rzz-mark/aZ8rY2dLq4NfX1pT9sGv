-- memory.lua

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI

    assert(C and UI and UI.Tabs and UI.Tabs.Memory, "memory.lua: Memory tab missing")

    local Services = C.Services or {}
    local WS       = Services.WS       or game:GetService("Workspace")

    local MemoryTab = UI.Tabs.Memory

    local function safeDestroy(inst)
        if inst and inst.Parent then
            pcall(function()
                inst:Destroy()
            end)
        end
    end

    local function namesMatchWithDigits(actualName, sigName)
        if not actualName or not sigName then return false end
        if actualName == sigName then return true end
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

    local function deleteBySignature(sig)
        local containerName = sig.containerName or "Map"
        local className     = sig.className     or "Model"
        local rootName      = sig.rootName
        if not rootName then return end

        local container = WS:FindFirstChild(containerName)
        if not container then return end

        for _, inst in ipairs(container:GetDescendants()) do
            if inst.ClassName == className then
                local n = inst.Name
                if n == rootName or namesMatchWithDigits(n, rootName) then
                    safeDestroy(inst)
                end
            end
        end
    end

    local function deleteCavesSubtree()
        local Map = WS:FindFirstChild("Map")
        if not Map then return end
        local caves = Map:FindFirstChild("Caves")
        if caves then
            safeDestroy(caves)
        end
    end

    local function deleteOuterFogWall()
        local Map = WS:FindFirstChild("Map")
        if not Map then return end
        local boundaries = Map:FindFirstChild("Boundaries")
        if not boundaries then return end
        local fog = boundaries:FindFirstChild("Fog")
        if fog then
            safeDestroy(fog)
        end
    end

    local GROUPS = {
        {
            id = "Caves",
            label = "Map.Caves subtree",
            custom = deleteCavesSubtree,
        },
        {
            id = "OuterFog",
            label = "Outer Fog / Boundary Wall",
            custom = deleteOuterFogWall,
        },

        {
            id = "Bush",
            label = "Foliage: Bush",
            signatures = {
                { containerName = "Map", rootName = "Bush", className = "Model" },
            },
        },
        {
            id = "StoneSmall",
            label = "Foliage: StoneSmall",
            signatures = {
                { containerName = "Map", rootName = "StoneSmall", className = "Model" },
            },
        },
        {
            id = "StoneTall",
            label = "Foliage: StoneTall",
            signatures = {
                { containerName = "Map", rootName = "StoneTall", className = "Model" },
            },
        },
        {
            id = "BasaltPiles",
            label = "Foliage: Basalt Piles (Basalt Pile[0-9])",
            signatures = {
                { containerName = "Map", rootName = "Basalt Pile1", className = "Model" },
            },
        },
        {
            id = "BasaltPillars",
            label = "Foliage: Basalt Pillars (Basalt Pillar[0-9])",
            signatures = {
                { containerName = "Map", rootName = "Basalt Pillar2", className = "Model" },
            },
        },
        {
            id = "DeadTrees",
            label = "Foliage: Dead Trees (Dead Tree[0-9])",
            signatures = {
                { containerName = "Map", rootName = "Dead Tree3", className = "Model" },
            },
        },

        {
            id = "Icicles",
            label = "Foliage: Icicle2 (Icicle[0-9])",
            signatures = {
                { containerName = "Map", rootName = "Icicle2", className = "Model" },
            },
        },
        {
            id = "SnowStonesTall",
            label = "Foliage: SnowStoneTall",
            signatures = {
                { containerName = "Map", rootName = "SnowStoneTall", className = "Model" },
            },
        },
        {
            id = "SnowStonesSmall",
            label = "Foliage: SnowStoneSmall",
            signatures = {
                { containerName = "Map", rootName = "SnowStoneSmall", className = "Model" },
            },
        },

        {
            id = "ItemsBerry",
            label = "Items: Berry models",
            signatures = {
                { containerName = "Items", rootName = "Berry", className = "Model" },
            },
        },
        {
            id = "BerryBushes",
            label = "Landmarks: Berry Bush",
            signatures = {
                { containerName = "Map", rootName = "Berry Bush", className = "Model" },
            },
        },
        {
            id = "Flowers",
            label = "Landmarks: Flower (FlowerRing decorations)",
            signatures = {
                { containerName = "Map", rootName = "Flower", className = "Model" },
            },
        },

        {
            id = "MilitarySatDish",
            label = "Military Base: Satellite Dish",
            signatures = {
                { containerName = "Map", rootName = "Satellite Dish", className = "Model" },
            },
        },
        {
            id = "MilitaryRadar",
            label = "Military Base: Radar Tower",
            signatures = {
                { containerName = "Map", rootName = "Radar Tower", className = "Model" },
            },
        },
        {
            id = "MilitaryCrate",
            label = "Map: Crates (incl. Military Decor)",
            signatures = {
                { containerName = "Map", rootName = "Crate", className = "Model" },
            },
        },

        {
            id = "PlaygroundRoundabout",
            label = "Abandoned Playground: Roundabout",
            signatures = {
                { containerName = "Map", rootName = "Roundabout", className = "Model" },
            },
        },
        {
            id = "PlaygroundSwings",
            label = "Abandoned Playground: Swings",
            signatures = {
                { containerName = "Map", rootName = "Swings", className = "Model" },
            },
        },

        {
            id = "Bones",
            label = "Map: Bone",
            signatures = {
                { containerName = "Map", rootName = "Bone", className = "Model" },
            },
        },
        {
            id = "PillarsGeneric",
            label = "Map: Pillar",
            signatures = {
                { containerName = "Map", rootName = "Pillar", className = "Model" },
            },
        },
        {
            id = "LeatherBody",
            label = "Items: Leather Body",
            signatures = {
                { containerName = "Items", rootName = "Leather Body", className = "Model" },
            },
        },
    }

    local function runGroupOnce(group)
        if group.signatures then
            for _, sig in ipairs(group.signatures) do
                deleteBySignature(sig)
            end
        end
        if group.custom then
            group.custom()
        end
    end

    C.State = C.State or {}
    C.State.Memory = C.State.Memory or {}
    local MemState = C.State.Memory
    MemState.Groups = MemState.Groups or {}
    local groupState = MemState.Groups

    MemState.Connections = MemState.Connections or {}
    local Connections = MemState.Connections

    local containerIndex = {
        Map   = {},
        Items = {},
    }

    for _, group in ipairs(GROUPS) do
        if group.signatures then
            for _, sig in ipairs(group.signatures) do
                local cname = sig.containerName or "Map"
                local bucket = containerIndex[cname]
                if bucket then
                    bucket[#bucket + 1] = { group = group, sig = sig }
                end
            end
        end
    end

    local function isGroupEnabled(id)
        local st = groupState[id]
        return st and st.Enabled == true
    end

    local function anyEnabledForContainer(containerName)
        local bucket = containerIndex[containerName]
        if not bucket then return false end
        for _, entry in ipairs(bucket) do
            if isGroupEnabled(entry.group.id) then
                return true
            end
        end
        return false
    end

    local function processInstance(inst, containerName)
        if not (inst and inst.Parent) then return end
        local bucket = containerIndex[containerName]
        if not bucket or #bucket == 0 then return end
        local className = inst.ClassName
        local name = inst.Name
        for _, entry in ipairs(bucket) do
            local group = entry.group
            local sig = entry.sig
            if isGroupEnabled(group.id) then
                local wantClass = sig.className or "Model"
                if className == wantClass then
                    local rootName = sig.rootName
                    if rootName and (name == rootName or namesMatchWithDigits(name, rootName)) then
                        safeDestroy(inst)
                        break
                    end
                end
            end
        end
    end

    local function ensureMapConnection()
        if Connections.MapConn and Connections.MapConn.Connected then return end
        if not anyEnabledForContainer("Map") then return end
        local map = WS:FindFirstChild("Map")
        if not map then return end
        Connections.MapConn = map.DescendantAdded:Connect(function(inst)
            processInstance(inst, "Map")
        end)
    end

    local function ensureItemsConnection()
        if Connections.ItemsConn and Connections.ItemsConn.Connected then return end
        if not anyEnabledForContainer("Items") then return end
        local items = WS:FindFirstChild("Items")
        if not items then return end
        Connections.ItemsConn = items.DescendantAdded:Connect(function(inst)
            processInstance(inst, "Items")
        end)
    end

    local function refreshContainerConnections()
        if not anyEnabledForContainer("Map") then
            if Connections.MapConn and Connections.MapConn.Connected then
                Connections.MapConn:Disconnect()
            end
            Connections.MapConn = nil
        else
            ensureMapConnection()
        end

        if not anyEnabledForContainer("Items") then
            if Connections.ItemsConn and Connections.ItemsConn.Connected then
                Connections.ItemsConn:Disconnect()
            end
            Connections.ItemsConn = nil
        else
            ensureItemsConnection()
        end
    end

    local function ensureWorkspaceWatcher()
        if Connections.WSChildConn and Connections.WSChildConn.Connected then return end
        Connections.WSChildConn = WS.ChildAdded:Connect(function(child)
            local n = child.Name
            if n == "Map" and anyEnabledForContainer("Map") then
                ensureMapConnection()
                for _, group in ipairs(GROUPS) do
                    if isGroupEnabled(group.id) and group.signatures then
                        for _, sig in ipairs(group.signatures) do
                            if (sig.containerName or "Map") == "Map" then
                                deleteBySignature(sig)
                            end
                        end
                    end
                end
            elseif n == "Items" and anyEnabledForContainer("Items") then
                ensureItemsConnection()
                for _, group in ipairs(GROUPS) do
                    if isGroupEnabled(group.id) and group.signatures then
                        for _, sig in ipairs(group.signatures) do
                            if (sig.containerName or "Items") == "Items" then
                                deleteBySignature(sig)
                            end
                        end
                    end
                end
            end
        end)
    end

    for _, group in ipairs(GROUPS) do
        local id = group.id
        local st = groupState[id]
        if not st then
            st = { Enabled = false }
            groupState[id] = st
        end

        MemoryTab:Toggle({
            Title = group.label,
            Default = st.Enabled and true or false,
            Callback = function(on)
                st.Enabled = on and true or false
                groupState[id] = st
                if on then
                    pcall(runGroupOnce, group)
                end
                refreshContainerConnections()
                ensureWorkspaceWatcher()
            end,
        })
    end

    refreshContainerConnections()
    ensureWorkspaceWatcher()

    for _, group in ipairs(GROUPS) do
        if isGroupEnabled(group.id) then
            pcall(runGroupOnce, group)
        end
    end
end
