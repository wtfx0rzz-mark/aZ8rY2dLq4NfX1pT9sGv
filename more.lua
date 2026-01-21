-- more.lua

return function(C, R, UI)
    local function run()
        C  = C  or _G.C
        UI = UI or _G.UI

        local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
        local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
        local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
        local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")

        local lp = Players.LocalPlayer
        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.More
        if not tab then return end

        C.State = C.State or { Toggles = {} }
        C.State.Toggles = C.State.Toggles or {}

        if _G.__MoreTemporal and type(_G.__MoreTemporal.Destroy) == "function" then
            pcall(function() _G.__MoreTemporal.Destroy() end)
        end

        local function chr()
            return lp.Character or lp.CharacterAdded:Wait()
        end

        local function hrp()
            local ch = chr()
            return ch and ch:WaitForChild("HumanoidRootPart")
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

        local STREAM_TIMEOUT = 6.0
        local function requestStreamAt(pos, timeout)
            local p = typeof(pos) == "CFrame" and pos.Position or pos
            local ok = pcall(function() WS:RequestStreamAroundAsync(p, timeout or STREAM_TIMEOUT) end)
            return ok
        end

        local function prefetchRing(cf, r)
            local base = typeof(cf) == "CFrame" and cf.Position or cf
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

        local STICK_DURATION    = 0.35
        local STICK_EXTRA_FR    = 2
        local STICK_CLEAR_VEL   = true
        local TELEPORT_UP_NUDGE = 0.05
        local SAFE_DROP_UP      = 4.0

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

        local function teleportWithDive(targetCF)
            if not targetCF then return end
            local upCF = targetCF + Vector3.new(0, SAFE_DROP_UP, 0)
            prefetchRing(upCF)
            requestStreamAt(upCF)
            waitGameplayResumed(1.0)
            teleportSticky(upCF, true)
            waitUntilGroundedOrMoving(3)
            waitGameplayResumed(1.0)
        end

        local function structureFolder()
            return WS:FindFirstChild("Structures")
        end

        local function modelPos(m)
            if not m then return nil end
            if m.PrimaryPart then return m.PrimaryPart.Position end
            local ok, cf = pcall(function() return m:GetPivot() end)
            if ok and cf then return cf.Position end
            local bp = m:FindFirstChildWhichIsA("BasePart", true)
            return bp and bp.Position or nil
        end

        local function nearestStructure()
            local root = hrp()
            local folder = structureFolder()
            if not (root and folder) then return nil, nil end
            local best, bestD = nil, math.huge
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and m.Parent then
                    local p = modelPos(m)
                    if p then
                        local d = (p - root.Position).Magnitude
                        if d < bestD then bestD, best = d, m end
                    end
                end
            end
            return best, bestD
        end

        local function resolveAccelModel()
            local folder = structureFolder()
            if not folder then return nil end
            local m = folder:FindFirstChild("Temporal Accelerometer") or folder:FindFirstChild("TemporalAccelerometer")
            if m and m:IsA("Model") then return m end
            for _, ch in ipairs(folder:GetChildren()) do
                if ch:IsA("Model") then
                    local n = ch.Name:lower()
                    if n:find("temporal", 1, true) and n:find("acceler", 1, true) then
                        return ch
                    end
                end
            end
            return nil
        end

        local function nightSkipTeleportCF(machine)
            if not machine then return nil end
            local mp = mainPart(machine) or machine.PrimaryPart
            if not mp then
                local ok, cf = pcall(function() return machine:GetPivot() end)
                return ok and cf or nil
            end
            local look = mp.CFrame.LookVector
            local desired = mp.Position - look * 8
            local g = groundBelow(desired)
            local standPos = Vector3.new(desired.X, g.Y + 3.0, desired.Z)
            return CFrame.new(standPos, mp.Position)
        end

        local function inv()
            return lp:FindFirstChild("Inventory")
        end

        local function findAccelBlueprintInstance()
            local f = inv()
            if not f then return nil end
            for _, ch in ipairs(f:GetChildren()) do
                if ch:IsA("Model") then
                    local n = ch.Name
                    if type(n) == "string" then
                        local ln = n:lower()
                        if ln:sub(-9) == "blueprint" and ln:find("temporal", 1, true) and ln:find("acceler", 1, true) then
                            return ch
                        end
                    end
                end
            end
            return nil
        end

        local function waitForAccelBlueprint(timeout)
            local t0 = os.clock()
            while os.clock() - t0 < (timeout or 8) do
                local bp = findAccelBlueprintInstance()
                if bp and bp.Parent then return bp end
                task.wait(0.15)
            end
            return nil
        end

        local function waitForAccelModel(timeout)
            local t0 = os.clock()
            while os.clock() - t0 < (timeout or 8) do
                local m = resolveAccelModel()
                if m and m.Parent then return m end
                task.wait(0.15)
            end
            return nil
        end

        local cam = WS.CurrentCamera
        WS:GetPropertyChangedSignal("CurrentCamera"):Connect(function() cam = WS.CurrentCamera end)

        local function yawOnly(pos, lookVec)
            local lv = Vector3.new(lookVec.X, 0, lookVec.Z)
            if lv.Magnitude < 1e-6 then
                lv = Vector3.new(0, 0, -1)
            else
                lv = lv.Unit
            end
            return CFrame.lookAt(pos, pos + lv, Vector3.new(0, 1, 0))
        end

        local function groundYAtSnap(xz, fallbackY, excludeModel)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local ex = { chr(), cam }
            if excludeModel then table.insert(ex, excludeModel) end
            params.FilterDescendantsInstances = ex
            params.IgnoreWater = false
            local origin = xz + Vector3.new(0, 200, 0)
            local dir = Vector3.new(0, -1200, 0)
            local hit = WS:Raycast(origin, dir, params)
            local y = hit and hit.Position.Y or (fallbackY or xz.Y)
            if fallbackY and math.abs(y - fallbackY) > 35 then
                y = fallbackY
            end
            return y
        end

        local function placementFromExistingModel(model)
            local ok, cf0 = pcall(function() return model:GetPivot() end)
            if not ok or not cf0 then return nil, nil, nil end
            local fallbackY = hrp() and hrp().Position.Y or cf0.Position.Y
            local gy = groundYAtSnap(Vector3.new(cf0.Position.X, cf0.Position.Y, cf0.Position.Z), fallbackY, model)
            local pos = Vector3.new(cf0.Position.X, gy, cf0.Position.Z)
            local yOff = (cf0.Position.Y - gy)
            local fwd = cf0.LookVector
            local cf = yawOnly(Vector3.new(pos.X, pos.Y + yOff, pos.Z), fwd)
            local placement = { Valid = true, Position = pos, CFrame = cf }
            local rot = (cf - cf.Position)
            return placement, rot, true
        end

        local function findPickUpRemote()
            local re = RS:FindFirstChild("RemoteEvents")
            if re then
                local r = re:FindFirstChild("RequestPickUpStructure")
                if r then return r end
            end
            local rf = RS:FindFirstChild("RemoteFunctions")
            if rf then
                local r = rf:FindFirstChild("RequestPickUpStructure")
                if r then return r end
            end
            return RS:FindFirstChild("RequestPickUpStructure", true)
        end

        local function doPickupNearest()
            local target = nil
            local nearest, _ = nearestStructure()
            if nearest then target = nearest end
            local remote = findPickUpRemote()
            if not (remote and target) then return false end
            local ok = pcall(function()
                if remote:IsA("RemoteFunction") then
                    remote:InvokeServer(target)
                elseif remote:IsA("RemoteEvent") then
                    remote:FireServer(target)
                end
            end)
            return ok
        end

        local function placeAccelAtSnap(placeRemote, bp, placement, rot)
            if not (placeRemote and bp and placement and rot) then return false end
            local ok1, r1 = pcall(function()
                return placeRemote:InvokeServer(bp, placement, rot, nil)
            end)
            if ok1 and r1 ~= nil then return true end
            local ok2 = pcall(function()
                placeRemote:InvokeServer(bp, placement, rot, true)
            end)
            return ok2
        end

        local function fireAccelRemote(model)
            local r = getRemote("RequestActivateNightSkipMachine")
            if not (r and model) then return false end
            local ok = pcall(function()
                if r:IsA("RemoteEvent") then
                    r:FireServer(model)
                elseif r:IsA("RemoteFunction") then
                    r:InvokeServer(model)
                end
            end)
            return ok
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
            stack.Size = UDim2.new(0, 150, 1, -12)
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
                b.LayoutOrder = order or 50
                b.Parent = stack
                local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = b
            else
                b.Text = label
                b.LayoutOrder = order or b.LayoutOrder
                b.Visible = false
            end
            return b
        end

        local edgeBtn = makeEdgeBtn("TemporalAccelEdge", "Temporal Cycle", 40)

        local busy = false
        local function runTemporalSequence()
            if busy then return end
            busy = true

            local root0 = hrp()
            local returnCF = root0 and root0.CFrame or nil

            local ok = pcall(function()
                local machine = resolveAccelModel()
                if not machine then return end

                local destCF = nightSkipTeleportCF(machine)
                if not destCF then return end

                local placement, rot = placementFromExistingModel(machine)
                if not placement then return end

                teleportSticky(destCF, true)
                task.wait(1.0)

                doPickupNearest()
                task.wait(1.0)

                local placeRemote = RS:WaitForChild("RemoteEvents"):WaitForChild("RequestPlaceStructure")
                local bp = waitForAccelBlueprint(8)
                if not (bp and bp.Parent) then return end

                placeAccelAtSnap(placeRemote, bp, placement, rot)
                task.wait(1.0)

                local placed = waitForAccelModel(8)
                if placed then
                    fireAccelRemote(placed)
                end

                task.wait(1.0)
            end)

            if returnCF then
                pcall(function() teleportSticky(returnCF, true) end)
            end

            busy = false
            return ok
        end

        local edgeConn = edgeBtn.MouseButton1Click:Connect(function()
            runTemporalSequence()
        end)

        if C.State.Toggles.MoreTemporalEdge == nil then
            C.State.Toggles.MoreTemporalEdge = false
        end
        if C.State.Toggles.MoreTemporalTimer == nil then
            C.State.Toggles.MoreTemporalTimer = false
        end

        edgeBtn.Visible = (C.State.Toggles.MoreTemporalEdge == true)

        tab:Section({ Title = "Temporal Accelerometer" })

        tab:Toggle({
            Title = "Edge Button: Temporal Cycle",
            Value = (C.State.Toggles.MoreTemporalEdge == true),
            Callback = function(state)
                C.State.Toggles.MoreTemporalEdge = (state == true)
                if edgeBtn then edgeBtn.Visible = (state == true) end
            end
        })

        tab:Button({
            Title = "Run Temporal Cycle Now",
            Callback = function()
                runTemporalSequence()
            end
        })

        local timerOn = false
        local timerThread = nil
        local TIMER_SECONDS = 180

        local function stopTimer()
            timerOn = false
            if timerThread then
                pcall(function() task.cancel(timerThread) end)
                timerThread = nil
            end
        end

        local function startTimer()
            if timerOn then return end
            timerOn = true
            if timerThread then
                pcall(function() task.cancel(timerThread) end)
                timerThread = nil
            end
            timerThread = task.spawn(function()
                runTemporalSequence()
                local nextAt = os.clock() + TIMER_SECONDS
                while timerOn do
                    local now = os.clock()
                    if now >= nextAt then
                        runTemporalSequence()
                        nextAt = nextAt + TIMER_SECONDS
                        if now >= nextAt + TIMER_SECONDS then
                            nextAt = now + TIMER_SECONDS
                        end
                    end
                    task.wait(0.25)
                end
            end)
        end

        tab:Toggle({
            Title = "Temporal Cycle Timer (every 3 minutes)",
            Value = (C.State.Toggles.MoreTemporalTimer == true),
            Callback = function(state)
                C.State.Toggles.MoreTemporalTimer = (state == true)
                if state then
                    startTimer()
                else
                    stopTimer()
                end
            end
        })

        if C.State.Toggles.MoreTemporalTimer == true then
            startTimer()
        end

        Players.LocalPlayer.CharacterAdded:Connect(function()
            local pg = lp:WaitForChild("PlayerGui")
            local eg = pg:FindFirstChild("EdgeButtons")
            if eg and eg.Parent ~= pg then eg.Parent = pg end
            if edgeBtn then edgeBtn.Visible = (C.State.Toggles.MoreTemporalEdge == true) end
        end)

        _G.__MoreTemporal = {
            Destroy = function()
                stopTimer()
                if rollbackThread then pcall(function() task.cancel(rollbackThread) end) rollbackThread = nil end
                if edgeConn then pcall(function() edgeConn:Disconnect() end) edgeConn = nil end
                if edgeBtn and edgeBtn.Parent then pcall(function() edgeBtn:Destroy() end) end
                if DUMMY_MODEL then pcall(function() DUMMY_MODEL:Destroy() end) end
            end
        }
    end

    local ok, err = pcall(run)
    if not ok then warn("[More] module error: " .. tostring(err)) end
end
