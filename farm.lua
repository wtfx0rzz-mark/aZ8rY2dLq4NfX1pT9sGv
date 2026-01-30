local Players = game:GetService("Players")
local WS = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local lp = Players.LocalPlayer
if not lp then return end
local pg = lp:WaitForChild("PlayerGui")

if _G.__TreeHitLogger and type(_G.__TreeHitLogger.Destroy) == "function" then
    pcall(function() _G.__TreeHitLogger.Destroy() end)
end

local STATE = {
    AutoClosest = true,
    Locked = false,
    UpdateEvery = 0.20,
    MaxLines = 240,
}

local conns = {}
local hbConn
local targetModel
local targetPart
local targetLockedAt
local last = {
    hit = nil,
    destroyed = nil,
    full = nil,
    parent = nil,
    pos = nil,
    dist3 = nil,
    distXZ = nil,
}

local function now() return os.clock() end

local function safeFullName(inst)
    if typeof(inst) ~= "Instance" then return tostring(inst) end
    local ok, s = pcall(function() return inst:GetFullName() end)
    return ok and s or tostring(inst)
end

local function chr()
    return lp.Character or lp.CharacterAdded:Wait()
end

local function hrp()
    local ch = lp.Character
    return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function clampLines(lines, max)
    if #lines <= max then return lines end
    local out = {}
    for i = #lines - max + 1, #lines do
        out[#out + 1] = lines[i]
    end
    return out
end

local function fmtVec3(v)
    return ("(%.2f, %.2f, %.2f)"):format(v.X, v.Y, v.Z)
end

local function xzDist(a, b)
    return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function bestTreeHitPart(model)
    if not (model and model:IsA("Model")) then return nil end
    local hr = model:FindFirstChild("HitRegisters")
    if hr then
        local t = hr:FindFirstChild("Trunk")
        if t and t:IsA("BasePart") then return t end
        local any = hr:FindFirstChildWhichIsA("BasePart")
        if any then return any end
    end
    local t2 = model:FindFirstChild("Trunk")
    if t2 and t2:IsA("BasePart") then return t2 end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function attrBucket(treeModel)
    local hr = treeModel and treeModel:FindFirstChild("HitRegisters")
    if hr then return hr end
    return treeModel
end

local function getHitCountMax(treeModel)
    local bucket = attrBucket(treeModel)
    if not (bucket and bucket.GetAttributes) then return 0 end
    local attrs = bucket:GetAttributes()
    local maxN = 0
    for k in pairs(attrs) do
        local key = tostring(k or "")
        local n = key:match("^(%d+)_")
        n = n and tonumber(n) or nil
        if n and n > maxN then maxN = n end
    end
    return maxN
end

local function getDestroyedFlag(treeModel, hitPart)
    if not treeModel then return true end
    if treeModel:GetAttribute("Destroyed") == true then return true end
    if treeModel:GetAttribute("LocalDestroyed") == true then return true end
    if treeModel:GetAttribute("IsDestroyed") == true then return true end
    if treeModel:GetAttribute("Dead") == true then return true end
    if hitPart and hitPart.GetAttribute then
        if hitPart:GetAttribute("Destroyed") == true then return true end
        if hitPart:GetAttribute("LocalDestroyed") == true then return true end
        if hitPart:GetAttribute("IsDestroyed") == true then return true end
        if hitPart:GetAttribute("Dead") == true then return true end
    end
    return false
end

local function looksTreeishModel(m)
    if not (m and m:IsA("Model")) then return false end
    local name = string.lower(tostring(m.Name or ""))
    if not name:find("tree", 1, true) then return false end
    local p = bestTreeHitPart(m)
    if not p then return false end
    local b = attrBucket(m)
    if b and b.GetAttributes then
        local attrs = b:GetAttributes()
        for k in pairs(attrs) do
            if tostring(k):match("^(%d+)_") then
                return true
            end
        end
    end
    if m:FindFirstChild("HitRegisters") then return true end
    if m:FindFirstChild("Trunk") then return true end
    return true
end

local function findNearestTree(rootPos)
    local bestM, bestP, bestD = nil, nil, nil
    for _, inst in ipairs(WS:GetDescendants()) do
        if inst:IsA("Model") and looksTreeishModel(inst) then
            local p = bestTreeHitPart(inst)
            if p then
                local d = (p.Position - rootPos).Magnitude
                if bestD == nil or d < bestD then
                    bestM, bestP, bestD = inst, p, d
                end
            end
        end
    end
    return bestM, bestP, bestD
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TreeHitLoggerGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = pg

local frame = Instance.new("Frame")
frame.Name = "Main"
frame.Parent = screenGui
frame.Size = UDim2.new(0, 520, 0, 260)
frame.Position = UDim2.new(0, 20, 0, 140)
frame.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true

local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Parent = frame
titleBar.Size = UDim2.new(1, 0, 0, 26)
titleBar.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
titleBar.BorderSizePixel = 0

local title = Instance.new("TextLabel")
title.Parent = titleBar
title.Size = UDim2.new(1, -220, 1, 0)
title.Position = UDim2.new(0, 8, 0, 0)
title.BackgroundTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(240, 240, 240)
title.Font = Enum.Font.SourceSansBold
title.TextSize = 14
title.Text = "Tree Hit Logger"

local btnClose = Instance.new("TextButton")
btnClose.Parent = titleBar
btnClose.Size = UDim2.new(0, 60, 1, 0)
btnClose.Position = UDim2.new(1, -60, 0, 0)
btnClose.BackgroundColor3 = Color3.fromRGB(140, 40, 40)
btnClose.TextColor3 = Color3.fromRGB(255, 255, 255)
btnClose.Font = Enum.Font.SourceSansBold
btnClose.TextSize = 14
btnClose.Text = "Unload"

local btnCopy = Instance.new("TextButton")
btnCopy.Parent = titleBar
btnCopy.Size = UDim2.new(0, 60, 1, 0)
btnCopy.Position = UDim2.new(1, -120, 0, 0)
btnCopy.BackgroundColor3 = Color3.fromRGB(40, 120, 40)
btnCopy.TextColor3 = Color3.fromRGB(255, 255, 255)
btnCopy.Font = Enum.Font.SourceSansBold
btnCopy.TextSize = 14
btnCopy.Text = "Copy"

local btnMin = Instance.new("TextButton")
btnMin.Parent = titleBar
btnMin.Size = UDim2.new(0, 40, 1, 0)
btnMin.Position = UDim2.new(1, -160, 0, 0)
btnMin.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
btnMin.TextColor3 = Color3.fromRGB(255, 255, 255)
btnMin.Font = Enum.Font.SourceSansBold
btnMin.TextSize = 14
btnMin.Text = "-"

local statusLine = Instance.new("TextLabel")
statusLine.Parent = frame
statusLine.Size = UDim2.new(1, -12, 0, 20)
statusLine.Position = UDim2.new(0, 6, 0, 30)
statusLine.BackgroundTransparency = 1
statusLine.TextXAlignment = Enum.TextXAlignment.Left
statusLine.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLine.Font = Enum.Font.SourceSans
statusLine.TextSize = 13
statusLine.Text = "READY"

local btnRow = Instance.new("Frame")
btnRow.Parent = frame
btnRow.Size = UDim2.new(1, -12, 0, 28)
btnRow.Position = UDim2.new(0, 6, 0, 52)
btnRow.BackgroundTransparency = 1

local btnAuto = Instance.new("TextButton")
btnAuto.Parent = btnRow
btnAuto.Size = UDim2.new(0, 120, 1, 0)
btnAuto.Position = UDim2.new(0, 0, 0, 0)
btnAuto.BackgroundColor3 = Color3.fromRGB(45, 80, 140)
btnAuto.TextColor3 = Color3.fromRGB(255, 255, 255)
btnAuto.Font = Enum.Font.SourceSansBold
btnAuto.TextSize = 14
btnAuto.Text = "Auto: ON"

local btnLock = Instance.new("TextButton")
btnLock.Parent = btnRow
btnLock.Size = UDim2.new(0, 120, 1, 0)
btnLock.Position = UDim2.new(0, 126, 0, 0)
btnLock.BackgroundColor3 = Color3.fromRGB(90, 60, 40)
btnLock.TextColor3 = Color3.fromRGB(255, 255, 255)
btnLock.Font = Enum.Font.SourceSansBold
btnLock.TextSize = 14
btnLock.Text = "Lock: OFF"

local btnPick = Instance.new("TextButton")
btnPick.Parent = btnRow
btnPick.Size = UDim2.new(0, 140, 1, 0)
btnPick.Position = UDim2.new(0, 252, 0, 0)
btnPick.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
btnPick.TextColor3 = Color3.fromRGB(255, 255, 255)
btnPick.Font = Enum.Font.SourceSansBold
btnPick.TextSize = 14
btnPick.Text = "Pick Now"

local btnClear = Instance.new("TextButton")
btnClear.Parent = btnRow
btnClear.Size = UDim2.new(0, 110, 1, 0)
btnClear.Position = UDim2.new(1, -110, 0, 0)
btnClear.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
btnClear.TextColor3 = Color3.fromRGB(255, 255, 255)
btnClear.Font = Enum.Font.SourceSansBold
btnClear.TextSize = 14
btnClear.Text = "Clear"

local logBox = Instance.new("TextBox")
logBox.Parent = frame
logBox.Size = UDim2.new(1, -12, 1, -88)
logBox.Position = UDim2.new(0, 6, 0, 84)
logBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
logBox.BorderSizePixel = 0
logBox.TextColor3 = Color3.fromRGB(230, 230, 230)
logBox.Font = Enum.Font.Code
logBox.TextSize = 13
logBox.TextXAlignment = Enum.TextXAlignment.Left
logBox.TextYAlignment = Enum.TextYAlignment.Top
logBox.ClearTextOnFocus = false
logBox.MultiLine = true
logBox.TextEditable = false
logBox.TextWrapped = false

local resizeGrip = Instance.new("Frame")
resizeGrip.Parent = frame
resizeGrip.Size = UDim2.new(0, 14, 0, 14)
resizeGrip.Position = UDim2.new(1, -14, 1, -14)
resizeGrip.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
resizeGrip.BorderSizePixel = 0
resizeGrip.Active = true

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 8)
uiCorner.Parent = frame

