-- debug.lua
return function(C, R, UI)
    local Players  = (C and C.Services and C.Services.Players)  or game:GetService("Players")
    local RS       = (C and C.Services and C.Services.RS)       or game:GetService("ReplicatedStorage")
    local WS       = (C and C.Services and C.Services.WS)       or game:GetService("Workspace")
    local Run      = (C and C.Services and C.Services.Run)      or game:GetService("RunService")
    local CS       = game:GetService("CollectionService")
    local UIS      = game:GetService("UserInputService")

    local lp  = Players.LocalPlayer
    local tabs = UI and UI.Tabs
    local tab  = tabs and (tabs.Debug or tabs.TPBring or tabs.Auto or tabs.Main)
    assert(tab, "No tab")

    local RADIUS = 20

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:FindFirstChild("HumanoidRootPart")
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

    local function getRemote(...)
        local f = RS:FindFirstChild("RemoteEvents"); if not f then return nil end
        for i = 1, select("#", ...) do
            local n = select(i, ...)
            local x = f:FindFirstChild(n)
            if x then return x end
        end
        return nil
    end

    local RF_Start = getRemote("RequestStartDraggingItem","StartDraggingItem")
    local RF_Stop  = getRemote("RequestStopDraggingItem","StopDraggingItem","StopDraggingItemRemote")

    local function itemsFolder()
        return WS:FindFirstChild("Items") or WS
    end

    local function nearbyItems()
        local out, root = {}, hrp(); if not root then return out end
        local origin = root.Position
        for _,d in ipairs(itemsFolder():GetDescendants()) do
            local m = d:IsA("Model") and d
                or (d:IsA("BasePart") and d:FindFirstAncestorOfClass("Model"))
                or nil
            if m and m.Parent then
                local p = mainPart(m)
                if p and (p.Position - origin).Magnitude <= RADIUS then
                    out[#out+1] = m
                end
            end
        end
        return out
    end

    local function setPhysicsRestore(m)
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.Anchored = false
                p.CanCollide = true
                p.CanTouch = true
                p.CanQuery = true
                p.Massless = false
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
                p.CollisionGroupId = 0
                pcall(function() p:SetNetworkOwner(nil) end)
                pcall(function()
                    if p.SetNetworkOwnershipAuto then
                        p:SetNetworkOwnershipAuto()
                    end
                end)
            end
        end
        for _,pp in ipairs(m:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                pp.Enabled = true
            end
        end
        m:SetAttribute("Dragging", nil)
        m:SetAttribute("PickedUp", nil)
    end

    local function snapshotCollision(m)
        local t = {}
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                t[p] = {
                    CanCollide = p.CanCollide,
                    CanQuery   = p.CanQuery,
                    CanTouch   = p.CanTouch,
                }
            end
        end
        return t
    end

    local function setCollisionOff(m)
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = false
                p.CanQuery   = false
                p.CanTouch   = false
            end
        end
    end

    local function restoreCollision(m, snap)
        if not snap then return end
        for part,st in pairs(snap) do
            if part and part.Parent then
                part.CanCollide = st.CanCollide
                part.CanQuery   = st.CanQuery
                part.CanTouch   = st.CanTouch
            end
        end
    end

    local function ownAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            if RF_Start then
                pcall(function() RF_Start:FireServer(m) end)
            end
            local p = mainPart(m)
            if p then
                pcall(function() p:SetNetworkOwner(lp) end)
                for _,bp in ipairs(m:GetDescendants()) do
                    if bp:IsA("BasePart") then
                        bp.Anchored = true
                        bp.CanTouch = true
                        bp.CanQuery = true
                    end
                end
            end
        end
    end

    local function disownAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            if RF_Stop then
                pcall(function() RF_Stop:FireServer(m) end)
            end
            setPhysicsRestore(m)
        end
    end

    local function startDragAll()
        if not RF_Start then return end
        local list = nearbyItems()
        for _,m in ipairs(list) do
            pcall(function() RF_Start:FireServer(m) end)
            Run.Heartbeat:Wait()
        end
    end

    local function stopDragAll()
        if not RF_Stop then return end
        local list = nearbyItems()
        for _,m in ipairs(list) do
            pcall(function() RF_Stop:FireServer(m) end)
            Run.Heartbeat:Wait()
        end
    end

    local function wakeGentle()
        local list = nearbyItems()
        local lin, ang = 0.05, 0.05
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") and not p.Anchored then
                    local lv = p.AssemblyLinearVelocity
                    local av = p.AssemblyAngularVelocity
                    if lv.Magnitude < 0.02 and av.Magnitude < 0.02 then
                        p.AssemblyLinearVelocity  = lv + Vector3.new(
                            (math.random()-0.5)*lin,
                            (math.random()-0.5)*lin,
                            (math.random()-0.5)*lin
                        )
                        p.AssemblyAngularVelocity = av + Vector3.new(
                            (math.random()-0.5)*ang,
                            (math.random()-0.5)*ang,
                            (math.random()-0.5)*ang
                        )
                    end
                end
            end
        end
    end

    local function deoverlap()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            local p = mainPart(m)
            if p and not p.Anchored then
                local cf = (m:IsA("Model") and m:GetPivot()) or p.CFrame
                local jitter = 0.03
                local dx = (math.random()-0.5)*jitter
                local dz = (math.random()-0.5)*jitter
                local offset = Vector3.new(dx, 0, dz)
                if m:IsA("Model") then
                    m:PivotTo(cf + offset)
                else
                    p.CFrame = cf + offset
                end
            end
        end
    end

    local function nudgeAll()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            setPhysicsRestore(m)
        end
        Run.Heartbeat:Wait()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") and not p.Anchored then
                    p.AssemblyLinearVelocity  = p.AssemblyLinearVelocity  + Vector3.new(0, 0.6, 0)
                    p.AssemblyAngularVelocity = p.AssemblyAngularVelocity + Vector3.new(
                        0,
                        0.3*(math.random()-0.5),
                        0
                    )
                end
            end
        end
    end

    local function mineOwnership()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = false
                    pcall(function() p:SetNetworkOwner(lp) end)
                end
            end
        end
    end

    local function serverOwnership()
        local list = nearbyItems()
        for _,m in ipairs(list) do
            for _,p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = false
                    pcall(function() p:SetNetworkOwner(nil) end)
                    pcall(function()
                        if p.SetNetworkOwnershipAuto then
                            p:SetNetworkOwnershipAuto()
                        end
                    end)
                end
            end
        end
    end

    local function groundBelow(pos)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ex = { lp.Character }

        local map = WS:FindFirstChild("Map")
        if map then
            local fol = map:FindFirstChild("Foliage")
            if fol then
                table.insert(ex, fol)
            end
        end

        local items = WS:FindFirstChild("Items")
        if items then
            table.insert(ex, items)
        end

        params.FilterDescendantsInstances = ex

        local start = pos + Vector3.new(0, 5, 0)
        local hit = WS:Raycast(start, Vector3.new(0, -1000, 0), params)
        if hit then return hit.Position end

        hit = WS:Raycast(pos + Vector3.new(0, 200, 0), Vector3.new(0, -1000, 0), params)
        return (hit and hit.Position) or pos
    end

    local function zeroAssembly(root)
        if not root then return end
        root.AssemblyLinearVelocity  = Vector3.new()
        root.AssemblyAngularVelocity = Vector3.new()
    end

    local function settleBodyOnGround(m)
        local p = mainPart(m); if not p then return end
        local cf = (m:IsA("Model") and m:GetPivot()) or p.CFrame
        local groundPos = groundBelow(cf.Position)
        local halfY = 0
        pcall(function()
            halfY = p.Size.Y * 0.5
        end)
        local newPos = Vector3.new(cf.Position.X, groundPos.Y + halfY + 0.05, cf.Position.Z)
        local look = cf.LookVector
        if look.Magnitude < 1e-4 then
            look = Vector3.new(0,0,-1)
        end
        local newCF = CFrame.new(newPos, newPos + look.Unit)
        pcall(function()
            if m:IsA("Model") then
                m:PivotTo(newCF)
            else
                p.CFrame = newCF
            end
        end)
        zeroAssembly(p)
    end

    local function allBodyModels()
        local out = {}
        local chars = WS:FindFirstChild("Characters") or WS
        for _,m in ipairs(chars:GetChildren()) do
            if m:IsA("Model") and m.Name:match("%sBody$") and mainPart(m) then
                out[#out+1] = m
            end
        end
        return out
    end

    local function findNearestBody()
        local root = hrp(); if not root then return nil end
        local best, bestD = nil, math.huge
        for _,m in ipairs(allBodyModels()) do
            local p = mainPart(m)
            if p then
                local d = (p.Position - root.Position).Magnitude
                if d < bestD then
                    bestD, best = d, m
                end
            end
        end
        return best
    end

    local function tpPlayerToBody()
        local m = findNearestBody(); if not m then return end
        local p = mainPart(m); if not p then return end
        local g = groundBelow(p.Position)
        local dest = Vector3.new(p.Position.X, g.Y + 2.5, p.Position.Z)
        local root = hrp(); if not root then return end

        local look = (p.Position - root.Position)
        if look.Magnitude < 1e-3 then
            look = root.CFrame.LookVector
        end

        local cf = CFrame.new(dest, dest + look.Unit)
        local ch = lp.Character
        if ch and ch.Parent then pcall(function() ch:PivotTo(cf) end) end
        pcall(function() root.CFrame = cf end)
        zeroAssembly(root)
    end

    local function bringBodiesFast()
        local root = hrp(); if not root then return end
        local bodies = allBodyModels(); if #bodies == 0 then return end

        local targetPos = groundBelow(root.Position + root.CFrame.LookVector * 2)
        local cf = CFrame.new(
            Vector3.new(targetPos.X, targetPos.Y + 1.5, targetPos.Z),
            root.Position
        )

        for _,m in ipairs(bodies) do
            local snap = snapshotCollision(m)
            setCollisionOff(m)
            if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
            Run.Heartbeat:Wait()
            pcall(function() m:PivotTo(cf) end)
            Run.Heartbeat:Wait()
            restoreCollision(m, snap)
            if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
            setPhysicsRestore(m)
            settleBodyOnGround(m)
            Run.Heartbeat:Wait()
        end
    end

    local function releaseBody()
        local m = findNearestBody(); if not m then return end
        if RF_Stop then
            pcall(function() RF_Stop:FireServer(m) end)
        end
        setPhysicsRestore(m)
    end

    local CAMP_CACHE = nil

    local function fireCenterPart(fire)
        if not fire then return nil end
        local c = fire:FindFirstChild("Center")
            or fire:FindFirstChild("InnerTouchZone")
            or fire:FindFirstChildWhichIsA("BasePart")
            or fire.PrimaryPart
        if c and c:IsA("BasePart") then
            return c
        end
        return nil
    end

    local function resolveCampfireModel()
        if CAMP_CACHE and CAMP_CACHE.Parent then
            return CAMP_CACHE
        end

        local function nameHit(n)
            n = (n or ""):lower()
            if n == "mainfire" then return true end
            if n == "campfire" or n == "camp fire" then return true end
            if n:find("main") and n:find("fire") then return true end
            if n:find("camp") and n:find("fire") then return true end
            return false
        end

        local map = WS:FindFirstChild("Map")
        local cg  = map and map:FindFirstChild("Campground")
        local mf  = cg and (
            cg:FindFirstChild("MainFire")
            or cg:FindFirstChild("Campfire")
            or cg:FindFirstChild("CampFire")
        )

        if mf then
            CAMP_CACHE = mf
            return mf
        end

        if map then
            for _,d in ipairs(map:GetDescendants()) do
                if d:IsA("Model") and nameHit(d.Name) then
                    CAMP_CACHE = d
                    return d
                end
            end
        end

        for _,d in ipairs(WS:GetDescendants()) do
            if d:IsA("Model") and nameHit(d.Name) then
                CAMP_CACHE = d
                return d
            end
        end

        return nil
    end

    local function campTargetCF()
        local fire = resolveCampfireModel(); if not fire then return nil end
        local c = fireCenterPart(fire); if not c then return nil end

        local size = Vector3.new()
        pcall(function()
            local min, max = fire:GetBoundingBox()
            size = (max - min)
        end)

        local pad = math.max(size.X, size.Z)
        if pad == 0 then
            local zone = fire:FindFirstChild("InnerTouchZone")
            if zone and zone:IsA("BasePart") then
                pad = math.max(zone.Size.X, zone.Size.Z)
            end
        end
        if pad == 0 then pad = 6 end

        local posAhead = c.Position + c.CFrame.LookVector * (pad * 0.5 + 2)
        local g = groundBelow(posAhead)
        local pos = Vector3.new(posAhead.X, g.Y + 1.5, posAhead.Z)
        return CFrame.new(pos, c.Position)
    end

    local function sendBodiesToCamp()
        local bodies = allBodyModels(); if #bodies == 0 then return end
        local cf = campTargetCF(); if not cf then return end

        for _,m in ipairs(bodies) do
            local snap = snapshotCollision(m)
            setCollisionOff(m)
            if RF_Start then pcall(function() RF_Start:FireServer(m) end) end
            Run.Heartbeat:Wait()
            pcall(function() m:PivotTo(cf) end)
            Run.Heartbeat:Wait()
            restoreCollision(m, snap)
            if RF_Stop then pcall(function() RF_Stop:FireServer(m) end) end
            setPhysicsRestore(m)
            settleBodyOnGround(m)
            Run.Heartbeat:Wait()
        end
    end

    local CORPSE_Enable = false
    local CORPSE_SPEED = 16
    local CORPSE_JUMP_BUMP = 5.0
    local corpseJumpQueued = 0

    local corpseGui = nil
    local corpseBody = nil
    local corpsePrepared = nil

    local corpseForward = false
    local corpseBack    = false
    local corpseLeft    = false
    local corpseRight   = false

    local function isMyBody(m)
        if not (m and m:IsA("Model")) then return false end
        local char = lp.Character
        if char and (m == char or m:IsDescendantOf(char)) then
            return false
        end

        local name = m.Name or ""
        local lower = name:lower()
        local corpseLike = false

        if name == (lp.Name .. " Body") or name == (lp.DisplayName .. " Body") then
            corpseLike = true
        elseif lower:find("1337b00g", 1, true) then
            corpseLike = true
        elseif name:match("%sBody$") then
            corpseLike = true
        end

        if not corpseLike then
            return false
        end

        local uid = lp.UserId
        local uidStr = tostring(uid)
        local owner = m:GetAttribute("Owner")
        local last  = m:GetAttribute("LastOwner")

        if owner == uid or owner == uidStr or last == uid or last == uidStr then
            return true
        end

        if name == (lp.Name .. " Body") or name == (lp.DisplayName .. " Body") then
            return true
        end

        if lower:find("1337b00g", 1, true) then
            return true
        end

        return false
    end

    local function findMyBodyFast()
        local container = WS:FindFirstChild("Characters") or WS
        for _,m in ipairs(container:GetChildren()) do
            if m:IsA("Model") and isMyBody(m) and mainPart(m) then
                return m
            end
        end
        return nil
    end

    local function findMyBodyDeep()
        local container = WS:FindFirstChild("Characters") or WS
        for _,inst in ipairs(container:GetDescendants()) do
            if inst:IsA("Model") and isMyBody(inst) and mainPart(inst) then
                return inst
            end
        end
        return nil
    end

    local function snapshotCollisionBody(m)
        local t = {}
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                t[p] = { CanCollide = p.CanCollide, CanQuery = p.CanQuery, CanTouch = p.CanTouch }
            end
        end
        return t
    end

    local function setCollisionOffBody(m)
        for _,p in ipairs(m:GetDescendants()) do
            if p:IsA("BasePart") then
                p.CanCollide = false
                p.CanQuery   = false
                p.CanTouch   = false
            end
        end
    end

    local function restoreCollisionBody(m, snap)
        if not snap then return end
        for part,st in pairs(snap) do
            if part and part.Parent then
                part.CanCollide = st.CanCollide
                part.CanQuery   = st.CanQuery
                part.CanTouch   = st.CanTouch
            end
        end
    end

    local function prepBodyForNetwork(m)
        if not m or not m.Parent then return end
        local root = mainPart(m); if not root then return end

        local snap = snapshotCollisionBody(m)
        setCollisionOffBody(m)

        if RF_Start then
            pcall(function() RF_Start:FireServer(m) end)
        end

        Run.Heartbeat:Wait()

        local cf = (m:IsA("Model") and m:GetPivot()) or root.CFrame
        pcall(function()
            if m:IsA("Model") then
                m:PivotTo(cf)
            else
                root.CFrame = cf
            end
        end)

        Run.Heartbeat:Wait()

        restoreCollisionBody(m, snap)

        if RF_Stop then
            pcall(function() RF_Stop:FireServer(m) end)
        end

        setPhysicsRestore(m)
        Run.Heartbeat:Wait()
    end

    local function getCorpseBody()
        if corpseBody and corpseBody.Parent and isMyBody(corpseBody) then
            return corpseBody
        end
        local found = findMyBodyFast() or findMyBodyDeep()
        corpseBody = found
        if found and found ~= corpsePrepared then
            prepBodyForNetwork(found)
            corpsePrepared = found
        end
        return found
    end

    local function moveCorpseDelta(body, delta)
        if not body or not body.Parent then return end
        local p = mainPart(body); if not p then return end
        local cf = (body:IsA("Model") and body:GetPivot()) or p.CFrame
        local newCF = cf + delta
        if body:IsA("Model") then
            body:PivotTo(newCF)
        else
            p.CFrame = newCF
        end
    end

    local function computeCorpseDir()
        local cam = workspace.CurrentCamera
        if not cam then
            return Vector3.new(0,0,0)
        end

        local look = cam.CFrame.LookVector
        local right = cam.CFrame.RightVector

        local f = Vector3.new(look.X, 0, look.Z)
        local r = Vector3.new(right.X, 0, right.Z)

        if f.Magnitude < 1e-4 then
            f = Vector3.new(0,0,-1)
        else
            f = f.Unit
        end

        if r.Magnitude < 1e-4 then
            r = Vector3.new(1,0,0)
        else
            r = r.Unit
        end

        local dir = Vector3.new(0,0,0)
        if corpseForward then dir += f end
        if corpseBack    then dir -= f end
        if corpseRight   then dir += r end
        if corpseLeft    then dir -= r end

        if dir.Magnitude <= 0 then
            return Vector3.new(0,0,0)
        end
        return dir.Unit
    end

    local function bindCorpseButton(btn, setter)
        btn.MouseButton1Down:Connect(function() setter(true) end)
        btn.MouseButton1Up:Connect(function() setter(false) end)
        btn.MouseLeave:Connect(function() setter(false) end)
    end

    local function createCorpseGui()
        if corpseGui then return end

        local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")

        local gui = Instance.new("ScreenGui")
        gui.Name = "CorpseMoveGui"
        gui.ResetOnSpawn = false
        gui.Enabled = false
        gui.Parent = pg

        local frame = Instance.new("Frame")
        frame.Name = "Pad"
        frame.Size = UDim2.new(0, 200, 0, 180)
        frame.Position = UDim2.new(0, 20, 0, 240)
        frame.BackgroundColor3 = Color3.fromRGB(20,20,20)
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Draggable = true
        frame.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = frame

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, -10, 0, 22)
        title.Position = UDim2.new(0, 5, 0, 5)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 16
        title.TextColor3 = Color3.fromRGB(255,255,255)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = "Corpse Move (Hold)"
        title.Parent = frame

        local grid = Instance.new("Frame")
        grid.Name = "Grid"
        grid.Size = UDim2.new(1, -10, 1, -32)
        grid.Position = UDim2.new(0, 5, 0, 30)
        grid.BackgroundTransparency = 1
        grid.Parent = frame

        local layout = Instance.new("UIGridLayout")
        layout.CellSize = UDim2.new(0, 90, 0, 30)
        layout.CellPadding = UDim2.new(0, 5, 0, 5)
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.VerticalAlignment = Enum.VerticalAlignment.Top
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = grid

        local function makeBtn(text, order)
            local b = Instance.new("TextButton")
            b.Name = text.."Button"
            b.LayoutOrder = order or 0
            b.Size = UDim2.new(0, 90, 0, 30)
            b.BackgroundColor3 = Color3.fromRGB(40,40,40)
            b.BorderSizePixel = 0
            b.TextColor3 = Color3.fromRGB(255,255,255)
            b.TextSize = 14
            b.Font = Enum.Font.SourceSansBold
            b.Text = text
            b.Parent = grid
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 6)
            c.Parent = b
            return b
        end

        local btnForward = makeBtn("Forward", 1)
        local btnBack    = makeBtn("Back",    2)
        local btnLeft    = makeBtn("Left",    3)
        local btnRight   = makeBtn("Right",   4)
        local btnJump    = makeBtn("Jump",    5)

        bindCorpseButton(btnForward, function(v) corpseForward = v end)
        bindCorpseButton(btnBack,    function(v) corpseBack    = v end)
        bindCorpseButton(btnLeft,    function(v) corpseLeft    = v end)
        bindCorpseButton(btnRight,   function(v) corpseRight   = v end)

        btnJump.MouseButton1Click:Connect(function()
            corpseJumpQueued = math.min(3, (corpseJumpQueued or 0) + 1)
        end)

        corpseGui = gui
    end

    local function hideCorpseGui()
        if corpseGui then corpseGui.Enabled = false end
        corpseForward, corpseBack, corpseLeft, corpseRight = false,false,false,false
        corpseJumpQueued = 0
    end

    local CORPSE_SCAN_INTERVAL = 0.25
    local corpseScanAcc = 0

    local function updateCorpseUiAndMove(dt)
        if not CORPSE_Enable then
            hideCorpseGui()
            return
        end

        local body = nil
        if corpseBody and corpseBody.Parent and isMyBody(corpseBody) then
            body = corpseBody
        else
            corpseScanAcc += dt
            if corpseScanAcc >= CORPSE_SCAN_INTERVAL then
                corpseScanAcc = 0
                body = getCorpseBody()
            end
        end

        if not (body and body.Parent) then
            corpseBody = nil
            hideCorpseGui()
            return
        end

        if corpseGui then corpseGui.Enabled = true end

        if corpseJumpQueued and corpseJumpQueued > 0 then
            local bumps = corpseJumpQueued
            corpseJumpQueued = 0
            for _ = 1, bumps do
                moveCorpseDelta(body, Vector3.new(0, CORPSE_JUMP_BUMP, 0))
            end
        end

        local dir = computeCorpseDir()
        if dir.Magnitude <= 0 then return end

        local step = CORPSE_SPEED * dt
        moveCorpseDelta(body, dir * step)
    end

    do
        local key = "__CorpseMoveControls_HB__"
        local prev = _G[key]
        if prev and typeof(prev) == "RBXScriptConnection" then
            pcall(function() prev:Disconnect() end)
        end
        _G[key] = Run.Heartbeat:Connect(updateCorpseUiAndMove)
    end

    local SAP_Enable = false
    local sap_seen = setmetatable({}, { __mode = "k" })
    local sap_conns = {}

    local function isSapling(m)
        if not m or not m.Parent then return false end
        if m:IsA("Model") then
            local n = (m.Name or ""):lower()
            if n:find("sapling") then return true end
            if CS:HasTag(m, "Sapling") then return true end
            if m:GetAttribute("IsSapling") == true then return true end
        end
        return false
    end

    local function tryStartDragSapling(m)
        if not SAP_Enable then return end
        if not m or not m.Parent then return end
        if not isSapling(m) then return end
        if sap_seen[m] then return end
        sap_seen[m] = true
        if RF_Start then
            pcall(function() RF_Start:FireServer(m) end)
        end
    end

    local function bindSaplingWatcher(items)
        for _,c in ipairs(sap_conns) do c:Disconnect() end
        table.clear(sap_conns)

        if not SAP_Enable then
            table.clear(sap_seen)
            return
        end

        if not items or not items.Parent then
            items = itemsFolder()
        end

        for _,d in ipairs(items:GetDescendants()) do
            local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
            if m then
                tryStartDragSapling(m)
            end
        end

        sap_conns[#sap_conns+1] = items.DescendantAdded:Connect(function(d)
            local m = d:IsA("Model") and d or d:FindFirstAncestorOfClass("Model")
            if m then
                tryStartDragSapling(m)
            end
        end)

        sap_conns[#sap_conns+1] = WS.ChildAdded:Connect(function(ch)
            if ch.Name == "Items" or ch == items then
                task.defer(function()
                    bindSaplingWatcher(itemsFolder())
                end)
            end
        end)
    end

    local PREC_Enable = false
    local PREC_Speed  = 2.0

    local PREC_BaseLook   = nil
    local PREC_BaseRight  = nil
    local PREC_CamOffset  = nil

    local moveForward = false
    local moveBack    = false
    local moveLeft    = false
    local moveRight   = false
    local moveUp      = false
    local moveDown    = false

    local moveGui     = nil
    local moveConn    = nil
    local moveUiConns = nil

    local origCamType    = nil
    local origCamSubject = nil

    local function clearMoveFlags()
        moveForward = false
        moveBack    = false
        moveLeft    = false
        moveRight   = false
        moveUp      = false
        moveDown    = false
    end

    local function destroyMoveGui()
        clearMoveFlags()
        if moveUiConns then
            for _,c in ipairs(moveUiConns) do pcall(function() c:Disconnect() end) end
        end
        moveUiConns = nil
        if moveGui then pcall(function() moveGui:Destroy() end) end
        moveGui = nil
        if moveConn then moveConn:Disconnect(); moveConn = nil end
    end

    local function ensureMoveHeartbeat()
        if moveConn then return end

        moveConn = Run.Heartbeat:Connect(function(dt)
            if not PREC_Enable then return end
            local root = hrp(); if not root then return end
            if not PREC_BaseLook or not PREC_BaseRight or not PREC_CamOffset then return end

            local rootPos = root.Position

            local cam = workspace.CurrentCamera
            if cam then
                local camPos = rootPos + PREC_CamOffset
                cam.CFrame = CFrame.new(camPos, camPos + PREC_BaseLook)
            end

            local forward3D = PREC_BaseLook
            local right3D   = PREC_BaseRight

            local forward = Vector3.new(forward3D.X, 0, forward3D.Z)
            if forward.Magnitude < 1e-4 then forward = Vector3.new(0, 0, -1) else forward = forward.Unit end

            local right = Vector3.new(right3D.X, 0, right3D.Z)
            if right.Magnitude < 1e-4 then right = Vector3.new(1, 0, 0) else right = right.Unit end

            local up = Vector3.new(0, 1, 0)

            local dir = Vector3.new(0, 0, 0)
            if moveForward then dir += forward end
            if moveBack    then dir -= forward end
            if moveRight   then dir += right   end
            if moveLeft    then dir -= right   end
            if moveUp      then dir += up      end
            if moveDown    then dir -= up      end

            if dir.Magnitude <= 0 then return end
            dir = dir.Unit

            local step   = PREC_Speed * dt
            local newPos = rootPos + dir * step

            local look = PREC_BaseLook or root.CFrame.LookVector
            if look.Magnitude < 1e-4 then look = Vector3.new(0, 0, -1) end

            local newCF = CFrame.new(newPos, newPos + look.Unit)
            root.CFrame = newCF
            zeroAssembly(root)
        end)
    end

    local function bindMoveButton(btn, setter)
        local c1 = btn.MouseButton1Down:Connect(function() setter(true) end)
        local c2 = btn.MouseButton1Up:Connect(function() setter(false) end)
        local c3 = btn.MouseLeave:Connect(function() setter(false) end)
        moveUiConns[#moveUiConns+1] = c1
        moveUiConns[#moveUiConns+1] = c2
        moveUiConns[#moveUiConns+1] = c3
    end

    local function createMoveGui()
        if moveGui then return end

        local pg = lp:FindFirstChildOfClass("PlayerGui") or lp:WaitForChild("PlayerGui")

        local gui = Instance.new("ScreenGui")
        gui.Name = "PrecisionMoveGui"
        gui.ResetOnSpawn = false
        gui.Parent = pg

        moveUiConns = {}

        local panel = Instance.new("Frame")
        panel.Name = "Panel"
        panel.Size = UDim2.new(0, 248, 0, 268)
        panel.Position = UDim2.new(0, 20, 0.5, -134)
        panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        panel.BackgroundTransparency = 0.12
        panel.BorderSizePixel = 0
        panel.Active = true
        panel.Draggable = true
        panel.Parent = gui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = panel

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 10)
        pad.PaddingRight = UDim.new(0, 10)
        pad.PaddingTop = UDim.new(0, 10)
        pad.PaddingBottom = UDim.new(0, 10)
        pad.Parent = panel

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Size = UDim2.new(1, 0, 0, 18)
        title.BackgroundTransparency = 1
        title.TextColor3 = Color3.fromRGB(255, 255, 255)
        title.TextSize = 14
        title.Font = Enum.Font.SourceSansBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Text = "Precision Move"
        title.Parent = panel

        local grid = Instance.new("Frame")
        grid.Name = "Grid"
        grid.Size = UDim2.new(1, 0, 0, 156)
        grid.Position = UDim2.new(0, 0, 0, 22)
        grid.BackgroundTransparency = 1
        grid.Parent = panel

        local layout = Instance.new("UIGridLayout")
        layout.CellSize = UDim2.new(0, 72, 0, 72)
        layout.CellPadding = UDim2.new(0, 6, 0, 6)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.VerticalAlignment   = Enum.VerticalAlignment.Center
        layout.FillDirection       = Enum.FillDirection.Horizontal
        layout.SortOrder           = Enum.SortOrder.LayoutOrder
        layout.Parent = grid

        local function makeButton(text, order)
            local b = Instance.new("TextButton")
            b.LayoutOrder = order or 0
            b.Size = UDim2.new(0, 72, 0, 72)
            b.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            b.BorderSizePixel = 0
            b.TextColor3 = Color3.fromRGB(255, 255, 255)
            b.TextSize = 18
            b.TextWrapped = true
            b.Font = Enum.Font.SourceSansBold
            b.Text = text
            b.AutoButtonColor = true
            b.Parent = grid

            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 8)
            c.Parent = b

            return b
        end

        local btnUp      = makeButton("Up",      1)
        local btnForward = makeButton("Forward", 2)
        local btnDown    = makeButton("Down",    3)
        local btnLeft    = makeButton("Left",    4)
        local btnBack    = makeButton("Back",    5)
        local btnRight   = makeButton("Right",   6)

        bindMoveButton(btnUp,      function(v) moveUp      = v end)
        bindMoveButton(btnDown,    function(v) moveDown    = v end)
        bindMoveButton(btnForward, function(v) moveForward = v end)
        bindMoveButton(btnBack,    function(v) moveBack    = v end)
        bindMoveButton(btnLeft,    function(v) moveLeft    = v end)
        bindMoveButton(btnRight,   function(v) moveRight   = v end)

        local sliderFrame = Instance.new("Frame")
        sliderFrame.Name = "SpeedSliderFrame"
        sliderFrame.Size = UDim2.new(1, 0, 0, 60)
        sliderFrame.Position = UDim2.new(0, 0, 0, 186)
        sliderFrame.BackgroundTransparency = 1
        sliderFrame.Parent = panel

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 0, 18)
        label.Position = UDim2.new(0, 0, 0, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextSize = 14
        label.Font = Enum.Font.SourceSans
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Text = "Speed: 2.00"
        label.Parent = sliderFrame

        local bar = Instance.new("Frame")
        bar.Name = "Bar"
        bar.Size = UDim2.new(1, -8, 0, 6)
        bar.Position = UDim2.new(0, 4, 0, 28)
        bar.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        bar.BorderSizePixel = 0
        bar.Parent = sliderFrame

        local barCorner = Instance.new("UICorner")
        barCorner.CornerRadius = UDim.new(0, 3)
        barCorner.Parent = bar

        local thumb = Instance.new("TextButton")
        thumb.Name = "Thumb"
        thumb.Size = UDim2.new(0, 14, 0, 22)
        thumb.Position = UDim2.new(0, 0, 0.5, -11)
        thumb.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
        thumb.BorderSizePixel = 0
        thumb.Text = ""
        thumb.AutoButtonColor = true
        thumb.Parent = bar

        local thumbCorner = Instance.new("UICorner")
        thumbCorner.CornerRadius = UDim.new(0, 7)
        thumbCorner.Parent = thumb

        local MIN_SPEED = 0.1
        local MAX_SPEED = 25

        local dragging = false
        local dragInput = nil

        local function getBarWidth()
            local w = bar.AbsoluteSize.X
            if w <= 0 then w = bar.Size.X.Offset end
            if w <= 0 then w = 140 end
            return w
        end

        local function applyAlpha(alpha)
            alpha = math.clamp(alpha, 0, 1)
            local speed = MIN_SPEED + (MAX_SPEED - MIN_SPEED) * alpha
            PREC_Speed = speed
            label.Text = string.format("Speed: %.2f", speed)

            local w = getBarWidth()
            local thumbX = alpha * w
            local halfThumb = thumb.Size.X.Offset / 2
            thumb.Position = UDim2.new(0, math.floor(thumbX - halfThumb), 0.5, -thumb.Size.Y.Offset/2)
        end

        local function setFromX(screenX)
            local barPos = bar.AbsolutePosition.X
            local w = getBarWidth()
            local rel = (screenX - barPos) / w
            applyAlpha(rel)
        end

        moveUiConns[#moveUiConns+1] = thumb.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = input
                setFromX(input.Position.X)
            end
        end)

        moveUiConns[#moveUiConns+1] = thumb.InputEnded:Connect(function(input)
            if input == dragInput then dragging = false; dragInput = nil end
        end)

        moveUiConns[#moveUiConns+1] = bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = input
                setFromX(input.Position.X)
            end
        end)

        moveUiConns[#moveUiConns+1] = UIS.InputChanged:Connect(function(input)
            if dragging then setFromX(input.Position.X) end
        end)

        moveUiConns[#moveUiConns+1] = UIS.InputEnded:Connect(function(input)
            if input == dragInput then dragging = false; dragInput = nil end
        end)

        applyAlpha(0.22)

        moveGui = gui
        ensureMoveHeartbeat()
    end

    local function setPrecisionEnabled(on)
        local cam = workspace.CurrentCamera
        local root = hrp()

        if on and not PREC_Enable then
            PREC_Enable = true

            if cam and root then
                if not origCamType then origCamType = cam.CameraType end
                if not origCamSubject then origCamSubject = cam.CameraSubject end

                local baseCF = cam.CFrame
                PREC_BaseLook  = baseCF.LookVector
                PREC_BaseRight = baseCF.RightVector
                PREC_CamOffset = baseCF.Position - root.Position

                cam.CameraType = Enum.CameraType.Scriptable
            end

            createMoveGui()
        elseif (not on) and PREC_Enable then
            PREC_Enable = false
            destroyMoveGui()
            if cam then
                if origCamType then cam.CameraType = origCamType end
                if origCamSubject then cam.CameraSubject = origCamSubject end
            end
            origCamType, origCamSubject = nil, nil
        end
    end

    tab:Section({ Title = "Item Recovery" })
    tab:Button({ Title = "Own All Items",    Callback = function() ownAll() end })
    tab:Button({ Title = "Disown All Items", Callback = function() disownAll() end })
    tab:Button({ Title = "Wake (Gentle)",    Callback = function() wakeGentle() end })
    tab:Button({ Title = "De-overlap",       Callback = function() deoverlap() end })
    tab:Button({ Title = "Nudge Items",      Callback = function() nudgeAll() end })
    tab:Button({ Title = "Mine Ownership",   Callback = function() mineOwnership() end })
    tab:Button({ Title = "Server Ownership", Callback = function() serverOwnership() end })

    tab:Section({ Title = "Drag Remotes" })
    tab:Button({ Title = "Start Drag Nearby", Callback = function() startDragAll() end })
    tab:Button({ Title = "Stop Drag Nearby",  Callback = function() stopDragAll() end })

    tab:Section({ Title = "Body Tests" })
    tab:Button({ Title = "TP To Body",             Callback = function() tpPlayerToBody() end })
    tab:Button({ Title = "Bring Body (Fast Drag)", Callback = function() bringBodiesFast(); bringBodiesFast() end })
    tab:Button({ Title = "Release Body",           Callback = function() releaseBody() end })
    tab:Button({ Title = "Send All Bodies To Camp", Callback = function() sendBodiesToCamp(); sendBodiesToCamp() end })

    tab:Section({ Title = "Corpse Movement" })
    if tab.Toggle then
        tab:Toggle({
            Title = "Corpse Movement Controls",
            Default = false,
            Callback = function(v)
                CORPSE_Enable = v and true or false
                if CORPSE_Enable then
                    createCorpseGui()
                else
                    hideCorpseGui()
                end
                corpseBody = nil
                corpsePrepared = nil
                corpseScanAcc = CORPSE_SCAN_INTERVAL
            end
        })
    else
        tab:Button({
            Title = "Corpse Movement Controls: OFF",
            Callback = function(btn)
                local newState = not CORPSE_Enable
                CORPSE_Enable = newState
                if newState then
                    createCorpseGui()
                else
                    hideCorpseGui()
                end
                corpseBody = nil
                corpsePrepared = nil
                corpseScanAcc = CORPSE_SCAN_INTERVAL
                if btn and btn.SetTitle then
                    btn:SetTitle("Corpse Movement Controls: " .. (newState and "ON" or "OFF"))
                end
            end
        })
    end

    tab:Section({ Title = "Protection" })
    if tab.Toggle then
        tab:Toggle({
            Title = "Sapling Protection",
            Default = false,
            Callback = function(v)
                SAP_Enable = v and true or false
                bindSaplingWatcher(itemsFolder())
            end
        })
    else
        tab:Button({
            Title = "Sapling Protection: OFF",
            Callback = function(btn)
                SAP_Enable = not SAP_Enable
                if btn and btn.SetTitle then
                    btn:SetTitle("Sapling Protection: " .. (SAP_Enable and "ON" or "OFF"))
                end
                bindSaplingWatcher(itemsFolder())
            end
        })
    end

    tab:Section({ Title = "Precision Movement" })
    if tab.Toggle then
        tab:Toggle({
            Title = "Precision Movement Controls",
            Default = false,
            Callback = function(v)
                setPrecisionEnabled(v)
            end
        })
    else
        tab:Button({
            Title = "Precision Movement Controls: OFF",
            Callback = function(btn)
                local newState = not PREC_Enable
                if btn and btn.SetTitle then
                    btn:SetTitle("Precision Movement Controls: " .. (newState and "ON" or "OFF"))
                end
                setPrecisionEnabled(newState)
            end
        })
    end

    --=====================================================
    -- Auto Revive (Bandage/MedKit only)  [PATCHED IN]
    --=====================================================
    local PPS = game:GetService("ProximityPromptService")

    local AR_Enable = false
    local AR_Running = false
    local AR_Busy = false
    local AR_InProgress = {}
    local AR_HealingAvailable = false

    local AR_SCAN_INTERVAL = 0.8
    local AR_MAX_ATTEMPTS = 3
    local AR_CONFIRM_WAIT = 2.2
    local AR_CONFIRM_STEP = 0.12
    local AR_STAY_SEC = 5.0

    local AR_STAND_DIST = 3.0
    local AR_STAND_UP   = 2.0

    local invConnA, invConnR
    local bpConnA, bpConnR
    local chConnA, chConnR, chConnC

    local function hasItemNamed(name)
        if not name then return false end
        local inv = lp:FindFirstChild("Inventory")
        if inv and inv:FindFirstChild(name) then return true end
        local bp = lp:FindFirstChild("Backpack")
        if bp and bp:FindFirstChild(name) then return true end
        local ch = lp.Character
        if ch and ch:FindFirstChild(name) then return true end
        return false
    end

    local function recomputeHealingAvailable()
        AR_HealingAvailable = hasItemNamed("Bandage") or hasItemNamed("MedKit")
        return AR_HealingAvailable
    end

    local function disconnectConn(c)
        if c then pcall(function() c:Disconnect() end) end
    end

    local function startHealingWatch()
        disconnectConn(invConnA); disconnectConn(invConnR)
        disconnectConn(bpConnA);  disconnectConn(bpConnR)
        disconnectConn(chConnA);  disconnectConn(chConnR); disconnectConn(chConnC)

        local function bind(container)
            if not container then return nil, nil end
            local a = container.ChildAdded:Connect(function() recomputeHealingAvailable() end)
            local r = container.ChildRemoved:Connect(function() recomputeHealingAvailable() end)
            return a, r
        end

        task.spawn(function()
            local inv = lp:WaitForChild("Inventory", 10)
            if inv then invConnA, invConnR = bind(inv) end

            local bp = lp:FindFirstChild("Backpack") or lp:WaitForChild("Backpack", 10)
            if bp then bpConnA, bpConnR = bind(bp) end

            local function bindChar(ch)
                disconnectConn(chConnA); disconnectConn(chConnR)
                if ch then chConnA, chConnR = bind(ch) end
            end

            bindChar(lp.Character)
            chConnC = lp.CharacterAdded:Connect(function(ch)
                task.defer(function() bindChar(ch) end)
            end)

            recomputeHealingAvailable()
        end)
    end

    local function bodyNameMatchesPlayer(bodyName, plr)
        if type(bodyName) ~= "string" or not plr then return false end
        local n1 = tostring(plr.Name or "") .. " Body"
        local n2 = tostring(plr.DisplayName or "") .. " Body"
        return bodyName == n1 or bodyName == n2
    end

    local function findPlayerBodyModel(plr)
        local chars = WS:FindFirstChild("Characters") or WS
        for _,child in ipairs(chars:GetChildren()) do
            if child and child:IsA("Model") and bodyNameMatchesPlayer(child.Name, plr) then
                return child
            end
        end
        return nil
    end

    local function bodyGoneForPlayer(plr, originalBody)
        if originalBody and (not originalBody.Parent) then return true end
        return findPlayerBodyModel(plr) == nil
    end

    local function findRevivePrompt(body)
        if not (body and body.Parent) then return nil end
        local best = nil
        local bestScore = -1

        for _,d in ipairs(body:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local a = tostring(d.ActionText or ""):lower()
                local o = tostring(d.ObjectText or ""):lower()
                local n = tostring(d.Name or ""):lower()

                local score = 0
                if a:find("revive", 1, true) then score += 3 end
                if o:find("revive", 1, true) then score += 2 end
                if n:find("revive", 1, true) then score += 1 end

                if score > bestScore then
                    bestScore = score
                    best = d
                end
            end
        end

        if best then return best end
        return body:FindFirstChildWhichIsA("ProximityPrompt", true)
    end

    local function triggerPrompt(prompt)
        if not (prompt and prompt.Parent) then return false end
        pcall(function() prompt.Enabled = true end)
        pcall(function() prompt.RequiresLineOfSight = false end)
        pcall(function()
            if typeof(prompt.HoldDuration) == "number" and prompt.HoldDuration > 0.12 then
                prompt.HoldDuration = 0.12
            end
        end)

        local ok = pcall(function()
            PPS:TriggerPrompt(prompt)
        end)
        if ok then return true end

        local hd = 0.08
        pcall(function()
            if typeof(prompt.HoldDuration) == "number" then
                hd = math.clamp(prompt.HoldDuration, 0.02, 0.12)
            end
        end)

        local ok2 = pcall(function()
            prompt:InputHoldBegin()
            task.wait(hd)
            prompt:InputHoldEnd()
        end)
        return ok2
    end

    local function teleportToCF(cf)
        local root = hrp()
        if not root then return false end
        local ch = lp.Character
        if ch and ch.Parent then pcall(function() ch:PivotTo(cf) end) end
        local ok = pcall(function() root.CFrame = cf end)
        if ok then pcall(function() zeroAssembly(root) end) end
        return ok
    end

    local function teleportNearBody(body)
        local root = hrp()
        local bp = mainPart(body)
        if not (root and bp) then return false end

        local bodyPos = bp.Position
        local rootPos = root.Position
        local dir = (rootPos - bodyPos)
        if dir.Magnitude < 0.5 then
            dir = -bp.CFrame.LookVector
        else
            dir = dir.Unit
        end

        local standPos = bodyPos + dir * AR_STAND_DIST + Vector3.new(0, AR_STAND_UP, 0)
        local g = groundBelow(standPos)
        standPos = Vector3.new(standPos.X, g.Y + AR_STAND_UP, standPos.Z)

        return teleportToCF(CFrame.new(standPos, bodyPos))
    end

    local function collectDownedQueue()
        local chars = WS:FindFirstChild("Characters") or WS
        local out = {}

        local root = hrp()
        local origin = root and root.Position or Vector3.new(0,0,0)

        local players = Players:GetPlayers()

        for _,m in ipairs(chars:GetChildren()) do
            if m:IsA("Model") then
                local nm = tostring(m.Name or "")
                if nm:match("%sBody$") then
                    local owner = nil
                    for _,p in ipairs(players) do
                        if p ~= lp and bodyNameMatchesPlayer(nm, p) then
                            owner = p
                            break
                        end
                    end
                    if owner and not AR_InProgress[owner.UserId] and mainPart(m) then
                        local ppart = mainPart(m)
                        local dist = ppart and (ppart.Position - origin).Magnitude or math.huge
                        out[#out+1] = { plr = owner, body = m, dist = dist }
                    end
                end
            end
        end

        table.sort(out, function(a,b)
            if a.dist == b.dist then
                return tostring(a.plr.Name or "") < tostring(b.plr.Name or "")
            end
            return a.dist < b.dist
        end)

        return out
    end

    local function tryReviveOne(plr, body, startCF)
        if not (plr and body and startCF) then return false end
        if AR_InProgress[plr.UserId] then return false end
        AR_InProgress[plr.UserId] = true

        local ok = false

        local function finally()
            pcall(function() teleportToCF(startCF) end)
            AR_InProgress[plr.UserId] = nil
        end

        local success = xpcall(function()
            if not recomputeHealingAvailable() then return end

            local prompt = findRevivePrompt(body)
            if not prompt then return end

            local attempt = 0
            while attempt < AR_MAX_ATTEMPTS do
                attempt += 1
                if not (body and body.Parent) then break end
                if bodyGoneForPlayer(plr, body) then ok = true break end

                teleportNearBody(body)
                task.wait(0.06)
                triggerPrompt(prompt)

                local t0 = os.clock()
                while os.clock() - t0 < AR_CONFIRM_WAIT do
                    if bodyGoneForPlayer(plr, body) then ok = true break end
                    task.wait(AR_CONFIRM_STEP)
                end
                if ok then break end

                task.wait(0.18)
                prompt = findRevivePrompt(body) or prompt
            end

            if ok then
                local stayUntil = os.clock() + AR_STAY_SEC
                while os.clock() < stayUntil do
                    task.wait(0.2)
                end

                if not bodyGoneForPlayer(plr, body) then
                    local extra = 0
                    while extra < AR_MAX_ATTEMPTS do
                        extra += 1
                        if bodyGoneForPlayer(plr, body) then break end
                        prompt = findRevivePrompt(body) or prompt
                        if prompt then triggerPrompt(prompt) end

                        local t1 = os.clock()
                        while os.clock() - t1 < AR_CONFIRM_WAIT do
                            if bodyGoneForPlayer(plr, body) then break end
                            task.wait(AR_CONFIRM_STEP)
                        end
                        if bodyGoneForPlayer(plr, body) then break end
                        task.wait(0.15)
                    end
                    ok = bodyGoneForPlayer(plr, body)
                end
            end
        end, debug.traceback)

        finally()
        return success and ok
    end

    local function runRevivePass()
        if AR_Busy then return end
        if not recomputeHealingAvailable() then return end

        local root = hrp()
        if not root then return end

        AR_Busy = true
        local startCF = root.CFrame

        local queue = collectDownedQueue()
        for _,it in ipairs(queue) do
            if not recomputeHealingAvailable() then break end
            if it and it.plr and it.body and it.body.Parent then
                tryReviveOne(it.plr, it.body, startCF)
                task.wait(0.08)
                local r2 = hrp()
                if r2 then startCF = r2.CFrame end
            end
        end

        AR_Busy = false
    end

    local function startAutoRevive()
        if AR_Running then return end
        AR_Running = true

        local key = "__AutoRevive_Loop__"
        local prev = _G[key]
        if prev and typeof(prev) == "thread" then
            _G[key] = nil
        end

        _G[key] = task.spawn(function()
            while AR_Running do
                task.wait(AR_SCAN_INTERVAL)
                if not (AR_Running and AR_Enable) then continue end
                if AR_Busy then continue end
                if not recomputeHealingAvailable() then continue end
                local q = collectDownedQueue()
                if #q > 0 then
                    runRevivePass()
                end
            end
        end)
    end

    local function stopAutoRevive()
        AR_Running = false
    end

    tab:Section({ Title = "Auto Revive" })

    if tab.Toggle then
        tab:Toggle({
            Title = "Auto Revive (Bandage/MedKit only)",
            Default = false,
            Callback = function(v)
                AR_Enable = v and true or false
                if AR_Enable then startAutoRevive() else stopAutoRevive() end
            end
        })
    else
        tab:Button({
            Title = "Auto Revive: OFF",
            Callback = function(btn)
                AR_Enable = not AR_Enable
                if btn and btn.SetTitle then
                    btn:SetTitle("Auto Revive: " .. (AR_Enable and "ON" or "OFF"))
                end
                if AR_Enable then startAutoRevive() else stopAutoRevive() end
            end
        })
    end

    tab:Button({
        Title = "Revive Now",
        Callback = function()
            task.spawn(function()
                runRevivePass()
            end)
        end
    })

    startHealingWatch()
    recomputeHealingAvailable()
end
