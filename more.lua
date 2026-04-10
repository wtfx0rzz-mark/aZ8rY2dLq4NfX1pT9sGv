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

        local RootRS, RootWS, cam = nil, nil, nil

        local function refreshRoots()
            local ugc = game:FindFirstChild("Ugc")
            if ugc then
                local rs = ugc:FindFirstChild("ReplicatedStorage")
                local ws = ugc:FindFirstChild("Workspace")
                if rs and ws then
                    RootRS = rs
                    RootWS = ws
                    cam = WS.CurrentCamera
                    return RootRS, RootWS
                end
            end
            RootRS = RS
            RootWS = WS
            cam = WS.CurrentCamera
            return RootRS, RootWS
        end
        refreshRoots()

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
                return m:FindFirstChildWhichIsA("BasePart", true)
            end
            return nil
        end

        local function getRemote(name)
            refreshRoots()
            local f = RootRS:FindFirstChild("RemoteEvents")
            local r = f and f:FindFirstChild(name)
            if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction")) then return r end
            for _, d in ipairs(RootRS:GetDescendants()) do
                if d.Name == name and (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) then
                    return d
                end
            end
            return nil
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

        local function stopRollbackWatch()
            rollbackCF = nil
            if rollbackThread then
                pcall(function() task.cancel(rollbackThread) end)
                rollbackThread = nil
            end
        end

        local function startRollbackWatch(afterCF)
            stopRollbackWatch()
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
                        moved = true
                        break
                    end
                    if h and h.MoveDirection.Magnitude > 0.05 then
                        moved = true
                        break
                    end
                    if not lp or lp.GameplayPaused then
                        moved = true
                        break
                    end
                    Run.Heartbeat:Wait()
                end
                if (not moved) and rollbackCF then
                    local root = hrp()
                    if root then
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
            refreshRoots()
            local map = (RootWS and RootWS:FindFirstChild("Map")) or WS:FindFirstChild("Map")
            if map then
                local fol = map:FindFirstChild("Foliage")
                if fol then table.insert(ex, fol) end
            end
            local items = (RootWS and RootWS:FindFirstChild("Items")) or WS:FindFirstChild("Items")
            local chars = (RootWS and RootWS:FindFirstChild("Characters")) or WS:FindFirstChild("Characters")
            if items then table.insert(ex, items) end
            if chars then table.insert(ex, chars) end
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
            local root = hrp()
            if not root then return end
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
            refreshRoots()
            return (RootWS and RootWS:FindFirstChild("Structures")) or WS:FindFirstChild("Structures")
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
            refreshRoots()
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

        local camConn = WS:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            cam = WS.CurrentCamera
        end)

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

        local function placementFromOrb(model, orbPos)
            if not (model and orbPos) then return nil, nil, nil end
            local ok, cf0 = pcall(function() return model:GetPivot() end)
            if not ok or not cf0 then return nil, nil, nil end
            local fallbackY = hrp() and hrp().Position.Y or cf0.Position.Y
            local gy0 = groundYAtSnap(Vector3.new(cf0.Position.X, cf0.Position.Y, cf0.Position.Z), fallbackY, model)
            local yOff = (cf0.Position.Y - gy0)
            local pos = Vector3.new(orbPos.X, orbPos.Y, orbPos.Z)
            local cf = yawOnly(Vector3.new(pos.X, pos.Y + yOff, pos.Z), cf0.LookVector)
            local placement = { Valid = true, Position = pos, CFrame = cf }
            local rot = (cf - cf.Position)
            return placement, rot, true
        end

        local function findPickUpRemote()
            refreshRoots()
            local re = RootRS:FindFirstChild("RemoteEvents")
            if re then
                local r = re:FindFirstChild("RequestPickUpStructure")
                if r and (r:IsA("RemoteFunction") or r:IsA("RemoteEvent")) then return r end
            end
            local rf = RootRS:FindFirstChild("RemoteFunctions")
            if rf then
                local r = rf:FindFirstChild("RequestPickUpStructure")
                if r and (r:IsA("RemoteFunction") or r:IsA("RemoteEvent")) then return r end
            end
            for _, d in ipairs(RootRS:GetDescendants()) do
                if d.Name == "RequestPickUpStructure" and (d:IsA("RemoteFunction") or d:IsA("RemoteEvent")) then
                    return d
                end
            end
            return nil
        end

        local function doPickupStructure(targetModel)
            local remote = findPickUpRemote()
            if not (remote and targetModel and targetModel.Parent) then return false end
            local ok = pcall(function()
                if remote:IsA("RemoteFunction") then
                    remote:InvokeServer(targetModel)
                else
                    remote:FireServer(targetModel)
                end
            end)
            return ok
        end

        local function doPickupNearest()
            local nearest = nil
            local m, _ = nearestStructure()
            if m then nearest = m end
            return doPickupStructure(nearest)
        end

        local function waitForModelGone(model, timeout)
            local t0 = os.clock()
            while os.clock() - t0 < (timeout or 4) do
                if not (model and model.Parent) then return true end
                task.wait(0.10)
            end
            return false
        end

        local function findPlaceRemote()
            refreshRoots()
            local re = RootRS:FindFirstChild("RemoteEvents")
            local r = re and re:FindFirstChild("RequestPlaceStructure")
            if r and r:IsA("RemoteFunction") then return r end
            for _, d in ipairs(RootRS:GetDescendants()) do
                if d.Name == "RequestPlaceStructure" and d:IsA("RemoteFunction") then
                    return d
                end
            end
            return nil
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
                else
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
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 8)
                corner.Parent = b
            else
                b.Text = label
                b.LayoutOrder = order or b.LayoutOrder
                b.Visible = false
            end
            return b
        end

        local edgeBtn = makeEdgeBtn("TemporalAccelEdge", "Temporal Cycle", 40)

        local function makeMiniBtn(parent, name, label, order)
            local b = parent:FindFirstChild(name)
            if not b then
                b = Instance.new("TextButton")
                b.Name = name
                b.Size = UDim2.new(1, 0, 0, 30)
                b.Text = label
                b.TextSize = 12
                b.Font = Enum.Font.GothamBold
                b.BackgroundColor3 = Color3.fromRGB(25,25,28)
                b.TextColor3 = Color3.new(1,1,1)
                b.BorderSizePixel = 0
                b.LayoutOrder = order or 10
                b.Parent = parent
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 8)
                corner.Parent = b
            else
                b.Text = label
                b.LayoutOrder = order or b.LayoutOrder
            end
            return b
        end

        local setupMenu = edgeGui:FindFirstChild("TemporalSetupMenu")
        if not setupMenu then
            setupMenu = Instance.new("Frame")
            setupMenu.Name = "TemporalSetupMenu"
            setupMenu.AnchorPoint = Vector2.new(1, 0)
            setupMenu.Position = UDim2.new(1, -6, 0, 46)
            setupMenu.Size = UDim2.new(0, 150, 0, 108)
            setupMenu.BackgroundTransparency = 1
            setupMenu.BorderSizePixel = 0
            setupMenu.Visible = false
            setupMenu.Parent = edgeGui
            local list = Instance.new("UIListLayout")
            list.Name = "VList"
            list.FillDirection = Enum.FillDirection.Vertical
            list.SortOrder = Enum.SortOrder.LayoutOrder
            list.Padding = UDim.new(0, 6)
            list.HorizontalAlignment = Enum.HorizontalAlignment.Right
            list.Parent = setupMenu
        end

        local btnSetPlace   = makeMiniBtn(setupMenu, "SetTemporalLocation", "Set Temporal Location", 10)
        local btnSetTP      = makeMiniBtn(setupMenu, "SetTeleportLocation", "Set Teleport Location", 20)
        local btnClearOrbs  = makeMiniBtn(setupMenu, "ClearLocations", "Clear Locations", 30)

        local temporalOrb = nil
        local teleportOrb = nil

        local function makeOrb(name, pos, color)
            refreshRoots()
            local p = Instance.new("Part")
            p.Name = name
            p.Shape = Enum.PartType.Ball
            p.Material = Enum.Material.Neon
            p.Size = Vector3.new(1.6, 1.6, 1.6)
            p.Anchored = true
            p.CanCollide = false
            p.CanTouch = false
            p.CanQuery = false
            p.CastShadow = false
            p.Color = color
            p.CFrame = CFrame.new(pos)
            p.Parent = RootWS
            return p
        end

        local function setOrbVisible(orb, on)
            if not orb then return end
            if on then orb.Transparency = 0.05 else orb.Transparency = 1 end
        end

        local function ensureOrbsFromState()
            if C.State.MoreTemporalPlacePos and typeof(C.State.MoreTemporalPlacePos) == "Vector3" then
                if not (temporalOrb and temporalOrb.Parent) then
                    temporalOrb = makeOrb("__cg_temporal_place_orb__", C.State.MoreTemporalPlacePos + Vector3.new(0, 0.8, 0), Color3.fromRGB(0, 200, 255))
                end
            end
            if C.State.MoreTemporalTeleportPos and typeof(C.State.MoreTemporalTeleportPos) == "Vector3" then
                if not (teleportOrb and teleportOrb.Parent) then
                    teleportOrb = makeOrb("__cg_temporal_tp_orb__", C.State.MoreTemporalTeleportPos + Vector3.new(0, 0.8, 0), Color3.fromRGB(255, 200, 0))
                end
            end
        end

        local function applySetupVisibility()
            local on = (C.State.Toggles.MoreTemporalSetup == true)
            setupMenu.Visible = on
            ensureOrbsFromState()
            setOrbVisible(temporalOrb, on)
            setOrbVisible(teleportOrb, on)
        end

        local function safeFlatForwardUnit(cf)
            local lv = cf.LookVector
            local v = Vector3.new(lv.X, 0, lv.Z)
            if v.Magnitude < 1e-6 then return Vector3.new(0, 0, -1) end
            return v.Unit
        end

        local function clearLocations()
            C.State.MoreTemporalPlacePos = nil
            C.State.MoreTemporalTeleportPos = nil
            C.State.MoreTemporalTeleportCF = nil
            if temporalOrb then pcall(function() temporalOrb:Destroy() end) end
            if teleportOrb then pcall(function() teleportOrb:Destroy() end) end
            temporalOrb = nil
            teleportOrb = nil
            applySetupVisibility()
        end

        local setupConns = {}

        setupConns[#setupConns+1] = btnSetPlace.MouseButton1Click:Connect(function()
            local root = hrp()
            if not root then return end
            local fwd = safeFlatForwardUnit(root.CFrame)
            local desired = root.Position + fwd * 10
            local g = groundBelow(desired)
            local placePos = Vector3.new(desired.X, g.Y, desired.Z)
            C.State.MoreTemporalPlacePos = placePos
            if temporalOrb then pcall(function() temporalOrb:Destroy() end) end
            temporalOrb = makeOrb("__cg_temporal_place_orb__", placePos + Vector3.new(0, 0.8, 0), Color3.fromRGB(0, 200, 255))
            applySetupVisibility()
        end)

        setupConns[#setupConns+1] = btnSetTP.MouseButton1Click:Connect(function()
            local root = hrp()
            if not root then return end
            local g = groundBelow(root.Position)
            local tpPos = Vector3.new(root.Position.X, g.Y, root.Position.Z)
            local tpCF = yawOnly(Vector3.new(tpPos.X, tpPos.Y + 3.0, tpPos.Z), root.CFrame.LookVector)
            C.State.MoreTemporalTeleportPos = tpPos
            C.State.MoreTemporalTeleportCF = tpCF
            if teleportOrb then pcall(function() teleportOrb:Destroy() end) end
            teleportOrb = makeOrb("__cg_temporal_tp_orb__", tpPos + Vector3.new(0, 0.8, 0), Color3.fromRGB(255, 200, 0))
            applySetupVisibility()
        end)

        setupConns[#setupConns+1] = btnClearOrbs.MouseButton1Click:Connect(function()
            clearLocations()
        end)

        local busy = false
        local temporalRunNonce = 0

        local function freshTemporalRunState()
            refreshRoots()
            stopRollbackWatch()
            cam = WS.CurrentCamera
            temporalRunNonce += 1
            return temporalRunNonce
        end

        local function doPickupTemporalAccelerometerOnly(targetModel)
            if not (targetModel and targetModel.Parent) then return false end
            local preBlueprint = findAccelBlueprintInstance()
            local okPickup = doPickupStructure(targetModel)
            if not okPickup then return false end

            local t0 = os.clock()
            while os.clock() - t0 < 5 do
                local bp = findAccelBlueprintInstance()
                if bp and bp.Parent and bp ~= preBlueprint then
                    return true
                end
                if not (targetModel and targetModel.Parent) then
                    local bp2 = findAccelBlueprintInstance()
                    if bp2 and bp2.Parent then
                        return true
                    end
                end
                task.wait(0.10)
            end
            return false
        end

        local function runTemporalSequence(fromTimer)
            if busy then return end
            busy = true

            local runNonce = freshTemporalRunState()
            local root0 = hrp()
            local returnCF = root0 and root0.CFrame or nil

            local ok, err = pcall(function()
                if fromTimer == true then
                    local tp = C.State.MoreTemporalTeleportCF
                    if typeof(tp) == "CFrame" then
                        teleportSticky(tp, true)
                        task.wait(0.75)
                    end
                end

                if runNonce ~= temporalRunNonce then return end

                local machine = resolveAccelModel()
                if not machine then return end

                local destCF = nightSkipTeleportCF(machine)
                if not destCF then return end

                local placement, rot
                if C.State.MoreTemporalPlacePos and typeof(C.State.MoreTemporalPlacePos) == "Vector3" then
                    placement, rot = placementFromOrb(machine, C.State.MoreTemporalPlacePos)
                else
                    placement, rot = placementFromExistingModel(machine)
                end
                if not placement then return end

                teleportSticky(destCF, true)
                task.wait(1.0)

                if not (machine and machine.Parent) then
                    machine = resolveAccelModel()
                    if not machine then return end
                end

                local picked = doPickupTemporalAccelerometerOnly(machine)
                if not picked then return end

                task.wait(0.35)

                local placeRemote = findPlaceRemote()
                if not placeRemote then return end

                local bp = waitForAccelBlueprint(8)
                if not (bp and bp.Parent) then return end

                local placed = placeAccelAtSnap(placeRemote, bp, placement, rot)
                if not placed then return end
                task.wait(1.0)

                local accelPlaced = waitForAccelModel(8)
                if accelPlaced and accelPlaced.Parent then
                    fireAccelRemote(accelPlaced)
                end

                task.wait(1.0)
            end)

            if not ok then
                warn("[More] runTemporalSequence error: " .. tostring(err))
            end

            if returnCF then
                pcall(function()
                    freshTemporalRunState()
                    teleportSticky(returnCF, true)
                end)
            end

            busy = false
        end

        local edgeConn = edgeBtn.MouseButton1Click:Connect(function()
            runTemporalSequence(false)
        end)

        if C.State.Toggles.MoreTemporalEdge == nil then C.State.Toggles.MoreTemporalEdge = false end
        if C.State.Toggles.MoreTemporalTimer == nil then C.State.Toggles.MoreTemporalTimer = false end
        if C.State.Toggles.MoreTemporalSetup == nil then C.State.Toggles.MoreTemporalSetup = false end

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
                runTemporalSequence(false)
            end
        })

        tab:Button({
            Title = "Pick Up Nearest Structure",
            Callback = function()
                local ok = doPickupNearest()
                if not ok then
                    warn("[More] pickup failed (no target/remote or invoke error)")
                end
            end
        })

        tab:Section({ Title = "Temporal Setup" })

        tab:Toggle({
            Title = "Temporal Setup",
            Value = (C.State.Toggles.MoreTemporalSetup == true),
            Callback = function(state)
                C.State.Toggles.MoreTemporalSetup = (state == true)
                applySetupVisibility()
            end
        })

        local timerOn = false
        local timerConn = nil

        local function stopTimer()
            timerOn = false
            if timerConn then
                pcall(function() timerConn:Disconnect() end)
                timerConn = nil
            end
        end

        local function getPeriod(clock)
            return (clock >= 6 and clock < 20) and "DAY" or "NIGHT"
        end

        local function startTimer()
            if timerOn then return end
            timerOn = true
            local lastPeriod = getPeriod(game:GetService("Lighting").ClockTime)
            timerConn = game:GetService("Lighting"):GetPropertyChangedSignal("ClockTime"):Connect(function()
                if not timerOn then return end
                local period = getPeriod(game:GetService("Lighting").ClockTime)
                if period ~= lastPeriod then
                    lastPeriod = period
                    if period == "NIGHT" then
                        task.spawn(function()
                            runTemporalSequence(true)
                        end)
                    end
                end
            end)
        end

        tab:Toggle({
            Title = "Auto Temporal Cycle",
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
        else
            stopTimer()
        end

        do
            local function lower(s)
                return (type(s) == "string") and string.lower(s) or ""
            end

            local function itemsFolder()
                refreshRoots()
                local f = RootWS:FindFirstChild("Items")
                if f then return f end
                local f2 = WS:FindFirstChild("Items")
                if f2 then return f2 end
                return nil
            end

            local function isMyCharModel(m)
                local c = lp.Character
                return c and m == c
            end

            local function isSelectedNPC(m, selectedSet)
                if not (m and m:IsA("Model")) then return false end
                if isMyCharModel(m) then return false end
                if not m:FindFirstChildWhichIsA("Humanoid", true) then return false end
                local n = lower(m.Name or "")
                if selectedSet["Cultist"] and n:find("cultist", 1, true) then return true end
                if selectedSet["Alien"] and n:find("alien", 1, true) then return true end
                return false
            end

            local function isSelectedItem(inst, selectedSet)
                if not inst then return false end
                local ln = lower(inst.Name or "")
                ln = ln:gsub("%s+", " ")
                local ln2 = (lower(inst.Name or "")):gsub("%s+", "")
                if selectedSet["Sapling"] and ln == "sapling" then return true end
                if selectedSet["Sacrifice Totem"] then
                    if ln == "sacrifice totem" or ln2 == "sacrificetotem" then return true end
                    if ln:find("sacrifice", 1, true) and ln:find("totem", 1, true) then return true end
                end
                return false
            end

            local function topModelUnderItems(part, items)
                local cur = part
                local lastModel = nil
                while cur and cur ~= WS and cur ~= RootWS and cur ~= items do
                    if cur:IsA("Model") then lastModel = cur end
                    cur = cur.Parent
                end
                if lastModel and items and lastModel:IsDescendantOf(items) then
                    return lastModel
                end
                return lastModel
            end

            local function findLavaBurnRemote()
                refreshRoots()
                local remFolder = RootRS:FindFirstChild("RemoteEvents") or RootRS
                local r = remFolder:FindFirstChild("RequestLavaBurnItem")
                if r and (r:IsA("RemoteFunction") or r:IsA("RemoteEvent")) then return r end
                for _, d in ipairs(RootRS:GetDescendants()) do
                    if d.Name == "RequestLavaBurnItem" and (d:IsA("RemoteFunction") or d:IsA("RemoteEvent")) then
                        return d
                    end
                end
                return nil
            end

            local function findLava()
                refreshRoots()
                local direct = RootWS:FindFirstChild("Map")
                if direct then
                    local lm = direct:FindFirstChild("Landmarks")
                    local v  = lm and lm:FindFirstChild("Volcano")
                    local f  = v and v:FindFirstChild("Functional")
                    local lv = f and f:FindFirstChild("Lava")
                    if lv and lv:IsA("BasePart") then return lv end
                end
                for _, d in ipairs(RootWS:GetDescendants()) do
                    if d:IsA("BasePart") and d.Name == "Lava" then
                        local a = d.Parent
                        while a do
                            if a.Name == "Volcano" then return d end
                            a = a.Parent
                        end
                    end
                end
                return nil
            end

            local function candidateFromPart(part, items, selectedSet)
                if not (part and part:IsA("BasePart")) then return nil end
                if RootWS ~= WS and not part:IsDescendantOf(RootWS) then return nil end
                if items and part:IsDescendantOf(items) then
                    local m = topModelUnderItems(part, items) or part:FindFirstAncestorOfClass("Model")
                    if m and isSelectedItem(m, selectedSet) then return m end
                    if isSelectedItem(part, selectedSet) then return part end
                end
                local m = part:FindFirstAncestorOfClass("Model")
                if m and isSelectedNPC(m, selectedSet) then return m end
                return nil
            end

            local SCAN_RADIUS = 140

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

            C.State.MoreLavaBurnChoice = C.State.MoreLavaBurnChoice or {}
            local burnSelectedSet = setFromChoice(C.State.MoreLavaBurnChoice)

            local burnBusy = false
            local function burnSelected()
                if burnBusy then return end
                burnBusy = true
                local ok = pcall(function()
                    if not burnSelectedSet or next(burnSelectedSet) == nil then return end
                    local Remote = findLavaBurnRemote()
                    local Lava = findLava()
                    if not (Remote and Lava and Lava.Parent) then
                        warn("[More] LavaBurn missing Remote or Lava")
                        return
                    end
                    local root = hrp()
                    if not root then return end
                    local items = itemsFolder()
                    local params = OverlapParams.new()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                    params.FilterDescendantsInstances = { lp.Character }
                    local parts = WS:GetPartBoundsInRadius(root.Position, SCAN_RADIUS, params) or {}
                    local uniq, targets = {}, {}
                    for _,p in ipairs(parts) do
                        local cand = candidateFromPart(p, items, burnSelectedSet)
                        if cand and not uniq[cand] then
                            uniq[cand] = true
                            targets[#targets+1] = cand
                        end
                    end
                    local okN, errN = 0, 0
                    for i = 1, #targets do
                        local inst = targets[i]
                        if inst and inst.Parent then
                            local okCall = false
                            if Remote:IsA("RemoteFunction") then
                                okCall = pcall(function() return Remote:InvokeServer(inst, Lava) end)
                            else
                                okCall = pcall(function() Remote:FireServer(inst, Lava) end)
                            end
                            if okCall then okN += 1 else errN += 1 end
                        end
                        if i % 8 == 0 then Run.Heartbeat:Wait() end
                        task.wait(0.02)
                    end
                    warn(("[More] LavaBurn: radius=%d targets=%d ok=%d err=%d"):format(SCAN_RADIUS, #targets, okN, errN))
                end)
                burnBusy = false
                return ok
            end

            tab:Section({ Title = "Lava Burn" })

            tab:Dropdown({
                Title = "Targets",
                Values = { "Cultist", "Alien", "Sacrifice Totem", "Sapling" },
                Multi = true,
                AllowNone = true,
                Callback = function(choice)
                    local list = {}
                    if type(choice) == "table" then
                        for i=1,#choice do
                            local v = choice[i]
                            if v and v ~= "" then list[#list+1] = v end
                        end
                    elseif choice and choice ~= "" then
                        list[1] = choice
                    end
                    C.State.MoreLavaBurnChoice = list
                    burnSelectedSet = setFromChoice(choice)
                end
            })

            tab:Button({
                Title = "Burn",
                Callback = function() burnSelected() end
            })

            local autoBurnConn = nil
            local autoBurnSeen = {}

            local function stopAutoBurn()
                if autoBurnConn then
                    pcall(function() autoBurnConn:Disconnect() end)
                    autoBurnConn = nil
                end
                autoBurnSeen = {}
            end

            local function startAutoBurn()
                stopAutoBurn()
                local items = itemsFolder()
                if not items then return end
                autoBurnConn = items.DescendantAdded:Connect(function(inst)
                    if not inst:IsA("Model") then return end
                    if autoBurnSeen[inst] then return end
                    local n = lower(inst.Name or "")
                    if not n:find("cultist", 1, true) then return end
                    if not inst:FindFirstChildWhichIsA("Humanoid", true) then return end
                    autoBurnSeen[inst] = true
                    task.spawn(function()
                        task.wait(0.2)
                        if not (inst and inst.Parent) then return end
                        local Remote = findLavaBurnRemote()
                        local Lava = findLava()
                        if not (Remote and Lava and Lava.Parent) then return end
                        pcall(function()
                            if Remote:IsA("RemoteFunction") then
                                Remote:InvokeServer(inst, Lava)
                            else
                                Remote:FireServer(inst, Lava)
                            end
                        end)
                        task.delay(30, function() autoBurnSeen[inst] = nil end)
                    end)
                end)
            end

            if C.State.Toggles.MoreAutoBurnCultist == nil then
                C.State.Toggles.MoreAutoBurnCultist = false
            end

            tab:Toggle({
                Title = "Auto Burn: Cultist",
                Value = (C.State.Toggles.MoreAutoBurnCultist == true),
                Callback = function(state)
                    C.State.Toggles.MoreAutoBurnCultist = (state == true)
                    if state then startAutoBurn() else stopAutoBurn() end
                end
            })

            if C.State.Toggles.MoreAutoBurnCultist == true then
                startAutoBurn()
            end

            -- shared scrap bring helpers
            local SCRAP_BRING_INTERVAL = 120
            local DRAG_SETTLE          = 0.06
            local scrapDragStarted     = setmetatable({}, { __mode = "k" })

            local function scrapGetRemotes()
                refreshRoots()
                local re = RootRS:FindFirstChild("RemoteEvents")
                return {
                    StartDrag = re and re:FindFirstChild("RequestStartDraggingItem"),
                    StopDrag  = re and re:FindFirstChild("StopDraggingItem"),
                }
            end

            local function scrapGetAllParts(m)
                local t = {}
                if not m then return t end
                if m:IsA("BasePart") then t[1] = m; return t end
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("BasePart") then t[#t+1] = d end
                end
                return t
            end

            local function scrapSetCollide(m, on, snapshot)
                if on and snapshot then
                    for part, can in pairs(snapshot) do
                        if part and part.Parent then part.CanCollide = can end
                    end
                    return
                end
                local snap = {}
                for _, p in ipairs(scrapGetAllParts(m)) do
                    snap[p] = p.CanCollide
                    p.CanCollide = false
                end
                return snap
            end

            local function scrapZeroAssembly(m)
                for _, p in ipairs(scrapGetAllParts(m)) do
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                end
            end

            local function scrapSevereExternalWelds(m)
                if not (m and m.Parent) then return end
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("WeldConstraint") then
                        local p0, p1 = d.Part0, d.Part1
                        if (p0 and not p0:IsDescendantOf(m)) or (p1 and not p1:IsDescendantOf(m)) then
                            pcall(function() d:Destroy() end)
                        end
                    end
                    if d:IsA("BasePart") and d.Anchored then
                        pcall(function() d.Anchored = false end)
                    end
                end
                if m:IsA("BasePart") and m.Anchored then
                    pcall(function() m.Anchored = false end)
                end
            end

            local function scrapRefreshPrompts(m)
                if not (m and m.Parent) then return end
                for _, d in ipairs(m:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then
                        local was = d.Enabled
                        d.Enabled = false
                        task.defer(function() d.Enabled = was ~= false end)
                    end
                end
            end

            local function scrapSafeStartDrag(r, m)
                if not (r and r.StartDrag and m and m.Parent) then return false end
                local ok = pcall(function() r.StartDrag:FireServer(m) end)
                return ok
            end

            local function scrapFinallyStopDragTwice(r, m)
                pcall(function() if r and r.StopDrag and m then r.StopDrag:FireServer(m) end end)
                Run.Heartbeat:Wait()
                pcall(function() if r and r.StopDrag and m then r.StopDrag:FireServer(m) end end)
                task.delay(0.05, function() pcall(function() if r and r.StopDrag and m then r.StopDrag:FireServer(m) end end) end)
                task.delay(0.20, function() pcall(function() if r and r.StopDrag and m then r.StopDrag:FireServer(m) end end) end)
            end

            local function scrapStopIfDragging(r, m)
                if not m then return end
                if scrapDragStarted[m] then
                    scrapFinallyStopDragTwice(r, m)
                    scrapDragStarted[m] = nil
                end
            end

            local function scrapperDropCF()
                local map  = WS:FindFirstChild("Map")
                local camp = map and map:FindFirstChild("Campground")
                local scr  = camp and camp:FindFirstChild("Scrapper")
                if not scr then return nil end
                local mp = mainPart(scr)
                local cf = (mp and mp.CFrame) or (scr:IsA("Model") and scr:GetPivot()) or nil
                if not cf then return nil end
                return CFrame.new(cf.Position + Vector3.new(0, 5, 0))
            end

            local function scrapDropAtScrapper(m)
                if not (m and m.Parent) then return false end
                scrapSevereExternalWelds(m)
                local r = scrapGetRemotes()
                local started = scrapSafeStartDrag(r, m)
                if started then scrapDragStarted[m] = true end
                Run.Heartbeat:Wait()
                task.wait(DRAG_SETTLE)
                local destCF = scrapperDropCF()
                if not destCF then
                    scrapStopIfDragging(r, m)
                    return false
                end
                local snap = scrapSetCollide(m, false)
                scrapZeroAssembly(m)
                if m:IsA("Model") then
                    m:PivotTo(destCF)
                else
                    local p = mainPart(m)
                    if p then p.CFrame = destCF end
                end
                scrapSetCollide(m, true, snap)
                scrapStopIfDragging(r, m)
                for _, p in ipairs(scrapGetAllParts(m)) do
                    p.Anchored = false
                    p.AssemblyLinearVelocity  = Vector3.new()
                    p.AssemblyAngularVelocity = Vector3.new()
                end
                scrapRefreshPrompts(m)
                return true
            end

            local function scrapRunPass(selectedSet)
                local items = itemsFolder()
                if not items then return end
                local queue, seen = {}, {}
                for _, m in ipairs(items:GetChildren()) do
                    if m:IsA("Model") and not seen[m] and selectedSet[m.Name] then
                        seen[m] = true
                        queue[#queue+1] = m
                    end
                end
                local active = 0
                for i = 1, #queue do
                    local m = queue[i]
                    if m and m.Parent then
                        active += 1
                        task.spawn(function()
                            scrapDropAtScrapper(m)
                            active -= 1
                        end)
                    end
                    while active >= 10 do Run.Heartbeat:Wait() end
                    task.wait(0.5)
                end
                local deadline = os.clock() + math.max(5, 0.5 * #queue + 5)
                while active > 0 and os.clock() < deadline do
                    Run.Heartbeat:Wait()
                end
            end

            local function makeScrapBringToggle(stateKey, selectedSet)
                local running   = false
                local timerThread = nil
                local descConn  = nil
                local descSeen  = setmetatable({}, { __mode = "k" })

                local function stop()
                    running = false
                    if timerThread then
                        pcall(function() task.cancel(timerThread) end)
                        timerThread = nil
                    end
                    if descConn then
                        pcall(function() descConn:Disconnect() end)
                        descConn = nil
                    end
                    descSeen = setmetatable({}, { __mode = "k" })
                end

                local function start()
                    stop()
                    running = true

                    local items = itemsFolder()
                    if items then
                        descConn = items.DescendantAdded:Connect(function(inst)
                            if not running then return end
                            if not inst:IsA("Model") then return end
                            if descSeen[inst] then return end
                            if not selectedSet[inst.Name] then return end
                            descSeen[inst] = true
                            task.spawn(function()
                                task.wait(0.2)
                                if not (inst and inst.Parent) then return end
                                scrapDropAtScrapper(inst)
                                task.delay(30, function() descSeen[inst] = nil end)
                            end)
                        end)
                    end

                    timerThread = task.spawn(function()
                        while running do
                            pcall(function() scrapRunPass(selectedSet) end)
                            local t0 = os.clock()
                            while running and (os.clock() - t0) < SCRAP_BRING_INTERVAL do
                                task.wait(1)
                            end
                        end
                    end)
                end

                return { start = start, stop = stop }
            end

            local CULTIST_GEM_SET = { ["Cultist Gem"] = true }
            local FOREST_GEM_SET  = {
                ["Gem of the Forest Fragment"] = true,
                ["Gem of the Forest"]          = true,
            }

            local cultistGemBring = makeScrapBringToggle("MoreAutoScrapCultistGem", CULTIST_GEM_SET)
            local forestGemBring  = makeScrapBringToggle("MoreAutoScrapForestGem",  FOREST_GEM_SET)

            if C.State.Toggles.MoreAutoScrapCultistGem == nil then
                C.State.Toggles.MoreAutoScrapCultistGem = false
            end
            if C.State.Toggles.MoreAutoScrapForestGem == nil then
                C.State.Toggles.MoreAutoScrapForestGem = false
            end

            tab:Section({ Title = "Auto Scrap" })

            tab:Toggle({
                Title = "Auto Scrap: Cultist Gem",
                Value = (C.State.Toggles.MoreAutoScrapCultistGem == true),
                Callback = function(state)
                    C.State.Toggles.MoreAutoScrapCultistGem = (state == true)
                    if state then cultistGemBring.start() else cultistGemBring.stop() end
                end
            })

            tab:Toggle({
                Title = "Auto Scrap: Forest Gem",
                Value = (C.State.Toggles.MoreAutoScrapForestGem == true),
                Callback = function(state)
                    C.State.Toggles.MoreAutoScrapForestGem = (state == true)
                    if state then forestGemBring.start() else forestGemBring.stop() end
                end
            })

            if C.State.Toggles.MoreAutoScrapCultistGem == true then cultistGemBring.start() end
            if C.State.Toggles.MoreAutoScrapForestGem  == true then forestGemBring.start()  end
        end

        local charConn = Players.LocalPlayer.CharacterAdded:Connect(function()
            refreshRoots()
            local pg = lp:WaitForChild("PlayerGui")
            local eg = pg:FindFirstChild("EdgeButtons")
            if eg and eg.Parent ~= pg then eg.Parent = pg end
            if edgeBtn then edgeBtn.Visible = (C.State.Toggles.MoreTemporalEdge == true) end
            applySetupVisibility()
        end)

        applySetupVisibility()

        _G.__MoreTemporal = {
            Destroy = function()
                stopTimer()
                stopAutoBurn()
                cultistGemBring.stop()
                forestGemBring.stop()
                busy = false
                stopRollbackWatch()
                if edgeConn then pcall(function() edgeConn:Disconnect() end) edgeConn = nil end
                if charConn then pcall(function() charConn:Disconnect() end) charConn = nil end
                if camConn then pcall(function() camConn:Disconnect() end) camConn = nil end
                for i=1,#setupConns do pcall(function() setupConns[i]:Disconnect() end) end
                setupConns = {}
                if temporalOrb then pcall(function() temporalOrb:Destroy() end) temporalOrb = nil end
                if teleportOrb then pcall(function() teleportOrb:Destroy() end) teleportOrb = nil end
                if setupMenu and setupMenu.Parent then pcall(function() setupMenu:Destroy() end) end
                if edgeBtn and edgeBtn.Parent then pcall(function() edgeBtn:Destroy() end) end
                if DUMMY_MODEL then pcall(function() DUMMY_MODEL:Destroy() end) end
            end
        }
    end

    local ok, err = pcall(run)
    if not ok then warn("[More] module error: " .. tostring(err)) end
end
