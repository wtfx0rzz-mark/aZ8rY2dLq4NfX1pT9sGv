-- esp.lua
return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI

    assert(C and UI and UI.Tabs and UI.Tabs.Esp, "esp.lua: ESP tab missing")

    local Services = C.Services or {}
    local Players  = Services.Players or game:GetService("Players")
    local WS       = Services.WS      or game:GetService("Workspace")
    local Run      = Services.Run     or game:GetService("RunService")
    local lp       = Players.LocalPlayer

    local tab = UI.Tabs.Esp

    C.State = C.State or {}
    if C.State.ESPEnabled == nil then
        C.State.ESPEnabled = false
    end
    if C.State.ESPItemCacheEnabled == nil then
        C.State.ESPItemCacheEnabled = false
    end

    C.State.ESPConfirmDistance = C.State.ESPConfirmDistance or 400
    local CACHE_LOAD_DISTANCE = C.State.ESPConfirmDistance

    local junkItems = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "UFO Junk","UFO Component"
    }
    local fuelItems = { "Log","Coal","Fuel Canister","Oil Barrel","Biofuel","Chair" }
    local foodItems = {
        "Morsel","Cooked Morsel","Steak","Cooked Steak","Ribs","Cooked Ribs","Cake","Berry","Carrot",
        "Chilli","Stew","Pumpkin","Hearty Stew","Corn","BBQ ribs","Apple","Mackerel"
    }
    local medicalItems = { "Bandage","MedKit" }
    local weaponsArmor = {
        "Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Hammer",
        "Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot Shield","Spear",
        "Tactical Shotgun","Wildfire","Sword","Ice Axe","Thorn Body"
    }
    local ammoMisc = {
        "Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling",
        "Basketball","Blueprint","Diamond","Forest Gem","Key","Flashlight","Taming flute","Cultist Gem","Tusk","Infernal Sack"
    }
    local pelts = {
        "Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Scorpion Shell","Polar Bear Pelt","Arctic Fox Pelt"
    }

    local function hrp()
        local ch = lp.Character
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function isWallVariant(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        if n == "logwall" or n == "log wall" then return true end
        if n:find("log", 1, true) and n:find("wall", 1, true) then return true end
        return false
    end

    local function isUnderLogWall(inst)
        local cur = inst
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm == "logwall" or nm == "log wall"
               or (nm:find("log", 1, true) and nm:find("wall", 1, true)) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end

    local function hasHumanoid(model)
        if not (model and model:IsA("Model")) then return false end
        return model:FindFirstChildOfClass("Humanoid") ~= nil
    end

    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        if n == "pelt trader" then return true end
        if n:find("trader", 1, true) or n:find("shopkeeper", 1, true) then return true end
        if isWallVariant(m) then return true end
        if isUnderLogWall(m) then return true end
        return false
    end

    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            if obj.PrimaryPart then return obj.PrimaryPart end
            return obj:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end

    local function itemsRootOrNil()
        return WS:FindFirstChild("Items")
    end

    local function isInsideTree(m)
        local cur = m and m.Parent
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm:find("tree", 1, true) then return true end
            if cur == itemsRootOrNil() then break end
            cur = cur.Parent
        end
        return false
    end

    local function nameMatches(selectedSet, m)
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then
            return false
        end

        local nm = m and m.Name or ""
        local l  = nm:lower()

        if selectedSet["Apple"] and nm == "Apple" then
            if itemsFolder and m.Parent ~= itemsFolder then return false end
            if isInsideTree(m) then return false end
            return true
        end

        if selectedSet["Berry"] and nm == "Berry" then
            if itemsFolder and m.Parent ~= itemsFolder then return false end
            if isInsideTree(m) then return false end
            return true
        end

        if selectedSet[nm] then return true end

        if selectedSet["Mossy Coin"]
           and (nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$")) then
            return true
        end

        if selectedSet["Cultist"] and m and m:IsA("Model")
           and l:find("cultist", 1, true) and hasHumanoid(m) then
            return true
        end

        if selectedSet["Sapling"] and nm == "Sapling" then return true end

        if selectedSet["Alpha Wolf Pelt"]
           and l:find("alpha", 1, true) and l:find("wolf", 1, true) then
            return true
        end

        if selectedSet["Bear Pelt"]
           and l:find("bear", 1, true) and not l:find("polar", 1, true) then
            return true
        end

        if selectedSet["Wolf Pelt"] and nm == "Wolf Pelt" then return true end
        if selectedSet["Bunny Foot"] and nm == "Bunny Foot" then return true end
        if selectedSet["Polar Bear Pelt"] and nm == "Polar Bear Pelt" then return true end
        if selectedSet["Arctic Fox Pelt"] and nm == "Arctic Fox Pelt" then return true end

        if selectedSet["Spear"] and l:find("spear", 1, true) and not hasHumanoid(m) then
            return true
        end

        if selectedSet["Sword"] and l:find("sword", 1, true) and not hasHumanoid(m) then
            return true
        end

        if selectedSet["Crossbow"] and l:find("crossbow", 1, true)
           and not l:find("cultist", 1, true) and not hasHumanoid(m) then
            return true
        end

        if selectedSet["Blueprint"] and l:find("blueprint", 1, true) then
            return true
        end

        if selectedSet["Flashlight"] and l:find("flashlight", 1, true)
           and not hasHumanoid(m) then
            return true
        end

        if selectedSet["Cultist Gem"] and l:find("cultist", 1, true)
           and l:find("gem", 1, true) then
            return true
        end

        if selectedSet["Forest Gem"]
           and (l:find("forest gem", 1, true)
                or (l:find("forest", 1, true) and l:find("fragment", 1, true))) then
            return true
        end

        if selectedSet["Tusk"] and l:find("tusk", 1, true) then
            return true
        end

        return false
    end

    local function topModelUnderItems(part, itemsFolder)
        local cur = part
        local lastModel = nil
        while cur and cur ~= WS and cur ~= itemsFolder do
            if cur:IsA("Model") then lastModel = cur end
            cur = cur.Parent
        end
        if lastModel and lastModel.Parent == itemsFolder then
            return lastModel
        end
        return lastModel
    end

    local function nearestSelectedModelFromPart(part, selectedSet)
        if not part or not part:IsA("BasePart") then return nil end
        local itemsFolder = itemsRootOrNil()
        local m = topModelUnderItems(part, itemsFolder)
                  or part:FindFirstAncestorOfClass("Model")
        if m and nameMatches(selectedSet, m) then
            return m
        end
        return nil
    end

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt =
        {}, {}, {}, {}, {}, {}, {}

    local AllSelectedSet = {}

    local function setFromChoice(choice)
        local s = {}
        if type(choice) == "table" then
            for _, v in ipairs(choice) do
                if v and v ~= "" then s[v] = true end
            end
        elseif choice and choice ~= "" then
            s[choice] = true
        end
        return s
    end

    local function rebuildAllSelectedSet()
        AllSelectedSet = {}
        local function addSet(t)
            for k, v in pairs(t) do
                if v then AllSelectedSet[k] = true end
            end
        end
        addSet(selJunk)
        addSet(selFuel)
        addSet(selFood)
        addSet(selMedical)
        addSet(selWA)
        addSet(selMisc)
        addSet(selPelt)
    end

    local function isNameSelected(name)
        return AllSelectedSet[name] and true or false
    end

    local function multiSelectDropdown(args)
        return tab:Dropdown({
            Title = args.title,
            Values = args.values,
            Multi = true,
            AllowNone = true,
            Callback = function(choice)
                local s = setFromChoice(choice)
                args.setter(s)
                rebuildAllSelectedSet()
            end
        })
    end

    local EspFolder = WS:FindFirstChild("__ESP_Anchors_Local")
    if not EspFolder then
        EspFolder = Instance.new("Folder")
        EspFolder.Name = "__ESP_Anchors_Local"
        EspFolder.Parent = WS
    end

    local CacheEntries    = {}
    local CacheByInstance = setmetatable({}, { __mode = "k" })
    local NextId          = 1

    local function addOrUpdateCachedModel(m)
        if not m or not m.Parent then return end
        if isExcludedModel(m) or isUnderLogWall(m) then return end

        local nm = m.Name or ""

        if not isNameSelected(nm) and not nameMatches(AllSelectedSet, m) then
            return
        end

        local mp = mainPart(m)
        if not mp then return end

        local pos   = mp.Position
        local entry = CacheByInstance[m]

        if entry then
            entry.lastPos      = pos
            entry.lastSeenTime = os.clock()
            entry.name         = nm
        else
            entry = {
                id           = NextId,
                name         = nm,
                instance     = m,
                lastPos      = pos,
                lastSeenTime = os.clock(),
                marker       = nil
            }
            NextId += 1
            table.insert(CacheEntries, entry)
            CacheByInstance[m] = entry
        end
    end

    local function fullScan()
        if not next(AllSelectedSet) then return end
        local items = itemsRootOrNil()
        if not items then return end

        for _, d in ipairs(items:GetDescendants()) do
            local m = nil
            if d:IsA("Model") then
                if nameMatches(AllSelectedSet, d) then
                    m = d
                end
            elseif d:IsA("BasePart") then
                m = nearestSelectedModelFromPart(d, AllSelectedSet)
            end
            if m then
                addOrUpdateCachedModel(m)
            end
        end
    end

    local NEARBY_SCAN_RADIUS = 250

    local function nearbyScan()
        if not next(AllSelectedSet) then return end
        local root = hrp()
        if not root then return end

        local origin = root.Position
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }

        local parts = WS:GetPartBoundsInRadius(origin, NEARBY_SCAN_RADIUS, params) or {}
        for _, p in ipairs(parts) do
            if p:IsA("BasePart") then
                local m = nearestSelectedModelFromPart(p, AllSelectedSet)
                if m then
                    addOrUpdateCachedModel(m)
                end
            end
        end
    end

    local MAX_CACHE_CONFIRMS_PER_TICK = 8

    local function confirmCacheEntries()
        if not next(AllSelectedSet) then return end

        local root = hrp()
        if not root then return end

        local rootPos = root.Position
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }

        local processed = 0

        for _, entry in ipairs(CacheEntries) do
            if processed >= MAX_CACHE_CONFIRMS_PER_TICK then
                break
            end

            local pos = entry.lastPos
            if pos then
                local dist = (pos - rootPos).Magnitude
                if dist <= CACHE_LOAD_DISTANCE then
                    processed += 1

                    if entry.instance and not entry.instance.Parent then
                        CacheByInstance[entry.instance] = nil
                        entry.instance = nil
                    end

                    local parts = WS:GetPartBoundsInRadius(pos, CACHE_LOAD_DISTANCE, params) or {}

                    local bestModel  = nil
                    local bestDistSq = nil

                    for _, p in ipairs(parts) do
                        if p:IsA("BasePart") then
                            local m = nearestSelectedModelFromPart(p, AllSelectedSet)
                            if m and not isExcludedModel(m) and not isUnderLogWall(m) then
                                local mn = m.Name or ""
                                if isNameSelected(mn) or nameMatches(AllSelectedSet, m) then
                                    local mp = mainPart(m)
                                    if mp then
                                        local dv  = mp.Position - pos
                                        local dsq = dv.X * dv.X + dv.Y * dv.Y + dv.Z * dv.Z
                                        if not bestDistSq or dsq < bestDistSq then
                                            bestDistSq = dsq
                                            bestModel  = m
                                        end
                                    end
                                end
                            end
                        end
                    end

                    if bestModel then
                        entry.instance = bestModel
                        CacheByInstance[bestModel] = entry
                        local mp = mainPart(bestModel)
                        if mp then
                            entry.lastPos = mp.Position
                        end
                        entry.lastSeenTime = os.clock()
                    end
                end
            end
        end
    end

    local function destroyMarker(entry)
        if entry.marker and entry.marker.part then
            entry.marker.part:Destroy()
        end
        entry.marker = nil
    end

    local function ensureMarker(entry)
        if entry.marker then return end

        local part = Instance.new("Part")
        part.Name = "ESP_" .. (entry.name or "Item")
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.Transparency = 1
        part.Size = Vector3.new(0.1, 0.1, 0.1)
        part.Parent = EspFolder

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ESPLabel"
        billboard.AlwaysOnTop = true
        billboard.Size = UDim2.new(0, 120, 0, 18)
        billboard.MaxDistance = 0 -- visible from any distance
        billboard.StudsOffset = Vector3.new(0, 2.5, 0)
        billboard.Adornee = part
        billboard.Parent = part

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 255, 0)
        label.TextStrokeTransparency = 0
        label.Text = entry.name or "Item"
        label.Font = Enum.Font.SourceSansBold
        label.TextScaled = true
        label.Parent = billboard

        entry.marker = {
            part      = part,
            billboard = billboard,
            label     = label
        }
    end

    local function updateMarker(entry, espOn)
        if not entry.marker then return end
        local marker  = entry.marker
        local enabled = false

        if espOn and isNameSelected(entry.name or "") then
            local worldPos = nil

            if entry.instance and entry.instance.Parent then
                local mp = mainPart(entry.instance)
                if mp then
                    worldPos = mp.Position
                    entry.lastPos = mp.Position
                    entry.lastSeenTime = os.clock()
                end
            end

            if not worldPos and entry.lastPos then
                worldPos = entry.lastPos
            end

            if worldPos then
                marker.part.CFrame = CFrame.new(worldPos)
                marker.label.Text   = entry.name or "Item"
                enabled = true
            end
        end

        marker.billboard.Enabled = enabled
    end

    local function updateAllMarkers()
        local espOn = C.State.ESPEnabled and next(AllSelectedSet) ~= nil
        for _, entry in ipairs(CacheEntries) do
            if espOn and isNameSelected(entry.name or "") then
                ensureMarker(entry)
                updateMarker(entry, espOn)
            else
                if entry.marker then
                    entry.marker.billboard.Enabled = false
                end
            end
        end
    end

    local function clearAllMarkers()
        for _, entry in ipairs(CacheEntries) do
            destroyMarker(entry)
        end
    end

    local function pruneCacheToSelected()
        local selectedNames = {}
        for name, v in pairs(AllSelectedSet) do
            if v then selectedNames[name] = true end
        end

        local newEntries = {}
        for _, entry in ipairs(CacheEntries) do
            if selectedNames[entry.name] then
                table.insert(newEntries, entry)
            else
                if entry.instance then
                    CacheByInstance[entry.instance] = nil
                end
                destroyMarker(entry)
            end
        end
        CacheEntries = newEntries
    end

    tab:Section({ Title = "ESP Control" })

    tab:Toggle({
        Title   = "Enable ESP",
        Default = C.State.ESPEnabled and true or false,
        Callback = function(on)
            C.State.ESPEnabled = on and true or false
            if not C.State.ESPEnabled then
                clearAllMarkers()
            end
        end
    })

    tab:Toggle({
        Title   = "Enable Item Cache",
        Default = C.State.ESPItemCacheEnabled and true or false,
        Callback = function(on)
            C.State.ESPItemCacheEnabled = on and true or false
        end
    })

    tab:Button({
        Title = "Prune Cached Items To Current Selection",
        Callback = function()
            pruneCacheToSelected()
        end
    })

    tab:Section({ Title = "Junk (ESP Multi)" })
    multiSelectDropdown({
        title  = "Select Junk Items",
        values = junkItems,
        setter = function(s) selJunk = s end
    })

    tab:Section({ Title = "Fuel (ESP Multi)" })
    multiSelectDropdown({
        title  = "Select Fuel Items",
        values = fuelItems,
        setter = function(s) selFuel = s end
    })

    tab:Section({ Title = "Food (ESP Multi)" })
    multiSelectDropdown({
        title  = "Select Food Items",
        values = foodItems,
        setter = function(s) selFood = s end
    })

    tab:Section({ Title = "Medical (ESP Multi)" })
    multiSelectDropdown({
        title  = "Select Medical Items",
        values = medicalItems,
        setter = function(s) selMedical = s end
    })

    tab:Section({ Title = "Weapons/Armor (ESP Multi)" })
    multiSelectDropdown({
        title  = "Select Weapons/Armor",
        values = weaponsArmor,
        setter = function(s) selWA = s end
    })

    tab:Section({ Title = "Ammo & Misc (ESP Multi)" })
    multiSelectDropdown({
        title  = "Select Ammo/Misc",
        values = ammoMisc,
        setter = function(s) selMisc = s end
    })

    tab:Section({ Title = "Pelts (ESP Multi)" })
    multiSelectDropdown({
        title  = "Select Pelts",
        values = pelts,
        setter = function(s) selPelt = s end
    })

    rebuildAllSelectedSet()

    if C.State.ESP_HeartbeatConn then
        pcall(function()
            C.State.ESP_HeartbeatConn:Disconnect()
        end)
        C.State.ESP_HeartbeatConn = nil
    end

    local lastFullScan     = 0
    local lastNearbyScan   = 0
    local lastConfirm      = 0
    local lastMarkerUpdate = 0

    local FULL_SCAN_INTERVAL   = 20.0
    local NEARBY_SCAN_INTERVAL = 1.0
    local CONFIRM_INTERVAL     = 1.0
    local MARKER_INTERVAL      = 0.1

    C.State.ESP_HeartbeatConn = Run.Heartbeat:Connect(function()
        local now = os.clock()

        if not C.State.ESPEnabled then
            return
        end

        if next(AllSelectedSet) == nil then
            clearAllMarkers()
            return
        end

        if now - lastFullScan >= FULL_SCAN_INTERVAL then
            fullScan()
            lastFullScan = now
        end

        if now - lastNearbyScan >= NEARBY_SCAN_INTERVAL then
            nearbyScan()
            lastNearbyScan = now
        end

        if C.State.ESPItemCacheEnabled and now - lastConfirm >= CONFIRM_INTERVAL then
            confirmCacheEntries()
            lastConfirm = now
        end

        if now - lastMarkerUpdate >= MARKER_INTERVAL then
            updateAllMarkers()
            lastMarkerUpdate = now
        end
    end)
end
