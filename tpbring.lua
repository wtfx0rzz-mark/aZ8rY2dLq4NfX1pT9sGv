return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

    local lp  = Players.LocalPlayer
    local tab = UI and UI.Tabs and (UI.Tabs.TPBring or UI.Tabs.Bring or UI.Tabs.Auto or UI.Tabs.Main)
    if not tab then return end

    if _G.__TPBring__cleanup then
        pcall(_G.__TPBring__cleanup)
    end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end

    local function mainPart(m)
        if not m then return nil end
        if m:IsA("BasePart") then return m end
        if m:IsA("Model") then
            return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
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

    local function isAnyPartLocked(m)
        for _, p in ipairs(allParts(m)) do
            local locked = false
            local ok = pcall(function() locked = p.Locked end)
            if ok and locked then return true end
        end
        return false
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
    local function refreshRemoteRefs()
        startDrag, stopDrag = nil, nil
        local re = RS and RS:FindFirstChild("RemoteEvents")
        if re then
            startDrag = re:FindFirstChild("RequestStartDraggingItem")
            stopDrag  = re:FindFirstChild("StopDraggingItem")
        end
    end
    refreshRemoteRefs()

    local DRAG_SPEED              = 420
    local ORB_HEIGHT              = 10
    local GROUND_ORB_DROP_HEIGHT  = 6
    local MAX_CONCURRENT          = 100
    local SCAN_INTERVAL           = 0.20
    local MOVE_HZ                 = 30

    local LAND_MIN                = 0.35
    local LAND_MAX                = 0.85
    local ARRIVE_EPS_H            = 1.1
    local STALL_SEC               = 0.6

    local HOVER_ABOVE_ORB         = 1.2

    local RELEASE_RATE_HZ_DEFAULT      = 18
    local MAX_RELEASE_PER_TICK_DEFAULT = 2
    local releaseRateHz               = RELEASE_RATE_HZ_DEFAULT
    local maxReleasePerTick           = MAX_RELEASE_PER_TICK_DEFAULT

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

    local AIR_RELEASE_UP          = 0.0

    local OUTSIDE_LOG_MAX_DIST    = 260

    local AIR_TOUCH_DROP_OFFSET_Y = 10
    local AIR_TOUCH_ORB_SIZE      = 6.0
    local AIR_DROP_TIMEOUT_S      = 2.25
    local AIR_RETRY_PUSH_DOWN_VY  = -80

    local MAX_AIR_DROPPING        = 20
    local AIR_DROP_SPREAD_RADIUS  = 0.6

    local SCRAPPER_CHUTE_ABOVE    = 12

    local INFLT_ATTR = "OrbInFlightAt"
    local JOB_ATTR   = "OrbJob"
    local DONE_ATTR  = "OrbDelivered"

    local SENT_MODE_ATTR  = "TPBringSentMode"
    local SENT_TRIES_ATTR = "TPBringSentTries"
    local SENT_LAST_ATTR  = "TPBringSentAt"
    local SENT_DELIV_ATTR = "TPBringDeliveredAt"
    local RETRY_AFTER_S   = 3.0
    local RETRY_PUSH_BACK = 10.0
    local RETRY_MAX_TRIES = 6

    local CONFIRM_WINDOW_S = 2.0
    local pendingConfirm   = {}

    local CURRENT_RUN_ID = nil
    local CURRENT_MODE   = nil

    local running      = false
    local hb           = nil
    local orb          = nil
    local orbTouch     = nil
    local touchConn    = nil
    local orbPosVec    = nil
    local inflight     = {}
    local releaseQueue = {}
    local releaseAcc   = 0.0
    local activeCount  = 0
    local unstickConn  = nil
    local preclaimConn = nil
    local finalized    = {}
    local fruitNudged  = {}
    local dropStacks   = {}
    local pendingRetry = {}
    local charAddedConn = nil

    local airDropQueue     = {}
    local airDroppingCount = 0

    local cachedScrapperChute = nil
    local function getScrapperChute()
        if cachedScrapperChute and cachedScrapperChute.Parent then
            return cachedScrapperChute
        end
        cachedScrapperChute = nil
        local scr = WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Campground") and WS.Map.Campground:FindFirstChild("Scrapper")
        if not scr then return nil end
        for _, child in ipairs(scr:GetDescendants()) do
            if child.Name == "Chute" and child:IsA("BasePart") and child.Material == Enum.Material.DiamondPlate then
                cachedScrapperChute = child
                return child
            end
        end
        return nil
    end

    local function scrapperChuteTargetPos()
        local chute = getScrapperChute()
        if not chute then return nil end
        return chute.Position + Vector3.new(0, SCRAPPER_CHUTE_ABOVE, 0)
    end

    local function randomPosInChute()
        local chute = getScrapperChute()
        if not chute then return nil end
        local cf   = chute.CFrame
        local size = chute.Size
        local rx = (math.random() - 0.5) * size.X * 0.8
        local rz = (math.random() - 0.5) * size.Z * 0.8
        local worldOffset = cf:VectorToWorldSpace(Vector3.new(rx, 0, rz))
        return Vector3.new(
            chute.Position.X + worldOffset.X,
            chute.Position.Y + SCRAPPER_CHUTE_ABOVE,
            chute.Position.Z + worldOffset.Z
        )
    end

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

    local fuelModeSet  = { ["Coal"] = true, ["Fuel Canister"] = true, ["Oil Barrel"] = true, ["Log"] = true }
    local scrapModeSet = {}
    for k,v in pairs(junkSet) do if v then scrapModeSet[k] = true end end
    scrapModeSet["Log"]               = true
    scrapModeSet["Cultist Gem"]       = true
    scrapModeSet["Gem of the Forest"] = true
    local logOnlySet   = { ["Log"] = true }

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

    local ALLOW_OUTSIDE_ITEMS = {}

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
                if n:find("iceblock",1,true) or n:find("ice block",1,true) then return true end
            end
        end
        local cur = inst.Parent
        for _ = 1, 10 do
            if not cur then break end
            local n = (cur.Name or ""):lower()
            if n:find("iceblock",1,true) or n:find("ice block",1,true) then return true end
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
        if inst:IsA("Model") and isExcludedModel(inst) then return true end
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

    local function isDirectItemChild(m)
        local itemsFolder = itemsRootOrNil()
        if not itemsFolder then return true end
        if not (m and m.Parent) then return false end
        return m.Parent == itemsFolder
    end

    local function nameMatches(selectedSet, m)
        if not (selectedSet and m) then return false end
        local itemsFolder = itemsRootOrNil()

        if itemsFolder and not m:IsDescendantOf(itemsFolder) then
            return false
        end

        local nm = m.Name or ""
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
        if selectedSet["Cultist Gem"] and nm == "Cultist Gem" then return true end
        if selectedSet["Gem of the Forest"] and nm == "Gem of the Forest" then return true end
        if selectedSet["Forest Gem"] and nm == "Forest Gem" then return true end
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

    local function tryStartDrag(m, rec)
        if not rec then return end
        if rec.dragFired then return end
        refreshRemoteRefs()
        if not startDrag then return end
        rec.dragFired = true
        pcall(function() startDrag:FireServer(m) end)
    end

    local function tryStopDrag(m, rec)
        if not rec then return end
        if not rec.dragFired then return end
        if rec.stopFired then return end
        refreshRemoteRefs()
        if not stopDrag then return end
        rec.stopFired = true
        pcall(function() stopDrag:FireServer(m) end)
    end

    local function fruitPreNudge(m)
        if not isFruitModel(m) then return end
        if not (m and m.Parent) then return end
        if fruitNudged[m] then return end
        if inflight[m] and inflight[m].dragFired then return end
        local mp = mainPart(m)
        if not mp then return end
        fruitNudged[m] = true
        task.spawn(function()
            local tmp = { dragFired = false, stopFired = false }
            tryStartDrag(m, tmp)
            for _,p in ipairs(allParts(m)) do
                pcall(function() p:SetNetworkOwner(lp) end)
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            local mass = math.max(mp:GetMass(), 1)
            local dir = Vector3.new((math.random()-0.5)*2, 0, (math.random()-0.5)*2)
            if dir.Magnitude < 0.2 then dir = Vector3.new(1,0,0) else dir = dir.Unit end
            pcall(function() mp:ApplyImpulse(dir*(120*mass) + Vector3.new(0,80*mass,0)) end)
            pcall(function()
                mp:ApplyAngularImpulse(Vector3.new(
                    (math.random()-0.5)*300,
                    (math.random()-0.5)*300,
                    (math.random()-0.5)*300
                )*mass)
            end)
            task.delay(0.18, function() tryStopDrag(m, tmp) end)
            task.delay(0.9, function()
                for _,p in ipairs(allParts(m)) do
                    pcall(function() p:SetNetworkOwner(nil) end)
                    pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                end
            end)
        end)
    end

    local function isAirMode()
        return CURRENT_MODE == "fuel" or CURRENT_MODE == "scrap" or CURRENT_MODE == "scrap_logs"
    end

    local function isScrapperMode()
        return CURRENT_MODE == "scrap" or CURRENT_MODE == "scrap_logs"
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
        if not (running and m and m.Parent) then return end
        if not (m:IsA("Model") or m:IsA("BasePart")) then return false end
        if finalized[m] then return false end
        if pendingConfirm[m] then return false end
        if inflight[m] then return false end

        local itemsFolder = itemsRootOrNil()
        if itemsFolder and m:IsDescendantOf(itemsFolder) and not isDirectItemChild(m) then
            return false
        end
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then
            return false
        end

        if isExcludedInst(m) then return false end

        local done = m:GetAttribute(DONE_ATTR)
        if done and CURRENT_RUN_ID and tostring(done) == tostring(CURRENT_RUN_ID) then
            return false
        end

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
        if CURRENT_MODE == "fuel"       then return fuelModeSet  end
        if CURRENT_MODE == "scrap"      then return scrapModeSet end
        if CURRENT_MODE == "scrap_logs" then return logOnlySet   end
        if CURRENT_MODE == "all"        then return allModeSet   end
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
        rp.FilterType = Enum.RaycastFilterType.Exclude
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
    local orbEnabled  = { false, false, false, false }
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
            if orbEnabled[i] and next(orbItemSets[i]) ~= nil and nameMatches(orbItemSets[i], m) then
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

    local function collectCandidatesFromSet(selectedSet, jobId, maxDist)
        if not selectedSet then return {} end
        local itemsFolder = itemsRootOrNil()
        local root = hrp()
        local rootPos = root and root.Position

        local uniq, out = {}, {}

        if itemsFolder then
            for _,m in ipairs(itemsFolder:GetChildren()) do
                if (m:IsA("Model") or m:IsA("BasePart")) and not uniq[m] then
                    if canPick(m, selectedSet, jobId) then
                        if maxDist and rootPos then
                            local mp = mainPart(m)
                            if mp and (mp.Position - rootPos).Magnitude <= maxDist then
                                uniq[m] = true
                                out[#out+1] = m
                            end
                        else
                            uniq[m] = true
                            out[#out+1] = m
                        end
                    end
                end
            end
        end

        return out
    end

    local function getCandidatesForCurrent(jobId)
        return collectCandidatesFromSet(currentSelectedSet(), jobId, MAX_DIST_DEFAULT)
    end

    local function destroyOrb()
        if touchConn then pcall(function() touchConn:Disconnect() end) end
        touchConn = nil
        if orb     then pcall(function() orb:Destroy()      end) end
        if orbTouch then pcall(function() orbTouch:Destroy() end) end
        orb = nil
        orbTouch = nil
        orbPosVec = nil
    end

    local function campfireOrbPos()
        local fire = WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Campground") and WS.Map.Campground:FindFirstChild("MainFire")
        if not fire then return nil end
        local mp = mainPart(fire)
        local cf = (mp and mp.CFrame) or fire:GetPivot()
        return cf.Position + Vector3.new(0, ORB_HEIGHT + 3, 0)
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
        return (cf.Position + forward * edgeOffset) + Vector3.new(0, ORB_HEIGHT + 1, 0)
    end

    local function markForConfirm(m)
        if not (m and m.Parent) then return end
        pendingConfirm[m] = { at = os.clock(), runId = CURRENT_RUN_ID }
        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
        end)
        inflight[m] = nil
        finalized[m] = nil
    end

    local function processPendingConfirm()
        if not CURRENT_RUN_ID then pendingConfirm = {} return end
        local itemsFolder = itemsRootOrNil()
        local now = os.clock()

        for m,info in pairs(pendingConfirm) do
            if not m then
                pendingConfirm[m] = nil
            else
                local alive   = (m.Parent ~= nil)
                local inItems = alive and itemsFolder and m:IsDescendantOf(itemsFolder)

                if (not alive) or (itemsFolder and not inItems) then
                    local confirmedRunId = info and info.runId
                    if confirmedRunId and confirmedRunId == CURRENT_RUN_ID then
                        pcall(function() m:SetAttribute(DONE_ATTR, CURRENT_RUN_ID) end)
                    else
                        pcall(function() m:SetAttribute(DONE_ATTR, nil) end)
                    end
                    pendingConfirm[m] = nil
                    airDroppingCount = math.max(0, airDroppingCount - 1)
                else
                    local t0 = (info and info.at) or now
                    if (now - t0) >= CONFIRM_WINDOW_S then
                        pendingConfirm[m] = nil
                        airDroppingCount = math.max(0, airDroppingCount - 1)
                        pcall(function()
                            m:SetAttribute(DONE_ATTR, nil)
                            m:SetAttribute(INFLT_ATTR, nil)
                            m:SetAttribute(JOB_ATTR, nil)
                        end)
                    end
                end
            end
        end
    end

    local function finalizeAirDelivery(m, rec)
        if not (m and m.Parent and rec) then return end
        rec.dropping = false
        tryStopDrag(m, rec)
        setAnchored(m, false)
        setCollideFromSnapshot(rec.snap)
        for _,p in ipairs(allParts(m)) do
            pcall(function() p:SetNetworkOwner(nil) end)
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
        if rec.counted then
            rec.counted = false
            activeCount = math.max(0, activeCount - 1)
        end
        local now = os.clock()
        pcall(function() m:SetAttribute(SENT_DELIV_ATTR, now) end)
        local tries = tonumber(m:GetAttribute(SENT_TRIES_ATTR)) or 1
        pendingRetry[m] = { mode = CURRENT_MODE, at = now, tries = tries }
        markForConfirm(m)
    end

    local function processAirDropQueue()
        if not (running and isAirMode()) then return end
        local dropTarget = nil
        if isScrapperMode() then
            local chute = getScrapperChute()
            if not chute then return end
            dropTarget = chute.Position
        else
            if not orbPosVec then return end
            dropTarget = orbPosVec
        end

        while airDroppingCount < MAX_AIR_DROPPING and #airDropQueue > 0 do
            local entry = table.remove(airDropQueue, 1)
            local m = entry and entry.model
            local rec = m and inflight[m]
            if m and m.Parent and rec then
                local targetXZ = entry.targetXZ
                local waveIndex = airDroppingCount
		local waveY = math.sin(waveIndex * 10) * .3
		local dropPos = Vector3.new(
    		targetXZ and targetXZ.X or dropTarget.X,
    		dropTarget.Y + SCRAPPER_CHUTE_ABOVE + waveY,
    		targetXZ and targetXZ.Z or dropTarget.Z
		)
                setPivot(m, CFrame.new(dropPos))
                zeroAssembly(m)
                setCollideFromSnapshot(rec.snap)
                setAnchored(m, false)
                for _,p in ipairs(allParts(m)) do
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                    pcall(function() p:SetNetworkOwner(nil) end)
                    pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                end
                tryStopDrag(m, rec)
                rec.airQueued  = false
                rec.released   = true
                rec.dropping   = true
                rec.droppingAt = os.clock()
                airDroppingCount = airDroppingCount + 1
                if rec.counted then
                    rec.counted = false
                    activeCount = math.max(0, activeCount - 1)
                end
            end
        end
    end

    local function spawnOrbAt(pos, color, withTouchOrb)
        destroyOrb()
        local o = Instance.new("Part")
        o.Name = "tp_orb_fixed"
        o.Shape = Enum.PartType.Ball
        o.Size = Vector3.new(1.5,1.5,1.5)
        o.Material = Enum.Material.Neon
        o.Color = color or Color3.fromRGB(80,180,255)
        o.Transparency = 1
        o.Anchored, o.CanCollide, o.CanTouch, o.CanQuery = true,false,false,false
        o.CFrame = CFrame.new(pos)
        o.Parent = WS
        orb = o
        orbPosVec = o.Position

        if withTouchOrb then
            local t = Instance.new("Part")
            t.Name = "tp_orb_touch"
            t.Shape = Enum.PartType.Ball
            t.Size = Vector3.new(AIR_TOUCH_ORB_SIZE,AIR_TOUCH_ORB_SIZE,AIR_TOUCH_ORB_SIZE)
            t.Material = Enum.Material.Neon
            t.Color = Color3.fromRGB(255,90,90)
            t.Transparency = 1
            t.Anchored = true
            t.CanCollide = false
            t.CanQuery = false
            t.CanTouch = true
            t.CFrame = CFrame.new(pos - Vector3.new(0, AIR_TOUCH_DROP_OFFSET_Y, 0))
            t.Parent = WS
            orbTouch = t

            touchConn = t.Touched:Connect(function(hit)
                if not (running and isAirMode()) then return end
                if not hit or not hit.Parent then return end
                local itemsFolder = itemsRootOrNil()
                local m = hit
                if itemsFolder then
                    local cur = hit
                    while cur and cur.Parent and cur.Parent ~= itemsFolder and cur ~= itemsFolder do
                        cur = cur.Parent
                    end
                    if cur and cur.Parent == itemsFolder then m = cur else return end
                end
                local rec = inflight[m]
                if not rec or rec.dropKind ~= "air" or not rec.dropping then return end
                finalizeAirDelivery(m, rec)
            end)
        end
    end

    local function hash01(s)
        local h = 131071
        for i = 1, #s do h = (h * 131 + string.byte(s,i)) % 1000003 end
        return (h % 100000) / 100000
    end

    local function landingOffset(m, jobId)
        local key = (typeof(m.GetDebugId)=="function" and m:GetDebugId() or (m.Name or "")) .. tostring(jobId)
        local r1 = hash01(key.."a")
        local r2 = hash01(key.."b")
        local ang = r1 * math.pi * 2
        local rad = LAND_MIN + (LAND_MAX - LAND_MIN) * r2
        return Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
    end

    local function raycastDownAtXZ(xz, ignoreModel)
        local itemsFolder = itemsRootOrNil()
        local ch = lp.Character
        local origin = Vector3.new(xz.X, SKY_RAY_START_Y, xz.Z)
        local dir = Vector3.new(0, -SKY_RAY_LEN, 0)
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
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
        if tgt then setPivot(m, CFrame.new(tgt)) end
        local info = inflight[m]
        if info then
            info.staged   = true
            info.stagedAt = os.clock()
            info.snap     = snap
        end
        releaseQueue[#releaseQueue+1] = {
            model    = m,
            snap     = snap,
            destKey  = destKey or "default",
            centerXZ = centerXZ,
            dropKind = dropKind or "ground"
        }
    end

    local function releaseOne(rec)
        local m = rec and rec.model
        if not (m and m.Parent) then return end
        local info = inflight[m]
        local snap = (rec and rec.snap) or (info and info.snap) or snapshotCollide(m)

        if info then tryStopDrag(m, info) end

        if rec and rec.dropKind == "air" then
            if info then
                if info.airQueued or info.dropping or info.released then
                    return
                end
                info.airQueued = true
                info.staged    = true
                info.stagedAt  = os.clock()
            end
            local targetXZ = nil
            if isScrapperMode() then
                local pos = randomPosInChute()
                if pos then
                    targetXZ = Vector3.new(pos.X, 0, pos.Z)
                end
            end
            airDropQueue[#airDropQueue+1] = { model = m, targetXZ = targetXZ }
            return
        end

        local center = rec and rec.centerXZ
        if not center then
            local mp = mainPart(m)
            local p = (mp and mp.Position) or Vector3.new()
            center = Vector3.new(p.X, 0, p.Z)
        end

        dropStacks[rec.destKey or "default"] = (dropStacks[rec.destKey or "default"] or 0) + 1
        local idx = dropStacks[rec.destKey or "default"]
        local ang = idx * 2.399963229728653
        local rad = math.min(8.0, 0.8 * math.sqrt(math.max(idx, 1)))
        local off2d = Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
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
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
        local gInfo = inflight[m]
        if gInfo and gInfo.counted then
            gInfo.counted = false
            activeCount = math.max(0, activeCount - 1)
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
            pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
        end
        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
        end)
        inflight[m] = nil
    end

    local function markSentAttempt(m)
        if not (m and m.Parent) then return end
        if not isAirMode() then return end
        local now = os.clock()
        local tries = tonumber(m:GetAttribute(SENT_TRIES_ATTR)) or 0
        pcall(function()
            m:SetAttribute(SENT_MODE_ATTR, CURRENT_MODE)
            m:SetAttribute(SENT_TRIES_ATTR, tries + 1)
            m:SetAttribute(SENT_LAST_ATTR, now)
        end)
    end

    local function startConveyor(m, jobId, destBaseVec, destKey, dropKind)
        if not (running and m and m.Parent) then return end
        if isAnyPartLocked(m) then return end
        if not mainPart(m) then return end
        if not destBaseVec then return end

        if isFruitModel(m) then fruitPreNudge(m) end

        local off = landingOffset(m, jobId)
        local function target()
            if isScrapperMode() then
                local chute = getScrapperChute()
                if chute then
                    return chute.Position + Vector3.new(off.X, SCRAPPER_CHUTE_ABOVE + HOVER_ABOVE_ORB, off.Z)
                end
            end
            return Vector3.new(destBaseVec.X + off.X, destBaseVec.Y + HOVER_ABOVE_ORB, destBaseVec.Z + off.Z)
        end

        pcall(function()
            m:SetAttribute(INFLT_ATTR, os.clock())
            m:SetAttribute(JOB_ATTR, jobId)
        end)
        if dropKind == "air" and isAirMode() then markSentAttempt(m) end

        local snap = setNoCollide(m)
        setAnchored(m, true)
        zeroAssembly(m)

        local rec = {
            snap       = snap,
            lastD      = math.huge,
            lastT      = os.clock(),
            staged     = false,
            released   = false,
            dropping   = false,
            droppingAt = nil,
            dragFired  = false,
            stopFired  = false,
            counted    = true,
            destKey    = destKey or "default",
            off        = off,
            centerXZ   = Vector3.new(destBaseVec.X, 0, destBaseVec.Z),
            dropKind   = dropKind or "ground",
            targetFn   = target
        }
        inflight[m] = rec
        activeCount = activeCount + 1
        tryStartDrag(m, rec)
    end

    local function flushStaleStaged()
        local now = os.clock()
        for m,info in pairs(inflight) do
            if info and info.staged and not info.released and (now - (info.stagedAt or now)) >= STAGE_TIMEOUT_S then
                local queued = false
                for _,rec in ipairs(releaseQueue) do
                    if rec.model == m then queued = true break end
                end
                if not queued then
                    releaseQueue[#releaseQueue+1] = {
                        model    = m,
                        snap     = info.snap or snapshotCollide(m),
                        destKey  = info.destKey or "default",
                        centerXZ = info.centerXZ,
                        dropKind = info.dropKind or "ground"
                    }
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
                local now = os.clock()

                for _,m in ipairs(itemsFolder:GetChildren()) do
                    local mp = mainPart(m)
                    if not mp then continue end
                    if (mp.Position - orbPosVec).Magnitude > ORB_UNSTICK_RAD then continue end

                    local tIn  = m:GetAttribute(INFLT_ATTR)
                    local jIn  = m:GetAttribute(JOB_ATTR)
                    local info = inflight[m]
                    local age  = tIn and (now - tIn) or nil
                    local stuck = (not tIn) or (not jIn) or (not info) or (age and age >= STUCK_TTL)
                    if not stuck then continue end

                    if info then tryStopDrag(m, info) end
                    finalized[m] = true
                    inflight[m] = nil
                    teleportModelToGround(m)
                    for _,p in ipairs(allParts(m)) do
                        p.Anchored = false
                        p.AssemblyAngularVelocity = Vector3.new()
                        p.AssemblyLinearVelocity  = Vector3.new()
                        p.CanCollide = true
                        pcall(function() p:SetNetworkOwner(nil) end)
                        pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                    end
                end
            end)
        else
            if unstickConn then unstickConn:Disconnect() end
            unstickConn = nil
        end
    end

    local function wave(jobId)
        if not CURRENT_MODE then return end

        if CURRENT_MODE == "orbs" then
            local list = collectCandidatesFromSet(orbUnionSet, jobId, maxDistOrbs)
            for i = 1, #list do
                if not running then break end
                if #releaseQueue >= MAX_LINED_ITEMS then break end
                if activeCount >= MAX_CONCURRENT then break end
                local m = list[i]
                if m and m.Parent and not inflight[m] then
                    local idx = orbIndexForModel(m)
                    if idx then
                        local base = getOrbBasePosition(idx)
                        if base then startConveyor(m, jobId, base, "orb"..tostring(idx), "ground") end
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
                if isScrapperMode() then
                    local chute = getScrapperChute()
                    if chute then
                        dest = chute.Position + Vector3.new(0, SCRAPPER_CHUTE_ABOVE, 0)
                    end
                end
                if dest then
                    startConveyor(m, jobId, dest, "main", isAirMode() and "air" or "ground")
                end
            end
        end
    end

    local function updateInflight(dt)
        for m,rec in pairs(inflight) do
            if not (m and m.Parent and running) then
                abortRestore(m, rec)
            elseif not rec.staged then
                local pivot = m.GetPivot and m:GetPivot() or nil
                local pos = (pivot and pivot.Position) or (mainPart(m) and mainPart(m).Position) or nil
                if not pos then
                    abortRestore(m, rec)
                else
                    local tgt = rec.targetFn and rec.targetFn() or nil
                    if not tgt then
                        abortRestore(m, rec)
                    else
                        local flatDelta = Vector3.new(tgt.X-pos.X, 0, tgt.Z-pos.Z)
                        local distH = flatDelta.Magnitude

                        if distH <= ARRIVE_EPS_H and math.abs(tgt.Y-pos.Y) <= 1.2 then
                            tryStopDrag(m, rec)
                            if rec.dropKind == "air" then
                                releaseOne({ model = m, snap = rec.snap, dropKind = "air" })
                            else
                                stageForRelease(m, rec.snap, tgt, rec.destKey, rec.centerXZ, rec.dropKind)
                            end
                        else
                            if distH >= rec.lastD - 0.02 then
                                if os.clock() - rec.lastT >= STALL_SEC then
                                    rec.off = landingOffset(m, tostring(rec.destKey)..tostring(os.clock()))
                                    rec.lastT = os.clock()
                                end
                            else
                                rec.lastT = os.clock()
                            end
                            rec.lastD = distH

                            local step = math.min(DRAG_SPEED*dt, math.max(0, distH))
                            local dir  = distH > 1e-3 and (flatDelta/math.max(distH,1e-3)) or Vector3.new()
                            local vy   = math.clamp((tgt.Y-pos.Y), -7, 7)
                            local newPos = Vector3.new(pos.X, pos.Y+vy*dt*10, pos.Z) + dir*step
                            local look = (dir.Magnitude > 0 and dir) or Vector3.new(0,0,1)
                            setPivot(m, CFrame.new(newPos, newPos+look))
                        end
                    end
                end
            end
        end
    end

    local function checkAirDeliveries()
        if not (running and isAirMode()) then return end
        local now = os.clock()

        if isScrapperMode() then
            local chute = getScrapperChute()
            if not chute then return end
            local chuteCF   = chute.CFrame
            local chuteSize = chute.Size
            local halfX = chuteSize.X * 0.5 + 1.0
            local halfZ = chuteSize.Z * 0.5 + 1.0
            local chuteY = chute.Position.Y

            for m,rec in pairs(inflight) do
                if rec and rec.dropKind == "air" and rec.dropping and m and m.Parent then
                    local mp = mainPart(m)
                    if mp then
                        local localP = chuteCF:PointToObjectSpace(mp.Position)
                        local inBounds = math.abs(localP.X) <= halfX and math.abs(localP.Z) <= halfZ and mp.Position.Y <= chuteY + 3
                        if inBounds then
                            finalizeAirDelivery(m, rec)
                        else
                            local t0 = rec.droppingAt or now
                            if (now - t0) >= AIR_DROP_TIMEOUT_S then
                                local pos = randomPosInChute()
                                if pos then
                                    setPivot(m, CFrame.new(pos))
                                    zeroAssembly(m)
                                    setAnchored(m, false)
                                    for _,p in ipairs(allParts(m)) do
                                        p.CanCollide = false
                                        p.AssemblyLinearVelocity = Vector3.new(0, AIR_RETRY_PUSH_DOWN_VY, 0)
                                        pcall(function() p:SetNetworkOwner(nil) end)
                                        pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                                    end
                                    rec.droppingAt = now
                                end
                            end
                        end
                    end
                end
            end
            return
        end

        if not (orbTouch and orbTouch.Parent) then return end
        local touchPos = orbTouch.Position
        local rad = (AIR_TOUCH_ORB_SIZE * 0.5) + 1.25
        local rad2 = rad * rad

        for m,rec in pairs(inflight) do
            if rec and rec.dropKind == "air" and rec.dropping and m and m.Parent then
                local mp = mainPart(m)
                if mp then
                    local dp = mp.Position - touchPos
                    local d2 = dp.X*dp.X + dp.Y*dp.Y + dp.Z*dp.Z
                    if d2 <= rad2 then
                        finalizeAirDelivery(m, rec)
                    else
                        local t0 = rec.droppingAt or now
                        if (now - t0) >= AIR_DROP_TIMEOUT_S and orbPosVec then
                            local pos = orbPosVec + Vector3.new(0, AIR_RELEASE_UP, 0)
                            setPivot(m, CFrame.new(pos))
                            zeroAssembly(m)
                            setAnchored(m, false)
                            for _,p in ipairs(allParts(m)) do
                                p.CanCollide = false
                                p.AssemblyLinearVelocity = Vector3.new()
                                pcall(function() p:SetNetworkOwner(nil) end)
                                pcall(function() if p.SetNetworkOwnershipAuto then p:SetNetworkOwnershipAuto() end end)
                            end
                            rec.droppingAt = now
                        end
                    end
                end
            end
        end
    end

    local function processPendingRetries()
        if not (running and isAirMode()) then pendingRetry = {} return end
        local now = os.clock()
        for m,info in pairs(pendingRetry) do
            if not (m and m.Parent) then
                pendingRetry[m] = nil
            elseif not info or info.mode ~= CURRENT_MODE then
                pendingRetry[m] = nil
            else
                local at = info.at or now
                if (now - at) >= RETRY_AFTER_S then
                    local tries = tonumber(m:GetAttribute(SENT_TRIES_ATTR)) or (info.tries or 1)
                    if tries >= RETRY_MAX_TRIES then
                        pendingRetry[m] = nil
                    else
                        local mp = mainPart(m)
                        if not mp then
                            pendingRetry[m] = nil
                        else
                            local base = nil
                            if isScrapperMode() then
                                local chute = getScrapperChute()
                                if chute then base = chute.Position + Vector3.new(0, SCRAPPER_CHUTE_ABOVE, 0) end
                            else
                                base = orbPosVec
                            end
                            if not base then pendingRetry[m] = nil continue end
                            local v = Vector3.new(mp.Position.X-base.X, 0, mp.Position.Z-base.Z)
                            if v.Magnitude < 0.2 then v = Vector3.new(1,0,0) else v = v.Unit end
                            local away = base + v*RETRY_PUSH_BACK + Vector3.new(0, AIR_RELEASE_UP, 0)
                            pcall(function()
                                setAnchored(m, true)
                                setPivot(m, CFrame.new(away))
                                zeroAssembly(m)
                                setAnchored(m, false)
                            end)
                            startConveyor(m, tostring(os.clock()), base, "main", "air")
                            pendingRetry[m] = { mode = CURRENT_MODE, at = now, tries = tries + 1 }
                        end
                    end
                end
            end
        end
    end

    local function clearStaleAttributes()
        local itemsFolder = itemsRootOrNil()
        if not itemsFolder then return end
        for _,child in ipairs(itemsFolder:GetChildren()) do
            pcall(function()
                if child:GetAttribute(INFLT_ATTR) or child:GetAttribute(JOB_ATTR) then
                    child:SetAttribute(INFLT_ATTR, nil)
                    child:SetAttribute(JOB_ATTR, nil)
                end
            end)
        end
    end

    local function stopAll()
        running = false
        if hb then hb:Disconnect() hb = nil end
        setUnstickEnabled(false)
        for i = 1, #releaseQueue do
            local rec = releaseQueue[i]
            if rec and rec.model and rec.model.Parent then releaseOne(rec) end
        end
        releaseQueue     = {}
        airDropQueue     = {}
        airDroppingCount = 0
        for m,rec in pairs(inflight) do abortRestore(m, rec) end
        inflight       = {}
        pendingRetry   = {}
        pendingConfirm = {}
        finalized      = {}
        fruitNudged    = {}
        dropStacks     = {}
        activeCount    = 0
        releaseAcc     = 0.0
        destroyOrb()
        refreshRemoteRefs()
    end

    local PRECLAIM_DISTANCE   = 100
    local PRECLAIM_INTERVAL_S = 2.5
    local PRECLAIM_TTL_S      = 18.0
    local preclaimAcc         = 0
    local preclaimEnabled     = false
    local preclaimedAt        = {}

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
                refreshRemoteRefs()
                if not (startDrag and stopDrag) then return end
                local itemsFolder = itemsRootOrNil()
                if not itemsFolder then return end
                local campPos = campfireOrbPos()
                if not campPos then return end
                local now = os.clock()

                for _,m in ipairs(itemsFolder:GetChildren()) do
                    if inflight[m] then continue end
                    if isExcludedInst(m) then continue end
                    if not isPreDragImportantModel(m) then continue end
                    local mp = mainPart(m)
                    if not mp then continue end
                    if (mp.Position - campPos).Magnitude <= PRECLAIM_DISTANCE then continue end
                    local last = preclaimedAt[m]
                    if last and (now - last) < PRECLAIM_TTL_S then continue end
                    preclaimedAt[m] = now
                    local tmp = { dragFired = false, stopFired = false }
                    tryStartDrag(m, tmp)
                    task.delay(0.14, function()
                        refreshRemoteRefs()
                        tryStopDrag(m, tmp)
                    end)
                end
            end)
        else
            if preclaimConn then preclaimConn:Disconnect() end
            preclaimConn = nil
        end
    end

    local function startMode(mode)
        if mode == nil then
            CURRENT_MODE   = nil
            CURRENT_RUN_ID = nil
            setPreclaimEnabled(false)
            stopAll()
            return
        end
        if not hrp() then return end

        stopAll()
        refreshRemoteRefs()
        orbGroundBases   = { nil, nil, nil, nil }
        preclaimedAt     = {}
        airDropQueue     = {}
        airDroppingCount = 0
        cachedScrapperChute = nil

        CURRENT_MODE   = mode
        CURRENT_RUN_ID = tostring(os.clock())
        finalized      = {}
        fruitNudged    = {}
        dropStacks     = {}
        pendingRetry   = {}
        pendingConfirm = {}

        clearStaleAttributes()

        releaseRateHz     = RELEASE_RATE_HZ_DEFAULT
        maxReleasePerTick = MAX_RELEASE_PER_TICK_DEFAULT

        if mode == "fuel" or mode == "scrap" or mode == "scrap_logs" or mode == "all" then
            local pos, color, touch
            if mode == "fuel" then
                pos   = campfireOrbPos()
                color = Color3.fromRGB(255,200,50)
                touch = true
            elseif mode == "scrap" or mode == "scrap_logs" then
                local chute = getScrapperChute()
                if not chute then CURRENT_MODE = nil CURRENT_RUN_ID = nil return end
                pos   = chute.Position + Vector3.new(0, SCRAPPER_CHUTE_ABOVE, 0)
                color = Color3.fromRGB(120,255,160)
                touch = false
            elseif mode == "all" then
                pos   = noticeOrbPos()
                color = Color3.fromRGB(100,200,255)
                touch = false
            end
            if not pos then CURRENT_MODE = nil CURRENT_RUN_ID = nil return end
            if mode ~= "scrap" and mode ~= "scrap_logs" then
                spawnOrbAt(pos, color, touch)
            else
                orbPosVec = pos
            end
            setUnstickEnabled(mode == "all")
        elseif mode == "orbs" then
            local any = false
            for i = 1, 4 do if orbEnabled[i] and next(orbItemSets[i]) ~= nil then any = true break end end
            if not any then CURRENT_MODE = nil CURRENT_RUN_ID = nil return end
            destroyOrb()
            orbPosVec      = nil
            orbGroundBases = { nil, nil, nil, nil }
            setUnstickEnabled(false)
        else
            CURRENT_MODE = nil CURRENT_RUN_ID = nil return
        end

        running      = true
        releaseQueue = {}
        releaseAcc   = 0
        activeCount  = 0

        local scanAcc      = 0
        local moveAcc      = 0
        local moveInterval = 1 / MOVE_HZ

        if hb then hb:Disconnect() hb = nil end
        hb = Run.Heartbeat:Connect(function(dt)
            if not running then return end
            if isAirMode() then processPendingConfirm() end

            scanAcc = scanAcc + dt
            if scanAcc >= SCAN_INTERVAL then
                scanAcc = scanAcc - SCAN_INTERVAL
                wave(tostring(os.clock()))
            end

            moveAcc = moveAcc + dt
            if moveAcc >= moveInterval then
                local step = moveAcc
                moveAcc = 0
                updateInflight(step)
            end

            checkAirDeliveries()
            processAirDropQueue()

            releaseAcc = releaseAcc + dt
            local interval  = 1 / math.max(1, releaseRateHz)
            local toRelease = math.min(maxReleasePerTick, math.floor(releaseAcc / interval))
            if toRelease > 0 then
                releaseAcc = releaseAcc - toRelease * interval
                for i = 1, toRelease do
                    local rec = table.remove(releaseQueue, 1)
                    if not rec then break end
                    releaseOne(rec)
                end
            end

            flushStaleStaged()
            processPendingRetries()
        end)
    end

    tab:Toggle({ Title = "Send Fuel to Campfire",         Value = false, Callback = function(s) if s then startMode("fuel")       elseif CURRENT_MODE == "fuel"       then startMode(nil) end end })
    tab:Toggle({ Title = "Send Scrap to Scrapper",        Value = false, Callback = function(s) if s then startMode("scrap")      elseif CURRENT_MODE == "scrap"      then startMode(nil) end end })
    tab:Toggle({ Title = "Send Logs to Scrapper",         Value = false, Callback = function(s) if s then startMode("scrap_logs") elseif CURRENT_MODE == "scrap_logs" then startMode(nil) end end })
    tab:Toggle({ Title = "Send All Items to NoticeBoard",  Value = false, Callback = function(s) if s then startMode("all")       elseif CURRENT_MODE == "all"        then startMode(nil) end end })

    tab:Section({ Title = "Bring to Orbs (Level 4 Fire Edge)" })

    local function makeOrbDropdown(index)
        return tab:Dropdown({
            Title = ("Orb %d Items"):format(index),
            Values = { unpack(orbDropdownValues[index]) },
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

    makeOrbDropdown(1) makeOrbDropdown(2) makeOrbDropdown(3) makeOrbDropdown(4)

    tab:Toggle({ Title = "Orb 1 Enabled", Value = false, Callback = function(s) orbEnabled[1] = s recomputeOrbUnionSet() end })
    tab:Toggle({ Title = "Orb 2 Enabled", Value = false, Callback = function(s) orbEnabled[2] = s recomputeOrbUnionSet() end })
    tab:Toggle({ Title = "Orb 3 Enabled", Value = false, Callback = function(s) orbEnabled[3] = s recomputeOrbUnionSet() end })
    tab:Toggle({ Title = "Orb 4 Enabled", Value = false, Callback = function(s) orbEnabled[4] = s recomputeOrbUnionSet() end })

    tab:Slider({
        Title = "Ground Orb Search Radius",
        Value = { Min = 10, Max = 250, Default = MAX_DIST_ORBS_DEFAULT },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default or v[1] end
            nv = tonumber(nv)
            maxDistOrbs = nv and math.clamp(nv, 10, 250) or MAX_DIST_ORBS_DEFAULT
        end
    })

    tab:Toggle({ Title = "Bring Selected Items to Orbs", Value = false, Callback = function(s) if s then startMode("orbs") elseif CURRENT_MODE == "orbs" then startMode(nil) end end })

    tab:Section({ Title = "Background Utilities" })
    tab:Toggle({ Title = "Background Grab Important Items", Value = false, Callback = function(s) setPreclaimEnabled(s) end })

    if charAddedConn then pcall(function() charAddedConn:Disconnect() end) charAddedConn = nil end
    charAddedConn = Players.LocalPlayer.CharacterAdded:Connect(function()
        if not (running and CURRENT_MODE) then return end
        cachedScrapperChute = nil
        if CURRENT_MODE == "fuel" or CURRENT_MODE == "scrap" or CURRENT_MODE == "scrap_logs" or CURRENT_MODE == "all" then
            local pos
            if CURRENT_MODE == "fuel" then
                pos = campfireOrbPos()
            elseif CURRENT_MODE == "scrap" or CURRENT_MODE == "scrap_logs" then
                local chute = getScrapperChute()
                if chute then pos = chute.Position + Vector3.new(0, SCRAPPER_CHUTE_ABOVE, 0) end
            elseif CURRENT_MODE == "all" then
                pos = noticeOrbPos()
            end
            if pos then
                if CURRENT_MODE == "fuel" then
                    spawnOrbAt(pos, Color3.fromRGB(255,200,50), true)
                elseif CURRENT_MODE == "all" then
                    spawnOrbAt(pos, Color3.fromRGB(100,200,255), false)
                else
                    orbPosVec = pos
                end
            end
        elseif CURRENT_MODE == "orbs" then
            destroyOrb()
            orbPosVec      = nil
            orbGroundBases = { nil, nil, nil, nil }
        end
        airDropQueue     = {}
        airDroppingCount = 0
    end)

    local function cleanupModule()
        pcall(function() setPreclaimEnabled(false) end)
        pcall(function() CURRENT_MODE = nil CURRENT_RUN_ID = nil stopAll() end)
        if charAddedConn then pcall(function() charAddedConn:Disconnect() end) end
        charAddedConn = nil
        if _G.__TPBring__cleanup == cleanupModule then _G.__TPBring__cleanup = nil end
    end
    _G.__TPBring__cleanup = cleanupModule
end