local highlight = Instance.new("Highlight")
highlight.Name = "TreeHitLoggerHighlight"
highlight.Enabled = false
highlight.FillTransparency = 0.75
highlight.OutlineTransparency = 0.0
highlight.Parent = screenGui

local lines = {}

local function logLine(s)
    local t = now()
    local line = ("[%0.3f] %s"):format(t, tostring(s))
    lines[#lines + 1] = line
    lines = clampLines(lines, STATE.MaxLines)
    logBox.Text = table.concat(lines, "\n")
    logBox.CursorPosition = #logBox.Text + 1
end

local function setStatus(s)
    statusLine.Text = tostring(s)
end

local function applyHighlight(model)
    if model and model.Parent then
        highlight.Adornee = model
        highlight.Enabled = true
    else
        highlight.Enabled = false
        highlight.Adornee = nil
    end
end

local function snapshot(model, part)
    local root = hrp()
    local rootPos = root and root.Position or nil
    local partPos = part and part.Position or nil

    local dist3, distXZv = nil, nil
    if rootPos and partPos then
        dist3 = (partPos - rootPos).Magnitude
        distXZv = xzDist(partPos, rootPos)
    end

    local hit = model and getHitCountMax(model) or 0
    local destroyed = model and getDestroyedFlag(model, part) or true

    return {
        full = model and safeFullName(model) or "nil",
        parent = model and safeFullName(model.Parent) or "nil",
        part = part and safeFullName(part) or "nil",
        hit = hit,
        destroyed = destroyed,
        rootPos = rootPos and fmtVec3(rootPos) or "nil",
        partPos = partPos and fmtVec3(partPos) or "nil",
        dist3 = dist3,
        distXZ = distXZv,
        exists = (model ~= nil and model.Parent ~= nil),
        inWS = (model ~= nil and model:IsDescendantOf(WS)),
    }
end

local function summarizeSnap(sn)
    local d3 = sn.dist3 and ("%.2f"):format(sn.dist3) or "nil"
    local dxz = sn.distXZ and ("%.2f"):format(sn.distXZ) or "nil"
    return ("hit=%s destroyed=%s dist3=%s distXZ=%s inWS=%s model=%s"):format(
        tostring(sn.hit),
        tostring(sn.destroyed),
        d3,
        dxz,
        tostring(sn.inWS),
        sn.full
    )
end

local function disconnectTargetWatchers()
    for i = #conns, 1, -1 do
        local c = conns[i]
        conns[i] = nil
        pcall(function() c:Disconnect() end)
    end
end

local function watchTarget(model, part)
    disconnectTargetWatchers()
    if not (model and model.Parent) then return end

    if model.AttributeChanged then
        conns[#conns + 1] = model.AttributeChanged:Connect(function(attr)
            if not (targetModel == model) then return end
            if attr == "Destroyed" or attr == "LocalDestroyed" or attr == "IsDestroyed" or attr == "Dead" or attr == "MaxHealth" or attr == "Health" then
                local sn = snapshot(model, bestTreeHitPart(model))
                logLine("MODEL_ATTR " .. tostring(attr) .. " " .. summarizeSnap(sn))
            end
        end)
    end

    local bucket = attrBucket(model)
    if bucket and bucket.AttributeChanged then
        conns[#conns + 1] = bucket.AttributeChanged:Connect(function(attr)
            if not (targetModel == model) then return end
            if tostring(attr):match("^(%d+)_") then
                local sn = snapshot(model, bestTreeHitPart(model))
                logLine("HITKEY " .. tostring(attr) .. " " .. summarizeSnap(sn))
            end
        end)
    end

    conns[#conns + 1] = model.AncestryChanged:Connect(function(_, parent)
        if not (targetModel == model) then return end
        local sn = snapshot(model, bestTreeHitPart(model))
        logLine("MODEL_ANCESTRY parent=" .. safeFullName(parent) .. " " .. summarizeSnap(sn))
    end)

    if part and part.AncestryChanged then
        conns[#conns + 1] = part.AncestryChanged:Connect(function(_, parent)
            if not (targetModel == model) then return end
            local sn = snapshot(model, bestTreeHitPart(model))
            logLine("HITPART_ANCESTRY parent=" .. safeFullName(parent) .. " " .. summarizeSnap(sn))
        end)
    end
end

local function setTarget(model, part, why)
    targetModel = model
    targetPart = part
    targetLockedAt = now()
    applyHighlight(model)

    last.hit = nil
    last.destroyed = nil
    last.full = nil
    last.parent = nil
    last.pos = nil
    last.dist3 = nil
    last.distXZ = nil

    if model and part then
        setStatus("TARGET: " .. tostring(model.Name))
        local sn = snapshot(model, part)
        logLine((why or "TARGET_SET") .. " " .. summarizeSnap(sn))
        watchTarget(model, part)
    else
        setStatus("NO TARGET")
        logLine((why or "TARGET_CLEAR") .. " no target")
        disconnectTargetWatchers()
    end
end

local function pickClosestNow()
    local root = hrp()
    if not root then
        setTarget(nil, nil, "PICK_CLOSEST_NO_HRP")
        return
    end
    local m, p, d = findNearestTree(root.Position)
    if m and p then
        setTarget(m, p, "PICK_CLOSEST")
    else
        setTarget(nil, nil, "PICK_CLOSEST_NONE")
    end
end

local minimized = false
local function setMinimized(on)
    minimized = on and true or false
    if minimized then
        frame.Size = UDim2.new(0, frame.Size.X.Offset, 0, 26)
        statusLine.Visible = false
        btnRow.Visible = false
        logBox.Visible = false
        resizeGrip.Visible = false
        btnMin.Text = "+"
    else
        frame.Size = UDim2.new(0, math.max(frame.Size.X.Offset, 360), 0, math.max(frame.Size.Y.Offset, 180))
        statusLine.Visible = true
        btnRow.Visible = true
        logBox.Visible = true
        resizeGrip.Visible = true
        btnMin.Text = "-"
    end
end

local resizing = false
local resizeStartMouse
local resizeStartSize

resizeGrip.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        resizing = true
        resizeStartMouse = input.Position
        resizeStartSize = frame.Size
    end
end)

