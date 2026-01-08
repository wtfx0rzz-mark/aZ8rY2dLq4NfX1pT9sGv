return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp  = Players.LocalPlayer
    local tab = UI and UI.Tabs and (UI.Tabs.TPBring or UI.Tabs.Bring or UI.Tabs.Auto or UI.Tabs.Main)
    if not tab then return end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function mainPart(m)
        if not m then return nil end
        if m:IsA("BasePart") then return m end
        if m:IsA("Model") then
            return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
        end
        return nil
    end

    local function allParts(m)
        local t = {}
        if not m then return t end
        if m:IsA("BasePart") then
            t[1] = m
            return t
        end
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                t[#t+1] = d
            end
        end
        return t
    end

    local function setPivot(m, cf)
        if not m then return end
        if m:IsA("Model") then
            m:PivotTo(cf)
        else
            local p = mainPart(m)
            if p then p.CFrame = cf end
        end
    end

    local function zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
            p.RotVelocity             = Vector3.new()
            p.Velocity                = Vector3.new()
        end
    end

    local function snapshotCollide(m)
        local s = {}
        for _,p in ipairs(allParts(m)) do
            s[p] = p.CanCollide
        end
        return s
    end

    local function setCollideFromSnapshot(snap)
        for part,can in pairs(snap or {}) do
            if part and part.Parent then
                part.CanCollide = can
            end
        end
    end

    local function setAnchored(m, on)
        for _,p in ipairs(allParts(m)) do
            p.Anchored = on
        end
    end

    local function setNoCollide(m)
        local s = {}
        for _,p in ipairs(allParts(m)) do
            s[p] = p.CanCollide
            p.CanCollide = false
        end
        return s
    end

    local startDrag, stopDrag = nil, nil
    do
        local re = RS:FindFirstChild("RemoteEvents")
        if re then
            startDrag = re:FindFirstChild("RequestStartDraggingItem")
            stopDrag  = re:FindFirstChild("StopDraggingItem")
        end
    end

    local DRAG_SPEED              = 420
    local ORB_HEIGHT              = 10
    local GROUND_ORB_DROP_HEIGHT  = 6
    local MAX_CONCURRENT          = 80
    local START_STAGGER           = 0.005
    local STEP_WAIT               = 0.016

    local LAND_MIN                = 0.35
    local LAND_MAX                = 0.85
    local ARRIVE_EPS_H            = 1.1
    local STALL_SEC               = 0.6

    local HOVER_ABOVE_ORB         = 1.2
    local RELEASE_RATE_HZ         = 18
    local MAX_RELEASE_PER_TICK    = 2

    local STAGE_TIMEOUT_S         = 1.5
    local ORB_UNSTICK_RAD         = 2.0
    local ORB_UNSTICK_HZ          = 10
    local STUCK_TTL               = 1.0

    local MAX_LINED_ITEMS         = 14

    local MAX_DIST_DEFAULT        = 500
    local MAX_DIST_ORBS_DEFAULT   = 50
    local maxDistOrbs             = MAX_DIST_ORBS_DEFAULT

    local SKY_RAY_START_Y         = 320
    local SKY_RAY_LEN             = 900
    local PLACE_UP                = 1.6

    local AIR_RELEASE_UP          = 0.6
    local SPIRAL_STEP             = 0.8
    local SPIRAL_MAX_RADIUS       = 8.0
    local GOLDEN_ANGLE            = 2.399963229728653

    local INFLT_ATTR = "OrbInFlightAt"
    local JOB_ATTR   = "OrbJob"
    local DONE_ATTR  = "OrbDelivered"

    local CURRENT_RUN_ID   = nil
    local CURRENT_MODE     = nil

    local running      = false
    local hb           = nil
    local orb          = nil
    local orbPosVec    = nil
    local inflight     = {}
    local releaseQueue = {}
    local releaseAcc   = 0.0
    local activeCount  = 0
    local unstickConn  = nil
    local preclaimConn = nil
    local waveAcc      = 0.0
    local finalized    = {}
    local fruitNudged  = {}
    local dropStacks   = {}

    local junkItems = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "UFO Junk","UFO Component"
    }
    local fuelItems = {"Log","Coal","Fuel Canister","Oil Barrel"}
    local foodItems = {
        "Morsel","Cooked Morsel","Steak","Cooked Steak","Ribs","Cooked Ribs","Cake","Berry","Carrot",
        "Chilli","Stew","Pumpkin","Hearty Stew","Corn","BBQ ribs","Apple","Mackerel"
    }
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {
        "Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Hammer",
        "Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot shield","Spear","Tactical Shotgun","Wildfire",
        "Sword","Ice Axe","Thorn Body"
    }
    local ammoMisc = {
        "Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling",
        "Basketball","Blueprint","Diamond","Forest Gem","Key","Flashlight","Taming flute","Cultist Gem","Tusk","Infernal Sack"
    }
    local pelts = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Scorpion Shell","Polar Bear Pelt","Arctic Fox Pelt"}

    local fuelSet, junkSet, preDragImportantSet = {}, {}, {}
    for _,n in ipairs(fuelItems) do fuelSet[n] = true end
    for _,n in ipairs(junkItems) do junkSet[n] = true end
    for _,n in ipairs(weaponsArmor) do preDragImportantSet[n] = true end
    for _,n in ipairs({
        "Giant Sack","Good Sack","Blueprint","Forest Gem","Key","Flashlight","Strong Flashlight","Taming flute","Cultist Gem","Tusk","Infernal Sack"
    }) do preDragImportantSet[n] = true end

    local fuelModeSet = { ["Coal"] = true, ["Fuel Canister"] = true, ["Oil Barrel"] = true, ["Log"] = true }
    local scrapModeSet = {}
    for k,v in pairs(junkSet) do if v then scrapModeSet[k] = true end end
    scrapModeSet["Log"] = true

    local allModeSet = {}
    local function addListToSet(list, set)
        for _,n in ipairs(list) do set[n] = true end
    end
    local function addSetToSet(src, dst)
        for k,v in pairs(src) do if v then dst[k] = true end end
    end
    addSetToSet(junkSet, allModeSet)
    addSetToSet(fuelSet, allModeSet)
    addListToSet(foodItems, allModeSet)
    addListToSet(medicalItems, allModeSet)
    addListToSet(weaponsArmor, allModeSet)
    addListToSet(ammoMisc, allModeSet)
    addListToSet(pelts, allModeSet)

    local groupedItemValues = {}
    local function appendListIntoGrouped(list)
        for _,name in ipairs(list) do
            if allModeSet[name] then
                groupedItemValues[#groupedItemValues+1] = name
            end
        end
    end
    appendListIntoGrouped(junkItems)
    appendListIntoGrouped(fuelItems)
    appendListIntoGrouped(foodItems)
    appendListIntoGrouped(medicalItems)
    appendListIntoGrouped(weaponsArmor)
    appendListIntoGrouped(ammoMisc)
    appendListIntoGrouped(pelts)

    local function cloneArray(src)
        local t = {}
        for i,v in ipairs(src) do t[i] = v end
        return t
    end

    local function itemsRootOrNil()
        return WS:FindFirstChild("Items")
    end

    local function hasHumanoid(model)
        if not (model and model:IsA("Model")) then return false end
        return model:FindFirstChildOfClass("Humanoid") ~= nil
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

    local function hasIceBlockTag(inst)
        if not inst then return false end
        if inst:IsA("Model") then
            for _,d in ipairs(inst:GetDescendants()) do
                local n = (d.Name or ""):lower()
                if n:find("iceblock",1,true) or n:find("ice block",1,true) then
                    return true
                end
            end
        end
        local cur = inst.Parent
        for _ = 1, 10 do
            if not cur then break end
            local n = (cur.Name or ""):lower()
            if n:find("iceblock",1,true) or n:find("ice block",1,true) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end

    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        if n == "pelt trader" then return true end
        if n:find("trader",1,true) or n:find("shopkeeper",1,true) then return true end
        if isWallVariant(m) then return true end
        if isUnderLogWall(m) then return true end
        return false
    end

    local function isExcludedInst(inst)
        if not inst then return true end
        if inst:IsA("Model") then
            if isExcludedModel(inst) then return true end
        end
        if isUnderLogWall(inst) then return true end
        if hasIceBlockTag(inst) then return true end
        return false
    end

    local function isInsideTree(inst)
        local cur = inst and inst.Parent
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm:find("tree",1,true) or nm:find("bush",1,true) then return true end
            if cur == itemsRootOrNil() then break end
            cur = cur.Parent
        end
        return false
    end

    local ALLOW_OUTSIDE_ITEMS = { ["Log"] = true }

    local function nameMatches(selectedSet, m)
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then
            local nm0 = m and m.Name or ""
            if not (ALLOW_OUTSIDE_ITEMS[nm0] and selectedSet and selectedSet[nm0]) then
                return false
            end
        end

        local nm = m and m.Name or ""
        local l  = nm:lower()

        if nm == "Apple" and selectedSet["Apple"] then
            if itemsFolder and m.Parent ~= itemsFolder then return false end
            if isInsideTree(m) then return false end
            return true
        end
        if nm == "Berry" and selectedSet["Berry"] then
            if itemsFolder and m.Parent ~= itemsFolder then return false end
            if isInsideTree(m) then return false end
            return true
        end
        if selectedSet[nm] then return true end
        if selectedSet["Mossy Coin"] and (nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$")) then return true end
        if selectedSet["Cultist"] and m:IsA("Model") and l:find("cultist",1,true) and hasHumanoid(m) then return true end
        if selectedSet["Alpha Wolf Pelt"] and l:find("alpha",1,true) and l:find("wolf",1,true) then return true end
        if selectedSet["Bear Pelt"] and l:find("bear",1,true) and not l:find("polar",1,true) then return true end
        if selectedSet["Spear"] and l:find("spear",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Sword"] and l:find("sword",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Crossbow"] and l:find("crossbow",1,true) and not l:find("cultist",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Blueprint"] and l:find("blueprint",1,true) then return true end
        if (selectedSet["Flashlight"] or selectedSet["Strong Flashlight"]) and l:find("flashlight",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Cultist Gem"] and l:find("cultist",1,true) and l:find("gem",1,true) then return true end
        if selectedSet["Forest Gem"] and (l:find("forest gem",1,true) or (l:find("forest",1,true) and l:find("fragment",1,true))) then return true end
        if selectedSet["Tusk"] and l:find("tusk",1,true) then return true end
        return false
    end

    local function isPreDragImportantModel(m)
        return nameMatches(preDragImportantSet, m)
    end

    local function isFruitModel(m)
        local nm = m and m.Name or ""
        return nm == "Apple" or nm == "Berry"
    end

    local function topModelUnderItems(part, itemsFolder)
        local cur = part
        local lastModel = nil
        while cur and cur ~= WS and cur ~= itemsFolder do
            if cur:IsA("Model") then lastModel = cur end
            cur = cur.Parent
        end
        if lastModel and itemsFolder and lastModel.Parent == itemsFolder then return lastModel end
        return lastModel
    end

    local function nearestSelectedModelFromPart(part, selectedSet)
        if not part or not part:IsA("BasePart") then return nil end
        local itemsFolder = itemsRootOrNil()
        local m = topModelUnderItems(part, itemsFolder) or part:FindFirstAncestorOfClass("Model")
        if m and nameMatches(selectedSet, m) then return m end
        if nameMatches(selectedSet, part) then return part end
        return nil
    end

    local function tryStartDrag(m, rec)
        if not startDrag then return end
        if rec and rec.dragging then return end
        pcall(function() startDrag:FireServer(m) end)
        if rec then rec.dragging = true end
    end

    local function tryStopDrag(m, rec)
        if not stopDrag then return end
        if rec and rec.stopped then return end
        if rec and not rec.dragging then return end
        pcall(function() stopDrag:FireServer(m) end)
        if rec then rec.stopped = true end
    end

    local function fruitPreNudge(m)
        if not isFruitModel(m) then return end
        if not (m and m.Parent) then return end
        if fruitNudged[m] then return end
        if inflight[m] and inflight[m].dragging then return end

        local mp = mainPart(m)
        if not mp then return end
        fruitNudged[m] = true

        task.spawn(function()
            local tmp = { dragging = false, stopped = false }
            tryStartDrag(m, tmp)

            for _,p in ipairs(allParts(m)) do
                pcall(function() p:SetNetworkOwner(lp) end)
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end

            local mass = math.max(mp:GetMass(), 1)
            local dir = Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
            if dir.Magnitude < 0.2 then dir = Vector3.new(1, 0, 0) else dir = dir.Unit end

            pcall(function()
                mp:ApplyImpulse(dir * (120 * mass) + Vector3.new(0, 80 * mass, 0))
            end)

            pcall(function()
                mp:ApplyAngularImpulse(Vector3.new(
                    (math.random() - 0.5) * 300,
                    (math.random() - 0.5) * 300,
                    (math.random() - 0.5) * 300
                ) * mass)
            end)

            task.delay(0.18, function()
                tryStopDrag(m, tmp)
            end)

            task.delay(0.9, function()
                for _,p in ipairs(allParts(m)) do
                    pcall(function() p:SetNetworkOwner(nil) end)
                    pcall(function()
                        if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end
                    end)
                end
            end)
        end)
    end

    local function markDoneThisRun(m)
        if not (m and m.Parent) then return end
        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
            if CURRENT_RUN_ID then m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID) end
        end)
        finalized[m] = true
        inflight[m] = nil
    end

    local function canPick(m, selectedSet, jobId)
        if not (m and m.Parent) then return false end
        if not (m:IsA("Model") or m:IsA("BasePart")) then return false end
        if finalized[m] then return false end

        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then
            local nm0 = m.Name or ""
            if not (ALLOW_OUTSIDE_ITEMS[nm0] and selectedSet and selectedSet[nm0]) then
                return false
            end
        end

        if isExcludedInst(m) then return false end

        local done = m:GetAttribute(DONE_ATTR)
        if done and CURRENT_RUN_ID and tostring(done) == tostring(CURRENT_RUN_ID) then return false end

        local tIn = m:GetAttribute(INFLT_ATTR)
        local jIn = m:GetAttribute(JOB_ATTR)
        local age = tIn and (os.clock() - tIn) or nil
        if tIn and jIn and tostring(jIn) ~= tostring(jobId) and age and age < STUCK_TTL then
            return false
        end
        if not nameMatches(selectedSet, m) then return false end
        return true
    end

    local function currentSelectedSet()
        if CURRENT_MODE == "fuel" then return fuelModeSet end
        if CURRENT_MODE == "scrap" then return scrapModeSet end
        if CURRENT_MODE == "all" then return allModeSet end
        return nil
    end

    local CUSTOM_ORB_BASES = {
        Vector3.new(-27.85, 4.05 + GROUND_ORB_DROP_HEIGHT, 50.82),
        Vector3.new( -6.68, 4.05 + GROUND_ORB_DROP_HEIGHT, 47.66),
        Vector3.new( 14.50, 4.05 + GROUND_ORB_DROP_HEIGHT, 44.50),
        Vector3.new( 35.67, 4.05 + GROUND_ORB_DROP_HEIGHT, 41.33),
    }
    local orbGroundBases = { nil, nil, nil, nil }

    local function computeOrbGroundBase(index)
        local base = CUSTOM_ORB_BASES[index]
        if not base then return nil end

        local origin = base + Vector3.new(0, 80, 0)
        local dir    = Vector3.new(0, -300, 0)

        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Blacklist
        local ignore = {}
        local itemsFolder = itemsRootOrNil()
        if itemsFolder then ignore[#ignore+1] = itemsFolder end
        local ch = lp.Character
        if ch then ignore[#ignore+1] = ch end
        rp.FilterDescendantsInstances = ignore
        rp.IgnoreWater = true

        local result = WS:Raycast(origin, dir, rp)
        if result and result.Position then return result.Position end
        return base
    end

    local function getOrbBasePosition(index)
        if not orbGroundBases[index] then
            orbGroundBases[index] = computeOrbGroundBase(index)
        end
        return orbGroundBases[index]
    end

    local orbItemSets = { {}, {}, {}, {} }
    local orbEnabled = { false, false, false, false }
    local orbUnionSet = {}

    local function recomputeOrbUnionSet()
        orbUnionSet = {}
        for i = 1, 4 do
            if orbEnabled[i] then
                for name,_ in pairs(orbItemSets[i]) do orbUnionSet[name] = true end
            end
        end
    end

    local function orbIndexForModel(m)
        for i = 1, 4 do
            local set = orbItemSets[i]
            if orbEnabled[i] and next(set) ~= nil and nameMatches(set, m) then
                return i
            end
        end
        return nil
    end

    local orbDropdownValues = {
        cloneArray(groupedItemValues),
        cloneArray(groupedItemValues),
        cloneArray(groupedItemValues),
        cloneArray(groupedItemValues),
    }

    local overlapParams = OverlapParams.new()
    overlapParams.MaxParts = 1000

    local function refreshOverlapFilter(selectedSet)
        local itemsFolder = itemsRootOrNil()
        local allowOutside = (selectedSet and selectedSet["Log"]) and true or false

        if itemsFolder and not allowOutside then
            overlapParams.FilterType = Enum.RaycastFilterType.Include
            overlapParams.FilterDescendantsInstances = { itemsFolder }
        else
            overlapParams.FilterType = Enum.RaycastFilterType.Exclude
            overlapParams.FilterDescendantsInstances = { lp.Character }
        end
    end

    local function collectCandidatesFromSet_FullScan(selectedSet, jobId, maxDist)
        if not selectedSet then return {} end
        local itemsFolder = itemsRootOrNil()
        local root = hrp()
        if not root then return {} end
        local rootPos = root.Position

        local uniq, out = {}, {}

        if itemsFolder then
            for _,d in ipairs(itemsFolder:GetDescendants()) do
                local m = nil
                if d:IsA("Model") then
                    if nameMatches(selectedSet, d) then m = d end
                elseif d:IsA("BasePart") then
                    m = nearestSelectedModelFromPart(d, selectedSet)
                end
                if m and not uniq[m] and canPick(m, selectedSet, jobId) then
                    local mp = mainPart(m)
                    if mp then
                        local dist = (mp.Position - rootPos).Magnitude
                        if (not maxDist) or dist <= maxDist then
                            uniq[m] = true
                            out[#out+1] = m
                        end
                    end
                end
            end
        end

        if selectedSet["Log"] then
            for _,d in ipairs(WS:GetDescendants()) do
                if d:IsA("BasePart") and d.Name == "Log" then
                    local m = nearestSelectedModelFromPart(d, selectedSet) or d
                    if m and not uniq[m] and canPick(m, selectedSet, jobId) then
                        local mp = mainPart(m)
                        if mp then
                            local dist = (mp.Position - rootPos).Magnitude
                            if (not maxDist) or dist <= maxDist then
                                uniq[m] = true
                                out[#out+1] = m
                            end
                        end
                    end
                end
            end
        end

        return out
    end

    local function collectCandidatesFromSet(selectedSet, jobId, maxDist)
        if not selectedSet then return {} end
        local itemsFolder = itemsRootOrNil()
        if not itemsFolder and not selectedSet["Log"] then return {} end

        local root = hrp()
        if not root then return {} end
        local origin = root.Position
        local rad = maxDist or MAX_DIST_DEFAULT

        refreshOverlapFilter(selectedSet)

        local ok, parts = pcall(function()
            return WS:GetPartBoundsInRadius(origin, rad, overlapParams)
        end)

        if not ok or type(parts) ~= "table" then
            return collectCandidatesFromSet_FullScan(selectedSet, jobId, maxDist)
        end

        local uniq, out = {}, {}
        for _,p in ipairs(parts) do
            if p and p.Parent and p:IsA("BasePart") then
                local m = nearestSelectedModelFromPart(p, selectedSet)
                if m and not uniq[m] and canPick(m, selectedSet, jobId) then
                    uniq[m] = true
                    out[#out+1] = m
                end
            end
        end

        if selectedSet["Log"] and #out == 0 then
            return collectCandidatesFromSet_FullScan(selectedSet, jobId, maxDist)
        end

        return out
    end

    local function getCandidatesForCurrent(jobId)
        return collectCandidatesFromSet(currentSelectedSet(), jobId, MAX_DIST_DEFAULT)
    end

    local function getCandidatesForOrbs(jobId)
        return collectCandidatesFromSet(orbUnionSet, jobId, maxDistOrbs)
    end

    local function spawnOrbAt(pos, color)
        if orb then pcall(function() orb:Destroy() end) end
        local o = Instance.new("Part")
        o.Name = "tp_orb_fixed"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.5,1.5,1.5)
        o.Material = Enum.Material.Neon
        o.Color = color or Color3.fromRGB(80,180,255)
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.CFrame = CFrame.new(pos)
        o.Parent = WS
        local l = Instance.new("PointLight")
        l.Range = 16
        l.Brightness = 2.5
        l.Parent = o
        orb = o
        orbPosVec = orb.Position
    end

    local function destroyOrb()
        if orb then pcall(function() orb:Destroy() end) end
        orb = nil
        orbPosVec = nil
    end

    local function hash01(s)
        local h = 131071
        for i = 1, #s do h = (h * 131 + string.byte(s, i)) % 1000003 end
        return (h % 100000) / 100000
    end

    local function landingOffset(m, jobId)
        local key = (typeof(m.GetDebugId)=="function" and m:GetDebugId() or (m.Name or "")) .. tostring(jobId)
        local r1 = hash01(key .. "a")
        local r2 = hash01(key .. "b")
        local ang = r1 * math.pi * 2
        local rad = LAND_MIN + (LAND_MAX - LAND_MIN) * r2
        return Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
    end

    local function spiralOffset(destKey, idx)
        local phase = hash01(tostring(destKey or "k")) * (math.pi * 2)
        local ang = idx * GOLDEN_ANGLE + phase
        local rad = math.min(SPIRAL_MAX_RADIUS, SPIRAL_STEP * math.sqrt(math.max(idx, 1)))
        return Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
    end

    local function campfireOrbPos()
        local fire = WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Campground") and WS.Map.Campground:FindFirstChild("MainFire")
        if not fire then return nil end
        local mp = mainPart(fire)
        local cf = (mp and mp.CFrame) or fire:GetPivot()
        return cf.Position + Vector3.new(0, ORB_HEIGHT + 8, 0)
    end

    local function scrapperOrbPos()
        local scr = WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Campground") and WS.Map.Campground:FindFirstChild("Scrapper")
        if not scr then return nil end
        local mp = mainPart(scr)
        local cf = (mp and mp.CFrame) or scr:GetPivot()
        return cf.Position + Vector3.new(0, ORB_HEIGHT + 8, 0)
    end

    local function noticeOrbPos()
        local map = WS:FindFirstChild("Map")
        if not map then return nil end
        local camp = map:FindFirstChild("Campground")
        if not camp then return nil end
        local board = camp:FindFirstChild("NoticeBoard")
        if not board then
            for _,d in ipairs(camp:GetDescendants()) do
                if d:IsA("Model") and d.Name == "NoticeBoard" then board = d break end
            end
        end
        if not board then return nil end

        local mp = mainPart(board)
        if not mp then
            local cf = board:GetPivot()
            return cf.Position + Vector3.new(0, ORB_HEIGHT + 4, 0)
        end
        local cf = mp.CFrame
        local forward = cf.LookVector
        local edgeOffset = (mp.Size.Z * 0.5) + 1.0
        local pos = cf.Position + forward * edgeOffset
        return pos + Vector3.new(0, ORB_HEIGHT + 1, 0)
    end

    local function raycastDownAtXZ(xz, ignoreModel)
        local itemsFolder = itemsRootOrNil()
        local ch = lp.Character
        local origin = Vector3.new(xz.X, SKY_RAY_START_Y, xz.Z)
        local dir = Vector3.new(0, -SKY_RAY_LEN, 0)

        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Blacklist
        local ignore = {}
        if ignoreModel then ignore[#ignore+1] = ignoreModel end
        if itemsFolder then ignore[#ignore+1] = itemsFolder end
        if ch then ignore[#ignore+1] = ch end
        rp.FilterDescendantsInstances = ignore
        rp.IgnoreWater = true

        local res = WS:Raycast(origin, dir, rp)
        if res and res.Position then return res.Position end
        return Vector3.new(xz.X, 0, xz.Z)
    end

    local function stageForRelease(m, snap, tgt, destKey, centerXZ, dropKind)
        setAnchored(m, true)
        for _,p in ipairs(allParts(m)) do
            p.CanCollide = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        if tgt then
            setPivot(m, CFrame.new(tgt))
        end
        local info = inflight[m]
        if info then
            info.staged = true
            info.stagedAt = os.clock()
            info.snap = snap
        end
        releaseQueue[#releaseQueue+1] = { model = m, snap = snap, destKey = destKey or "default", centerXZ = centerXZ, dropKind = dropKind or "ground" }
    end

    local function releaseOne(rec)
        local m = rec and rec.model
        if not (m and m.Parent) then return end

        local info = inflight[m]
        local snap = (rec and rec.snap) or (info and info.snap) or snapshotCollide(m)
        if info then tryStopDrag(m, info) end

        local key = rec and rec.destKey or "default"
        dropStacks[key] = (dropStacks[key] or 0) + 1
        local idx = dropStacks[key]
        local off2d = spiralOffset(key, idx)

        if rec and rec.dropKind == "air" and orbPosVec then
            local pos = orbPosVec + off2d + Vector3.new(0, AIR_RELEASE_UP, 0)
            setPivot(m, CFrame.new(pos))
            setAnchored(m, false)
            zeroAssembly(m)
            setCollideFromSnapshot(snap)
            for _,p in ipairs(allParts(m)) do
                p.AssemblyAngularVelocity = Vector3.new()
                p.AssemblyLinearVelocity  = Vector3.new()
                pcall(function() p:SetNetworkOwner(nil) end)
                pcall(function()
                    if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end
                end)
            end
            markDoneThisRun(m)
            return
        end

        local center = rec and rec.centerXZ
        if not center then
            local mp = mainPart(m)
            local p = (mp and mp.Position) or Vector3.new()
            center = Vector3.new(p.X, 0, p.Z)
        end

        local xz = Vector3.new(center.X + off2d.X, 0, center.Z + off2d.Z)
        local hit = raycastDownAtXZ(xz, m)
        local placePos = hit + Vector3.new(0, PLACE_UP, 0)

        setPivot(m, CFrame.new(placePos))
        setAnchored(m, false)
        zeroAssembly(m)
        setCollideFromSnapshot(snap)

        for _,p in ipairs(allParts(m)) do
            p.AssemblyAngularVelocity = Vector3.new()
            p.AssemblyLinearVelocity  = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function()
                if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end
            end)
        end

        markDoneThisRun(m)
    end

    local function abortRestore(m, rec)
        if rec and rec.counted then
            rec.counted = false
            activeCount = math.max(0, activeCount - 1)
        end
        if not (m and m.Parent) then
            inflight[m] = nil
            return
        end
        tryStopDrag(m, rec)
        setAnchored(m, false)
        setCollideFromSnapshot(rec and rec.snap or snapshotCollide(m))
        zeroAssembly(m)
        for _,p in ipairs(allParts(m)) do
            p.AssemblyAngularVelocity = Vector3.new()
            p.AssemblyLinearVelocity  = Vector3.new()
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function()
                if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end
            end)
        end
        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
        end)
        inflight[m] = nil
    end

    local function startConveyor(m, jobId, destBaseVec, destKey, dropKind)
        if not (running and m and m.Parent) then return end
        local mp = mainPart(m)
        if not mp then return end
        if not destBaseVec then return end

        if isFruitModel(m) then fruitPreNudge(m) end

        local off = landingOffset(m, jobId)
        local function target()
            return Vector3.new(destBaseVec.X + off.X, destBaseVec.Y + HOVER_ABOVE_ORB, destBaseVec.Z + off.Z)
        end

        pcall(function()
            m:SetAttribute(INFLT_ATTR, os.clock())
            m:SetAttribute(JOB_ATTR, jobId)
        end)

        local snap = setNoCollide(m)
        setAnchored(m, true)
        zeroAssembly(m)

        local centerXZ = Vector3.new(destBaseVec.X, 0, destBaseVec.Z)
        local rec = { snap = snap, conn = nil, lastD = math.huge, lastT = os.clock(), staged = false, dragging = false, stopped = false, counted = true, destKey = destKey or "default", off = off, centerXZ = centerXZ, dropKind = dropKind or "ground" }
        inflight[m] = rec
        activeCount = activeCount + 1

        tryStartDrag(m, rec)

        rec.conn = Run.Heartbeat:Connect(function(dt)
            if not (running and m and m.Parent) then
                if rec.conn then rec.conn:Disconnect() end
                abortRestore(m, rec)
                return
            end
            if rec.staged then return end

            local pivot = m:GetPivot and m:GetPivot() or nil
            local pos = (pivot and pivot.Position) or (mainPart(m) and mainPart(m).Position) or nil
            if not pos then
                if rec.conn then rec.conn:Disconnect() end
                abortRestore(m, rec)
                return
            end

            local tgt = target()
            local flatDelta = Vector3.new(tgt.X - pos.X, 0, tgt.Z - pos.Z)
            local distH = flatDelta.Magnitude

            if distH <= ARRIVE_EPS_H and math.abs(tgt.Y - pos.Y) <= 1.2 then
                tryStopDrag(m, rec)
                if rec.counted then
                    rec.counted = false
                    activeCount = math.max(0, activeCount - 1)
                end
                stageForRelease(m, snap, tgt, rec.destKey, rec.centerXZ, rec.dropKind)
                if rec.conn then rec.conn:Disconnect() end
                return
            end

            if distH >= rec.lastD - 0.02 then
                if os.clock() - rec.lastT >= STALL_SEC then
                    off = landingOffset(m, tostring(jobId) .. tostring(os.clock()))
                    rec.off = off
                    rec.lastT = os.clock()
                end
            else
                rec.lastT = os.clock()
            end
            rec.lastD = distH

            local step = math.min(DRAG_SPEED * dt, math.max(0, distH))
            local dir  = distH > 1e-3 and (flatDelta / math.max(distH,1e-3)) or Vector3.new()
            local vy   = math.clamp((tgt.Y - pos.Y), -7, 7)
            local newPos = Vector3.new(pos.X, pos.Y + vy * dt * 10, pos.Z) + dir * step
            local look = (dir.Magnitude > 0 and dir) or Vector3.new(0,0,1)
            setPivot(m, CFrame.new(newPos, newPos + look))
        end)
    end

    local function flushStaleStaged()
        local now = os.clock()
        for m,info in pairs(inflight) do
            if info and info.staged and (now - (info.stagedAt or now)) >= STAGE_TIMEOUT_S then
                local queued = false
                for _,rec in ipairs(releaseQueue) do
                    if rec.model == m then queued = true break end
                end
                if not queued then
                    releaseQueue[#releaseQueue+1] = { model = m, snap = info.snap or snapshotCollide(m), destKey = info.destKey or "default", centerXZ = info.centerXZ, dropKind = info.dropKind or "ground" }
                end
            end
        end
    end

    local function teleportModelToGround(m)
        local mp = mainPart(m)
        if not (mp and mp.Parent) then return end
        local xz = Vector3.new(mp.Position.X, 0, mp.Position.Z)
        local hit = raycastDownAtXZ(xz, m)
        setPivot(m, CFrame.new(hit + Vector3.new(0, PLACE_UP, 0)))
    end

    local function setUnstickEnabled(on)
        if on then
            if unstickConn then return end
            local acc = 0
            unstickConn = Run.Heartbeat:Connect(function(dt)
                if not (running and orbPosVec) then return end
                acc = acc + dt
                if acc < (1 / ORB_UNSTICK_HZ) then return end
                acc = 0

                local itemsFolder = itemsRootOrNil()
                if not itemsFolder then return end
                local ch = lp.Character
                local root = ch and ch:FindFirstChild("HumanoidRootPart")
                if not root then return end

                local originBase = root.Position + Vector3.new(0, 5, 0)
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Whitelist
                rp.FilterDescendantsInstances = {itemsFolder}
                rp.IgnoreWater = true

                local directions = {
                    Vector3.new(1,0,0),Vector3.new(-1,0,0),Vector3.new(0,0,1),Vector3.new(0,0,-1),
                    Vector3.new(1,0,1).Unit,Vector3.new(-1,0,1).Unit,Vector3.new(1,0,-1).Unit,Vector3.new(-1,0,-1).Unit,
                }
                local RAY_DISTANCE = 200
                local seen = {}
                local now = os.clock()

                local function handleHit(result)
                    if not result or not result.Instance then return end
                    local m = result.Instance:FindFirstAncestorOfClass("Model") or result.Instance
                    if not m or seen[m] then return end
                    seen[m] = true

                    local mp = mainPart(m)
                    if not mp then return end
                    if (mp.Position - orbPosVec).Magnitude > ORB_UNSTICK_RAD then return end

                    local tIn  = m:GetAttribute(INFLT_ATTR)
                    local jIn  = m:GetAttribute(JOB_ATTR)
                    local info = inflight[m]
                    local age  = tIn and (now - tIn) or nil

                    local stuck = false
                    if not tIn or not jIn then stuck = true end
                    if not info then stuck = true end
                    if age and age >= STUCK_TTL then stuck = true end
                    if not stuck then return end

                    finalized[m] = true
                    inflight[m] = nil
                    teleportModelToGround(m)

                    for _,p in ipairs(allParts(m)) do
                        p.Anchored = false
                        p.AssemblyAngularVelocity = Vector3.new()
                        p.AssemblyLinearVelocity  = Vector3.new()
                        p.CanCollide = true
                        pcall(function() p:SetNetworkOwner(nil) end)
                        pcall(function()
                            if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end
                        end)
                    end
                end

                for _,dir in ipairs(directions) do
                    handleHit(WS:Raycast(originBase, dir * RAY_DISTANCE, rp))
                end
            end)
        else
            if unstickConn then unstickConn:Disconnect() end
            unstickConn = nil
        end
    end

    local function wave()
        if not CURRENT_MODE then return end
        local jobId = tostring(os.clock())

        if CURRENT_MODE == "orbs" then
            local list = getCandidatesForOrbs(jobId)
            for i = 1, #list do
                if not running then break end
                if #releaseQueue >= MAX_LINED_ITEMS then break end
                if activeCount >= MAX_CONCURRENT then break end

                local m = list[i]
                if m and m.Parent and not inflight[m] then
                    local idx = orbIndexForModel(m)
                    if idx then
                        local base = getOrbBasePosition(idx)
                        if base then
                            startConveyor(m, jobId, base, "orb"..tostring(idx), "ground")
                            task.wait(START_STAGGER)
                        end
                    end
                end
            end
            return
        end

        local list = getCandidatesForCurrent(jobId)
        for i = 1, #list do
            if not running then break end
            if #releaseQueue >= MAX_LINED_ITEMS then break end
            if activeCount >= MAX_CONCURRENT then break end

            local m = list[i]
            if m and m.Parent and not inflight[m] then
                local dest = orbPosVec
                if dest then
                    local kind = (CURRENT_MODE == "fuel" or CURRENT_MODE == "scrap") and "air" or "ground"
                    startConveyor(m, jobId, dest, "main", kind)
                    task.wait(START_STAGGER)
                end
            end
        end
    end

    local function stopAll()
        running = false
        if hb then hb:Disconnect() hb = nil end
        setUnstickEnabled(false)

        for i = 1, #releaseQueue do
            local rec = releaseQueue[i]
            if rec and rec.model and rec.model.Parent then
                releaseOne(rec)
            end
        end
        releaseQueue = {}

        for m,rec in pairs(inflight) do
            if rec and rec.conn then rec.conn:Disconnect() end
            abortRestore(m, rec)
        end

        inflight = {}
        activeCount = 0
        destroyOrb()
    end

    local PRECLAIM_DISTANCE    = 100
    local PRECLAIM_INTERVAL_S  = 2.5
    local PRECLAIM_TTL_S       = 18.0
    local preclaimAcc          = 0
    local preclaimEnabled      = false
    local preclaimedAt         = {}

    local function setPreclaimEnabled(state)
        preclaimEnabled = state and true or false
        if preclaimEnabled then
            if preclaimConn then return end
            preclaimAcc = 0
            preclaimConn = Run.Heartbeat:Connect(function(dt)
                preclaimAcc = preclaimAcc + dt
                if preclaimAcc < PRECLAIM_INTERVAL_S then return end
                preclaimAcc = 0
                if not preclaimEnabled then return end
                if not (startDrag and stopDrag) then return end

                local itemsFolder = itemsRootOrNil()
                if not itemsFolder then return end
                local campPos = campfireOrbPos()
                if not campPos then return end

                local ch = lp.Character
                local root = ch and ch:FindFirstChild("HumanoidRootPart")
                if not root then return end

                local originBase = root.Position + Vector3.new(0, 5, 0)
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Whitelist
                rp.FilterDescendantsInstances = {itemsFolder}
                rp.IgnoreWater = true

                local directions = {
                    Vector3.new(1,0,0),Vector3.new(-1,0,0),Vector3.new(0,0,1),Vector3.new(0,0,-1),
                    Vector3.new(1,0,1).Unit,Vector3.new(-1,0,1).Unit,Vector3.new(1,0,-1).Unit,Vector3.new(-1,0,-1).Unit,
                }
                local RAY_DISTANCE = 200
                local seen = {}
                local now = os.clock()

                local function handleHit(result)
                    if not result or not result.Instance then return end
                    local m = result.Instance:FindFirstAncestorOfClass("Model")
                    if not m or seen[m] then return end
                    seen[m] = true
                    if not m.Parent then return end
                    if inflight[m] then return end
                    if isExcludedInst(m) then return end
                    if not isPreDragImportantModel(m) then return end

                    local mp = mainPart(m)
                    if not mp then return end
                    if (mp.Position - campPos).Magnitude <= PRECLAIM_DISTANCE then return end

                    local last = preclaimedAt[m]
                    if last and (now - last) < PRECLAIM_TTL_S then return end
                    preclaimedAt[m] = now

                    pcall(function() startDrag:FireServer(m) end)
                    task.delay(0.14, function()
                        pcall(function() stopDrag:FireServer(m) end)
                    end)
                end

                for _,dir in ipairs(directions) do
                    handleHit(WS:Raycast(originBase, dir * RAY_DISTANCE, rp))
                end
            end)
        else
            if preclaimConn then preclaimConn:Disconnect() end
            preclaimConn = nil
        end
    end

    local function startMode(mode)
        if mode == nil then
            CURRENT_MODE = nil
            setPreclaimEnabled(false)
            stopAll()
            return
        end
        if not hrp() then return end
        if CURRENT_MODE == mode and running then return end

        stopAll()
        CURRENT_MODE   = mode
        CURRENT_RUN_ID = tostring(os.clock())
        finalized      = {}
        fruitNudged    = {}
        dropStacks     = {}

        if mode == "fuel" or mode == "scrap" or mode == "all" then
            local pos, color
            if mode == "fuel" then
                pos   = campfireOrbPos()
                color = Color3.fromRGB(255,200,50)
            elseif mode == "scrap" then
                pos   = scrapperOrbPos()
                color = Color3.fromRGB(120,255,160)
            elseif mode == "all" then
                pos   = noticeOrbPos()
                color = Color3.fromRGB(100,200,255)
            end
            if not pos then CURRENT_MODE = nil return end
            spawnOrbAt(pos, color)
            setUnstickEnabled(true)
        elseif mode == "orbs" then
            local any = false
            for i = 1, 4 do
                if orbEnabled[i] and next(orbItemSets[i]) ~= nil then any = true break end
            end
            if not any then CURRENT_MODE = nil return end
            destroyOrb()
            orbPosVec = nil
            orbGroundBases = { nil, nil, nil, nil }
            setUnstickEnabled(false)
        else
            CURRENT_MODE = nil
            return
        end

        running = true
        releaseQueue = {}
        releaseAcc   = 0
        waveAcc      = 0
        activeCount  = 0

        if hb then hb:Disconnect() hb = nil end
        hb = Run.Heartbeat:Connect(function(dt)
            if not running then return end

            waveAcc = waveAcc + dt
            if waveAcc >= STEP_WAIT then
                waveAcc = waveAcc - STEP_WAIT
                wave()
            end

            releaseAcc = releaseAcc + dt
            local interval = 1 / RELEASE_RATE_HZ
            local toRelease = math.min(MAX_RELEASE_PER_TICK, math.floor(releaseAcc / interval))
            if toRelease > 0 then
                releaseAcc = releaseAcc - toRelease * interval
                for i = 1, toRelease do
                    local rec = table.remove(releaseQueue, 1)
                    if not rec then break end
                    releaseOne(rec)
                end
            end
            flushStaleStaged()
        end)
    end

    tab:Toggle({
        Title = "Send Fuel to Campfire",
        Value = false,
        Callback = function(state)
            if state then startMode("fuel") else if CURRENT_MODE == "fuel" then startMode(nil) end end
        end
    })

    tab:Toggle({
        Title = "Send Scrap to Scrapper",
        Value = false,
        Callback = function(state)
            if state then startMode("scrap") else if CURRENT_MODE == "scrap" then startMode(nil) end end
        end
    })

    tab:Toggle({
        Title = "Send All Items to NoticeBoard",
        Value = false,
        Callback = function(state)
            if state then startMode("all") else if CURRENT_MODE == "all" then startMode(nil) end end
        end
    })

    tab:Section({ Title = "Bring to Orbs (Level 4 Fire Edge)" })

    local function makeOrbDropdown(index)
        return tab:Dropdown({
            Title = ("Orb %d Items"):format(index),
            Values = orbDropdownValues[index],
            Multi = true,
            AllowNone = true,
            Callback = function(selection)
                local set = {}
                if type(selection) == "table" and not selection[1] and selection.Value then selection = selection.Value end
                if type(selection) == "table" then
                    for _,name in ipairs(selection) do if name then set[tostring(name)] = true end end
                elseif selection then
                    set[tostring(selection)] = true
                end
                orbItemSets[index] = set
                recomputeOrbUnionSet()
            end
        })
    end

    makeOrbDropdown(1)
    makeOrbDropdown(2)
    makeOrbDropdown(3)
    makeOrbDropdown(4)

    tab:Toggle({ Title = "Orb 1 Enabled", Value = false, Callback = function(state) orbEnabled[1] = state and true or false recomputeOrbUnionSet() end })
    tab:Toggle({ Title = "Orb 2 Enabled", Value = false, Callback = function(state) orbEnabled[2] = state and true or false recomputeOrbUnionSet() end })
    tab:Toggle({ Title = "Orb 3 Enabled", Value = false, Callback = function(state) orbEnabled[3] = state and true or false recomputeOrbUnionSet() end })
    tab:Toggle({ Title = "Orb 4 Enabled", Value = false, Callback = function(state) orbEnabled[4] = state and true or false recomputeOrbUnionSet() end })

    tab:Slider({
        Title = "Ground Orb Search Radius",
        Value = { Min = 10, Max = 250, Default = MAX_DIST_ORBS_DEFAULT },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default or v[1] end
            nv = tonumber(nv)
            if nv then maxDistOrbs = math.clamp(nv, 10, 250) else maxDistOrbs = MAX_DIST_ORBS_DEFAULT end
        end
    })

    tab:Toggle({
        Title = "Bring Selected Items to Orbs",
        Value = false,
        Callback = function(state)
            if state then startMode("orbs") else if CURRENT_MODE == "orbs" then startMode(nil) end end
        end
    })

    tab:Section({ Title = "Background Utilities" })

    tab:Toggle({
        Title = "Background Grab Important Items",
        Value = false,
        Callback = function(state)
            setPreclaimEnabled(state)
        end
    })

    Players.LocalPlayer.CharacterAdded:Connect(function()
        if running and CURRENT_MODE then
            if CURRENT_MODE == "fuel" or CURRENT_MODE == "scrap" or CURRENT_MODE == "all" then
                local pos
                if CURRENT_MODE == "fuel" then pos = campfireOrbPos()
                elseif CURRENT_MODE == "scrap" then pos = scrapperOrbPos()
                elseif CURRENT_MODE == "all" then pos = noticeOrbPos() end
                if pos then
                    local color = (CURRENT_MODE == "fuel" and Color3.fromRGB(255,200,50))
                        or (CURRENT_MODE == "scrap" and Color3.fromRGB(120,255,160))
                        or Color3.fromRGB(100,200,255)
                    spawnOrbAt(pos, color)
                end
            elseif CURRENT_MODE == "orbs" then
                destroyOrb()
                orbPosVec = nil
                orbGroundBases = { nil, nil, nil, nil }
            end
        end
    end)
end
