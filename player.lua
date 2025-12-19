--=====================================================
-- 1337 Nights | Player Tab (mobile fly only, optimized)
--=====================================================
return function(C, R, UI)
    local Players    = C.Services.Players
    local RunService = C.Services.RunService or game:GetService("RunService")
    local UIS        = C.Services.UIS        or game:GetService("UserInputService")

    local lp = Players.LocalPlayer
    local tab = UI.Tabs and UI.Tabs.Player
    assert(tab, "Player tab not found in UI")

    local function clearInstance(x) if x then pcall(function() x:Destroy() end) end end
    local function disconnectConn(c) if c then pcall(function() c:Disconnect() end) end end

    local function humanoid()
        local ch = lp.Character
        return ch and ch:FindFirstChildOfClass("Humanoid")
    end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch:FindFirstChild("HumanoidRootPart")
    end

    C.State = C.State or {}
    do
        local key = "__PlayerTab1337Nights"
        local prev = C.State[key]
        if prev and prev.__cleanup then pcall(prev.__cleanup) end
        C.State[key] = {}
    end
    local BAG = C.State["__PlayerTab1337Nights"]

    local flyEnabled = false
    local FLYING = false
    local flySpeed = 3

    local walkSpeedValue = 50
    local speedEnabled = true

    local noclipEnabled = false
    local infiniteJumpEnabled = true

    local bodyGyro, bodyVelocity
    local flyRenderConn, flyCharConn

    local speedConn

    local noclipAddedConn, noclipCharConn, noclipTimerConn
    local noclipTouched = {}   -- [BasePart]=true
    local noclipOrig    = {}   -- [BasePart]=original CanCollide bool
    local noclipLastReassert = 0

    local jumpConn

    local cachedControlModule = nil
    local cachedControlOk = false

    local function cacheControlModule()
        cachedControlModule = nil
        cachedControlOk = false
        local ok, cm = pcall(function()
            local ps = lp:FindFirstChildOfClass("PlayerScripts") or lp:WaitForChild("PlayerScripts", 2)
            if not ps then return nil end
            local pm = ps:FindFirstChild("PlayerModule") or ps:WaitForChild("PlayerModule", 2)
            if not pm then return nil end
            local mod = pm:FindFirstChild("ControlModule") or pm:WaitForChild("ControlModule", 2)
            if not mod then return nil end
            return require(mod)
        end)
        if ok and cm and type(cm.GetMoveVector) == "function" then
            cachedControlModule = cm
            cachedControlOk = true
        end
    end

    local function ensureBodyMovers(root)
        clearInstance(bodyGyro); bodyGyro = nil
        clearInstance(bodyVelocity); bodyVelocity = nil

        bodyGyro = Instance.new("BodyGyro")
        bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bodyGyro.P = 1000
        bodyGyro.D = 50
        bodyGyro.Parent = root

        bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        bodyVelocity.Velocity = Vector3.zero
        bodyVelocity.Parent = root
    end

    local function startMobileFly()
        if FLYING then return end
        if not UIS.TouchEnabled then return end

        local root = hrp()
        local hum = humanoid()
        if not root or not hum then return end

        FLYING = true
        cacheControlModule()
        ensureBodyMovers(root)

        disconnectConn(flyRenderConn); flyRenderConn = nil
        flyRenderConn = RunService.RenderStepped:Connect(function()
            if not FLYING then return end
            local r = hrp()
            local h = humanoid()
            local cam = workspace.CurrentCamera
            if not r or not h or not cam then return end

            if bodyGyro == nil or bodyVelocity == nil or bodyGyro.Parent ~= r or bodyVelocity.Parent ~= r then
                ensureBodyMovers(r)
            end

            h.PlatformStand = true
            bodyGyro.CFrame = cam.CFrame

            local move = Vector3.zero
            if cachedControlOk and cachedControlModule then
                local ok, mv = pcall(function() return cachedControlModule:GetMoveVector() end)
                if ok and typeof(mv) == "Vector3" then move = mv end
            else
                pcall(cacheControlModule)
            end

            local spd = (flySpeed * 50)
            local vel = Vector3.zero
            vel = vel + cam.CFrame.RightVector * (move.X * spd)
            vel = vel - cam.CFrame.LookVector  * (move.Z * spd)
            bodyVelocity.Velocity = vel
        end)
    end

    local function stopMobileFly()
        FLYING = false
        disconnectConn(flyRenderConn); flyRenderConn = nil
        local hum = humanoid()
        if hum then hum.PlatformStand = false end
        clearInstance(bodyVelocity); bodyVelocity = nil
        clearInstance(bodyGyro); bodyGyro = nil
    end

    local function startFly()
        flyEnabled = true
        startMobileFly()
    end

    local function stopFly()
        flyEnabled = false
        stopMobileFly()
    end

    local function setWalkSpeed(val)
        local hum = humanoid()
        if hum then hum.WalkSpeed = val end
    end

    local function startSpeedEnforcer()
        disconnectConn(speedConn); speedConn = nil
        speedConn = RunService.Heartbeat:Connect(function()
            if not speedEnabled then return end
            local hum = humanoid()
            if hum and hum.WalkSpeed ~= walkSpeedValue then
                hum.WalkSpeed = walkSpeedValue
            end
        end)
    end

    --========================
    -- Noclip (cheap + restores on OFF)
    --========================
    local function setPartNoclip(part)
        if not part or not part:IsA("BasePart") then return end

        if noclipOrig[part] == nil then
            noclipOrig[part] = part.CanCollide
        end

        if part.CanCollide ~= false then
            part.CanCollide = false
        end

        noclipTouched[part] = true
    end

    local function restoreNoclipParts()
        for part, orig in pairs(noclipOrig) do
            if part and part.Parent and part:IsA("BasePart") then
                part.CanCollide = orig
            end
        end
    end

    local function applyNoclipToCharacter(ch)
        if not ch then return end
        for _, inst in ipairs(ch:GetDescendants()) do
            if inst:IsA("BasePart") then
                setPartNoclip(inst)
            end
        end
    end

    local function hookNoclipDescendants(ch)
        disconnectConn(noclipAddedConn); noclipAddedConn = nil
        if not ch then return end
        noclipAddedConn = ch.DescendantAdded:Connect(function(inst)
            if not noclipEnabled then return end
            if inst:IsA("BasePart") then
                setPartNoclip(inst)
            end
        end)
    end

    local function startNoclip()
        if noclipEnabled then return end
        noclipEnabled = true

        noclipTouched = {}
        noclipOrig = {}

        local ch = lp.Character
        if ch then
            applyNoclipToCharacter(ch)
            hookNoclipDescendants(ch)
        end

        disconnectConn(noclipCharConn); noclipCharConn = nil
        noclipCharConn = lp.CharacterAdded:Connect(function(newCh)
            if not noclipEnabled then return end
            task.defer(function()
                noclipTouched = {}
                noclipOrig = {}
                applyNoclipToCharacter(newCh)
                hookNoclipDescendants(newCh)
            end)
        end)

        disconnectConn(noclipTimerConn); noclipTimerConn = nil
        noclipLastReassert = 0
        noclipTimerConn = RunService.Heartbeat:Connect(function()
            if not noclipEnabled then return end
            local now = os.clock()
            if (now - noclipLastReassert) < 0.5 then return end
            noclipLastReassert = now
            for part in pairs(noclipTouched) do
                if part and part.Parent and part:IsA("BasePart") and part.CanCollide ~= false then
                    part.CanCollide = false
                end
            end
        end)
    end

    local function stopNoclip()
        if not noclipEnabled then return end
        noclipEnabled = false

        disconnectConn(noclipAddedConn); noclipAddedConn = nil
        disconnectConn(noclipCharConn);  noclipCharConn  = nil
        disconnectConn(noclipTimerConn); noclipTimerConn = nil

        restoreNoclipParts()

        noclipTouched = {}
        noclipOrig = {}
    end

    --========================
    -- Infinite Jump
    --========================
    local function startInfJump()
        disconnectConn(jumpConn); jumpConn = nil
        jumpConn = UIS.JumpRequest:Connect(function()
            local hum = humanoid()
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end

    local function stopInfJump()
        disconnectConn(jumpConn); jumpConn = nil
    end

    --========================
    -- Cleanup (module reload safety)
    --========================
    BAG.__cleanup = function()
        if flyEnabled or FLYING then stopFly() end
        disconnectConn(flyCharConn); flyCharConn = nil

        disconnectConn(speedConn); speedConn = nil

        if noclipEnabled then
            stopNoclip()
        else
            disconnectConn(noclipAddedConn); noclipAddedConn = nil
            disconnectConn(noclipCharConn);  noclipCharConn  = nil
            disconnectConn(noclipTimerConn); noclipTimerConn = nil
        end

        if infiniteJumpEnabled then stopInfJump() else disconnectConn(jumpConn); jumpConn = nil end

        cachedControlModule = nil
        cachedControlOk = false
    end

    -- Start the speed enforcer once per module load (and ensure old one is cleaned up)
    startSpeedEnforcer()

    --========================
    -- UI Controls
    --========================
    tab:Section({ Title = "Movement Controls", Icon = "activity" })

    tab:Slider({
        Title = "Fly Speed",
        Value = { Min = 1, Max = 20, Default = 3 },
        Callback = function(v)
            flySpeed = tonumber(v) or flySpeed
        end
    })

    tab:Toggle({
        Title = "Enable Fly (Mobile)",
        Value = false,
        Callback = function(state)
            if state then startFly() else stopFly() end
        end
    })

    tab:Divider()
    tab:Section({ Title = "Walk Speed", Icon = "walk" })

    tab:Slider({
        Title = "Speed",
        Value = { Min = 16, Max = 150, Default = 50 },
        Callback = function(v)
            walkSpeedValue = tonumber(v) or walkSpeedValue
            if speedEnabled then setWalkSpeed(walkSpeedValue) end
        end
    })

    tab:Toggle({
        Title = "Enable Speed",
        Value = true,
        Callback = function(state)
            speedEnabled = state
            if state then setWalkSpeed(walkSpeedValue) else setWalkSpeed(16) end
        end
    })

    tab:Divider()
    tab:Section({ Title = "Modifiers", Icon = "hammer" })

    tab:Toggle({
        Title = "Noclip",
        Value = false,
        Callback = function(state)
            if state then startNoclip() else stopNoclip() end
        end
    })

    tab:Toggle({
        Title = "Infinite Jump",
        Value = true,
        Callback = function(state)
            infiniteJumpEnabled = state
            if state then startInfJump() else stopInfJump() end
        end
    })

    if infiniteJumpEnabled then startInfJump() end
    if speedEnabled then setWalkSpeed(walkSpeedValue) end

    --========================
    -- Character lifecycle
    --========================
    disconnectConn(flyCharConn); flyCharConn = nil
    flyCharConn = lp.CharacterAdded:Connect(function()
        task.defer(function()
            cachedControlModule = nil
            cachedControlOk = false

            if flyEnabled then
                stopFly()
                startFly()
            end

            if speedEnabled then
                setWalkSpeed(walkSpeedValue)
            end

            if noclipEnabled then
                noclipTouched = {}
                noclipOrig = {}
                local ch = lp.Character
                if ch then
                    applyNoclipToCharacter(ch)
                    hookNoclipDescendants(ch)
                end
            end
        end)
    end)
end
