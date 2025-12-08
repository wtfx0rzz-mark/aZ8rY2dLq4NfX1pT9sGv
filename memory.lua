-- memory.lua

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI

    assert(C and UI and UI.Tabs and UI.Tabs.Memory, "memory.lua: Memory tab missing")

    local Services = C.Services or {}
    local WS       = Services.WS or game:GetService("Workspace")

    local MemoryTab = UI.Tabs.Memory

    local function safeDestroy(inst)
        if inst and inst.Parent then
            pcall(function()
                inst:Destroy()
            end)
        end
    end

    local function namesMatchWithDigits(actualName, sigName)
        if not actualName or not sigName then
            return false
        end
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
            if aBase == base then
                return true
            end
        end
        return false
    end

    local function deleteBySignature(sig)
        local containerName = sig.containerName or "Map"
        local className     = sig.className     or "Model"
        local rootName      = sig.rootName
        if not rootName then
            return
        end

        local container = WS:FindFirstChild(containerName)
        if not container then
            return
        end

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
        if not Map then
            return
        end
        local caves = Map:FindFirstChild("Caves")
        if caves then
            safeDestroy(caves)
        end
    end

    local function deleteOuterFogWall()
        local Map = WS:FindFirstChild("Map")
        if not Map then
            return
        end
        local boundaries = Map:FindFirstChild("Boundaries")
        if not boundaries then
            return
        end
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

        -- Logged blacklist items (and variants)

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

        -- Extra buckets you called out

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

    local function runGroup(group)
        if group.signatures then
            for _, sig in ipairs(group.signatures) do
                deleteBySignature(sig)
            end
        end
        if group.custom then
            group.custom()
        end
    end

    for _, group in ipairs(GROUPS) do
        MemoryTab:Toggle({
            Title = group.label,
            Default = false,
            Callback = function(value)
                if value then
                    runGroup(group)
                end
            end,
        })
    end
end