resizeGrip.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        resizing = false
    end
end)

local uis = game:GetService("UserInputService")
uis.InputChanged:Connect(function(input)
    if not resizing then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = input.Position - resizeStartMouse
    local newW = math.clamp(resizeStartSize.X.Offset + delta.X, 360, 900)
    local newH = math.clamp(resizeStartSize.Y.Offset + delta.Y, 180, 700)
    if minimized then
        frame.Size = UDim2.new(0, newW, 0, 26)
    else
        frame.Size = UDim2.new(0, newW, 0, newH)
    end
end)

btnMin.MouseButton1Click:Connect(function()
    setMinimized(not minimized)
end)

btnClear.MouseButton1Click:Connect(function()
    lines = {}
    logBox.Text = ""
end)

btnCopy.MouseButton1Click:Connect(function()
    local txt = logBox.Text
    if setclipboard then
        pcall(function() setclipboard(txt) end)
    end
end)

btnAuto.MouseButton1Click:Connect(function()
    STATE.AutoClosest = not STATE.AutoClosest
    if STATE.AutoClosest then
        btnAuto.Text = "Auto: ON"
        btnAuto.BackgroundColor3 = Color3.fromRGB(45, 80, 140)
    else
        btnAuto.Text = "Auto: OFF"
        btnAuto.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    end
end)

