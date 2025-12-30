-- bring.lua
return function(C, R, UI)
    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local WS      = (C and C.Services and C.Services.WS)      or game:GetService("Workspace")
    local RS      = (C and C.Services and C.Services.RS)      or game:GetService("ReplicatedStorage")
    local Run     = (C and C.Services and C.Services.Run)     or game:GetService("RunService")

    local lp   = Players.LocalPlayer
    local Tabs = UI and UI.Tabs or {}
    local tab  = Tabs.Bring
    assert(tab, "Bring tab not found in UI")

    C.State = C.State or {}
    if C.State.BringLimitEnabled == nil then C.State.BringLimitEnabled = false end
    if not tonumber(C.State.BringLimitAmount) then C.State.BringLimitAmount = 10 end

    local function currentLimit()
        local v = tonumber(C.State.BringLimitAmount) or 10
        return math.clamp(v, 1, 100)
    end

    local COLLIDE_OFF_SEC       = 0.22
    local DROP_ABOVE_HEAD_STUDS = 10
    local FALLBACK_UP           = 4
    local FALLBACK_AHEAD        = 5
    local ORB_OFFSET_Y          = 20

    local LOG_TRACE = true
    local LOG_STAT  = true

    local function nowClock()
        local t = os.date("*t")
        return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
    end

    local function _emit(level, msg)
        local line = string.format("[%s] [%s] %s", nowClock(), level, msg)
        if C and type(C.LogLine) == "function" then
            C.LogLine(line)
        elseif C and type(C.Log) == "function" then
            C.Log(line)
        else
            print(line)
        end
    end

    local function trace(msg) if LOG_TRACE then _emit("TRACE", msg) end end
    local function info(msg) _emit("INFO", msg) end
    local function stat(msg) if LOG_STAT then _emit("STAT", msg) end end
    local function warn(msg) _emit("WARN", msg) end
    local function errl(msg) _emit("ERROR", msg) end

    local function hrp()
        local ch = lp.Character or lp.CharacterAdded:Wait()
        return ch and ch:WaitForChild("HumanoidRootPart", 5)
    end

    local function getMemMB()
        local ok, s = pcall(function()
            return (game:GetService("Stats"):GetTotalMemoryUsageMb())
        end)
        return ok and s or -1
    end

    local metrics = {
        last="",
        remoteFires=0,
        streamReqs=0,
        overlapCalls=0,
        overlapParts=0,
        cand=0,
        queued=0,
        dropped=0,
        convJobs=0,
        convWaves=0,
        convMoved=0,
        convActiveMax=0,
        convKick=0,
        errors=0,
        stopDup=0,
        stopSkip=0,
        stopNoStart=0,
        startFail=0,
        startOk=0,
        stopOk=0,
        remotesResolved=0,
        remotesFail=0
    }

    local errorsByKey = {}
    local errorSeen = {}
    local lastErrorBurstAt = 0
    local function recordError(key, e, where)
        metrics.errors += 1
        local k = tostring(key or "error")
        errorsByKey[k] = (errorsByKey[k] or 0) + 1
        local msg = tostring(e or "unknown")
        if where then msg = where .. ": " .. msg end

        if not errorSeen[k] then
            errorSeen[k] = true
            errl(("NEW_ERROR key=%s %s"):format(k, msg))
        else
            local t = os.clock()
            if t - lastErrorBurstAt > 2.0 then
                lastErrorBurstAt = t
                errl(("ERROR key=%s %s"):format(k, msg))
            end
        end
    end

    local function topErrors(n)
        n = n or 3
        local arr = {}
        for k, v in pairs(errorsByKey) do
            arr[#arr+1] = {k=k, v=v}
        end
        table.sort(arr, function(a,b) return a.v > b.v end)
        local out = {}
        for i=1, math.min(n, #arr) do
            out[#out+1] = arr[i].k .. "=" .. tostring(arr[i].v)
        end
        return table.concat(out, ",")
    end

    local Remotes = nil
    local REFolder = nil
    local function resolveRemotes(force)
        if Remotes and not force then return Remotes end
        local ok, out = pcall(function()
            local re = RS:WaitForChild("RemoteEvents", 10)
            if not re then return nil end
            local t = {}
            t.StartDrag = re:WaitForChild("RequestStartDraggingItem", 10)
            t.StopDrag  = re:WaitForChild("StopDraggingItem", 10)
            t.CookItem  = re:WaitForChild("RequestCookItem", 10)
            t.ScrapItem = re:WaitForChild("RequestScrapItem", 10)
            t.BurnItem  = re:WaitForChild("RequestBurnItem", 10)
            return t, re
        end)
        if not ok or not out then
            metrics.remotesFail += 1
            recordError("resolveRemotes", ok and "nil remotes" or out, "resolveRemotes")
            Remotes = nil
            return nil
        end
        Remotes, REFolder = out, select(2, pcall(function() return nil end))
        metrics.remotesResolved += 1
        trace(("resolveRemotes cached {StartDrag=%s,StopDrag=%s,CookItem=%s,ScrapItem=%s,BurnItem=%s}"):format(
            tostring(out.StartDrag and out.StartDrag.Name),
            tostring(out.StopDrag and out.StopDrag.Name),
            tostring(out.CookItem and out.CookItem.Name),
            tostring(out.ScrapItem and out.ScrapItem.Name),
            tostring(out.BurnItem and out.BurnItem.Name)
        ))
        return Remotes
    end

    local function fireRemote(remote, label, ...)
        metrics.last = label or metrics.last
        if not remote then
            recordError("nil_remote:"..tostring(label), "remote is nil", "fireRemote")
            return false
        end
        metrics.remoteFires += 1
        local ok, e = pcall(function()
            remote:FireServer(...)
        end)
        if not ok then
            recordError("FireServer:"..tostring(label), e, "FireServer")
            return false
        end
        return true
    end

    local activeDrag = setmetatable({}, {__mode="k"})
    local stopSent   = setmetatable({}, {__mode="k"})

    local function startDrag(model)
        local r = resolveRemotes(false)
        if not r then
            metrics.startFail += 1
            return false
        end
        if not model or not model.Parent then
            metrics.startFail += 1
            metrics.stopNoStart += 1
            recordError("startDrag:invalidModel", "model missing/parent nil", "startDrag")
            return false
        end
        local ok = fireRemote(r.StartDrag, "StartDrag", model)
        if ok then
            activeDrag[model] = true
            stopSent[model] = nil
            metrics.startOk += 1
        else
            metrics.startFail += 1
        end
        return ok
    end

    local function stopDragOnce(model, reason)
        local r = resolveRemotes(false)
        if not r then
            metrics.stopSkip += 1
            return false
        end
        if not model or not model.Parent then
            metrics.stopSkip += 1
            return false
        end
        if stopSent[model] then
            metrics.stopDup += 1
            return false
        end
        if not activeDrag[model] then
            metrics.stopNoStart += 1
            stopSent[model] = true
            return false
        end
        stopSent[model] = true
        activeDrag[model] = nil
        local ok = fireRemote(r.StopDrag, "StopDrag", model)
        if ok then metrics.stopOk += 1 else metrics.stopSkip += 1 end
        if reason then trace(("StopDragOnce model=%s reason=%s"):format(model.Name, reason)) end
        return ok
    end

    local function requestStream(pos)
        metrics.last = "RequestStreamAroundAsync"
        metrics.streamReqs += 1
        local ok, e = pcall(function()
            WS:RequestStreamAroundAsync(pos)
        end)
        if ok then
            trace(("RequestStreamAroundAsync pos=%s, %s, %s"):format(tostring(pos.X), tostring(pos.Y), tostring(pos.Z)))
        else
            recordError("RequestStreamAroundAsync", e, "stream")
        end
    end

    local function safePivotTo(model, cf)
        local ok, e = pcall(function()
            if model and model.Parent and model:IsA("Model") then
                model:PivotTo(cf)
            end
        end)
        if not ok then
            recordError("PivotTo", e, "pivot")
        end
    end

    local function dropCFrameNearPlayer()
        local h = hrp()
        if not h then return CFrame.new() end
        local up = Vector3.new(0, DROP_ABOVE_HEAD_STUDS, 0)
        local ahead = h.CFrame.LookVector * FALLBACK_AHEAD
        local pos = h.Position + up + ahead
        return CFrame.new(pos, pos + h.CFrame.LookVector)
    end

    local function shouldConsiderModel(m)
        if not m or not m.Parent then return false end
        if not m:IsA("Model") then return false end
        if m:FindFirstChildOfClass("Humanoid") then return false end
        local pp = m.PrimaryPart
        if pp and pp:IsA("BasePart") then return true end
        local bp = m:FindFirstChildWhichIsA("BasePart", true)
        if bp then return true end
        return false
    end

    local function modelKey(m)
        if not m then return "nil" end
        return tostring(m.Name or "Model")
    end

    local function getCandidatesByOverlap(centerPos, radius)
        metrics.last = "overlap"
        metrics.overlapCalls += 1
        local parts = {}
        local ok, res = pcall(function()
            local params = OverlapParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {lp.Character}
            return WS:GetPartBoundsInRadius(centerPos, radius, params)
        end)
        if not ok then
            recordError("GetPartBoundsInRadius", res, "overlap")
            return {}
        end
        parts = res or {}
        metrics.overlapParts += #parts

        local models = {}
        local seen = {}
        for _, p in ipairs(parts) do
            local m = p:FindFirstAncestorOfClass("Model")
            if m and not seen[m] and shouldConsiderModel(m) then
                seen[m] = true
                models[#models+1] = m
            end
        end
        return models
    end

    local function fastBringToGround()
        metrics.last = "fastBringToGround"
        local h = hrp()
        if not h then return end

        requestStream(h.Position)

        local t0 = os.clock()
        local descendants = WS:GetDescendants()
        local itemsDesc = #descendants
        trace(("fastBringToGround scan descendants=%d limitOn=%s maxPerName=%d"):format(
            itemsDesc,
            tostring(C.State.BringLimitEnabled),
            currentLimit()
        ))

        local limitOn = (C.State.BringLimitEnabled == true)
        local limit = currentLimit()
        local perName = {}

        local queue = {}
        local queuedThis = 0
        local droppedThis = 0

        local overlapRadius = 75
        local overlapModels = getCandidatesByOverlap(h.Position, overlapRadius)
        metrics.cand = #overlapModels
        if #overlapModels > 0 then
            for _, m in ipairs(overlapModels) do
                local k = modelKey(m)
                if not limitOn or (perName[k] or 0) < limit then
                    perName[k] = (perName[k] or 0) + 1
                    queue[#queue+1] = m
                end
            end
        end

        if #queue == 0 then
            for _, inst in ipairs(descendants) do
                if inst:IsA("Model") and shouldConsiderModel(inst) then
                    local k = modelKey(inst)
                    if not limitOn or (perName[k] or 0) < limit then
                        perName[k] = (perName[k] or 0) + 1
                        queue[#queue+1] = inst
                        if #queue >= 250 then break end
                    end
                end
            end
        end

        metrics.queued += #queue
        queuedThis = #queue

        trace(("fastBringToGround scan done queue=%d dt=%.3f overlapCand=%d overlapParts=%d"):format(
            #queue,
            os.clock() - t0,
            metrics.cand,
            metrics.overlapParts
        ))

        local targetCF = dropCFrameNearPlayer()

        for i, m in ipairs(queue) do
            if m and m.Parent then
                trace(("dropNearPlayer model=%s idx=%d"):format(m.Name, i))
                local okStart = startDrag(m)
                if okStart then
                    safePivotTo(m, targetCF + Vector3.new(0, ORB_OFFSET_Y, 0))
                    stopDragOnce(m, "dropNearPlayer")
                    droppedThis += 1
                else
                    stopDragOnce(m, "startFail_cleanup")
                end
            end
        end

        metrics.dropped += droppedThis
        trace(("fastBringToGround dropped=%d"):format(droppedThis))
        info(("fastBringToGround end dt=%.3f runQueued=%d runDropped=%d stopDup=%d stopSkip=%d stopNoStart=%d startOk=%d startFail=%d topErrors={%s}"):format(
            os.clock() - t0,
            queuedThis,
            droppedThis,
            metrics.stopDup,
            metrics.stopSkip,
            metrics.stopNoStart,
            metrics.startOk,
            metrics.startFail,
            topErrors(3)
        ))

        for m, _ in pairs(activeDrag) do
            if m and m.Parent then
                stopDragOnce(m, "final_cleanup")
            end
        end
    end

    local lastStatAt = 0
    Run.Heartbeat:Connect(function()
        local t = os.clock()
        if t - lastStatAt < 0.25 then return end
        lastStatAt = t

        local luaKB = collectgarbage("count")
        local memMB = getMemMB()

        stat(("METRICS luaKB=%d itemsDesc=%d last=%s remoteFires=%d streamReqs=%d overlapCalls=%d overlapParts=%d cand=%d queued=%d dropped=%d convJobs=%d convWaves=%d convMoved=%d convActiveMax=%d convKick=%d errors=%d stopDup=%d stopSkip=%d stopNoStart=%d startOk=%d startFail=%d totalMemMB=%.3f topErr={%s}"):format(
            math.floor(luaKB + 0.5),
            #(WS:GetDescendants()),
            tostring(metrics.last),
            metrics.remoteFires,
            metrics.streamReqs,
            metrics.overlapCalls,
            metrics.overlapParts,
            metrics.cand,
            metrics.queued,
            metrics.dropped,
            metrics.convJobs,
            metrics.convWaves,
            metrics.convMoved,
            metrics.convActiveMax,
            metrics.convKick,
            metrics.errors,
            metrics.stopDup,
            metrics.stopSkip,
            metrics.stopNoStart,
            metrics.startOk,
            metrics.startFail,
            memMB,
            topErrors(3)
        ))
    end)

    if tab and type(tab.Button) == "function" then
        tab:Button({
            Title = "Fast Bring To Ground",
            Desc = "Drag nearby items and drop near you",
            Callback = function()
                fastBringToGround()
            end
        })
    end

    resolveRemotes(false)
end
