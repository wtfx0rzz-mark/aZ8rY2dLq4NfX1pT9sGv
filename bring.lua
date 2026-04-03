return function(C, R, UI)
    local Players = C.Services.Players
    local WS      = C.Services.WS
    local RS      = C.Services.RS
    local Run     = C.Services.Run or game:GetService("RunService")
    local lp      = Players.LocalPlayer

    C.State = C.State or {}

    local function now() return os.clock() end

    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    if not tab then
        error("Bring tab not found in UI")
    end

    local function currentLimit()
        local v = tonumber(C.State.BringLimitAmount) or 10
        return math.clamp(v, 1, 100)
    end

    if C.State.BringLimitAmount == nil then
        C.State.BringLimitAmount = 10
    end

    local COLLIDE_OFF_SEC       = 0.22
    local DROP_ABOVE_HEAD_STUDS = 10
    local FALLBACK_UP           = 4
    local FALLBACK_AHEAD        = 5
    local ORB_OFFSET_Y          = 20
    local CLUSTER_RADIUS_MIN    = 0.75
    local CLUSTER_RADIUS_STEP   = 0.04
    local CLUSTER_RADIUS_MAX    = 2.25

    local AIR_DROP_WAVE_AMPLITUDE = 1.0
    local AIR_DROP_WAVE_FREQUENCY = 1.3

    local _map  = workspace:FindFirstChild("Map")
    local _camp = _map and _map:FindFirstChild("Campground")
    local CAMPFIRE_PATH = _camp and _camp:FindFirstChild("MainFire")
    local SCRAPPER_PATH = _camp and _camp:FindFirstChild("Scrapper")

    local junkItems = {
        "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
        "Metal Chair","Cultist Prototype","Cultist Experiment","UFO Junk","UFO Component","Gears"
    }
    local fuelItems = {"Log","Coal","Fuel Canister","Oil Barrel","Biofuel","Chair"}
    local foodItems = {
        "Rotten",
        "Morsel","Cooked Morsel",
        "Steak","Cooked Steak",
        "Ribs","Cooked Ribs","Cake","Berry",
        "Carrot",
        "Chilli","Stew","Pumpkin","Hearty Stew","Corn","BBQ ribs","Apple","Mackerel","Salmon","Swordfish","Shark","Strawberry","Acorn"
    }
    local medicalItems = {"Bandage","MedKit"}
    local weaponsArmor = {
        "Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Hammer",
        "Chainsaw","Crossbow","Katana","Kunai","Laser Cannon","Ray Gun","Infernal Sword","Laser Sword","Ice Sword","Poison Claws","Morningstar","Riot Shield","Spear","Poison Spear","Tactical Shotgun","Wildfire",
        "Sword","Ice Axe","Scythe","Thorn Body","Alien Armour","Corrupted Thorn Body","Impact Grenade","Dynamite","Corrupted Shotgun","Corrupted Revolver","Corrupted Thrown Axe","Blowpipe"
    }
    local ammoMisc = {
        "Giant Sack","Infernal Sack","Good Sack","Mossy Coin","Cultist","Alien","Alien Elite","Sapling",
        "Basketball","Blueprint","Diamond","Gem of the Forest Fragment","Gem of the Forest","Flashlight","Old Taming flute","Old Rod","Cultist Gem",
        "Tusk","Revolver Ammo","Rifle Ammo","Shotgun Ammo","Explosive Revolver Ammo","Explosive Rifle Ammo","Sacrifice Totem","Anvil Back","Anvil Front","Anvil Base","Armor Trim","Crystal Skull Key"
    }
    local pelts = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Scorpion Shell","Polar Bear Pelt","Arctic Fox Pelt","Basic Egg","Blue Orchid","Pink Tulip","Yellow Peony","Red Rose","White Lily","Purple Carnation",}

    local fuelSet, junkSet, cookSet, scrapAlso, foodSet = {}, {}, {}, {}, {}
    for _,n in ipairs(fuelItems) do fuelSet[n] = true end
    for _,n in ipairs(junkItems) do junkSet[n] = true end
    for _,n in ipairs(foodItems) do if n ~= "Rotten" then foodSet[n] = true end end
    cookSet["Morsel"] = true; cookSet["Steak"] = true; cookSet["Ribs"] = true
    scrapAlso["Log"] = true;  scrapAlso["Chair"] = true

    local RAW_TO_COOKED = { ["Morsel"]="Cooked Morsel", ["Steak"]="Cooked Steak", ["Ribs"]="Cooked Ribs" }

    local function hrp()
        local ch = Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
    end
    local function headPart()
        local ch = Players.LocalPlayer.Character
        return ch and ch:FindFirstChild("Head")
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
    local function isExcludedModel(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        if n == "pelt trader" then return true end
        if n:find("trader",1,true) or n:find("shopkeeper",1,true) then return true end
        return false
    end
    local function isLogWallBlocked(m, selectedSet)
        if not (selectedSet and selectedSet["Log"] and m.Name == "Log") then return false end
        return isWallVariant(m) or isUnderLogWall(m)
    end
    local function mainPart(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then return obj end
        if obj:IsA("Model") then
            if obj.PrimaryPart then return obj.PrimaryPart end
            return obj:FindFirstChildWhichIsA("BasePart", true)
        end
        return nil
    end
    local function physicalRootPart(model)
        if not (model and model.Parent) then return nil end
        if model:IsA("BasePart") then return model end
        if not model:IsA("Model") then return mainPart(model) end
        local m = model:FindFirstChild("Main", true)
        if m and m:IsA("BasePart") then return m end
        if model.PrimaryPart then return model.PrimaryPart end
        return model:FindFirstChildWhichIsA("BasePart", true)
    end
    local function getAllParts(target)
        local t = {}
        if not target then return t end
        if target:IsA("BasePart") then
            t[1] = target
        elseif target:IsA("Model") then
            for _,d in ipairs(target:GetDescendants()) do
                if d:IsA("BasePart") then t[#t+1] = d end
            end
        end
        return t
    end
    local function isAnyPartLocked(model)
    for _, p in ipairs(getAllParts(model)) do
        local locked = false
        local ok = pcall(function() locked = p.Locked end)
        if ok and locked then return true end
    end
    return false
end
    local function bboxHeight(model)
        local rp = physicalRootPart(model)
        if rp then return rp.Size.Y end
        local parts = getAllParts(model)
        local minY, maxY = nil, nil
        for _,p in ipairs(parts) do
            if p and p.Parent and p.CanCollide then
                local y0 = p.Position.Y - (p.Size.Y * 0.5)
                local y1 = p.Position.Y + (p.Size.Y * 0.5)
                if not minY or y0 < minY then minY = y0 end
                if not maxY or y1 > maxY then maxY = y1 end
            end
        end
        if minY and maxY then
            return math.max(0.5, maxY - minY)
        end
        return 2
    end

    local function requestMoreStreamingAround(posList)
        if not (WS and WS.StreamingEnabled) then return end
        local seen = {}
        for _,pos in ipairs(posList) do
            if typeof(pos) == "Vector3" then
                local key = math.floor(pos.X/64).."|"..math.floor(pos.Z/64)
                if not seen[key] then
                    seen[key] = true
                    pcall(function()
                        WS:RequestStreamAroundAsync(pos)
                    end)
                end
            end
        end
        task.wait(0.12)
    end

    local function getRemote(...)
        local re = RS:FindFirstChild("RemoteEvents"); if not re then return nil end
        for _,n in ipairs({...}) do local x=re:FindFirstChild(n); if x then return x end end
        return nil
    end
    local function resolveRemotes()
        return {
            StartDrag = getRemote("RequestStartDraggingItem","StartDraggingItem"),
            BurnItem  = getRemote("RequestBurnItem","BurnItem","RequestFireAdd"),
            CookItem  = getRemote("RequestCookItem","CookItem"),
            ScrapItem = getRemote("RequestScrapItem","ScrapItem","RequestWorkbenchScrap"),
            StopDrag  = getRemote("StopDraggingItem","RequestStopDraggingItem"),
        }
    end

    local DragStarted = setmetatable({}, { __mode = "k" })

    local function safeStartDrag(r, model)
        if r and r.StartDrag and model and model.Parent then
            local ok = pcall(function() r.StartDrag:FireServer(model) end)
            return ok
        end
        return false
    end
    local function safeStopDrag(r, model)
        if r and r.StopDrag and model and model.Parent then
            local ok = pcall(function() r.StopDrag:FireServer(model) end)
            return ok
        end
        return false
    end
    local function finallyStopDrag(r, model)
        task.delay(0.05, function() pcall(safeStopDrag, r, model) end)
        task.delay(0.20, function() pcall(safeStopDrag, r, model) end)
    end
    local function finallyStopDragTwice(r, model)
        pcall(safeStopDrag, r, model)
        Run.Heartbeat:Wait()
        pcall(safeStopDrag, r, model)
        task.delay(0.05, function() pcall(safeStopDrag, r, model) end)
        task.delay(0.20, function() pcall(safeStopDrag, r, model) end)
    end
    local function markDragStarted(model)
        if not (model and model.Parent) then return end
        DragStarted[model] = true
        pcall(function() model:SetAttribute("BringDragStarted", true) end)
    end
    local function clearDragStarted(model)
        if not model then return end
        DragStarted[model] = nil
        pcall(function()
            if model and model.Parent then
                model:SetAttribute("BringDragStarted", nil)
            end
        end)
    end
    local function stopIfDragging(r, model)
        if not model then return end
        if DragStarted[model] then
            finallyStopDrag(r, model)
            clearDragStarted(model)
        end
    end
    local function stopIfDraggingTwice(r, model)
        if not model then return end
        if DragStarted[model] then
            finallyStopDragTwice(r, model)
            clearDragStarted(model)
        end
    end
    local function stopAllOutstandingDrags()
        local r = resolveRemotes()
        for model,_ in pairs(DragStarted) do
            if model and model.Parent then
                finallyStopDragTwice(r, model)
                clearDragStarted(model)
            else
                DragStarted[model] = nil
            end
        end
    end

    local function setCollide(model, on, snapshot)
        local parts = getAllParts(model)
        if on and snapshot then
            for part,can in pairs(snapshot) do
                if part and part.Parent then part.CanCollide = can end
            end
            return
        end
        local snap = {}
        for _,p in ipairs(parts) do snap[p]=p.CanCollide; p.CanCollide=false end
        return snap
    end
    local function zeroAssembly(model)
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
    end

    local function severeExternalWelds(model)
        if not (model and model.Parent) then return end
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                local p0 = d.Part0
                local p1 = d.Part1
                if (p0 and not p0:IsDescendantOf(model)) or (p1 and not p1:IsDescendantOf(model)) then
                    pcall(function() d:Destroy() end)
                end
            end
            if d:IsA("BasePart") and d.Anchored then
                pcall(function() d.Anchored = false end)
            end
        end
        if model:IsA("BasePart") and model.Anchored then
            pcall(function() model.Anchored = false end)
        end
    end

    local function computeForwardDropCF()
        local root = hrp(); if not root then return nil end
        local head = headPart()
        local basePos = head and head.Position or (root.Position + Vector3.new(0,4,0))
        local look = root.CFrame.LookVector
        local center = basePos + Vector3.new(0, DROP_ABOVE_HEAD_STUDS, 0) + look * FALLBACK_AHEAD
        return CFrame.lookAt(center, center + look)
    end

    local function pivotOverTarget(model, target)
        local mp = mainPart(target); if not mp then return end
        local above = mp.CFrame + Vector3.new(0, FALLBACK_UP, 0)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(above)
        else
            local p=mainPart(model); if p then p.CFrame=above end
        end
        for _,p in ipairs(getAllParts(model)) do
            p.AssemblyLinearVelocity = Vector3.new(0,-8,0)
        end
        task.delay(COLLIDE_OFF_SEC, function() setCollide(model, true, snap) end)
    end
    local function moveModel(model, cf)
        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p=mainPart(model); if p then p.CFrame=cf end
        end
        setCollide(model, true, snap)
    end

    local function fireCenterCF(fire)
        local p = fire:FindFirstChild("Center") or fire:FindFirstChild("InnerTouchZone") or mainPart(fire) or fire.PrimaryPart
        return (p and p.CFrame) or fire:GetPivot()
    end
    local function fireHandoffCF(fire) return fireCenterCF(fire) + Vector3.new(0, 1.5, 0) end
    local function scrCenterCF(scr)
        local p = mainPart(scr) or scr.PrimaryPart
        return (p and p.CFrame) or scr:GetPivot()
    end

    local function refreshPrompts(model)
        for _,d in ipairs(model:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local was = d.Enabled
                d.Enabled = false
                task.defer(function() d.Enabled = was ~= false end)
            end
        end
    end

    local INFLT_ATTR   = "OrbInFlightAt"
    local DELIVER_ATTR = "DeliveredAtOrb"
    local JOB_ATTR     = "OrbJob"

    local DRAG_SETTLE  = 0.06
    local ACTION_HOLD  = 0.12
    local CONSUME_WAIT = 1.0
    local JOB_HARD_TIMEOUT_S = 60

    local function awaitConsumedOrMoved(model, timeout)
        local t0 = now()
        local p0 = model and model.Parent or nil
        while now() - t0 < (timeout or 1) do
            if not model or not model.Parent then return true end
            if model.Parent ~= p0 then return true end
            if model:GetAttribute("Consumed") == true then return true end
            Run.Heartbeat:Wait()
        end
        return false
    end

    local function burnFlow(model, campfire)
        local r = resolveRemotes()
        local started = safeStartDrag(r, model)
        if started then markDragStarted(model) end
        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)
        pivotOverTarget(model, campfire)
        task.wait(ACTION_HOLD)
        if r.BurnItem then
            pcall(function() r.BurnItem:FireServer(campfire, Instance.new("Model")) end)
        end
        awaitConsumedOrMoved(model, CONSUME_WAIT)
        if started then stopIfDragging(r, model) end
        refreshPrompts(model)
    end
    local function cookFlow(model, campfire)
        local r = resolveRemotes()
        local started = safeStartDrag(r, model)
        if started then markDragStarted(model) end
        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)
        moveModel(model, fireHandoffCF(campfire))
        local okCall = false
        if r.CookItem then
            local ok = pcall(function() r.CookItem:FireServer(campfire, Instance.new("Model")) end)
            okCall = ok
        end
        if not okCall then pivotOverTarget(model, campfire) end
        task.wait(ACTION_HOLD)
        local cookedName = RAW_TO_COOKED[model.Name]
        awaitConsumedOrMoved(model, CONSUME_WAIT)
        if started then stopIfDragging(r, model) end
        task.delay(0.15, function()
            if cookedName then
                local cooked = (function()
                    local center = fireCenterCF(campfire).Position
                    local best, bestD
                    for _,m in ipairs(WS:GetDescendants()) do
                        if m:IsA("Model") and m.Name == cookedName and not isExcludedModel(m) then
                            local mp = mainPart(m)
                            if mp then
                                local d = (mp.Position - center).Magnitude
                                if d <= 10 and (not bestD or d < bestD) then best, bestD = m, d end
                            end
                        end
                    end
                    return best
                end)()
                if cooked then
                    local center = fireCenterCF(campfire).Position
                    local mp = mainPart(cooked)
                    if mp then
                        local dir = (mp.Position - center).Unit
                        local snap = setCollide(cooked, false)
                        if cooked:IsA("Model") then cooked:PivotTo(mp.CFrame + CFrame.new(dir*1.5).Position) end
                        setCollide(cooked, true, snap)
                    end
                end
            end
        end)
        refreshPrompts(model)
    end
    local function scrapFlow(model, scrapper)
        local r = resolveRemotes()
        local started = safeStartDrag(r, model)
        if started then markDragStarted(model) end
        Run.Heartbeat:Wait()
        task.wait(DRAG_SETTLE)
        moveModel(model, scrCenterCF(scrapper) + Vector3.new(0, 1.5, 0))
        local okCall = false
        if r.ScrapItem then
            local ok = pcall(function() r.ScrapItem:FireServer(scrapper, Instance.new("Model")) end)
            okCall = ok
        end
        if not okCall then pivotOverTarget(model, scrapper) end
        task.wait(ACTION_HOLD)
        awaitConsumedOrMoved(model, CONSUME_WAIT)
        if started then stopIfDragging(r, model) end
        refreshPrompts(model)
    end

    local dropCounter = 0
    local function ringOffset()
        dropCounter += 1
        local i = dropCounter
        local a = i * 2.399963229728653
        local r = math.min(CLUSTER_RADIUS_MIN + CLUSTER_RADIUS_STEP * (i - 1), CLUSTER_RADIUS_MAX)
        return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
    end

    local function groundCFAroundPlayer(model)
        local root = hrp(); if not root then return nil end
        local head = headPart()
        local basePos = head and head.Position or (root.Position + Vector3.new(0, 4, 0))
        local look    = root.CFrame.LookVector
        local offset  = ringOffset()
        local waveY   = math.sin(dropCounter * AIR_DROP_WAVE_FREQUENCY) * AIR_DROP_WAVE_AMPLITUDE
        local pos = basePos
            + look * FALLBACK_AHEAD
            + Vector3.new(0, DROP_ABOVE_HEAD_STUDS, 0)
            + Vector3.new(offset.X, 0, offset.Z)
            + Vector3.new(0, waveY, 0)
        return CFrame.lookAt(pos, pos + look)
    end

    local function rayParamsForGround(extras)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true
        local ex = { lp.Character }
        local items = WS:FindFirstChild("Items")
        if items then table.insert(ex, items) end
        if extras then
            for i=1,#extras do
                local v = extras[i]
                if v then table.insert(ex, v) end
            end
        end
        params.FilterDescendantsInstances = ex
        return params
    end

    local function groundBelow(xz, ignoreInst, maxDepth)
        local depth = maxDepth or 220
        local params = rayParamsForGround({ ignoreInst })
        local start = Vector3.new(xz.X, xz.Y + 60, xz.Z)
        local hit = WS:Raycast(start, Vector3.new(0, -depth, 0), params)
        return hit and hit.Position or nil
    end

    local function settleCFForModelAtXZ(model, xz, facing)
        local rp = physicalRootPart(model)
        local halfY = (rp and rp.Size and rp.Size.Y * 0.5) or (bboxHeight(model) * 0.5)
        local hitPos = groundBelow(xz, model, 260) or xz
        local y = hitPos.Y + halfY + 0.15
        local pos = Vector3.new(xz.X, y, xz.Z)
        local dir = facing or Vector3.new(0,0,-1)
        if dir.Magnitude < 1e-3 then dir = Vector3.new(0,0,-1) end
        return CFrame.lookAt(pos, pos + Vector3.new(dir.X, 0, dir.Z))
    end

    local function dropNearPlayer(model)
    if not (model and model.Parent) then return false end
    if isAnyPartLocked(model) then return false end
    severeExternalWelds(model)

        local r = resolveRemotes()
        local started = safeStartDrag(r, model)
        if started then markDragStarted(model) end
        Run.Heartbeat:Wait()

        local cf = groundCFAroundPlayer(model) or computeForwardDropCF()
        if not cf then
            if started then
                stopIfDragging(r, model)
            end
            return false
        end

        local snap = setCollide(model, false)
        zeroAssembly(model)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model); if p then p.CFrame = cf end
        end
        setCollide(model, true, snap)

        if started then
            stopIfDragging(r, model)
        end

        for _,p in ipairs(getAllParts(model)) do
            p.Anchored = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        refreshPrompts(model)
        task.delay(0.5, function()
            pcall(function()
                if model and model.Parent then
                    model:SetAttribute("OrbInFlightAt", nil)
                    model:SetAttribute("OrbJob", nil)
                    model:SetAttribute("DeliveredAtOrb", nil)
                end
            end)
        end)
        return true
    end

    local function makeOrb(cf, name)
        local part = Instance.new("Part")
        part.Name = name; part.Shape = Enum.PartType.Ball; part.Size = Vector3.new(1.5,1.5,1.5)
        part.Material = Enum.Material.Neon; part.Color = Color3.fromRGB(255,200,50)
        part.Anchored = true; part.CanCollide = false; part.CanTouch = false; part.CanQuery = false
        part.CFrame = cf; part.Parent = WS
        local light = Instance.new("PointLight"); light.Range = 16; light.Brightness = 3; light.Parent = part
        return part
    end
    local function mergedSet(a, b)
        local t = {}; for k,v in pairs(a) do if v then t[k]=true end end; for k,v in pairs(b) do if v then t[k]=true end end; return t
    end

    local DRAG_SPEED    = 18
    local VERTICAL_MULT = 1.35
    local STEP_WAIT     = 0.03
    local STUCK_TTL     = 6.0
    local ORB_PICK_RADIUS = 60

    local function setPivot(model, cf)
        if model:IsA("Model") then
            model:PivotTo(cf)
        else
            local p = mainPart(model); if p then p.CFrame = cf end
        end
    end

    local function dropFromOrbSmooth(model, orbPos, jobId, origSnap, H)
        if not (model and model.Parent) then return end
        zeroAssembly(model)

        local rp = physicalRootPart(model)
        local halfY = (rp and rp.Size and rp.Size.Y * 0.5) or math.max(0.5, (H or bboxHeight(model)) * 0.5)

        local xz = Vector3.new(orbPos.X, orbPos.Y, orbPos.Z)
        local g = groundBelow(xz, model, 320)
        local y = g and (g.Y + halfY + 0.15) or (orbPos.Y + math.max(0.5, (H or 2) * 0.25))
        local above = Vector3.new(orbPos.X, y, orbPos.Z)

        setPivot(model, CFrame.new(above))

        for _,p in ipairs(getAllParts(model)) do
            p.Anchored = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        setCollide(model, true, origSnap)
        pcall(function()
            model:SetAttribute(INFLT_ATTR, nil)
            model:SetAttribute(JOB_ATTR, nil)
            model:SetAttribute(DELIVER_ATTR, tostring(jobId))
        end)
        refreshPrompts(model)
        task.delay(0.5, function()
            pcall(function()
                if model and model.Parent then
                    model:SetAttribute(DELIVER_ATTR, nil)
                end
            end)
        end)
    end

    local function itemsRootOrNil() return WS:FindFirstChild("Items") end

    local CROCKPOT_SCAN_PERIOD = 3.0
    local _crockCache = { t = 0, parts = {} }

    local function _refreshCrockpotsIfNeeded()
        if (now() - (_crockCache.t or 0)) < CROCKPOT_SCAN_PERIOD then return end
        _crockCache.t = now()
        _crockCache.parts = {}

        local seen = {}
        local function scan(root)
            if not root then return end
            for _,d in ipairs(root:GetDescendants()) do
                if d:IsA("Model") then
                    local n = (d.Name or ""):lower()
                    if n == "crockpot" or n == "crock pot" or n:find("crockpot", 1, true) or (n:find("crock", 1, true) and n:find("pot", 1, true)) then
                        local mp = mainPart(d)
                        if mp and mp.Parent and not seen[mp] then
                            seen[mp] = true
                            _crockCache.parts[#_crockCache.parts+1] = mp
                            if #_crockCache.parts >= 8 then return end
                        end
                    end
                end
            end
        end

        local structures = WS:FindFirstChild("Structures")
        scan(structures)
        if #_crockCache.parts == 0 then scan(_camp) end
        if #_crockCache.parts == 0 then scan(WS) end
    end

    local function isModelWeldedToOutside(m)
        if not (m and m.Parent) then return false end
        for _,d in ipairs(m:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                local p0, p1 = d.Part0, d.Part1
                if (p0 and not p0:IsDescendantOf(m)) or (p1 and not p1:IsDescendantOf(m)) then
                    return true
                end
            elseif d:IsA("JointInstance") then
                local p0, p1 = d.Part0, d.Part1
                if (p0 and not p0:IsDescendantOf(m)) or (p1 and not p1:IsDescendantOf(m)) then
                    return true
                end
            elseif d:IsA("Constraint") then
                local a0, a1 = d.Attachment0, d.Attachment1
                if (a0 and not a0:IsDescendantOf(m)) or (a1 and not a1:IsDescendantOf(m)) then
                    return true
                end
            end
        end
        return false
    end

    local function isStewOnCrockpot(stewModel)
        if not (stewModel and stewModel.Parent) then return false end
        local smp = mainPart(stewModel)
        if not smp then return false end

        _refreshCrockpotsIfNeeded()
        if not _crockCache.parts or #_crockCache.parts == 0 then return false end

        local p = smp.Position
        for _,cp in ipairs(_crockCache.parts) do
            if cp and cp.Parent then
                local q = cp.Position
                local dxz = (Vector3.new(p.X, 0, p.Z) - Vector3.new(q.X, 0, q.Z)).Magnitude
                local dy  = p.Y - q.Y
                if dxz <= 2.2 and dy >= 0 and dy <= 5.0 then
                    return true
                end
            end
        end
        return false
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

        if selectedSet["Rotten"] and m:GetAttribute("FoodRot") ~= nil and foodSet[nm] then
            if nm == "Apple" then
                if itemsFolder and m.Parent ~= itemsFolder then return false end
                if isInsideTree(m) then return false end
                return true
            end
            if nm == "Berry" then
                if itemsFolder and m.Parent ~= itemsFolder then return false end
                if isInsideTree(m) then return false end
                return true
            end
            return true
        end

        local rk = "Rotten " .. nm
        if selectedSet[rk] then
            return m:GetAttribute("FoodRot") ~= nil
        end

        if selectedSet[nm] then return true end
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
        if selectedSet["Sword"] and l:find("sword",1,true) and not l:find("fish",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Crossbow"] and l:find("crossbow",1,true) and not l:find("cultist",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Blueprint"] and l:find("blueprint",1,true) then return true end
        if selectedSet["Flashlight"] and l:find("flashlight",1,true) and not hasHumanoid(m) then return true end
        if selectedSet["Cultist Gem"] and l:find("cultist",1,true) and l:find("gem",1,true) then return true end
        if selectedSet["Forest Gem"] and (l:find("forest gem",1,true) or (l:find("forest",1,true) and l:find("fragment",1,true))) then return true end
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

    local function canPick(m, center, radius, selectedSet, jobId)
        if not (m and m.Parent and m:IsA("Model")) then return false end
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
        if isExcludedModel(m) then return false end
        if isLogWallBlocked(m, selectedSet) then return false end
        local tIn = tonumber(m:GetAttribute(INFLT_ATTR))
        local jIn = m:GetAttribute(JOB_ATTR)
        if tIn and jIn and tostring(jIn) ~= tostring(jobId) and (now() - tIn) < STUCK_TTL then
            return false
        end
        if not nameMatches(selectedSet, m) then
            return false
        end
        local mp = mainPart(m); if not mp then return false end
        return (mp.Position - center).Magnitude <= radius
    end

    local function getCandidates(center, radius, selectedSet, jobId)
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local parts = WS:GetPartBoundsInRadius(center, radius, params) or {}
        local uniq, out = {}, {}
        for _,part in ipairs(parts) do
            local pick = nil
            if part:IsA("BasePart") then
                pick = nearestSelectedModelFromPart(part, selectedSet)
            end
            if pick and not uniq[pick] and canPick(pick, center, radius, selectedSet, jobId) then
                uniq[pick] = true
                out[#out+1] = pick
            end
        end
        return out
    end

    local function startConveyor(model, orbPos, jobId)
        if not (model and model.Parent) then return end
        severeExternalWelds(model)
        pcall(function()
            model:SetAttribute(INFLT_ATTR, now())
            model:SetAttribute(JOB_ATTR, tostring(jobId))
        end)
        local mp = mainPart(model); if not mp then return end
        local H = bboxHeight(model)

        local riserY = orbPos.Y - 1.0 + math.clamp(H * 0.45, 0.8, 3.0)
        local lookDir = (Vector3.new(orbPos.X, mp.Position.Y, orbPos.Z) - mp.Position)
        lookDir = (lookDir.Magnitude > 0.001) and lookDir.Unit or Vector3.zAxis

        local snapOrig = setCollide(model, false)
        zeroAssembly(model)

        local function setPivotLocal(model0, cf)
            if model0:IsA("Model") then
                model0:PivotTo(cf)
            else
                local p = mainPart(model0); if p then p.CFrame = cf end
            end
        end

        while model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local dy = riserY - pos.Y
            if math.abs(dy) <= 0.4 then break end
            local stepY = math.sign(dy) * math.min(DRAG_SPEED * VERTICAL_MULT * STEP_WAIT, math.abs(dy))
            local newPos = Vector3.new(pos.X, pos.Y + stepY, pos.Z)
            setPivotLocal(model, CFrame.new(newPos, newPos + lookDir))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            task.wait(STEP_WAIT)
        end
        while model and model.Parent do
            local pivot = model:IsA("Model") and model:GetPivot() or (mainPart(model) and mainPart(model).CFrame)
            if not pivot then break end
            local pos = pivot.Position
            local delta = Vector3.new(orbPos.X - pos.X, 0, orbPos.Z - pos.Z)
            local dist = delta.Magnitude
            if dist <= 1.0 then break end
            local step = math.min(DRAG_SPEED * STEP_WAIT, dist)
            local dir = delta.Unit
            local newPos = Vector3.new(pos.X, riserY, pos.Z) + dir * step
            setPivotLocal(model, CFrame.new(newPos, newPos + dir))
            for _,p in ipairs(getAllParts(model)) do
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
            end
            task.wait(STEP_WAIT)
        end

        dropFromOrbSmooth(model, orbPos, jobId, snapOrig, H)
    end

    local function runConveyorWave(centerPos, orbPos, targets, jobId, perNameCount)
        local picked = getCandidates(centerPos, ORB_PICK_RADIUS, targets, jobId)
        if #picked == 0 then
            return 0
        end

        local limitOn = C.State.BringLimitEnabled and true or false
        local maxPerName = currentLimit()

        local cnt = perNameCount or {}
        local out = {}
        for _,m in ipairs(picked) do
            local nm = m.Name or ""
            cnt[nm] = (cnt[nm] or 0) + 1
            if (not limitOn) or cnt[nm] <= maxPerName then
                out[#out+1] = m
            end
        end
        picked = out

        local active = 0
        local function spawnOne(m)
            if m and m.Parent then
                active += 1
                task.spawn(function()
                    startConveyor(m, orbPos, jobId)
                    active -= 1
                end)
            end
        end

        for i = 1, #picked do
            while active >= 10 do Run.Heartbeat:Wait() end
            spawnOne(picked[i])
            task.wait(0.5)
        end

        local deadline = now() + math.max(5, 0.5 * #picked + 5)
        while active > 0 and now() < deadline do
            Run.Heartbeat:Wait()
        end

        return #picked
    end

    local function runConveyorJob(centerPos, orbPos, targets, jobId)
        local t0 = now()
        local emptyPasses = 0
        local perNameCount = {}

        while true do
            if now() - t0 >= JOB_HARD_TIMEOUT_S then
                break
            end
            local moved = runConveyorWave(centerPos, orbPos, targets, jobId, perNameCount)
            if moved == 0 then
                emptyPasses += 1
                if emptyPasses >= 2 then break end
                requestMoreStreamingAround({ centerPos, orbPos })
                task.wait(0.2)
            else
                emptyPasses = 0
            end
        end
    end

    local function burnNearby()
        local camp = CAMPFIRE_PATH; if not camp then return end
        local root = hrp(); if not root then return end
        local campCF = (mainPart(camp) and mainPart(camp).CFrame or camp:GetPivot())
        requestMoreStreamingAround({ root.Position, campCF.Position })
        local jobId = ("%d-%d"):format(os.time(), math.random(1,1e6))
        local orb2 = makeOrb(root.CFrame, "orb2")
        local orb1 = makeOrb(campCF + Vector3.new(0, ORB_OFFSET_Y + 10, 0), "orb1")
        local targets = mergedSet(fuelSet, cookSet)
        runConveyorJob(orb2.Position, orb1.Position, targets, jobId)
        if orb1 then orb1:Destroy() end
        if orb2 then orb2:Destroy() end
    end

    local function scrapNearby()
        local scr = SCRAPPER_PATH; if not scr then return end
        local root = hrp(); if not root then return end
        local scrCF = (mainPart(scr) and mainPart(scr).CFrame or scr:GetPivot()).Position
        requestMoreStreamingAround({ root.Position, scrCF })
        local jobId = ("%d-%d"):format(os.time(), math.random(1,1e6))
        local orb2 = makeOrb(root.CFrame, "orb2")
        local orb1 = makeOrb((mainPart(SCRAPPER_PATH) and mainPart(SCRAPPER_PATH).CFrame or SCRAPPER_PATH:GetPivot()) + Vector3.new(0, ORB_OFFSET_Y + 10, 0), "orb1")
        local targets = mergedSet(junkSet, scrapAlso)
        runConveyorJob(orb2.Position, orb1.Position, targets, jobId)
        if orb1 then orb1:Destroy() end
        if orb2 then orb2:Destroy() end
    end

    local function setFromChoice(choice)
        local s = {}
        if type(choice) == "table" then
            for _,v in ipairs(choice) do if v and v ~= "" then s[v]=true end end
        elseif choice and choice ~= "" then
            s[choice] = true
        end
        return s
    end

    local selJunkMany, selFuelMany, selFoodMany, selMedicalMany, selWAMany, selMiscMany, selPeltMany =
        {},{},{},{},{},{},{}

    local _bringBusy = false
    local function fastBringToGround(selectedSet, opts)
        if not selectedSet or next(selectedSet) == nil then
            return
        end
        if _bringBusy then
            return
        end
        _bringBusy = true

        local skipFoodRot   = (opts and opts.SkipFoodRot == true) or false
        local excludeCorpse = (opts and opts.ExcludeCorpse == true) or false

        local ok = pcall(function()
            dropCounter = 0
            local itemsFolder = itemsRootOrNil(); if not itemsFolder then return end
            local root = hrp()

            local limitOn = C.State.BringLimitEnabled and true or false
            local maxPerName = currentLimit()

            local perNameCount = {}

            local function scanQueue(alreadyMoved)
                local seenModel, queue = {}, {}
                local desc = itemsFolder:GetDescendants()
                for _,d in ipairs(desc) do
                    local m = nil
                    if d:IsA("Model") then
                        if nameMatches(selectedSet, d) then m = d end
                    elseif d:IsA("BasePart") then
                        m = nearestSelectedModelFromPart(d, selectedSet)
                    end
                    if m and not seenModel[m] and not alreadyMoved[m] then
                        seenModel[m] = true

                        if excludeCorpse then
                            local ln = (m.Name or ""):lower()
                            if ln:find("corpse", 1, true) then
                                continue
                            end
                        end

                        if skipFoodRot then
                            local rot = m:GetAttribute("FoodRot")
                            if rot ~= nil then
                                local nm0 = tostring(m.Name or "")
                                local rk = "Rotten " .. nm0
                                local allow = false
                                if selectedSet["Rotten"] and foodSet[nm0] then allow = true end
                                if selectedSet[rk] then allow = true end
                                if not allow then
                                    continue
                                end
                            end
                        end

                        if m.Name == "Stew" then
                            if isModelWeldedToOutside(m) or isStewOnCrockpot(m) then
                                continue
                            end
                        end

                        if not isExcludedModel(m) and not isLogWallBlocked(m, selectedSet) then
                            local mp = mainPart(m)
                            if mp then
                                perNameCount[m.Name] = (perNameCount[m.Name] or 0) + 1
                                if (not limitOn) or perNameCount[m.Name] <= maxPerName then
                                    queue[#queue+1] = m
                                end
                            end
                        end
                    end
                end
                return queue
            end

            local alreadyMoved = {}
            local maxPasses = 3
            for pass = 1, maxPasses do
                if root then
                    requestMoreStreamingAround({ root.Position })
                end

                local queue = scanQueue(alreadyMoved)

                if #queue == 0 then
                    if WS.StreamingEnabled and root then
                        requestMoreStreamingAround({ root.Position })
                        task.wait(0.20)
                    else
                        break
                    end
                else
                    local dropped = 0
                    for i=1,#queue do
                        local m = queue[i]
                        alreadyMoved[m] = true
                        if dropNearPlayer(m) then dropped += 1 end
                        if i % 25 == 0 then Run.Heartbeat:Wait() end
                    end
                    if WS.StreamingEnabled and dropped > 0 then
                        task.wait(0.10)
                    end
                end
            end
        end)

        _bringBusy = false
        if not ok then
            stopAllOutstandingDrags()
            return
        end
    end

    local function multiSelectDropdown(args)
        return tab:Dropdown({
            Title = args.title,
            Values = args.values,
            Multi = true,
            AllowNone = true,
            Callback = function(choice) args.setter(setFromChoice(choice)) end
        })
    end

    local function parseSliderNumber(v)
        if type(v) == "number" then return v end
        if type(v) == "string" then return tonumber(v) end
        if type(v) ~= "table" then return nil end

        local keys = {
            "Value","value",
            "Current","current",
            "CurrentValue","currentValue",
            "Number","number",
            "Slider","slider",
        }
        for _,k in ipairs(keys) do
            local n = tonumber(v[k])
            if n then return n end
        end

        if type(v.Value) == "table" then
            local n = tonumber(v.Value.Value) or tonumber(v.Value.Current) or tonumber(v.Value.CurrentValue)
            if n then return n end
        end

        if #v >= 1 then
            local n = tonumber(v[1])
            if n then return n end
        end

        return nil
    end

    tab:Section({ Title = "Actions" })
    tab:Button({ Title = "Burn/Cook Nearby", Callback = burnNearby })
    tab:Button({ Title = "Scrap Nearby",      Callback = scrapNearby })

    tab:Section({ Title = "Bring Limits" })
    tab:Toggle({
        Title = "Enable per-name limit",
        Default = C.State.BringLimitEnabled and true or false,
        Callback = function(on)
            C.State.BringLimitEnabled = on and true or false
        end
    })
    tab:Slider({
        Title = "Max per item name",
        Value = { Min = 1, Max = 100, Default = currentLimit() },
        Callback = function(v)
            local nv = parseSliderNumber(v)
            if nv then
                C.State.BringLimitAmount = math.clamp(nv, 1, 100)
            end
        end
    })

    tab:Section({ Title = "Bring Scrap" })
    multiSelectDropdown({ title = "Bring Scrap", values = junkItems, setter = function(s) selJunkMany = s end })
    tab:Button({ Title = "Bring Selected", Callback = function() fastBringToGround(selJunkMany) end })

    tab:Section({ Title = "Bring Fuel" })
    multiSelectDropdown({ title = "Bring Fuel", values = fuelItems, setter = function(s) selFuelMany = s end })
    tab:Button({ Title = "Bring Selected", Callback = function() fastBringToGround(selFuelMany) end })

    tab:Section({ Title = "Bring Food" })
    multiSelectDropdown({ title = "Bring Food", values = foodItems, setter = function(s) selFoodMany = s end })
    tab:Button({ Title = "Bring Selected", Callback = function() fastBringToGround(selFoodMany, { SkipFoodRot = true }) end })

    tab:Section({ Title = "Bring Medical" })
    multiSelectDropdown({ title = "Bring Medical", values = medicalItems, setter = function(s) selMedicalMany = s end })
    tab:Button({ Title = "Bring Selected", Callback = function() fastBringToGround(selMedicalMany) end })

    tab:Section({ Title = "Bring Weapons/Armor" })
    multiSelectDropdown({ title = "Bring Weapons/Armor", values = weaponsArmor, setter = function(s) selWAMany = s end })
    tab:Button({ Title = "Bring Selected", Callback = function() fastBringToGround(selWAMany) end })

    tab:Section({ Title = "Bring Ammo & Misc" })
    multiSelectDropdown({ title = "Bring Ammo & Misc", values = ammoMisc, setter = function(s) selMiscMany = s end })
    tab:Button({ Title = "Bring Selected", Callback = function() fastBringToGround(selMiscMany) end })

    tab:Section({ Title = "Bring Pelts" })
    multiSelectDropdown({ title = "Bring Pelts", values = pelts, setter = function(s) selPeltMany = s end })
    tab:Button({ Title = "Bring Selected", Callback = function() fastBringToGround(selPeltMany, { ExcludeCorpse = true }) end })

    do
        local ORB_RADIUS     = 2.2
        local ORB_STUCK_SECS = 0.9
        local ORB_FALL_DELTA = 2.5
        local ORB_MAX_KICKS  = 2
        local ORB_RESET_UP   = 1.2
        local ORB_KICK_VY    = -60
        local GUARD_HZ       = 12

        local function campOrbPos()
            local camp = CAMPFIRE_PATH
            if not camp then return nil end
            local c = (mainPart(camp) and mainPart(camp).CFrame or camp:GetPivot()).Position
            return Vector3.new(c.X, c.Y + ORB_OFFSET_Y + 10, c.Z)
        end
        local function scrapOrbPos()
            local scr = SCRAPPER_PATH
            if not scr then return nil end
            local c = (mainPart(scr) and mainPart(scr).CFrame or scr:GetPivot()).Position
            return Vector3.new(c.X, c.Y + ORB_OFFSET_Y + 10, c.Z)
        end
        local function liveOrb1Pos()
            local o = WS:FindFirstChild("orb1")
            return o and o:IsA("BasePart") and o.Position or nil
        end

        local function kickDown(m, orbY)
            local mp = mainPart(m); if not mp then return end
            pcall(function() mp.Anchored = false end)
            pcall(function() mp.AssemblyLinearVelocity  = Vector3.new(0, ORB_KICK_VY, 0) end)
            pcall(function() mp.AssemblyAngularVelocity = Vector3.new() end)
            pcall(function()
                local p = mp.Position
                mp.CFrame = CFrame.new(Vector3.new(p.X, orbY + ORB_RESET_UP, p.Z))
            end)
            refreshPrompts(m)
        end

        local watched = setmetatable({}, {__mode="k"})
        local acc = 0
        Run.Heartbeat:Connect(function(dt)
            acc += dt
            if acc < (1 / GUARD_HZ) then return end
            acc = 0

            local positions = {}
            local pLive = liveOrb1Pos(); if pLive then positions[#positions+1] = pLive end
            local pCamp = campOrbPos();  if pCamp then positions[#positions+1] = pCamp end
            local pScr  = scrapOrbPos(); if pScr  then positions[#positions+1] = pScr  end
            if #positions == 0 then return end

            local items = WS:FindFirstChild("Items"); if not items then return end
            for _,m in ipairs(items:GetChildren()) do
                if not m:IsA("Model") then continue end
                local mp = mainPart(m); if not mp then continue end

                local nearest, orbY = nil, nil
                local pos = mp.Position
                for _,o in ipairs(positions) do
                    local d = (pos - o).Magnitude
                    if d <= ORB_RADIUS then nearest, orbY = true, o.Y; break end
                end

                if nearest then
                    local rec = watched[m]
                    if not rec then
                        watched[m] = {t=now(), y0=pos.Y, kicks=0}
                    else
                        local fell = (rec.y0 - pos.Y) >= ORB_FALL_DELTA or pos.Y < (orbY - ORB_FALL_DELTA)
                        if fell then
                            watched[m] = nil
                        elseif (now() - rec.t) >= ORB_STUCK_SECS then
                            if rec.kicks < ORB_MAX_KICKS then
                                rec.kicks += 1
                                rec.t = now()
                                rec.y0 = pos.Y
                                kickDown(m, orbY)
                            else
                                watched[m] = nil
                            end
                        end
                    end
                else
                    watched[m] = nil
                end
            end
        end)
    end

    if type(C.RegisterCleanup) == "function" then
        C.RegisterCleanup(function()
            stopAllOutstandingDrags()
        end)
    end
end
