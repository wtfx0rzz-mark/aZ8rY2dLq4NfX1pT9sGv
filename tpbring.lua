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

    local function itemsRootOrNil()
        return WS:FindFirstChild("Items")
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

    local function isExcludedInst(inst)
        if not inst then return true end
        if inst:IsA("Model") then
            local n = (inst.Name or ""):lower()
            if n == "pelt trader" then return true end
            if n:find("trader",1,true) or n:find("shopkeeper",1,true) then return true end
            if isWallVariant(inst) then return true end
        end
        if isUnderLogWall(inst) then return true end
        if hasIceBlockTag(inst) then return true end
        return false
    end

    local function isDirectItemChild(m)
        local itemsFolder = itemsRootOrNil()
        if not itemsFolder then return true end
        if not (m and m.Parent) then return false end
        return m.Parent == itemsFolder
    end

    local function rootItemUnderItems(inst)
        local itemsFolder = itemsRootOrNil()
        if not (itemsFolder and inst) then return nil end
        local cur = inst
        while cur and cur.Parent and cur.Parent ~= itemsFolder and cur ~= itemsFolder do
            cur = cur.Parent
        end
        if cur and cur.Parent == itemsFolder and (cur:IsA("Model") or cur:IsA("BasePart")) then
            return cur
        end
        return nil
    end

    local function nameMatches_LogOnly(m)
        if not m then return false end
        local itemsFolder = itemsRootOrNil()
        if itemsFolder and not m:IsDescendantOf(itemsFolder) then
            return false
        end
        return (m.Name or "") == "Log"
    end

    local overlapParams = OverlapParams.new()
    overlapParams.MaxParts = 2000

    local function refreshOverlapFilter()
        local itemsFolder = itemsRootOrNil()
        if itemsFolder then
            overlapParams.FilterType = Enum.RaycastFilterType.Include
            overlapParams.FilterDescendantsInstances = { itemsFolder }
        else
            overlapParams.FilterType = Enum.RaycastFilterType.Exclude
            overlapParams.FilterDescendantsInstances = { lp.Character }
        end
    end

    local function scrapperOrbPos()
        local scr = WS:FindFirstChild("Map") and WS.Map:FindFirstChild("Campground") and WS.Map.Campground:FindFirstChild("Scrapper")
        if not scr then return nil end
        local mp = mainPart(scr)
        local cf = (mp and mp.CFrame) or scr:GetPivot()
        return cf.Position + Vector3.new(0, 10 + 3, 0)
    end

    local startDrag, stopDrag = nil, nil
    do
        local re = RS:FindFirstChild("RemoteEvents")
        if re then
            startDrag = re:FindFirstChild("RequestStartDraggingItem")
            stopDrag  = re:FindFirstChild("StopDraggingItem")
        end
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

    local INFLT_ATTR = "OrbInFlightAt"
    local JOB_ATTR   = "OrbJob"
    local DONE_ATTR  = "OrbDelivered"

    local DRAG_SPEED         = 420
    local ARRIVE_EPS_H       = 1.1
    local STALL_SEC          = 0.6
    local SCAN_INTERVAL      = 0.20
    local MOVE_HZ            = 30
    local MAX_DIST_DEFAULT   = 500

    local MAX_CONCURRENT     = 10
    local MAX_LINED_ITEMS    = 10

    local SKY_RAY_START_Y    = 320
    local SKY_RAY_LEN        = 900
    local PLACE_UP           = 1.6

    local running     = false
    local hb          = nil
    local orbPosVec   = nil
    local inflight    = {}
    local releaseQueue = {}
    local releaseAcc  = 0.0
    local activeCount = 0
    local dropStacks  = {}

    local charAddedConn = nil

    -- ===== Logger (GUI console with Copy + Close) =====
    local logGui, logFrame, logText, logArea = nil, nil, nil, nil
    local logLines = {}
    local LOG_MAX_LINES = 800
    local function setClipboard(s)
        if setclipboard then
            pcall(function() setclipboard(s) end)
        end
    end

    local function ensureLogger()
        if logGui and logGui.Parent then return end
        local pg = lp:FindFirstChild("PlayerGui")
        if not pg then return end

        logGui = Instance.new("ScreenGui")
        logGui.Name = "__TPBringLogGui__"
        logGui.ResetOnSpawn = false
        logGui.Parent = pg

        logFrame = Instance.new("Frame")
        logFrame.Name = "Window"
        logFrame.Parent = logGui
        logFrame.Size = UDim2.new(0, 520, 0, 260)
        logFrame.Position = UDim2.new(1, -540, 1, -290)
        logFrame.BackgroundColor3 = Color3.fromRGB(20,20,20)
        logFrame.BorderSizePixel = 0
        logFrame.Active = true
        logFrame.Draggable = true

        local title = Instance.new("TextLabel")
        title.Parent = logFrame
        title.Size = UDim2.new(1, 0, 0, 24)
        title.Position = UDim2.new(0, 0, 0, 0)
        title.BackgroundColor3 = Color3.fromRGB(12,12,12)
        title.BorderSizePixel = 0
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Font = Enum.Font.SourceSansBold
        title.TextSize = 14
        title.TextColor3 = Color3.fromRGB(235,235,235)
        title.Text = "TPBring Log Scrapper Debug"

        local closeBtn = Instance.new("TextButton")
        closeBtn.Parent = logFrame
        closeBtn.Size = UDim2.new(0, 54, 0, 24)
        closeBtn.Position = UDim2.new(1, -54, 0, 0)
        closeBtn.BackgroundColor3 = Color3.fromRGB(160,50,50)
        closeBtn.BorderSizePixel = 0
        closeBtn.Font = Enum.Font.SourceSansBold
        closeBtn.TextSize = 14
        closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
        closeBtn.Text = "Close"
        closeBtn.MouseButton1Click:Connect(function()
            if logGui then pcall(function() logGui:Destroy() end) end
            logGui, logFrame, logText, logArea = nil, nil, nil, nil
        end)

        local copyBtn = Instance.new("TextButton")
        copyBtn.Parent = logFrame
        copyBtn.Size = UDim2.new(0, 54, 0, 24)
        copyBtn.Position = UDim2.new(1, -108, 0, 0)
        copyBtn.BackgroundColor3 = Color3.fromRGB(50,140,60)
        copyBtn.BorderSizePixel = 0
        copyBtn.Font = Enum.Font.SourceSansBold
        copyBtn.TextSize = 14
        copyBtn.TextColor3 = Color3.fromRGB(255,255,255)
        copyBtn.Text = "Copy"
        copyBtn.MouseButton1Click:Connect(function()
            setClipboard(table.concat(logLines, "\n"))
        end)

        logArea = Instance.new("ScrollingFrame")
        logArea.Parent = logFrame
        logArea.Position = UDim2.new(0, 8, 0, 32)
        logArea.Size = UDim2.new(1, -16, 1, -40)
        logArea.BackgroundColor3 = Color3.fromRGB(30,30,30)
        logArea.BorderSizePixel = 0
        logArea.ScrollBarThickness = 6
        logArea.CanvasSize = UDim2.new(0, 0, 0, 0)

        logText = Instance.new("TextLabel")
        logText.Parent = logArea
        logText.BackgroundTransparency = 1
        logText.Size = UDim2.new(1, -10, 0, 0)
        logText.Position = UDim2.new(0, 0, 0, 0)
        logText.Font = Enum.Font.Code
        logText.TextSize = 12
        logText.TextColor3 = Color3.fromRGB(210,210,210)
        logText.TextXAlignment = Enum.TextXAlignment.Left
        logText.TextYAlignment = Enum.TextYAlignment.Top
        logText.TextWrapped = true
        logText.Text = ""

        local function refreshText()
            if not (logText and logText.Parent) then return end
            logText.Text = table.concat(logLines, "\n")
            task.defer(function()
                if logText and logArea then
                    local h = logText.TextBounds.Y + 8
                    logText.Size = UDim2.new(1, -10, 0, h)
                    logArea.CanvasSize = UDim2.new(0, 0, 0, h)
                    logArea.CanvasPosition = Vector2.new(0, math.max(0, h - logArea.AbsoluteWindowSize.Y))
                end
            end)
        end

        logGui:SetAttribute("__refresh__", 0)
        logGui:GetAttributeChangedSignal("__refresh__"):Connect(refreshText)
        refreshText()
    end

    local function logLine(s)
        ensureLogger()
        local ts = string.format("%.3f", os.clock())
        logLines[#logLines+1] = ("[%s] %s"):format(ts, tostring(s))
        if #logLines > LOG_MAX_LINES then
            table.remove(logLines, 1)
        end
        if logGui and logGui.Parent then
            logGui:SetAttribute("__refresh__", (logGui:GetAttribute("__refresh__") or 0) + 1)
        end
    end

    -- ===== Debug counters per scan tick (aggregated to avoid spam) =====
    local function newCounters()
        return {
            parts = 0,
            roots = 0,
            uniqRoots = 0,
            cand = 0,
            start = 0,
            skip = {},
            samples = {}
        }
    end

    local function bumpSkip(cnt, key, sample)
        cnt.skip[key] = (cnt.skip[key] or 0) + 1
        if sample then
            local a = cnt.samples[key]
            if not a then a = {} cnt.samples[key] = a end
            if #a < 4 then a[#a+1] = sample end
        end
    end

    local function dumpCounters(cnt, label)
        local parts = cnt.parts or 0
        local roots = cnt.roots or 0
        local uniq = cnt.uniqRoots or 0
        local cand = cnt.cand or 0
        local started = cnt.start or 0
        logLine(("%s parts=%d roots=%d uniq=%d candidates=%d started=%d active=%d queued=%d")
            :format(label, parts, roots, uniq, cand, started, activeCount, #releaseQueue))
        for k,v in pairs(cnt.skip or {}) do
            local samp = cnt.samples and cnt.samples[k]
            local extra = ""
            if samp and #samp > 0 then
                extra = " samples=" .. table.concat(samp, ", ")
            end
            logLine(("  skip[%s]=%d%s"):format(k, v, extra))
        end
    end

    -- ===== Candidate selection with reasons =====
    local function canPick_LogOnly(m, jobId)
        if not (m and m.Parent) then return false, "no_parent" end
        if not (m:IsA("Model") or m:IsA("BasePart")) then return false, "not_model_or_part" end
        if isExcludedInst(m) then return false, "excluded" end

        local itemsFolder = itemsRootOrNil()
        if not itemsFolder then return false, "no_items_folder" end
        if not m:IsDescendantOf(itemsFolder) then return false, "not_in_items" end
        if not isDirectItemChild(m) then return false, "not_direct_child" end

        if not nameMatches_LogOnly(m) then return false, "not_log" end

        local done = m:GetAttribute(DONE_ATTR)
        if done and tostring(done) == tostring(jobId) then return false, "done_this_jobid" end

        local tIn = m:GetAttribute(INFLT_ATTR)
        local jIn = m:GetAttribute(JOB_ATTR)
        if tIn and jIn and tostring(jIn) ~= tostring(jobId) then
            return false, "inflight_other_job"
        end
        return true, "ok"
    end

    local function nearestSelectedModelFromPart_LogOnly(part, jobId)
        if not (part and part:IsA("BasePart")) then return nil, "not_basepart" end
        local itemsFolder = itemsRootOrNil()
        if not itemsFolder then return nil, "no_items_folder" end
        if not part:IsDescendantOf(itemsFolder) then return nil, "part_not_in_items" end
        local root = rootItemUnderItems(part)
        if not root then return nil, "no_root_under_items" end
        local ok, why = canPick_LogOnly(root, jobId)
        if not ok then return nil, why end
        return root, "ok"
    end

    local function collectLogs(jobId, maxDist)
        local cnt = newCounters()
        local itemsFolder = itemsRootOrNil()
        if not itemsFolder then
            bumpSkip(cnt, "no_items_folder")
            return {}, cnt
        end

        local root = hrp()
        if not root then
            bumpSkip(cnt, "no_hrp")
            return {}, cnt
        end

        local origin = root.Position
        local rad = maxDist or MAX_DIST_DEFAULT

        refreshOverlapFilter()
        local ok, parts = pcall(function()
            return WS:GetPartBoundsInRadius(origin, rad, overlapParams)
        end)

        if not ok or type(parts) ~= "table" then
            bumpSkip(cnt, "overlap_failed")
            local out = {}
            local uniq = {}
            for _,d in ipairs(itemsFolder:GetChildren()) do
                if (d:IsA("Model") or d:IsA("BasePart")) then
                    local mp = mainPart(d)
                    if mp then
                        local dist = (mp.Position - origin).Magnitude
                        if dist <= rad then
                            local ok2, why = canPick_LogOnly(d, jobId)
                            if ok2 then
                                if not uniq[d] then
                                    uniq[d] = true
                                    out[#out+1] = d
                                end
                            else
                                bumpSkip(cnt, why, d.Name)
                            end
                        end
                    end
                end
            end
            cnt.uniqRoots = #out
            cnt.cand = #out
            return out, cnt
        end

        cnt.parts = #parts

        local uniq = {}
        local out = {}
        for _,p in ipairs(parts) do
            if p and p.Parent then
                local m, why = nearestSelectedModelFromPart_LogOnly(p, jobId)
                if m then
                    cnt.roots = cnt.roots + 1
                    if not uniq[m] then
                        uniq[m] = true
                        out[#out+1] = m
                    end
                else
                    bumpSkip(cnt, why, p.Name)
                end
            end
        end

        cnt.uniqRoots = #out
        cnt.cand = #out
        return out, cnt
    end

    -- ===== Delivery (scrapper orb) =====
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

    local function markDone(m, runId)
        if not (m and m.Parent) then return end
        pcall(function()
            m:SetAttribute(INFLT_ATTR, nil)
            m:SetAttribute(JOB_ATTR, nil)
            if runId then m:SetAttribute(DONE_ATTR, runId) end
        end)
        inflight[m] = nil
    end

    local function stageForRelease(m, snap, destKey, centerXZ)
        setAnchored(m, true)
        for _,p in ipairs(allParts(m)) do
            p.CanCollide = false
            p.AssemblyLinearVelocity  = Vector3.new()
            p.AssemblyAngularVelocity = Vector3.new()
        end
        local info = inflight[m]
        if info then
            info.staged = true
            info.stagedAt = os.clock()
            info.snap = snap
        end
        releaseQueue[#releaseQueue+1] = { model = m, snap = snap, destKey = destKey or "scrap", centerXZ = centerXZ }
    end

    local function releaseOne(rec, runId)
        local m = rec and rec.model
        if not (m and m.Parent) then return end

        local info = inflight[m]
        local snap = (rec and rec.snap) or (info and info.snap) or snapshotCollide(m)
        if info then tryStopDrag(m, info) end

        local center = rec and rec.centerXZ
        if not center then
            local mp = mainPart(m)
            local p = (mp and mp.Position) or Vector3.new()
            center = Vector3.new(p.X, 0, p.Z)
        end

        dropStacks[rec.destKey or "scrap"] = (dropStacks[rec.destKey or "scrap"] or 0) + 1
        local idx = dropStacks[rec.destKey or "scrap"]
        local ang = idx * 2.399963229728653
        local rad = math.min(8.0, 0.8 * math.sqrt(math.max(idx, 1)))
        local off2d = Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)

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

        markDone(m, runId)
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

    local function hash01(s)
        local h = 131071
        for i = 1, #s do h = (h * 131 + string.byte(s, i)) % 1000003 end
        return (h % 100000) / 100000
    end

    local LAND_MIN = 0.35
    local LAND_MAX = 0.85
    local HOVER_ABOVE_ORB = 1.2

    local function landingOffset(m, jobId)
        local key = (typeof(m.GetDebugId)=="function" and m:GetDebugId() or (m.Name or "")) .. tostring(jobId)
        local r1 = hash01(key .. "a")
        local r2 = hash01(key .. "b")
        local ang = r1 * math.pi * 2
        local rad = LAND_MIN + (LAND_MAX - LAND_MIN) * r2
        return Vector3.new(math.cos(ang)*rad, 0, math.sin(ang)*rad)
    end

    local function startConveyor_Log(m, jobId, destBaseVec)
        if not (running and m and m.Parent) then return false, "not_running_or_no_parent" end
        local mp = mainPart(m)
        if not mp then return false, "no_mainpart" end
        if not destBaseVec then return false, "no_dest" end

        local ok, why = canPick_LogOnly(m, jobId)
        if not ok then return false, "canpick_" .. tostring(why) end
        if inflight[m] then return false, "already_inflight" end

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
        local rec = {
            snap = snap,
            lastD = math.huge,
            lastT = os.clock(),
            staged = false,
            dragging = false,
            stopped = false,
            counted = true,
            centerXZ = centerXZ,
            targetFn = target
        }
        inflight[m] = rec
        activeCount = activeCount + 1
        tryStartDrag(m, rec)
        return true, "ok"
    end

    local function updateInflight(dt, runId)
        for m,rec in pairs(inflight) do
            if not (m and m.Parent and running) then
                abortRestore(m, rec)
            else
                if not rec.staged then
                    local pivot = m.GetPivot and m:GetPivot() or nil
                    local pos = (pivot and pivot.Position) or (mainPart(m) and mainPart(m).Position) or nil
                    if not pos then
                        abortRestore(m, rec)
                    else
                        local tgt = rec.targetFn and rec.targetFn() or nil
                        if not tgt then
                            abortRestore(m, rec)
                        else
                            local flatDelta = Vector3.new(tgt.X - pos.X, 0, tgt.Z - pos.Z)
                            local distH = flatDelta.Magnitude
                            if distH <= ARRIVE_EPS_H and math.abs(tgt.Y - pos.Y) <= 1.2 then
                                tryStopDrag(m, rec)
                                if rec.counted then
                                    rec.counted = false
                                    activeCount = math.max(0, activeCount - 1)
                                end
                                stageForRelease(m, rec.snap, "scrap", rec.centerXZ)
                            else
                                if distH >= rec.lastD - 0.02 then
                                    if os.clock() - rec.lastT >= STALL_SEC then
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
                            end
                        end
                    end
                end
            end
        end
    end

    local function stopAll(runId)
        running = false
        if hb then hb:Disconnect() hb = nil end

        for i = 1, #releaseQueue do
            local rec = releaseQueue[i]
            if rec and rec.model and rec.model.Parent then
                releaseOne(rec, runId)
            end
        end
        releaseQueue = {}

        for m,rec in pairs(inflight) do
            abortRestore(m, rec)
        end

        inflight = {}
        activeCount = 0
        orbPosVec = nil
    end

    local CURRENT_RUN_ID = nil

    local function startScrapLogs(state)
        if not state then
            logLine("STOP requested")
            stopAll(CURRENT_RUN_ID)
            CURRENT_RUN_ID = nil
            return
        end

        local root = hrp()
        if not root then
            logLine("START failed: no HRP")
            return
        end

        local pos = scrapperOrbPos()
        if not pos then
            logLine("START failed: scrapper not found")
            return
        end

        stopAll(CURRENT_RUN_ID)
        CURRENT_RUN_ID = tostring(os.clock())
        orbPosVec = pos
        running = true
        releaseQueue = {}
        releaseAcc = 0
        activeCount = 0
        dropStacks = {}

        logLine(("START runId=%s orbPos=(%.2f,%.2f,%.2f) maxConcurrent=%d maxQueue=%d")
            :format(CURRENT_RUN_ID, pos.X, pos.Y, pos.Z, MAX_CONCURRENT, MAX_LINED_ITEMS))

        local scanAcc = 0
        local moveAcc = 0
        local moveInterval = 1 / MOVE_HZ

        if hb then hb:Disconnect() hb = nil end
        hb = Run.Heartbeat:Connect(function(dt)
            if not running then return end

            scanAcc = scanAcc + dt
            if scanAcc >= SCAN_INTERVAL then
                scanAcc = scanAcc - SCAN_INTERVAL
                local jobId = tostring(CURRENT_RUN_ID)

                local list, cnt = collectLogs(jobId, MAX_DIST_DEFAULT)
                local startedThisTick = 0

                for i = 1, #list do
                    if not running then break end
                    if #releaseQueue >= MAX_LINED_ITEMS then break end
                    if activeCount >= MAX_CONCURRENT then break end
                    local m = list[i]
                    if m and m.Parent and not inflight[m] then
                        local ok, why = startConveyor_Log(m, jobId, orbPosVec)
                        if ok then
                            startedThisTick = startedThisTick + 1
                            cnt.start = (cnt.start or 0) + 1
                        else
                            bumpSkip(cnt, "start_" .. tostring(why), m.Name)
                        end
                    end
                end

                dumpCounters(cnt, "SCAN")
                if startedThisTick > 0 then
                    logLine(("  startedThisTick=%d"):format(startedThisTick))
                end
            end

            moveAcc = moveAcc + dt
            if moveAcc >= moveInterval then
                local step = moveAcc
                moveAcc = 0
                updateInflight(step, CURRENT_RUN_ID)
            end

            releaseAcc = releaseAcc + dt
            local releaseRateHz = 18
            local maxReleasePerTick = 2
            local interval = 1 / math.max(1, releaseRateHz)
            local toRelease = math.min(maxReleasePerTick, math.floor(releaseAcc / interval))
            if toRelease > 0 then
                releaseAcc = releaseAcc - toRelease * interval
                for i = 1, toRelease do
                    local rec = table.remove(releaseQueue, 1)
                    if not rec then break end
                    releaseOne(rec, CURRENT_RUN_ID)
                end
            end
        end)
    end

    tab:Section({ Title = "TPBring Debug (Logs -> Scrapper only)" })

    tab:Toggle({
        Title = "Send Logs to Scrapper (Debug)",
        Value = false,
        Callback = function(state)
            startScrapLogs(state)
        end
    })

    tab:Button({
        Title = "Open Debug Logger",
        Callback = function()
            ensureLogger()
            logLine("Logger opened")
        end
    })

    if charAddedConn then
        pcall(function() charAddedConn:Disconnect() end)
        charAddedConn = nil
    end

    charAddedConn = Players.LocalPlayer.CharacterAdded:Connect(function()
        if running and CURRENT_RUN_ID then
            local pos = scrapperOrbPos()
            if pos then
                orbPosVec = pos
                logLine(("CharacterAdded: refreshed orbPos=(%.2f,%.2f,%.2f)"):format(pos.X, pos.Y, pos.Z))
            else
                logLine("CharacterAdded: scrapper not found (orbPos unchanged)")
            end
        end
    end)

    local function cleanupModule()
        pcall(function() stopAll(CURRENT_RUN_ID) end)
        if charAddedConn then pcall(function() charAddedConn:Disconnect() end) end
        charAddedConn = nil
        if logGui and logGui.Parent then pcall(function() logGui:Destroy() end) end
        logGui, logFrame, logText, logArea = nil, nil, nil, nil
        if _G.__TPBring__cleanup == cleanupModule then
            _G.__TPBring__cleanup = nil
        end
    end

    _G.__TPBring__cleanup = cleanupModule
end
