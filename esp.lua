-- esp.lua

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Esp, "esp.lua: ESP tab missing")

    local Services = C.Services or {}
    local Players  = Services.Players  or game:GetService("Players")
    local WS       = Services.WS       or game:GetService("Workspace")
    local Run      = Services.Run      or game:GetService("RunService")

    local lp       = Players.LocalPlayer
    local tab      = UI.Tabs.Esp

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
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

    local junkItems = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "Metal Chair","UFO Junk","UFO Component","Gears"
    }

    local fuelItems = {
        "Log","Coal","Fuel Canister","Oil Barrel","Biofuel","Chair"
    }

    local foodItems = {
        "Rotten",
        "Morsel","Cooked Morsel",
        "Steak","Cooked Steak",
        "Ribs","Cooked Ribs",
        "Cake","Berry",
        "Carrot",
        "Chilli","Stew","Pumpkin","Hearty Stew","Corn","BBQ ribs","Apple",
        "Mackerel","Salmon","Swordfish","Shark",
        "Acorn","Strawberry"
    }

    local medicalItems = {
        "Bandage","MedKit"
    }

    local weaponsArmor = {
        "Revolver","Rifle",
        "Leather Body","Iron Body","Thorn Body",
        "Good Axe","Strong Axe","Hammer","Ice Axe","Scythe",
        "Chainsaw","Crossbow","Katana","Kunai",
        "Laser Cannon","Laser Sword",
        "Morningstar","Riot Shield","Spear","Sword",
        "Tactical Shotgun","Wildfire",
        "Impact Grenade","Dynamite"
    }

    local ammoMisc = {
        "Revolver Ammo","Rifle Ammo",
        "Giant Sack","Good Sack","Mossy Coin",
        "Cultist","Cultist Gem",
        "Alien","Alien Elite",
        "Sapling",
        "Basketball","Blueprint","Diamond","Gem of the Forest Fragment",
        "Flashlight","Old Taming flute","Old Rod",
        "Tusk","Infernal Sack",
        "Sacrifice Totem",
        "Anvil Back","Anvil Front","Anvil Base"
    }

    local pelts = {
        "Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Scorpion Shell","Polar Bear Pelt","Arctic Fox Pelt"
    }

    local characterTargets = { "Kiwi" }

    local function isForestGemName(n)
        local l = string.lower(n or "")
        if l == "forest gem" or l == "gem of the forest fragment" then
            return true
        end
        if l:find("forest", 1, true) and l:find("fragment", 1, true) then
            return true
        end
        return false
    end

    local function isWallVariant(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        return n == "logwall" or n == "log wall" or (n:find("log",1,true) and n:find("wall",1,true))
    end

    local function isUnderLogWall(inst)
        local cur = inst
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm == "logwall" or nm == "log wall" or (nm:find("log",1,true) and nm:find("wall",1,true)) then
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

    local function itemsRootOrNil()
        return WS:FindFirstChild("Items")
    end

    local function charactersRootOrNil()
        return WS:FindFirstChild("Characters")
    end

    local function isInsideTree(m)
        local cur = m and m.Parent
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm:find("tree",1,true) then return true end
            if cur == itemsRootOrNil() then break end
            cur = cur.Parent
        end
        return false
    end

    local function nameMatches(selectedSet, m)
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end

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

        if (selectedSet["Forest Gem"] or selectedSet["Gem of the Forest Fragment"]) and isForestGemName(nm) then
            return true
        end

        if selectedSet["Mossy Coin"] and (nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$")) then return true end
        if selectedSet["Cultist"] and m and m:IsA("Model") and l:find("cultist",1,true) and hasHumanoid(m) then return true end
        if selectedSet["Sapling"] and nm == "Sapling" then return true end
        if selectedSet["Alpha Wolf Pelt"] and l:find("alpha",1,true) and l:find("wolf",1,true) then return true end
        if selectedSet["Bear Pelt"] and l:find("bear",1,true) and not l:find("polar",1,true) then return true end
        if selectedSet["Wolf Pelt"] and nm == "Wolf Pelt" then return true end
        if selectedSet["Bunny Foot"] and nm == "Bunny Foot" then return true end
        if selectedSet["Polar Bear Pelt"] and nm == "Polar Bear Pelt" then return true end
        if selectedSet["Arctic Fox Pelt"] and nm == "Arctic Fox Pelt" then return true end
        if selectedSet["Spear"] and l:find("spear",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Sword"] and l:find("sword",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Crossbow"] and l:find("crossbow",1,true) and not l:find("cultist",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Blueprint"] and l:find("blueprint",1,true) then return true end
        if selectedSet["Flashlight"] and l:find("flashlight",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Cultist Gem"] and l:find("cultist",1,true) and l:find("gem",1,true) then return true end
        if selectedSet["Tusk"] and l:find("tusk",1,true) then return true end
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
        local m = topModelUnderItems(part, itemsFolder) or part:FindFirstAncestorOfClass("Model")
        if m and nameMatches(selectedSet, m) then return m end
        return nil
    end

    local ESP_SCAN_RADIUS      = 260
    local VERIFY_RADIUS        = 400
    local LOCAL_PICKUP_RADIUS  = 16
    local SCAN_INTERVAL        = 0.25
    local MISSED_SCANS_REMOVE  = 4

    local BASE_LABEL_WIDTH     = 120
    local BASE_LABEL_HEIGHT    = 24
    local SIZE_NEAR_DIST       = 40
    local SIZE_FAR_DIST        = 220
    local SIZE_NEAR_SCALE      = 1.25
    local SIZE_FAR_SCALE       = 0.6

    C.State = C.State or {}
    C.State.ESP = C.State.ESP or {}
    local S = C.State.ESP
    if S.Enabled == nil then S.Enabled = false end
    if S.CacheEnabled == nil then S.CacheEnabled = false end

    local espCache = {}
    local modelToKey = setmetatable({}, { __mode = "k" })

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt = {},{},{},{},{},{},{}
    local selChars = {}
    local activeSelection = {}

    local function mergeSet(dst, src)
        for k,v in pairs(src) do
            if v then dst[k] = true end
        end
    end

    local function clearEntry(entry)
        if entry.con then
            entry.con:Disconnect()
            entry.con = nil
        end
        if entry.marker then
            entry.marker:Destroy()
            entry.marker = nil
            entry.label = nil
        end
        if entry.ghostPart then
            entry.ghostPart:Destroy()
            entry.ghostPart = nil
        end
    end

    local function clearUnselectedCaches()
        for key, entry in pairs(espCache) do
            local name = entry.name
            if not activeSelection[name] then
                clearEntry(entry)
                espCache[key] = nil
            end
        end
    end

    local function recomputeActiveSelection()
        local dst = {}
        mergeSet(dst, selJunk)
        mergeSet(dst, selFuel)
        mergeSet(dst, selFood)
        mergeSet(dst, selMedical)
        mergeSet(dst, selWA)
        mergeSet(dst, selMisc)
        mergeSet(dst, selPelt)
        mergeSet(dst, selChars)
        activeSelection = dst
        clearUnselectedCaches()
    end

    local function setFromChoice(choice)
        local s = {}
        if type(choice) == "table" then
            for _,v in ipairs(choice) do
                if v and v ~= "" then s[v] = true end
            end
        elseif choice and choice ~= "" then
            s[choice] = true
        end
        return s
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
                recomputeActiveSelection()
            end
        })
    end

    local function createBillboard(name)
        local pg = lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local gui = Instance.new("BillboardGui")
        gui.Name = "ESP_Item"
        gui.Size = UDim2.new(0, BASE_LABEL_WIDTH, 0, BASE_LABEL_HEIGHT)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 10000
        gui.StudsOffset = Vector3.new(0, 3, 0)
        gui.Parent = pg

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.Font = Enum.Font.SourceSansBold
        lbl.TextScaled = false
        lbl.TextSize = 14
        lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        lbl.TextStrokeTransparency = 0.3
        lbl.Text = name
        lbl.Parent = gui

        return gui, lbl
    end

    local function shouldCacheName(name)
        if not name then return false end
        local l = string.lower(name)
        if l == "log" then return false end
        return true
    end

    local function updateEntryVisual(entry, rootPos)
        if not entry.marker or not entry.label then return end
        entry.label.Text = entry.name
        local pos = entry.lastPos
        local scale = 1
        if rootPos and pos then
            local d = (rootPos - pos).Magnitude
            local t
            if d <= SIZE_NEAR_DIST then
                t = 0
            elseif d >= SIZE_FAR_DIST then
                t = 1
            else
                t = (d - SIZE_NEAR_DIST) / (SIZE_FAR_DIST - SIZE_NEAR_DIST)
            end
            scale = SIZE_NEAR_SCALE - (SIZE_NEAR_SCALE - SIZE_FAR_SCALE) * t
        else
            scale = 1
        end
        entry.marker.Size = UDim2.new(0, BASE_LABEL_WIDTH * scale, 0, BASE_LABEL_HEIGHT * scale)
        entry.marker.Enabled = S.Enabled
    end

    local function attachToModel(entry, model, rootPos)
        local mp = mainPart(model)
        if not mp then return end
        entry.lastPos = mp.Position
        if not entry.marker then
            local gui, lbl = createBillboard(entry.name)
            if not gui then return end
            entry.marker = gui
            entry.label  = lbl
        end
        if entry.ghostPart then
            entry.ghostPart:Destroy()
            entry.ghostPart = nil
        end
        local att = mp:FindFirstChild("__ESP_Att") or Instance.new("Attachment")
        att.Name = "__ESP_Att"
        att.Parent = mp
        entry.marker.Adornee = att
        updateEntryVisual(entry, rootPos)
    end

    local function attachGhost(entry, rootPos)
        if not S.CacheEnabled or not shouldCacheName(entry.name) then
            clearEntry(entry)
            return
        end
        if not entry.lastPos then
            clearEntry(entry)
            return
        end
        if not entry.marker then
            local gui, lbl = createBillboard(entry.name)
            if not gui then return end
            entry.marker = gui
            entry.label  = lbl
        end
        if not entry.ghostPart then
            local p = Instance.new("Part")
            p.Name = "ESP_Ghost"
            p.Anchored = true
            p.CanCollide = false
            p.CanTouch = false
            p.CanQuery = false
            p.Transparency = 1
            p.Size = Vector3.new(0.1, 0.1, 0.1)
            p.CFrame = CFrame.new(entry.lastPos)
            p.Parent = WS
            entry.ghostPart = p

            local att = Instance.new("Attachment")
            att.Name = "ESP_GhostAtt"
            att.Parent = p
            entry.marker.Adornee = att
        else
            entry.ghostPart.CFrame = CFrame.new(entry.lastPos)
        end
        updateEntryVisual(entry, rootPos)
    end

    local function isProbablyPickedOrDisabled(m, mp)
        if not m or not mp then return false end

        local ch = lp.Character
        local bp = lp:FindFirstChildOfClass("Backpack")
        if (ch and m:IsDescendantOf(ch)) or (bp and m:IsDescendantOf(bp)) then
            return true
        end

        if mp.Transparency >= 0.95 and (mp.CanQuery == false) and (mp.CanTouch == false) and (mp.CanCollide == false) then
            return true
        end

        local ok, v = pcall(function() return m:GetAttribute("PickedUp") end)
        if ok and v == true then return true end
        ok, v = pcall(function() return m:GetAttribute("IsPickedUp") end)
        if ok and v == true then return true end
        ok, v = pcall(function() return m:GetAttribute("Collected") end)
        if ok and v == true then return true end
        ok, v = pcall(function() return m:GetAttribute("IsCollected") end)
        if ok and v == true then return true end
        ok, v = pcall(function() return m:GetAttribute("Taken") end)
        if ok and v == true then return true end
        ok, v = pcall(function() return m:GetAttribute("IsTaken") end)
        if ok and v == true then return true end
        ok, v = pcall(function() return m:GetAttribute("InInventory") end)
        if ok and v == true then return true end
        ok, v = pcall(function() return m:GetAttribute("IsInInventory") end)
        if ok and v == true then return true end

        ok, v = pcall(function() return m:GetAttribute("Owner") end)
        if ok and (v == lp.UserId or v == lp.Name) then return true end
        ok, v = pcall(function() return m:GetAttribute("HeldBy") end)
        if ok and (v == lp.UserId or v == lp.Name) then return true end
        ok, v = pcall(function() return m:GetAttribute("Carrier") end)
        if ok and (v == lp.UserId or v == lp.Name) then return true end

        return false
    end

    local function handleDespawn(model, key, rootPos)
        local entry = espCache[key]
        if not entry then return end
        entry.live = nil
        if entry.con then
            entry.con:Disconnect()
            entry.con = nil
        end

        local root = hrp()
        local pos  = entry.lastPos
        local pickedUp = false
        if root and pos then
            local dist = (root.Position - pos).Magnitude
            if dist <= LOCAL_PICKUP_RADIUS * 2 then
                pickedUp = true
            end
        end

        if pickedUp or not S.CacheEnabled or not shouldCacheName(entry.name) then
            clearEntry(entry)
            espCache[key] = nil
        else
            attachGhost(entry, rootPos)
        end
    end

    local function makeKeyFor(model, pos)
        local name = model.Name or "?"
        local gx = math.floor(pos.X / VERIFY_RADIUS)
        local gz = math.floor(pos.Z / VERIFY_RADIUS)

        local ok, did = pcall(function() return model:GetDebugId(2) end)
        local suffix = ok and tostring(did) or tostring(model)

        return name .. "|" .. gx .. "|" .. gz .. "|" .. suffix
    end

    local function makeCharKeyFor(model, pos)
        local ok, did = pcall(function() return model:GetDebugId(2) end)
        local suffix = ok and tostring(did) or tostring(model)
        return "CHAR|" .. makeKeyFor(model, pos) .. "|" .. suffix
    end

    tab:Section({ Title = "ESP Controls" })
    tab:Toggle({
        Title = "Enable ESP",
        Value = S.Enabled,
        Callback = function(on)
            S.Enabled = on and true or false
            for _,entry in pairs(espCache) do
                if entry.marker then
                    entry.marker.Enabled = S.Enabled
                end
            end
        end
    })
    tab:Toggle({
        Title = "Item cache (remember last positions)",
        Value = S.CacheEnabled,
        Callback = function(on)
            S.CacheEnabled = on and true or false
            if not S.CacheEnabled then
                for key, entry in pairs(espCache) do
                    if not entry.live then
                        clearEntry(entry)
                        espCache[key] = nil
                    end
                end
            end
        end
    })

    tab:Section({ Title = "Junk ESP (Multi)" })
    multiSelectDropdown({ title = "Select Junk Items", values = junkItems, setter = function(s) selJunk = s end })

    tab:Section({ Title = "Fuel ESP (Multi)" })
    multiSelectDropdown({ title = "Select Fuel Items", values = fuelItems, setter = function(s) selFuel = s end })

    tab:Section({ Title = "Food ESP (Multi)" })
    multiSelectDropdown({ title = "Select Food Items", values = foodItems, setter = function(s) selFood = s end })

    tab:Section({ Title = "Medical ESP (Multi)" })
    multiSelectDropdown({ title = "Select Medical Items", values = medicalItems, setter = function(s) selMedical = s end })

    tab:Section({ Title = "Weapons/Armor ESP (Multi)" })
    multiSelectDropdown({ title = "Select Weapons/Armor", values = weaponsArmor, setter = function(s) selWA = s end })

    tab:Section({ Title = "Ammo & Misc ESP (Multi)" })
    multiSelectDropdown({ title = "Select Ammo/Misc", values = ammoMisc, setter = function(s) selMisc = s end })

    tab:Section({ Title = "Pelts ESP (Multi)" })
    multiSelectDropdown({ title = "Select Pelts", values = pelts, setter = function(s) selPelt = s end })

    tab:Section({ Title = "Cache Maintenance" })
    tab:Button({
        Title = "Clear cached items not in selection",
        Callback = clearUnselectedCaches
    })

    tab:Section({ Title = "Character ESP (Multi)" })
    multiSelectDropdown({ title = "Select Characters", values = characterTargets, setter = function(s) selChars = s end })

    recomputeActiveSelection()

    task.spawn(function()
        while true do
            if S.Enabled and next(activeSelection) ~= nil then
                local ok, err = pcall(function()
                    local root = hrp()
                    if not root then return end
                    local center = root.Position

                    local params = OverlapParams.new()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances = { lp.Character }

                    local parts = WS:GetPartBoundsInRadius(center, ESP_SCAN_RADIUS, params) or {}
                    local seenKeys = {}

                    for _, part in ipairs(parts) do
                        if part:IsA("BasePart") then
                            local m = nearestSelectedModelFromPart(part, activeSelection)
                            if m then
                                if not (isUnderLogWall(m) or isWallVariant(m)) then
                                    local mp = mainPart(m)
                                    if mp then
                                        local pos = mp.Position
                                        local key = modelToKey[m]
                                        if not key then
                                            key = makeKeyFor(m, pos)
                                            modelToKey[m] = key
                                        end
                                        seenKeys[key] = true
                                        local entry = espCache[key]
                                        if not entry then
                                            entry = { key = key, name = m.Name, lastPos = pos, live = m, missed = 0 }
                                            espCache[key] = entry
                                        else
                                            entry.name = m.Name
                                            entry.lastPos = pos
                                            entry.live = m
                                            entry.missed = 0
                                        end
                                        if not entry.con then
                                            entry.con = m.AncestryChanged:Connect(function(_, parent)
                                                if not parent or not m:IsDescendantOf(WS) then
                                                    handleDespawn(m, key, center)
                                                end
                                            end)
                                        end
                                        attachToModel(entry, m, center)
                                    end
                                end
                            end
                        end
                    end

                    local charsFolder = charactersRootOrNil()
                    if charsFolder and selChars["Kiwi"] then
                        for _, m in ipairs(charsFolder:GetChildren()) do
                            if m and m:IsA("Model") and m.Name == "Kiwi" then
                                local mp = mainPart(m)
                                if mp then
                                    local pos = mp.Position
                                    local dist = (center - pos).Magnitude
                                    if dist <= (ESP_SCAN_RADIUS + 60) then
                                        local key = modelToKey[m]
                                        if not key then
                                            key = makeCharKeyFor(m, pos)
                                            modelToKey[m] = key
                                        end
                                        seenKeys[key] = true
                                        local entry = espCache[key]
                                        if not entry then
                                            entry = { key = key, name = m.Name, lastPos = pos, live = m, missed = 0 }
                                            espCache[key] = entry
                                        else
                                            entry.name = m.Name
                                            entry.lastPos = pos
                                            entry.live = m
                                            entry.missed = 0
                                        end
                                        if not entry.con then
                                            entry.con = m.AncestryChanged:Connect(function(_, parent)
                                                if not parent or not m:IsDescendantOf(WS) then
                                                    handleDespawn(m, key, center)
                                                end
                                            end)
                                        end
                                        attachToModel(entry, m, center)
                                    end
                                end
                            end
                        end
                    end

                    for key, entry in pairs(espCache) do
                        if entry.live then
                            local m = entry.live
                            if not m.Parent or not m:IsDescendantOf(WS) then
                                handleDespawn(m, key, center)
                            else
                                if not seenKeys[key] then
                                    entry.missed = (entry.missed or 0) + 1
                                    local mp = mainPart(m)
                                    if mp then
                                        entry.lastPos = mp.Position
                                        if isProbablyPickedOrDisabled(m, mp) then
                                            clearEntry(entry)
                                            espCache[key] = nil
                                        else
                                            local dist = (center - entry.lastPos).Magnitude
                                            if dist <= (ESP_SCAN_RADIUS + 30) and entry.missed >= MISSED_SCANS_REMOVE then
                                                clearEntry(entry)
                                                espCache[key] = nil
                                            else
                                                updateEntryVisual(entry, center)
                                            end
                                        end
                                    else
                                        if entry.missed >= MISSED_SCANS_REMOVE then
                                            clearEntry(entry)
                                            espCache[key] = nil
                                        else
                                            updateEntryVisual(entry, center)
                                        end
                                    end
                                else
                                    if entry.marker then
                                        updateEntryVisual(entry, center)
                                    end
                                end
                            end
                        else
                            if entry.marker and entry.lastPos then
                                updateEntryVisual(entry, center)
                            end
                        end
                    end
                end)
                if not ok then
                    warn("ESP scan error: " .. tostring(err))
                end
            end
            task.wait(SCAN_INTERVAL)
        end
    end)
end
