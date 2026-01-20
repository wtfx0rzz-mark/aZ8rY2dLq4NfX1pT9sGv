-- auto.lua

return function(C, R, UI)
    local function run()
        local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
        local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
        local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
        local PPS      = game:GetService("ProximityPromptService")
        local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
        local Lighting = (C and C.Services and C.Services.Lighting) or game:GetService("Lighting")
        local VIM      = game:GetService("VirtualInputManager")

        local lp = Players.LocalPlayer
        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Auto
        if not tab then return end

        local function hrp()
            local ch = lp.Character or lp.CharacterAdded:Wait()
            return ch and ch:FindFirstChild("HumanoidRootPart")
        end
        local function hum()
            local ch = lp.Character
            return ch and ch:FindFirstChildOfClass("Humanoid")
        end
        local function mainPart(m)
            if not m then return nil end
            if m:IsA("BasePart") then return m end
            if m:IsA("Model") then
                if m.PrimaryPart then return m.PrimaryPart end
                return m:FindFirstChildWhichIsA("BasePart")
            end
            return nil
        end
        local function getRemote(name)
            local f = RS:FindFirstChild("RemoteEvents")
            return f and f:FindFirstChild(name) or nil
        end

        local DUMMY_MODEL = Instance.new("Model")
        DUMMY_MODEL.Name = "__cg_dummy__"

        local function zeroAssembly(root)
            if not root then return end
            root.AssemblyLinearVelocity  = Vector3.new()
            root.AssemblyAngularVelocity = Vector3.new()
        end

        local STICK_DURATION    = 0.35
        local STICK_EXTRA_FR    = 2
        local STICK_CLEAR_VEL   = true
        local TELEPORT_UP_NUDGE = 0.05
        local SAFE_DROP_UP      = 4.0

        local UID_OPEN_KEY = tostring(lp.UserId) .. "Opened"

        local STREAM_TIMEOUT    = 6.0
        local function requestStreamAt(pos, timeout)
            local p = typeof(pos) == "CFrame" and pos.Position or pos
            local ok = pcall(function() WS:RequestStreamAroundAsync(p, timeout or STREAM_TIMEOUT) end)
            return ok
        end
        local function prefetchRing(cf, r)
            local base = typeof(cf)=="CFrame" and cf.Position or cf
            r = r or 80
            local o = {
                Vector3.new( 0,0, 0),
                Vector3.new( r,0, 0), Vector3.new(-r,0, 0),
                Vector3.new( 0,0, r), Vector3.new( 0,0,-r),
                Vector3.new( r,0, r), Vector3.new( r,0,-r),
                Vector3.new(-r,0, r), Vector3.new(-r,0,-r),
            }
            for i=1,#o do requestStreamAt(base + o[i]) end
        end
        local function waitGameplayResumed(timeout)
            local t0 = os.clock()
            while lp and lp.GameplayPaused do
                if os.clock() - t0 > (timeout or STREAM_TIMEOUT) then break end
                Run.Heartbeat:Wait()
            end
        end

        local function snapshotCollide()
            local ch = lp.Character
            if not ch then return {} end
            local t = {}
            for _,d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") then t[d] = d.CanCollide end
            end
            return t
        end
        local function setCollideAll(on, snapshot)
            local ch = lp.Character
            if not ch then return end
            if on and snapshot then
                for part,can in pairs(snapshot) do
                    if part and part.Parent then part.CanCollide = can end
                end
            else
                for _,d in ipairs(ch:GetDescendants()) do
                    if d:IsA("BasePart") then d.CanCollide = false end
                end
            end
        end
        local function isNoclipNow()
            local ch = lp.Character
            if not ch then return false end
            local total, off = 0, 0
            for _,d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") then
                    total += 1
                    if d.CanCollide == false then off += 1 end
                end
            end
            return (total > 0) and ((off / total) >= 0.9) or false
        end

        local rollbackCF = nil
        local rollbackThread = nil
        local ROLLBACK_IDLE_S = 30
        local MIN_MOVE_DIST = 2.0

        local function startRollbackWatch(afterCF)
            if rollbackThread then task.cancel(rollbackThread) end
            rollbackCF = afterCF
            local startRoot = hrp()
            local startPos = startRoot and startRoot.Position or nil
            local startTime = os.clock()
            rollbackThread = task.spawn(function()
                local moved = false
                while os.clock() - startTime < ROLLBACK_IDLE_S do
                    local h = hum()
                    local r = hrp()
                    if r and startPos and (r.Position - startPos).Magnitude >= MIN_MOVE_DIST then
                        moved = true; break
                    end
                    if h and h.MoveDirection.Magnitude > 0.05 then
                        moved = true; break
                    end
                    if not lp or lp.GameplayPaused then
                        moved = true; break
                    end
                    Run.Heartbeat:Wait()
                end
                if (not moved) and rollbackCF then
                    local root = hrp(); if root then
                        local cf = rollbackCF
                        local snap = snapshotCollide()
                        setCollideAll(false)
                        prefetchRing(cf)
                        requestStreamAt(cf)
                        waitGameplayResumed(1.0)
                        pcall(function() (lp.Character or {}).PrimaryPart.CFrame = cf end)
                        pcall(function() root.CFrame = cf end)
                        zeroAssembly(root)
                        setCollideAll(true, snap)
                        waitGameplayResumed(1.0)
                    end
                end
            end)
        end

        local function diveBelowGround(depth, frames)
            local root = hrp(); if not root then return end
            local ch = lp.Character
            local look = root.CFrame.LookVector
            local dest = root.Position + Vector3.new(0, -math.abs(depth), 0)
            for _=1,(frames or 4) do
                local cf = CFrame.new(dest, dest + look)
                if ch then pcall(function() ch:PivotTo(cf) end) end
                pcall(function() root.CFrame = cf end)
                zeroAssembly(root)
                Run.Heartbeat:Wait()
            end
        end

        local function groundBelow(pos)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local ex = { lp.Character }
            local map = WS:FindFirstChild("Map")
            if map then
                local fol = map:FindFirstChild("Foliage")
                if fol then table.insert(ex, fol) end
            end
            local items = WS:FindFirstChild("Items");      if items then table.insert(ex, items) end
            local chars = WS:FindFirstChild("Characters"); if chars then table.insert(ex, chars) end
            params.FilterDescendantsInstances = ex
            local start = pos + Vector3.new(0, 5, 0)
            local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
            if hit then return hit.Position end
            hit = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
            return (hit and hit.Position) or pos
        end

        local function teleportSticky(cf, dropMode)
            local root = hrp(); if not root then return end
            local ch   = lp.Character
            local targetCF = cf + Vector3.new(0, TELEPORT_UP_NUDGE, 0)

            prefetchRing(targetCF)
            requestStreamAt(targetCF)
            waitGameplayResumed(1.0)

            local hadNoclip = isNoclipNow()
            local snap
            if not hadNoclip then
                snap = snapshotCollide()
                setCollideAll(false)
            end

            if ch then pcall(function() ch:PivotTo(targetCF) end) end
            pcall(function() root.CFrame = targetCF end)
            if STICK_CLEAR_VEL then zeroAssembly(root) end

            if dropMode then
                if not hadNoclip then setCollideAll(true, snap) end
                waitGameplayResumed(1.0)
                startRollbackWatch(targetCF)
                return
            end

            local t0 = os.clock()
            while (os.clock() - t0) < STICK_DURATION do
                if ch then pcall(function() ch:PivotTo(targetCF) end) end
                pcall(function() root.CFrame = targetCF end)
                if STICK_CLEAR_VEL then zeroAssembly(root) end
                Run.Heartbeat:Wait()
            end
            for _=1,STICK_EXTRA_FR do
                if ch then pcall(function() ch:PivotTo(targetCF) end) end
                pcall(function() root.CFrame = targetCF end)
                if STICK_CLEAR_VEL then zeroAssembly(root) end
                Run.Heartbeat:Wait()
            end

            if not hadNoclip then
                setCollideAll(true, snap)
            end
            if STICK_CLEAR_VEL then zeroAssembly(root) end
            waitGameplayResumed(1.0)
            startRollbackWatch(targetCF)
        end

        local function waitUntilGroundedOrMoving(timeout)
            local h = hum()
            local t0 = os.clock()
            local groundedFrames = 0
            while os.clock() - t0 < (timeout or 3) do
                if h then
                    local grounded = (h.FloorMaterial ~= Enum.Material.Air)
                    if grounded then groundedFrames += 1 else groundedFrames = 0 end
                    if groundedFrames >= 5 then
                        local t1 = os.clock()
                        while os.clock() - t1 < 0.35 do
                            if h.MoveDirection.Magnitude > 0.05 then return true end
                            Run.Heartbeat:Wait()
                        end
                        return true
                    end
                end
                Run.Heartbeat:Wait()
            end
            return false
        end

        local DIVE_DEPTH = 200
        local function teleportWithDive(targetCF)
            local upCF = targetCF + Vector3.new(0, SAFE_DROP_UP, 0)
            prefetchRing(upCF)
            requestStreamAt(upCF)
            waitGameplayResumed(1.0)
            local root = hrp(); if not root then return end
            local snap = snapshotCollide()
            setCollideAll(false)
            diveBelowGround(DIVE_DEPTH, 4)
            teleportSticky(upCF, true)
            waitUntilGroundedOrMoving(3)
            setCollideAll(true, snap)
            waitGameplayResumed(1.0)
        end

        local function fireCenterPart(fire)
            return fire:FindFirstChild("Center")
                or fire:FindFirstChild("InnerTouchZone")
                or mainPart(fire)
                or fire.PrimaryPart
        end
        local function resolveCampfireModel()
            local map = WS:FindFirstChild("Map")
            local cg  = map and map:FindFirstChild("Campground")
            local mf  = cg and cg:FindFirstChild("MainFire")
            if mf then return mf end
            for _,d in ipairs(WS:GetDescendants()) do
                if d:IsA("Model") then
                    local n = (d.Name or ""):lower()
                    if n == "mainfire" or n == "campfire" or n == "camp fire" then
                        return d
                    end
                end
            end
            return nil
        end

        local CAMPFIRE_GROUND_PAD_Y        = 4.25
        local CAMPFIRE_MIN_ABOVE_CENTER_Y  = 1.00
        local CAMPFIRE_RAY_START_ABOVE_Y   = 250
        local CAMPFIRE_RAY_DEPTH_Y         = 1600

        local function groundBelowCampfire(pos, extraExcludes)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.IgnoreWater = true

            local ex = { lp.Character }
            local map = WS:FindFirstChild("Map")
            if map then
                local fol = map:FindFirstChild("Foliage")
                if fol then table.insert(ex, fol) end
            end
            local items = WS:FindFirstChild("Items");      if items then table.insert(ex, items) end
            local chars = WS:FindFirstChild("Characters"); if chars then table.insert(ex, chars) end

            if typeof(extraExcludes) == "table" then
                for i = 1, #extraExcludes do
                    local inst = extraExcludes[i]
                    if inst then table.insert(ex, inst) end
                end
            end

            params.FilterDescendantsInstances = ex

            local start = Vector3.new(pos.X, pos.Y + CAMPFIRE_RAY_START_ABOVE_Y, pos.Z)
            local hit = WS:Raycast(start, Vector3.new(0, -CAMPFIRE_RAY_DEPTH_Y, 0), params)
            if hit then return hit.Position end

            start = Vector3.new(pos.X, pos.Y + (CAMPFIRE_RAY_START_ABOVE_Y * 2), pos.Z)
            hit = WS:Raycast(start, Vector3.new(0, -CAMPFIRE_RAY_DEPTH_Y, 0), params)
            return (hit and hit.Position) or pos
        end

        local function campfireTeleportCF()
            local fire = resolveCampfireModel(); if not fire then return nil end
            local center = fireCenterPart(fire); if not center then return fire:GetPivot() end

            local look   = center.CFrame.LookVector
            local zone   = fire:FindFirstChild("InnerTouchZone")

            local offset = 6
            if zone and zone:IsA("BasePart") then
                offset = math.max(zone.Size.X, zone.Size.Z) * 0.5 + 4
            end

            local desiredXZ = center.Position + look * offset
            local g = groundBelowCampfire(desiredXZ, { fire })

            local minY = math.max(g.Y + CAMPFIRE_GROUND_PAD_Y, center.Position.Y + CAMPFIRE_MIN_ABOVE_CENTER_Y)
            local finalPos = Vector3.new(desiredXZ.X, minY, desiredXZ.Z)

            return CFrame.new(finalPos, center.Position)
        end

        local playerGui = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")
        local edgeGui   = playerGui:FindFirstChild("EdgeButtons")
        if not edgeGui then
            edgeGui = Instance.new("ScreenGui")
            edgeGui.Name = "EdgeButtons"
            edgeGui.ResetOnSpawn = false
            pcall(function() edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
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
            local list = Instance.new("UIListLayout")
            list.Name = "VList"
            list.FillDirection = Enum.FillDirection.Vertical
            list.SortOrder = Enum.SortOrder.LayoutOrder
            list.Padding = UDim.new(0, 6)
            list.HorizontalAlignment = Enum.HorizontalAlignment.Right
            list.Parent = stack
        end
        local function makeEdgeBtn(name, label, order)
            local b = stack:FindFirstChild(name)
            if not b then
                b = Instance.new("TextButton")
                b.Name = name
                b.Size = UDim2.new(1, 0, 0, 30)
                b.Text = label
                b.TextSize = 12
                b.Font = Enum.Font.GothamBold
                b.BackgroundColor3 = Color3.fromRGB(30,30,35)
                b.TextColor3 = Color3.new(1,1,1)
                b.BorderSizePixel = 0
                b.Visible = false
                b.LayoutOrder = order or 1
                b.Parent = stack
                local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = b
            else
                b.Text = label
                b.LayoutOrder = order or b.LayoutOrder
                b.Visible = false
            end
            return b
        end

        local PHASE_DIST = 10
        local phaseBtn = makeEdgeBtn("Phase10Edge", "Phase 10", 1)
        local tpBtn    = makeEdgeBtn("TpEdge",      "Teleport", 2)
        local plantBtn = makeEdgeBtn("PlantEdge",   "Plant",    3)
        local lostBtn  = makeEdgeBtn("LostEdge",    "Lost Child", 4)
        local campBtn  = makeEdgeBtn("CampEdge",    "Campfire", 5)

        local skipNightBtn = makeEdgeBtn("SkipNightEdge", "Skip Night", 6)

        local showPhaseEdge, showPlantEdge = false, false
        local showTeleportEdge, showCampEdge = false, true
        local showSkipNightEdge = false

        phaseBtn.Visible = showPhaseEdge
        plantBtn.Visible = showPlantEdge
        tpBtn.Visible    = showTeleportEdge
        campBtn.Visible  = showCampEdge
        lostBtn.Visible  = false
        skipNightBtn.Visible = showSkipNightEdge

        phaseBtn.MouseButton1Click:Connect(function()
            local root = hrp(); if not root then return end
            local dest = root.Position + root.CFrame.LookVector * PHASE_DIST
            teleportSticky(CFrame.new(dest, dest + root.CFrame.LookVector))
        end)

        local markedCF, HOLD_THRESHOLD, downAt, suppressClick = nil, 0.2, 0, false
        tpBtn.MouseButton1Down:Connect(function() downAt = os.clock(); suppressClick = false end)
        tpBtn.MouseButton1Up:Connect(function()
            local held = os.clock() - (downAt or 0)
            if held >= HOLD_THRESHOLD then
                local root = hrp()
                if root then
                    markedCF = root.CFrame
                    suppressClick = true
                    local old = tpBtn.Text; tpBtn.Text = "Marked"; task.delay(0.5, function() if tpBtn then tpBtn.Text = old end end)
                end
            end
        end)
        tpBtn.MouseButton1Click:Connect(function()
            if suppressClick then suppressClick = false return end
            if not markedCF then return end
            teleportWithDive(markedCF)
        end)

        campBtn.MouseButton1Click:Connect(function()
            local cf = campfireTeleportCF()
            if cf then teleportWithDive(cf) end
        end)

        -- === Skip Night: single press (unchanged UI, but safer behavior under the hood) ===

        local function teleportToAccelerometer()
            local structures = WS:FindFirstChild("Structures")
            if not structures then return nil end
            local machine = structures:FindFirstChild("Temporal Accelerometer")
            if not (machine and machine:IsA("Model")) then return nil end
            local mp = mainPart(machine)
            if not mp then return machine end
            local g = groundBelow(mp.Position)
            local stand = Vector3.new(mp.Position.X, g.Y + 3.0, mp.Position.Z)
            teleportWithDive(CFrame.new(stand, mp.Position))
            return machine
        end

        local function doSkipNightOnce()
            local root = hrp()
            local savedCF = root and root.CFrame or nil
            if not savedCF then return end

            local machine = teleportToAccelerometer()
            if not machine then
                teleportWithDive(savedCF)
                return
            end

            -- Let streaming/physics settle so the server sees our new position before we fire
            for _ = 1, 4 do Run.Heartbeat:Wait() end
            task.wait(0.12)

            local ev = getRemote("RequestActivateNightSkipMachine")
            if (ev and ev:IsA("RemoteEvent")) then
                pcall(function() ev:FireServer(machine) end)
            end

            -- Give the server a brief moment to process activation before we leave
            task.wait(0.20)

            teleportWithDive(savedCF)
        end

        skipNightBtn.MouseButton1Click:Connect(function()
            pcall(doSkipNightOnce)
        end)

        local AHEAD_DIST, RAY_DEPTH = 3, 2000
        local function groundAhead(root)
            if not root then return nil end
            local ch   = lp.Character
            local head = ch and ch:FindFirstChild("Head")
            if not head then return root.Position end
            local castFrom = head.Position + root.CFrame.LookVector * AHEAD_DIST
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local itemsFolder = WS:FindFirstChild("Items")
            if itemsFolder then
                params.FilterDescendantsInstances = { lp.Character, itemsFolder }
            else
                params.FilterDescendantsInstances = { lp.Character }
            end
            local hit = WS:Raycast(castFrom, Vector3.new(0, -RAY_DEPTH, 0), params)
            return hit and hit.Position or (castFrom - Vector3.new(0, 3, 0))
        end
        local function findClosestSapling()
            local items = WS:FindFirstChild("Items")
            local root  = hrp()
            if not (items and root) then return nil end
            local closest, bestDist = nil, math.huge
            for _,m in ipairs(items:GetChildren()) do
                if m:IsA("Model") and m.Name == "Sapling" then
                    local mp = mainPart(m)
                    if mp then
                        local d = (mp.Position - root.Position).Magnitude
                        if d < bestDist then bestDist, closest = d, m end
                    end
                end
            end
            return closest
        end
        local function plantNearestSaplingInFront()
            local sapling = findClosestSapling(); if not sapling then return end
            local startDrag = getRemote("RequestStartDraggingItem")
            local stopDrag  = getRemote("StopDraggingItem")
            local plantRF   = getRemote("RequestPlantItem"); if not plantRF then return end
            local root = hrp(); if not root then return end
            local plantPos = groundAhead(root)
            if startDrag then pcall(function() startDrag:FireServer(sapling) end); pcall(function() startDrag:FireServer(DUMMY_MODEL) end) end
            task.wait(0.05)
            local ok = pcall(function() return plantRF:InvokeServer(sapling, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end)
            if not ok then ok = pcall(function() return plantRF:InvokeServer(DUMMY_MODEL, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end) end
            if not ok then pcall(function() plantRF:FireServer(sapling, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end); pcall(function() plantRF:FireServer(DUMMY_MODEL, Vector3.new(plantPos.X, plantPos.Y, plantPos.Z)) end) end
            task.wait(0.05)
            if stopDrag then pcall(function() stopDrag:FireServer(sapling) end); pcall(function() stopDrag:FireServer(DUMMY_MODEL) end) end
        end
        plantBtn.MouseButton1Click:Connect(function() plantNearestSaplingInFront() end)

        tab:Toggle({
            Title = "Edge Button: Phase 10",
            Value = false,
            Callback = function(state)
                showPhaseEdge = state
                if phaseBtn then phaseBtn.Visible = state end
            end
        })
        tab:Toggle({
            Title = "Edge Button: Plant Sapling",
            Value = false,
            Callback = function(state)
                showPlantEdge = state
                if plantBtn then plantBtn.Visible = state end
            end
        })
        tab:Toggle({
            Title = "Edge Button: Teleport",
            Value = false,
            Callback = function(state)
                showTeleportEdge = state
                if tpBtn then tpBtn.Visible = state end
            end
        })
        tab:Toggle({
            Title = "Edge Button: Campfire",
            Value = true,
            Callback = function(state)
                showCampEdge = state
                if campBtn then campBtn.Visible = state end
            end
        })
        tab:Toggle({
            Title = "Edge Button: Skip Night",
            Value = false,
            Callback = function(state)
                showSkipNightEdge = state
                if skipNightBtn then skipNightBtn.Visible = state end
            end
        })

        -- === Skip Nights With Timer (patched to use the same safe skip behavior) ===

        local skipNightTimerOn = false
        local skipNightTimerThread = nil
        local SKIP_NIGHT_TIMER_SECONDS = 180

        local function enableSkipNightTimer()
            if skipNightTimerOn then return end
            skipNightTimerOn = true

            if skipNightTimerThread then
                pcall(function() task.cancel(skipNightTimerThread) end)
                skipNightTimerThread = nil
            end

            skipNightTimerThread = task.spawn(function()
                while skipNightTimerOn do
                    pcall(doSkipNightOnce)
                    local t0 = os.clock()
                    while skipNightTimerOn and (os.clock() - t0) < SKIP_NIGHT_TIMER_SECONDS do
                        task.wait(0.25)
                    end
                end
            end)
        end

        local function disableSkipNightTimer()
            skipNightTimerOn = false
            if skipNightTimerThread then
                pcall(function() task.cancel(skipNightTimerThread) end)
                skipNightTimerThread = nil
            end
        end

        tab:Toggle({
            Title = "Skip Nights With Timer",
            Value = false,
            Callback = function(state)
                if state then
                    enableSkipNightTimer()
                else
                    disableSkipNightTimer()
                end
            end
        })

        local MAX_TO_SAVE, savedCount = 4, 0
        local autoLostEnabled = false
        local lostEligible  = setmetatable({}, {__mode="k"})
        local visitedLost   = setmetatable({}, {__mode="k"})
        local lostModelConns = setmetatable({}, {__mode="k"})
        local lostDescAddConn = nil
        local lostBtnConn = nil

        local function isLostChildModel(m) return m and m:IsA("Model") and m.Name:match("^Lost Child") end
        local function refreshLostBtn()
            if not autoLostEnabled then
                lostBtn.Visible = false
                return
            end
            local anyEligible = next(lostEligible) ~= nil
            lostBtn.Visible = (savedCount < MAX_TO_SAVE) and anyEligible
        end
        local function onLostAttrChange(m)
            if not autoLostEnabled then return end
            local v = m:GetAttribute("Lost") == true
            local was = lostEligible[m] == true
            if v then
                lostEligible[m] = true
                visitedLost[m] = nil
            else
                if was and savedCount < MAX_TO_SAVE then savedCount += 1 end
                lostEligible[m] = nil
                visitedLost[m] = nil
            end
            refreshLostBtn()
        end
        local function untrackLostModel(m)
            local t = lostModelConns[m]
            if t then
                for i=1,#t do
                    local c = t[i]
                    if c and c.Disconnect then pcall(function() c:Disconnect() end) end
                end
            end
            lostModelConns[m] = nil
            lostEligible[m] = nil
            visitedLost[m] = nil
        end
        local function trackLostModel(m)
            if not autoLostEnabled then return end
            if not isLostChildModel(m) then return end
            if lostModelConns[m] then
                onLostAttrChange(m)
                return
            end
            onLostAttrChange(m)
            local conns = {}
            conns[#conns+1] = m:GetAttributeChangedSignal("Lost"):Connect(function()
                if autoLostEnabled then onLostAttrChange(m) end
            end)
            conns[#conns+1] = m.AncestryChanged:Connect(function(_, parent)
                if not parent then
                    untrackLostModel(m)
                    refreshLostBtn()
                end
            end)
            lostModelConns[m] = conns
        end
        local function findUnvisitedLost()
            local root = hrp(); if not root then return nil end
            local best, bestD = nil, math.huge
            for m,_ in pairs(lostEligible) do
                if not visitedLost[m] then
                    local mp = mainPart(m)
                    if mp then
                        local dist = (mp.Position - root.Position).Magnitude
                        if dist < bestD then bestD, best = dist, m end
                    end
                end
            end
            return best
        end
        local function findNearestEligibleLost()
            local root = hrp(); if not root then return nil end
            local best, bestD = nil, math.huge
            for m,_ in pairs(lostEligible) do
                local mp = mainPart(m)
                if mp then
                    local dist = (mp.Position - root.Position).Magnitude
                    if dist < bestD then bestD, best = dist, m end
                end
            end
            return best
        end
        local function teleportToNearestLost()
            if not autoLostEnabled then return end
            if savedCount >= MAX_TO_SAVE then return end
            local target = findUnvisitedLost()
            if not target then target = findNearestEligibleLost() end
            if not target then return end
            local mp = mainPart(target)
            if mp then
                visitedLost[target] = mp.Position
                teleportWithDive(CFrame.new(mp.Position + Vector3.new(0, 3, 0), mp.Position))
            end
        end
        local function enableLostChild()
            if autoLostEnabled then return end
            autoLostEnabled = true
            savedCount = 0
            table.clear(lostEligible)
            table.clear(visitedLost)
            for m,_ in pairs(lostModelConns) do untrackLostModel(m) end
            for _,d in ipairs(WS:GetDescendants()) do trackLostModel(d) end
            if lostDescAddConn then lostDescAddConn:Disconnect() lostDescAddConn = nil end
            lostDescAddConn = WS.DescendantAdded:Connect(function(d) trackLostModel(d) end)
            if lostBtnConn then lostBtnConn:Disconnect() lostBtnConn = nil end
            lostBtnConn = lostBtn.MouseButton1Click:Connect(function() teleportToNearestLost() end)
            refreshLostBtn()
        end
        local function disableLostChild()
            if not autoLostEnabled then
                lostBtn.Visible = false
                return
            end
            autoLostEnabled = false
            if lostDescAddConn then lostDescAddConn:Disconnect() lostDescAddConn = nil end
            if lostBtnConn then lostBtnConn:Disconnect() lostBtnConn = nil end
            for m,_ in pairs(lostModelConns) do untrackLostModel(m) end
            table.clear(lostEligible)
            table.clear(visitedLost)
            lostBtn.Visible = false
        end
        tab:Toggle({
            Title = "Teleport to Missing Kids",
            Value = true,
            Callback = function(state)
                if state then enableLostChild() else disableLostChild() end
            end
        })
        task.defer(enableLostChild)

        local godOn = false
        local godHB = nil
        local godLastHealth = nil
        local godRecentUntil = 0
        local godHealthConn = nil
        local godCharConn = nil
        local GOD_POST_DAMAGE_WINDOW = 8.0
        local GOD_POST_DAMAGE_INTERVAL = 1.5
        local GOD_IDLE_INTERVAL = 15.0

        local function fireGod()
            local f = RS:FindFirstChild("RemoteEvents")
            local ev = f and f:FindFirstChild("DamagePlayer")
            if ev and ev:IsA("RemoteEvent") then
                pcall(function() ev:FireServer(-math.huge) end)
            end
        end

        local function bindGodToHumanoid()
            if godHealthConn then godHealthConn:Disconnect(); godHealthConn = nil end
            local h = hum()
            if not h then return end
            godLastHealth = h.Health
            godHealthConn = h.HealthChanged:Connect(function(newHealth)
                if not godOn then return end
                if typeof(newHealth) ~= "number" then return end
                local last = godLastHealth
                godLastHealth = newHealth
                if last ~= nil and newHealth < last then
                    godRecentUntil = os.clock() + GOD_POST_DAMAGE_WINDOW
                    fireGod()
                    task.defer(fireGod)
                end
            end)
        end

        local function enableGod()
            if godOn then return end
            godOn = true
            bindGodToHumanoid()
            if godCharConn then godCharConn:Disconnect(); godCharConn = nil end
            godCharConn = lp.CharacterAdded:Connect(function()
                task.wait(0.15)
                if godOn then bindGodToHumanoid() end
            end)
            if godHB then godHB:Disconnect() end
            local acc = 0
            godHB = Run.Heartbeat:Connect(function(dt)
                if not godOn then return end
                acc += dt
                local now = os.clock()
                local interval = (now <= godRecentUntil) and GOD_POST_DAMAGE_INTERVAL or GOD_IDLE_INTERVAL
                if acc >= interval then
                    acc = 0
                    fireGod()
                end
            end)
        end
        local function disableGod()
            godOn = false
            if godHB then godHB:Disconnect() godHB = nil end
            if godHealthConn then godHealthConn:Disconnect() godHealthConn = nil end
            if godCharConn then godCharConn:Disconnect() godCharConn = nil end
            godLastHealth = nil
            godRecentUntil = 0
        end
        tab:Toggle({
            Title = "Godmode",
            Value = true,
            Callback = function(state)
                if state then enableGod() else disableGod() end
            end
        })
        task.defer(enableGod)

        local INSTANT_HOLD, TRIGGER_COOLDOWN = 0.2, 0.2
        local EXCLUDE_NAME_SUBSTR = { "door", "closet", "gate", "hatch" }
        local EXCLUDE_ANCESTOR_SUBSTR = { "closetdoors", "closet", "door", "landmarks" }
        local function strfindAny(s, list)
            s = string.lower(s or "")
            for _, w in ipairs(list) do if string.find(s, w, 1, true) then return true end end
            return false
        end
        local function shouldSkipPrompt(p)
            if not p or not p.Parent then return true end
            if strfindAny(p.Name, EXCLUDE_NAME_SUBSTR) then return true end
            pcall(function()
                if strfindAny(p.ObjectText, EXCLUDE_NAME_SUBSTR) then error(true) end
                if strfindAny(p.ActionText, EXCLUDE_NAME_SUBSTR) then error(true) end
            end)
            local a = p.Parent
            while a and a ~= workspace do
                if strfindAny(a.Name, EXCLUDE_ANCESTOR_SUBSTR) then return true end
                a = a.Parent
            end
            return false
        end
        local promptDurations = setmetatable({}, { __mode = "k" })
        local shownConn, trigConn, hiddenConn
        local function restorePrompt(prompt)
            local orig = promptDurations[prompt]
            if orig ~= nil and prompt and prompt.Parent then pcall(function() prompt.HoldDuration = orig end) end
            promptDurations[prompt] = nil
        end
        local function tagChestFromPrompt(prompt)
            if not prompt then return end
            local node = prompt
            for _ = 1, 8 do
                if not node then break end
                if node:IsA("Model") then
                    local n = node.Name
                    if type(n) == "string" and (n:match("Chest%d*$") or n:match("Chest$")) then
                        pcall(function()
                            node:SetAttribute(UID_OPEN_KEY, true)
                        end)
                        break
                    end
                end
                node = node.Parent
            end
        end
        local function onPromptShown(prompt)
            if not prompt or not prompt:IsA("ProximityPrompt") then return end
            if shouldSkipPrompt(prompt) then return end
            if promptDurations[prompt] == nil then promptDurations[prompt] = prompt.HoldDuration end
            if prompt and prompt.Parent and not shouldSkipPrompt(prompt) then pcall(function() prompt.HoldDuration = INSTANT_HOLD end) end
        end
        local function enableInstantInteract()
            if shownConn then return end
            shownConn  = PPS.PromptShown:Connect(onPromptShown)
            trigConn   = PPS.PromptTriggered:Connect(function(prompt, player)
                if player ~= lp or shouldSkipPrompt(prompt) then return end
                tagChestFromPrompt(prompt)
                if TRIGGER_COOLDOWN and TRIGGER_COOLDOWN > 0 then
                    pcall(function() prompt.Enabled = false end)
                    task.delay(TRIGGER_COOLDOWN, function() if prompt and prompt.Parent then pcall(function() prompt.Enabled = true end) end end)
                end
                restorePrompt(prompt)
            end)
            hiddenConn = PPS.PromptHidden:Connect(function(prompt) if shouldSkipPrompt(prompt) then return end; restorePrompt(prompt) end)
        end
        local function disableInstantInteract()
            if shownConn  then shownConn:Disconnect();  shownConn  = nil end
            if trigConn   then trigConn:Disconnect();   trigConn   = nil end
            if hiddenConn then hiddenConn:Disconnect(); hiddenConn = nil end
            for p,_ in pairs(promptDurations) do restorePrompt(p) end
        end
        enableInstantInteract()
        tab:Toggle({ Title = "Instant Interact", Value = true, Callback = function(state) if state then enableInstantInteract() else disableInstantInteract() end end })

        -- ... rest of your file unchanged ...

        Players.LocalPlayer.CharacterAdded:Connect(function()
            local playerGui2 = lp:WaitForChild("PlayerGui")
            local edgeGui2 = playerGui2:FindFirstChild("EdgeButtons")
            if edgeGui2 and edgeGui2.Parent ~= playerGui2 then edgeGui2.Parent = playerGui2 end
            if phaseBtn then phaseBtn.Visible = showPhaseEdge end
            if plantBtn then plantBtn.Visible = showPlantEdge end
            if tpBtn    then tpBtn.Visible    = showTeleportEdge end
            if campBtn  then campBtn.Visible  = showCampEdge end
            lostBtn.Visible = false
            if skipNightBtn then skipNightBtn.Visible = showSkipNightEdge end
            if noShadowsOn and not lightConn then enableNoShadows() end
            if loadDefenseOnDefault then enableLoadDefenseSafe() end
            pcall(function() WS.StreamingPauseMode = Enum.StreamingPauseMode.Disabled end)
            if coinOn and not coinConn then enableCoin() end
            if chestFinderOn and enableChestFinder then enableChestFinder() end
            if godOn then
                task.wait(0.15)
                bindGodToHumanoid()
            end
            if autoLostEnabled then
                task.wait(0.15)
                for _,d in ipairs(WS:GetDescendants()) do trackLostModel(d) end
                refreshLostBtn()
            end
        end)
    end
    local ok, err = pcall(run)
    if not ok then warn("[Auto] module error: " .. tostring(err)) end
end