btnLock.MouseButton1Click:Connect(function()
    STATE.Locked = not STATE.Locked
    if STATE.Locked then
        btnLock.Text = "Lock: ON"
        btnLock.BackgroundColor3 = Color3.fromRGB(140, 95, 50)
        if targetModel and targetModel.Parent then
            setTarget(targetModel, bestTreeHitPart(targetModel), "LOCK_ON")
        else
            pickClosestNow()
            if targetModel then
                setTarget(targetModel, bestTreeHitPart(targetModel), "LOCK_ON_PICK")
            end
        end
    else
        btnLock.Text = "Lock: OFF"
        btnLock.BackgroundColor3 = Color3.fromRGB(90, 60, 40)
        logLine("LOCK_OFF")
    end
end)

btnPick.MouseButton1Click:Connect(function()
    pickClosestNow()
end)

local function destroyAll()
    if hbConn then pcall(function() hbConn:Disconnect() end) hbConn = nil end
    disconnectTargetWatchers()
    pcall(function() highlight:Destroy() end)
    pcall(function() screenGui:Destroy() end)
end

btnClose.MouseButton1Click:Connect(function()
    if _G.__TreeHitLogger and type(_G.__TreeHitLogger.Destroy) == "function" then
        pcall(function() _G.__TreeHitLogger.Destroy() end)
    else
        destroyAll()
    end
end)

