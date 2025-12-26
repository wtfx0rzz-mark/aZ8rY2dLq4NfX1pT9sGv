-- gather.lua

return function(C, R, UI)
    local function run()
        C  = C  or _G.C
        UI = UI or _G.UI

        local Services = (C and C.Services) or {}
        local Players  = Services.Players or game:GetService("Players")
        local RS       = Services.RS or game:GetService("ReplicatedStorage")
        local WS       = Services.WS or game:GetService("Workspace")
        local Run      = Services.Run or game:GetService("RunService")

        local lp = Players.LocalPlayer
        if not lp then return end

        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Gather or Tabs.Auto
        if not tab then
            warn("[Gather] Gather tab not found")
            return
        end

        if type(C.State) ~= "table" then C.State = {} end
        if type(C.State.Toggles) ~= "table" then C.State.Toggles = {} end
        if C.State.AuraRadius == nil then C.State.AuraRadius = 150 end
        if not tonumber(C.State.GatherRadius) then
            C.State.GatherRadius = tonumber(C.State.AuraRadius) or 150
        end

        local junkItems = {
            "Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine",
            "UFO Junk","UFO Component"
        }
        local fuelItems = { "Log","Coal","Fuel Canister","Oil Barrel","Chair","Biofuel" }
        local foodItems = {
            "Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot",
            "Chilli","Stew","Ribs","Pumpkin","Hearty Stew","Cooked Ribs","Corn","BBQ ribs","Apple","Mackerel"
        }
        local medicalItems = {"Bandage","MedKit"}
        local weaponsArmor = {
            "Revolver","Rifle","Leather Body","Iron Body","Good Axe","Strong Axe","Hammer",
            "Chainsaw","Crossbow","Katana","Kunai","Laser cannon","Laser sword","Morningstar","Riot Shield","Spear","Tactical Shotgun","Wildfire",
            "Sword","Ice Axe","Thorn Body"
        }
        local ammoMisc = {
            "Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Mossy Coin","Cultist","Sapling",
            "Basketball","Blueprint","Diamond","Gem of the Forest Fragment","Flashlight","Old Taming flute","Cultist Gem","Tusk","Infernal Sack"
        }
        local pelts = {"Bunny Foot","Wolf Pelt","Alpha Wolf Pelt","Bear Pelt","Scorpion Shell","Polar Bear Pelt","Arctic Fox Pelt"}

        local Selected = { Junk = {}, Fuel = {}, Food = {}, Medical = {}, WA = {}, Misc = {}, Pelts = {} }
        local wantMossy, wantCultist, wantSapling = false, false, false
        local wantBlueprint, wantForestGem, wantKey, wantFlashlight, wantTamingFlute = false, false, false, false, false

        local hoverHeight  = 5
        local forwardDrop  = 5
        local upDrop       = 5
        local scanInterval = 0.1

        local DROP_ABOVE_HEAD_STUDS = 10

        local UNANCHOR_BATCH = 10
        local UNANCHOR_STEP  = 0.04
        local NUDGE_DOWN     = 4
        local CULTIST_LIMIT  = math.huge

        local PLACE_BATCH    = 10
        local PLACE_YIELD_FN = function() Run.Heartbeat:Wait() end

        local CLUSTER_RADIUS_MIN  = 0.75
        local CLUSTER_RADIUS_STEP = 0.05
        local CLUSTER_RADIUS_MAX  = 2.35
        local AIR_DROP_WAVE_AMPLITUDE = 0.8
        local AIR_DROP_WAVE_FREQUENCY = 1.35

        local function getRemote(...)
            local f = RS:FindFirstChild("RemoteEvents")
            if not f then return nil end
            for i = 1, select("#", ...) do
                local n = select(i, ...)
                local x = f:FindFirstChild(n)
                if x then return x end
            end
            return nil
        end

        local RF_Start  = getRemote("RequestStartDraggingItem","StartDraggingItem")
        local RF_Stop   = getRemote("RequestStopDraggingItem","StopDraggingItem","StopDraggingItemRemote")

        local DragActive = {}
        local DRAG_TTL   = 3.0

        local function itemsRootOrNil()
            return WS:FindFirstChild("Items")
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

        local function hrp()
            local ch = lp.Character or lp.CharacterAdded:Wait()
            return ch and ch:FindFirstChild("HumanoidRootPart")
        end

        local function gatherRadius()
            return math.clamp(tonumber(C.State and C.State.GatherRadius) or 150, 0, 500)
        end

        local function isWallVariant(m)
            if not (m and m:IsA("Model")) then return false end
            local n = (m.Name or ""):lower()
            return n == "logwall" or n == "log wall" or (n:find("log", 1, true) and n:find("wall", 1, true))
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

        local function isInsideTree(m)
            local itemsFolder = itemsRootOrNil()
            local cur = m and m.Parent
            while cur and cur ~= WS do
                local nm = (cur.Name or ""):lower()
                if nm:find("tree",1,true) then return true end
                if itemsFolder and cur == itemsFolder then break end
                cur = cur.Parent
            end
            return false
        end

        local function isCultist(m)
            if not (m and m:IsA("Model")) then return false end
            local nl = (m.Name or ""):lower()
            return nl:find("cultist",1,true) and hasHumanoid(m)
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

        local function setNoCollideModel(m, on)
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.CanCollide = not on
                    d.CanQuery   = not on
                    d.CanTouch   = not on
                    d.Massless   = on and true or false
                    d.AssemblyLinearVelocity  = Vector3.new()
                    d.AssemblyAngularVelocity = Vector3.new()
                end
            end
        end

        local function setAnchoredModel(m, on)
            for _,d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then d.Anchored = on end
            end
        end

        local function dragSafeStop(m)
            if not (m and RF_Stop) then return end
            pcall(function() RF_Stop:FireServer(m) end)
        end

        local function dragTrackRelease(m)
            local rec = DragActive[m]
            if not rec then return end
            DragActive[m] = nil
            for _,c in ipairs(rec.conns) do pcall(function() c:Disconnect() end) end
            dragSafeStop(m)
        end

        local function dragStart(m)
            if not (m and m.Parent and RF_Start) then return false end
            if DragActive[m] then
                DragActive[m].t0 = os.clock()
                return true
            end
            local ok = pcall(function() RF_Start:FireServer(m) end)
            if not ok then return false end
            local conns = {}
            conns[#conns+1] = m.AncestryChanged:Connect(function(_, parent)
                if not parent then dragTrackRelease(m) end
            end)
            conns[#conns+1] = m:GetPropertyChangedSignal("Parent"):Connect(function()
                if not m.Parent then dragTrackRelease(m) end
            end)
            DragActive[m] = { t0 = os.clock(), conns = conns }
            return true
        end

        local function dragStop(m)
            dragTrackRelease(m)
        end

        Run.Heartbeat:Connect(function()
            local now = os.clock()
            for m, rec in pairs(DragActive) do
                if (not m) or (not m.Parent) or (now - rec.t0) > DRAG_TTL then
                    dragTrackRelease(m)
                end
            end
        end)

        local function buildSelectedSet()
            local set = {}
            for name,_ in pairs(Selected.Junk or {})    do set[name] = true end
            for name,_ in pairs(Selected.Fuel or {})    do set[name] = true end
            for name,_ in pairs(Selected.Food or {})    do set[name] = true end
            for name,_ in pairs(Selected.Medical or {}) do set[name] = true end
            for name,_ in pairs(Selected.WA or {})      do set[name] = true end
            for name,_ in pairs(Selected.Misc or {})    do set[name] = true end
            for name,_ in pairs(Selected.Pelts or {})   do set[name] = true end
            if wantMossy       then set["Mossy Coin"]   = true end
            if wantCultist     then set["Cultist"]      = true end
            if wantSapling     then set["Sapling"]      = true end
            if wantBlueprint   then set["Blueprint"]    = true end
            if wantForestGem   then set["Forest Gem"]   = true end
            if wantKey         then set["Key"]          = true end
            if wantFlashlight  then set["Flashlight"]   = true end
            if wantTamingFlute then set["Taming flute"] = true end
            return set
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
            if selectedSet["Mossy Coin"] and (nm == "Mossy Coin" or nm:match("^Mossy Coin%d+$")) then return true end
            if selectedSet["Cultist"] and m:IsA("Model") and l:find("cultist",1,true) and hasHumanoid(m) then return true end
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
            if lastModel and lastModel.Parent == itemsFolder then return lastModel end
            return lastModel
        end

        local function nearestSelectedModelFromPart(part, selectedSet)
            if not part or not part:IsA("BasePart") then return nil end
            local itemsFolder = itemsRootOrNil()
            local m = topModelUnderItems(part, itemsFolder) or part:FindFirstAncestorOfClass("Model")
            if m and nameMatches(selectedSet, m) then return m end
            return nil
        end

        local function canGather(m, selectedSet, origin, rad)
            if not (m and m.Parent and m:IsA("Model")) then return false end
            local itemsFolder = itemsRootOrNil()
            if itemsFolder and not m:IsDescendantOf(itemsFolder) then return false end
            if isExcludedModel(m) or isUnderLogWall(m) then return false end
            if m.Name == "Log" and isWallVariant(m) then return false end
            local mp = mainPart(m)
            if not mp or mp.Anchored then return false end
            if origin and rad then
                if (mp.Position - origin).Magnitude > rad then return false end
            end
            if not nameMatches(selectedSet, m) then return false end
            return true
        end

        local gatherOn = false
        local scanConn, hoverConn = nil, nil
        local gathered, list = {}, {}
        local cultistCount = 0
        local itemsChildConn = nil

        local function addGather(m)
            if gathered[m] then return end
            gathered[m] = true
            list[#list+1] = m
            if isCultist(m) then cultistCount = cultistCount + 1 end
        end

        local function removeGather(m)
            if not gathered[m] then return end
            if isCultist(m) then cultistCount = math.max(0, cultistCount - 1) end
            gathered[m] = nil
            for i = #list, 1, -1 do
                if list[i] == m then
                    table.remove(list, i)
                    break
                end
            end
        end

        local function clearAll()
            for m,_ in pairs(gathered) do gathered[m] = nil end
            table.clear(list)
            cultistCount = 0
        end

        local function releaseAll()
            for _,m in ipairs(list) do
                if m and m.Parent then
                    dragStop(m)
                    setNoCollideModel(m, false)
                    setAnchoredModel(m, false)
                    local mp = mainPart(m)
                    if mp then
                        pcall(function() mp:SetNetworkOwner(nil) end)
                        pcall(function() if mp.SetNetworkOwnershipAuto then mp:SetNetworkOwnershipAuto() end end)
                    end
                end
            end
        end

        local function anySelection()
            if wantMossy or wantCultist or wantSapling or wantBlueprint or wantForestGem or wantKey or wantFlashlight or wantTamingFlute then
                return true
            end
            for _,set in pairs(Selected) do
                for _ in pairs(set) do return true end
            end
            return false
        end

        local lastScan   = 0
        local START_YIELD = 0.06

        local overlapParams = OverlapParams.new()
        overlapParams.MaxParts = 1000

        local function refreshOverlapFilter()
            local items = itemsRootOrNil()
            if items then
                overlapParams.FilterType = Enum.RaycastFilterType.Include
                overlapParams.FilterDescendantsInstances = { items }
            else
                overlapParams.FilterType = Enum.RaycastFilterType.Exclude
                overlapParams.FilterDescendantsInstances = { lp.Character }
            end
        end

        refreshOverlapFilter()

        local function pivotModel(m, cf)
            if m:IsA("Model") then
                m:PivotTo(cf)
            else
                local p = mainPart(m)
                if p then p.CFrame = cf end
            end
        end

        local function captureIfNear_FullScan(origin, rad, selectedSet)
            local pool = itemsRootOrNil() or WS
            for _,d in ipairs(pool:GetDescendants()) do
                repeat
                    if not (d:IsA("Model") or d:IsA("BasePart")) then break end
                    local m
                    if d:IsA("Model") then
                        if not nameMatches(selectedSet, d) then break end
                        m = d
                    else
                        m = nearestSelectedModelFromPart(d, selectedSet)
                        if not m then break end
                    end
                    if gathered[m] then break end
                    if isCultist(m) and cultistCount >= CULTIST_LIMIT then break end
                    if not canGather(m, selectedSet, origin, rad) then break end
                    local mp = mainPart(m); if not mp then break end
                    if not dragStart(m) then break end
                    task.wait(START_YIELD)
                    pcall(function() mp:SetNetworkOwner(lp) end)
                    setNoCollideModel(m, true)
                    setAnchoredModel(m, true)
                    addGather(m)
                    dragStop(m)
                until true
            end
        end

        local function captureIfNear()
            local now = os.clock()
            if now - lastScan < scanInterval then return end
            lastScan = now
            if not gatherOn then return end
            if not anySelection() then return end
            local root = hrp(); if not root then return end
            local origin = root.Position
            local rad = gatherRadius()
            local selectedSet = buildSelectedSet()
            refreshOverlapFilter()
            local ok, parts = pcall(function()
                return WS:GetPartBoundsInRadius(origin, rad, overlapParams)
            end)
            if not ok or type(parts) ~= "table" then
                captureIfNear_FullScan(origin, rad, selectedSet)
                return
            end
            for _,p in ipairs(parts) do
                repeat
                    if not p or not p.Parent or not p:IsA("BasePart") then break end
                    local m = nearestSelectedModelFromPart(p, selectedSet)
                    if not m then break end
                    if gathered[m] then break end
                    if isCultist(m) and cultistCount >= CULTIST_LIMIT then break end
                    if not canGather(m, selectedSet, origin, rad) then break end
                    local mp = mainPart(m); if not mp then break end
                    if not dragStart(m) then break end
                    task.wait(START_YIELD)
                    pcall(function() mp:SetNetworkOwner(lp) end)
                    setNoCollideModel(m, true)
                    setAnchoredModel(m, true)
                    addGather(m)
                    dragStop(m)
                until true
            end
        end

        local function onItemsChildAdded(child)
            if not gatherOn then return end
            if not child or not child:IsA("Model") then return end
            local items = itemsRootOrNil()
            if not items or not child:IsDescendantOf(items) then return end
            if not anySelection() then return end
            local root = hrp(); if not root then return end
            local origin = root.Position
            local rad = gatherRadius()
            local selectedSet = buildSelectedSet()
            if gathered[child] then return end
            if isCultist(child) and cultistCount >= CULTIST_LIMIT then return end
            if not canGather(child, selectedSet, origin, rad) then return end
            local mp = mainPart(child); if not mp then return end
            if not dragStart(child) then return end
            task.delay(START_YIELD, function()
                if not gatherOn then dragStop(child); return end
                if not child or not child.Parent then dragStop(child); return end
                local mp2 = mainPart(child); if not mp2 then dragStop(child); return end
                pcall(function() mp2:SetNetworkOwner(lp) end)
                setNoCollideModel(child, true)
                setAnchoredModel(child, true)
                addGather(child)
                dragStop(child)
            end)
        end

        local function hoverFollow()
            if not gatherOn then return end
            local root = hrp(); if not root then return end
            local forward = root.CFrame.LookVector
            local above   = root.Position + Vector3.new(0, hoverHeight, 0)
            local baseCF  = CFrame.lookAt(above, above + forward)
            for _,m in ipairs(list) do
                if m and m.Parent then
                    pivotModel(m, baseCF)
                else
                    removeGather(m)
                end
            end
        end

        local function startGather()
            if gatherOn then return end
            gatherOn = true
            scanConn  = Run.Heartbeat:Connect(captureIfNear)
            hoverConn = Run.RenderStepped:Connect(hoverFollow)
            local items = itemsRootOrNil()
            if items then
                if itemsChildConn then pcall(function() itemsChildConn:Disconnect() end) end
                itemsChildConn = items.ChildAdded:Connect(onItemsChildAdded)
            end
            if _G._PlaceEdgeBtn then _G._PlaceEdgeBtn.Visible = true end
        end

        local function stopGather()
            gatherOn = false
            if scanConn  then pcall(function() scanConn:Disconnect()  end) end; scanConn = nil
            if hoverConn then pcall(function() hoverConn:Disconnect() end) end; hoverConn = nil
            if itemsChildConn then pcall(function() itemsChildConn:Disconnect() end) end; itemsChildConn = nil
        end

        local dropCounter = 0
        local function ringOffset()
            dropCounter += 1
            local i = dropCounter
            local a = i * 2.399963229728653
            local r = math.min(CLUSTER_RADIUS_MIN + CLUSTER_RADIUS_STEP * (i - 1), CLUSTER_RADIUS_MAX)
            return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
        end

        local function baseDropAnchor()
            local root = hrp(); if not root then return nil end
            local forward = root.CFrame.LookVector
            local basePos =
                root.Position
                + Vector3.new(0, DROP_ABOVE_HEAD_STUDS, 0)
                + forward * forwardDrop
            local baseCF = CFrame.lookAt(basePos, basePos + forward)
            return baseCF, forward, basePos
        end

        local function sprinkleCF(baseForward, basePos)
            local off = ringOffset()
            local jitterX = (math.random() - 0.5) * 0.14
            local jitterZ = (math.random() - 0.5) * 0.14
            local waveY = math.sin(dropCounter * AIR_DROP_WAVE_FREQUENCY) * AIR_DROP_WAVE_AMPLITUDE
            local dropPos = basePos + Vector3.new(off.X + jitterX, upDrop + waveY, off.Z + jitterZ)
            return CFrame.lookAt(dropPos, dropPos + baseForward)
        end

        local function finalizeSprinkleDrop(items)
            for _,m in ipairs(items) do
                if m and m.Parent then
                    dragStop(m)
                    setNoCollideModel(m, false)
                    local mp = mainPart(m)
                    if mp then
                        pcall(function() mp:SetNetworkOwner(nil) end)
                        pcall(function() if mp.SetNetworkOwnershipAuto then mp:SetNetworkOwnershipAuto() end end)
                    end
                    for _,p in ipairs(m:GetDescendants()) do
                        if p:IsA("BasePart") then
                            p.AssemblyLinearVelocity  = Vector3.new()
                            p.AssemblyAngularVelocity = Vector3.new()
                        end
                    end
                end
            end

            local n = #items
            local i = 1
            while i <= n do
                for j = i, math.min(i + UNANCHOR_BATCH - 1, n) do
                    local m = items[j]
                    if m and m.Parent then
                        setAnchoredModel(m, false)
                        for _,p in ipairs(m:GetDescendants()) do
                            if p:IsA("BasePart") then
                                p.AssemblyLinearVelocity  = Vector3.new(0, -NUDGE_DOWN, 0)
                                p.AssemblyAngularVelocity = Vector3.new()
                            end
                        end
                    end
                    task.wait(0.006 + ((j % 7) * 0.002))
                end
                task.wait(UNANCHOR_STEP)
                i = i + UNANCHOR_BATCH
            end
        end

        local function immediateDropOne(m)
            if not (m and m.Parent) then return end
            setNoCollideModel(m, false)
            setAnchoredModel(m, false)
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.AssemblyLinearVelocity  = Vector3.new(0, -NUDGE_DOWN, 0)
                    p.AssemblyAngularVelocity = Vector3.new()
                end
            end
        end

        local function placeDown()
            -- USER TWEAKS
            local PLACE_STAGE_ALL_BEFORE_DROP  = false
            local PLACE_PER_ITEM_WAIT_ENABLED  = false
            local PLACE_PER_ITEM_WAIT_SEC      = 0.06

            local baseCF, baseForward, basePos = baseDropAnchor()
            if not baseCF then return end

            if _G._PlaceEdgeBtn then _G._PlaceEdgeBtn.Visible = false end
            stopGather()

            local n = #list
            if n == 0 then return end

            dropCounter = 0
            local placed = 0

            for i = 1, n do
                local m = list[i]
                if m and m.Parent then
                    if dragStart(m) then
                        if PLACE_PER_ITEM_WAIT_ENABLED and (tonumber(PLACE_PER_ITEM_WAIT_SEC) or 0) > 0 then
                            task.wait(tonumber(PLACE_PER_ITEM_WAIT_SEC))
                        end

                        local mp = mainPart(m)
                        if mp then pcall(function() mp:SetNetworkOwner(lp) end) end

                        setAnchoredModel(m, true)
                        setNoCollideModel(m, true)

                        local cf = sprinkleCF(baseForward, basePos)
                        pivotModel(m, cf)

                        dragStop(m)
                        placed += 1

                        if PLACE_STAGE_ALL_BEFORE_DROP then
                            if placed % PLACE_BATCH == 0 then
                                PLACE_YIELD_FN()
                            end
                        else
                            immediateDropOne(m)
                            if placed % PLACE_BATCH == 0 then
                                PLACE_YIELD_FN()
                            end
                        end
                    end
                end
            end

            if PLACE_STAGE_ALL_BEFORE_DROP then
                finalizeSprinkleDrop(list)
            end

            clearAll()
        end

        C.Gather = C.Gather or {}
        C.Gather.IsOn      = function() return gatherOn end
        C.Gather.PlaceDown = placeDown

        tab:Section({ Title = "Gather Settings", Icon = "sliders" })

        tab:Slider({
            Title = "Distance",
            Min = 0,
            Max = 500,
            Default = gatherRadius(),
            Value = { Min = 0, Max = 500, Default = gatherRadius() },
            Callback = function(v)
                local nv = v
                if type(v) == "table" then
                    nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
                end
                nv = tonumber(nv)
                if nv then
                    C.State.GatherRadius = math.clamp(nv, 0, 500)
                end
            end
        })

        tab:Button({
            Title = "Gather Items",
            Callback = function()
                if anySelection() then
                    clearAll()
                    startGather()
                end
            end
        })

        tab:Button({ Title = "Drop Items", Callback = function() placeDown() end })

        local function dropdownMulti(args)
            return tab:Dropdown({
                Title = args.title,
                Values = args.values,
                Multi = true,
                AllowNone = true,
                Callback = function(options)
                    local set = args.set
                    for k,_ in pairs(set) do set[k] = nil end
                    if args.kind == "Misc" then
                        wantMossy, wantCultist, wantSapling = false, false, false
                        wantBlueprint, wantForestGem, wantKey, wantFlashlight, wantTamingFlute = false, false, false, false, false
                        for _,vv in ipairs(options) do
                            if vv == "Mossy Coin" then
                                wantMossy = true
                            elseif vv == "Cultist" then
                                wantCultist = true
                            elseif vv == "Sapling" then
                                wantSapling = true
                            elseif vv == "Blueprint" then
                                wantBlueprint = true
                            elseif vv == "Forest Gem" then
                                wantForestGem = true
                            elseif vv == "Key" then
                                wantKey = true
                            elseif vv == "Flashlight" then
                                wantFlashlight = true
                            elseif vv == "Taming flute" then
                                wantTamingFlute = true
                            else
                                set[vv] = true
                            end
                        end
                    else
                        for _,vv in ipairs(options) do set[vv] = true end
                    end
                end
            })
        end

        tab:Section({ Title = "Junk" })
        dropdownMulti({ title="Select Junk Items", values=junkItems, set=Selected.Junk, kind="Junk" })

        tab:Section({ Title = "Fuel" })
        dropdownMulti({ title="Select Fuel Items", values=fuelItems, set=Selected.Fuel, kind="Fuel" })

        tab:Section({ Title = "Food" })
        dropdownMulti({ title="Select Food Items", values=foodItems, set=Selected.Food, kind="Food" })

        tab:Section({ Title = "Medical" })
        dropdownMulti({ title="Select Medical Items", values=medicalItems, set=Selected.Medical, kind="Medical" })

        tab:Section({ Title = "Weapons & Armor" })
        dropdownMulti({ title="Select Weapon/Armor", values=weaponsArmor, set=Selected.WA, kind="WA" })

        tab:Section({ Title = "Ammo & Misc." })
        dropdownMulti({ title="Select Ammo/Misc", values=ammoMisc, set=Selected.Misc, kind="Misc" })

        tab:Section({ Title = "Pelts" })
        dropdownMulti({ title="Select Pelts", values=pelts, set=Selected.Pelts, kind="Pelts" })

        local function ensurePlaceEdge()
            local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
            local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
            if not edgeGui then
                edgeGui = Instance.new("ScreenGui")
                edgeGui.Name = "EdgeButtons"
                edgeGui.ResetOnSpawn = false
                edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                edgeGui.Parent = playerGui
            end

            local stack = edgeGui:FindFirstChild("EdgeStack")
            if not stack then
                stack = Instance.new("Frame")
                stack.Name = "EdgeStack"
                stack.AnchorPoint = Vector2.new(1, 0)
                stack.Position = UDim2.new(1, -6, 0, 6)
                stack.Size = UDim2.new(0, 130, 1, -12)
                stack.BackgroundTransparency = 1
                stack.BorderSizePixel = 0
                stack.Parent = edgeGui

                local listLay = Instance.new("UIListLayout")
                listLay.Name = "VList"
                listLay.FillDirection = Enum.FillDirection.Vertical
                listLay.SortOrder = Enum.SortOrder.LayoutOrder
                listLay.Padding = UDim.new(0, 6)
                listLay.HorizontalAlignment = Enum.HorizontalAlignment.Right
                listLay.Parent = stack
            end

            local btn = stack:FindFirstChild("PlaceEdge")
            if not btn then
                btn = Instance.new("TextButton")
                btn.Name = "PlaceEdge"
                btn.Size = UDim2.new(1, 0, 0, 30)
                btn.Text = "Place"
                btn.TextSize = 12
                btn.Font = Enum.Font.GothamBold
                btn.BackgroundColor3 = Color3.fromRGB(30,30,35)
                btn.TextColor3  = Color3.new(1,1,1)
                btn.BorderSizePixel = 0
                btn.Visible     = false
                btn.LayoutOrder = 1000
                btn.Parent = stack

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 8)
                corner.Parent = btn
            end

            return btn
        end

        _G._PlaceEdgeBtn = _G._PlaceEdgeBtn or ensurePlaceEdge()

        if _G._PlaceEdgeBtnConn then
            pcall(function() _G._PlaceEdgeBtnConn:Disconnect() end)
        end
        _G._PlaceEdgeBtnConn = _G._PlaceEdgeBtn.MouseButton1Click:Connect(function()
            _G._PlaceEdgeBtn.Visible = false
            placeDown()
        end)

        lp.CharacterAdded:Connect(function()
            if _G._PlaceEdgeBtn then _G._PlaceEdgeBtn.Visible = false end
            releaseAll()
            if gatherOn then
                task.defer(function()
                    stopGather()
                    startGather()
                end)
            end
            refreshOverlapFilter()
        end)
    end

    local ok, err = pcall(run)
    if not ok then
        warn("[Gather] module error: " .. tostring(err))
    end
end
