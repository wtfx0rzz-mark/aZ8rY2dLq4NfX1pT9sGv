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
        "UFO Junk","UFO Component"
    }
    local fuelItems = {"Log","Coal","Fuel Canister","Oil Barrel","Biofuel","Chair"}
    local foodItems = {
        "Morsel","Cooked Morsel","Steak","Cooked Steak","Ribs","Cooked Ribs","Cake","Berry","Carrot",
        "Chilli","Stew","Pumpkin","Hearty Stew","Corn","BBQ ribs","Apple","Mackerel"
    }
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {
        "Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Hammer",
        "Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot Shield","Spear","Tactical Shotgun","Wildfire",
        "Sword","Ice Axe","Thorn Body"
    }
    local ammoMisc = {
        "Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling",
        "Basketball","Blueprint","Diamond","Gem of the Forest Fragment","Key","Flashlight","Taming flute","Cultist Gem","Tusk","Infernal Sack"
    }
    local pelts = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Scorpion Shell","Polar Bear Pelt","Arctic Fox Pelt"}

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

    C.State.ESP = C.State.ESP or {}
    local S = C.State.ESP
    if S.Enabled == nil then S.Enabled = false end
    if S.CacheEnabled == nil then S.CacheEnabled = false end

    local selJunk, selFuel, selFood, selMedical, selWA, selMisc, selPelt = {},{},{},{},{},{},{}
    local activeSelection = {}

    local function mergeSet(dst, src)
        for k,v in pairs(src) do
            if v then dst[k] = true end
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
        activeSelection = dst
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

    local espCache = {}
    local modelToKey = setmetatable({}, { __mode = "k" })

    local function createBillboard(name)
        local pg = lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil end
        local gui = Instance.new("BillboardGui")
        gui.Name = "ESP_Item"
        gui.Size = UDim2.new(0, 200, 0, 40)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 10000
        gui.StudsOffset = Vector3.new(0, 3, 0)
        gui.Parent = pg

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.Font = Enum.Font.SourceSansBold
        lbl.TextScaled = true
        lbl.TextColor3 = Color3.fromRGB(0, 255, 0)
        lbl.TextStrokeTransparency = 0
        lbl.Text = name
        lbl.Parent = gui

        return gui, lbl
    end

    local function clearEntry(entry)
        if entry.con then
            entry.con:Disconnect()
            entry.con = nil
        end
        if entry.marker then
            entry.marker:Destroy()
            entry.marker = nil
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

    local function attachToModel(entry, model)
        local mp = mainPart(model)
        if not mp then return end
        entry.lastPos = mp.Position
        if not entry.marker then
            local gui, lbl = createBillboard(entry.name)
            if not gui then return end
            entry.marker = gui
            entry.label  = lbl
        end
        if entry.label then
            entry.label.Text = entry.name
        end
        if entry.ghostPart then
            entry.ghostPart:Destroy()
            entry.ghostPart = nil
        end
        local att = mp:FindFirstChild("__ESP_Att") or Instance.new("Attachment")
        att.Name = "__ESP_Att"
        att.Parent = mp
        entry.marker.Adornee = att
        entry.marker.Enabled = S.Enabled
    end

    local function attachGhost(entry)
        if not S.CacheEnabled then
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
        entry.marker.Enabled = S.Enabled
    end

    local function handleDespawn(model, key)
        local entry = espCache[key]
        if not entry then return end
        entry.live = nil
        if entry.con then
            entry.con:Disconnect()
            entry.con = nil
        end
        local root = hrp()
        local pos  = entry.lastPos
        local near = false
        if root and pos then
            near = (root.Position - pos).Magnitude <= LOCAL_PICKUP_RADIUS
        end
        if near then
            clearEntry(entry)
            espCache[key] = nil
        else
            attachGhost(entry)
        end
    end

    local function makeKeyFor(model, pos)
        local name = model.Name or "?"
        local gx = math.floor(pos.X / VERIFY_RADIUS)
        local gz = math.floor(pos.Z / VERIFY_RADIUS)
        return name .. "|" .. gx .. "|" .. gz
    end

    tab:Section({ Title = "ESP Controls" })
    tab:Toggle({
        Title = "Enable ESP",
        Default = S.Enabled,
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
        Default = S.CacheEnabled,
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
    tab:Button({
        Title = "Clear cached items not in selection",
        Callback = clearUnselectedCaches
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
                                if isUnderLogWall(m) or isWallVariant(m) then
                                    -- skip
                                else
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
                                            entry = { key = key, name = m.Name, lastPos = pos, live = m }
                                            espCache[key] = entry
                                        else
                                            entry.name = m.Name
                                            entry.lastPos = pos
                                            entry.live = m
                                        end
                                        if not entry.con then
                                            entry.con = m.AncestryChanged:Connect(function(_, parent)
                                                if not parent then
                                                    handleDespawn(m, key)
                                                end
                                            end)
                                        end
                                        attachToModel(entry, m)
                                    end
                                end
                            end
                        end
                    end

                    for key, entry in pairs(espCache) do
                        if entry.live and not seenKeys[key] then
                            local m = entry.live
                            if m and m.Parent then
                                local mp = mainPart(m)
                                if mp then
                                    entry.lastPos = mp.Position
                                end
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