_G.__TreeHitLogger = {
    Destroy = function()
        destroyAll()
        _G.__TreeHitLogger = nil
    end
}

logLine("READY. AutoClosest=" .. tostring(STATE.AutoClosest) .. " Lock=" .. tostring(STATE.Locked))

local acc = 0
hbConn = RunService.Heartbeat:Connect(function(dt)
    acc += (dt or 0)
    if acc < STATE.UpdateEvery then return end
    acc = 0

    local root = hrp()
    if not root then
        if targetModel ~= nil then
            setTarget(nil, nil, "NO_HRP_CLEAR")
        end
        return
    end

    if STATE.AutoClosest and not STATE.Locked then
        local m, p = findNearestTree(root.Position)
        if m and p then
            if targetModel ~= m then
                setTarget(m, p, "AUTO_SWITCH")
            end
        else
            if targetModel ~= nil then
                setTarget(nil, nil, "AUTO_NONE")
            end
        end
    end

    if targetModel and targetModel.Parent then
        local p = bestTreeHitPart(targetModel)
        if not p then
            local sn = snapshot(targetModel, nil)
            logLine("TARGET_NO_PART " .. summarizeSnap(sn))
            applyHighlight(targetModel)
            return
        end

        local sn = snapshot(targetModel, p)

        if last.full ~= sn.full then
            last.full = sn.full
            logLine("TARGET " .. summarizeSnap(sn))
        end

        if last.parent ~= sn.parent then
            last.parent = sn.parent
            logLine("PARENT " .. summarizeSnap(sn))
        end

        if last.hit == nil or sn.hit ~= last.hit then
            local prev = last.hit
            last.hit = sn.hit
            logLine("HITCOUNT " .. tostring(prev) .. " -> " .. tostring(sn.hit) .. " " .. summarizeSnap(sn))
        end

        if last.destroyed == nil or sn.destroyed ~= last.destroyed then
            local prev = last.destroyed
            last.destroyed = sn.destroyed
            logLine("DESTROYED " .. tostring(prev) .. " -> " .. tostring(sn.destroyed) .. " " .. summarizeSnap(sn))
        end

        if sn.partPos ~= "nil" then
            if last.pos ~= sn.partPos then
                last.pos = sn.partPos
                logLine("PART_POS " .. sn.partPos)
            end
        end

        if last.dist3 == nil or sn.dist3 ~= last.dist3 or last.distXZ == nil or sn.distXZ ~= last.distXZ then
            last.dist3 = sn.dist3
            last.distXZ = sn.distXZ
            local d3 = sn.dist3 and ("%.2f"):format(sn.dist3) or "nil"
            local dxz = sn.distXZ and ("%.2f"):format(sn.distXZ) or "nil"
            setStatus(("TARGET: %s  hit=%d  d3=%s  dXZ=%s  destroyed=%s"):format(
                tostring(targetModel.Name),
                tonumber(sn.hit) or 0,
                d3,
                dxz,
                tostring(sn.destroyed)
            ))
        end

        applyHighlight(targetModel)
    else
        if targetModel ~= nil then
            setTarget(nil, nil, "TARGET_GONE")
        else
            setStatus("NO TARGET")
            applyHighlight(nil)
        end
    end
end)
