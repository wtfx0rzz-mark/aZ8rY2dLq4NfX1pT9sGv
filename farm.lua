return function(C, R, UI)
    local function run()
        C = C or _G.C
        UI = UI or _G.UI

        local Services = (C and C.Services) or {}
        local Players = Services.Players or game:GetService("Players")
        local RS = Services.RS or game:GetService("ReplicatedStorage")
        local WS = Services.WS or game:GetService("Workspace")
        local RunService = Services.Run or game:GetService("RunService")
        local VIM = game:GetService("VirtualInputManager")

        local Tabs = (UI and UI.Tabs) or {}
        local tab = Tabs.Farm
        if not tab then return end

        local lp = Players.LocalPlayer
        if not lp then return end

        C.Farm = C.Farm or {}
        if type(C.Farm._cleanup) == "function" then
            pcall(C.Farm._cleanup)
        end

        local UID_SUFFIX = "0000000000"
        local BIG_MAX_HITS_BEFORE_SKIP = 36
        local DEAD_SKIP_SEC = 6.0

        local ARRIVE_DIST = 10
        local TELEPORT_TICK = 0.20
        local RESCAN_COOLDOWN = 0.25
        local NO_CANDIDATE_STEP = 30
        local NO_CANDIDATE_STEP_COOLDOWN = 0.35

        local BIG_GIVEUP_DIST = 25
        local Y_ABOVE_TARGET_PAD = 0.5

        local SPACE_TAP_EVERY = 60.0
        local DEBUG_DISTANCE = true
        local DEBUG_PRINT_EVERY = 0.6

        local RecentSkipUntil = {}

        local function shouldSkipTree(treeModel)
            local untilT = RecentSkipUntil[treeModel]
            return untilT ~= nil and os.clock() < untilT
        end

        local function markSkip(treeModel, sec)
            if not treeModel then return end
            RecentSkipUntil[treeModel] = os.clock() + (sec or DEAD_SKIP_SEC)
        end

        local function hrp()
            local ch = lp.Character
            return ch and ch:FindFirstChild("HumanoidRootPart")
        end

        local function attrBucket(treeModel)
            local hr = treeModel and treeModel:FindFirstChild("HitRegisters")
            if hr then return hr end
            return treeModel
        end

        local function parseHitAttrKey(k)
            local n = string.match(k or "", "^(%d+)_" .. UID_SUFFIX .. "$")
            return n and tonumber(n) or nil
        end

        local function getCurrentHitCount(treeModel)
            local bucket = attrBucket(treeModel)
            if not (bucket and bucket.GetAttributes) then return 0 end
            local attrs = bucket:GetAttributes()
            local maxN = 0
            for key in pairs(attrs) do
                local n = parseHitAttrKey(key)
                if n and n > maxN then maxN = n end
            end
            return maxN
        end

        local function bestTreeHitPart(tree)
            if not (tree and tree:IsA("Model")) then return nil end
            local hr = tree:FindFirstChild("HitRegisters")
            if hr then
                local t = hr:FindFirstChild("Trunk")
                if t and t:IsA("BasePart") then return t end
                local any = hr:FindFirstChildWhichIsA("BasePart")
                if any then return any end
            end
            local t2 = tree:FindFirstChild("Trunk")
            if t2 and t2:IsA("BasePart") then return t2 end
            if tree.PrimaryPart and tree.PrimaryPart:IsA("BasePart") then return tree.PrimaryPart end
            return tree:FindFirstChildWhichIsA("BasePart")
        end

        -- UPDATED: stronger "cut down" detection based on your logs:
        -- - Destroyed/LocalDestroyed attribute flips true
        -- - model/hitPart can reparent to ReplicatedStorage
        -- - HitRegisters/parts get removed
        local function looksDestroyed(treeModel, hitPart)
            if not treeModel then return true end

            -- if it leaves Workspace (logs show it reparenting to ReplicatedStorage), treat as destroyed/invalid
            if treeModel:IsDescendantOf(WS) == false then
                return true
            end

            if treeModel.GetAttribute then
                local a =
                    treeModel:GetAttribute("Destroyed") or
                    treeModel:GetAttribute("LocalDestroyed") or
                    treeModel:GetAttribute("IsDestroyed") or
                    treeModel:GetAttribute("Dead")
                if a == true then return true end
            end

            if hitPart and hitPart.GetAttribute then
                local b =
                    hitPart:GetAttribute("Destroyed") or
                    hitPart:GetAttribute("LocalDestroyed") or
                    hitPart:GetAttribute("IsDestroyed") or
                    hitPart:GetAttribute("Dead")
                if b == true then return true end
            end

            -- Post-cut behavior: HitRegisters removed and/or parts removed. Treat as destroyed if no HitRegisters and no parts.
            if treeModel:FindFirstChild("HitRegisters") == nil then
                local anyPart = treeModel:FindFirstChildWhichIsA("BasePart", true)
                if not anyPart then
                    return true
                end
            end

            return false
        end

        local function buildNameSet(baseSet, extra)
            local out = {}
            if type(baseSet) == "table" then
                for k, v in pairs(baseSet) do
                    if v == true and type(k) == "string" then out[k] = true end
                end
            end
            if type(extra) == "table" then
                for k, v in pairs(extra) do
                    if type(k) == "number" then
                        if type(v) == "string" then out[v] = true end
                    elseif type(k) == "string" and v == true then
                        out[k] = true
                    end
                end
            end
            return out
        end

        local TREE_NAMES_BASE = { ["Small Tree"] = true, ["Snowy Small Tree"] = true, ["Small Webbed Tree"] = true }
        local EXTRA_SMALL_TREE_NAMES = { ["Christmas Pine"] = true }
        local EXTRA_BIG_TREE_NAMES = { ["Northern Pine"] = true }
        local TREE_NAMES = buildNameSet(TREE_NAMES_BASE, EXTRA_SMALL_TREE_NAMES)

        local BIG_TREE_NAMES_BASE = { TreeBig1 = true, TreeBig2 = true, TreeBig3 = true }
        local BIG_TREE_NAMES = buildNameSet(BIG_TREE_NAMES_BASE, EXTRA_BIG_TREE_NAMES)

        local function isBigTreeName(name)
            if BIG_TREE_NAMES[name] then return true end
            if type(name) ~= "string" then return false end
            if name:match("^TreeBig%d+$") ~= nil then return true end
            return name:match("^WebbedTreeBig%d*$") ~= nil
        end

        local function maybeSmallTreeName(name)
            if TREE_NAMES[name] then return true end
            local lower = string.lower(name or "")
            return lower:find("small", 1, true) and lower:find("tree", 1, true)
        end

        local function maybeBigTreeName(name)
            return isBigTreeName(name)
        end

        -- UPDATED: ensure we only consider trees still in Workspace and not destroyed.
        local function isSmallTreeModel(model)
            if not (model and model:IsA("Model")) then return false end
            if model:IsDescendantOf(WS) == false then return false end
            if shouldSkipTree(model) then return false end

            local name = model.Name
            if TREE_NAMES[name] then
                local p = bestTreeHitPart(model)
                return p ~= nil and not looksDestroyed(model, p)
            end

            local lower = string.lower(name or "")
            if lower:find("small", 1, true) and lower:find("tree", 1, true) then
                local p = bestTreeHitPart(model)
                return p ~= nil and not looksDestroyed(model, p)
            end

            return false
        end

        -- UPDATED: same for big trees + hit ceiling pre-filter.
        local function isBigTreeModel(model)
            if not (model and model:IsA("Model")) then return false end
            if model:IsDescendantOf(WS) == false then return false end
            if shouldSkipTree(model) then return false end

            if type(model.Name) == "string" and model.Name:match("^TreeBig%d+$") then
                local parent = model.Parent
                if parent and parent.Name == "Snare Trap" then
                    return false
                end
            end

            if not isBigTreeName(model.Name) then return false end

            if getCurrentHitCount(model) >= BIG_MAX_HITS_BEFORE_SKIP then
                return false
            end

            local p = bestTreeHitPart(model)
            if not p or looksDestroyed(model, p) then return false end

            return true
        end

        local SmallCandidates = {}
        local BigCandidates = {}

        local function addCandidateFromModel(m)
            if not (m and m:IsA("Model")) then return end
            if maybeSmallTreeName(m.Name) then SmallCandidates[m] = true end
            if maybeBigTreeName(m.Name) then BigCandidates[m] = true end
        end

        local function addCandidateFromPart(p)
            if not (p and p:IsA("BasePart")) then return end
            local m = p:FindFirstAncestorOfClass("Model")
            if m then addCandidateFromModel(m) end
        end

        for _, inst in ipairs(WS:GetDescendants()) do
            if inst:IsA("Model") then
                addCandidateFromModel(inst)
            elseif inst:IsA("BasePart") then
                addCandidateFromPart(inst)
            end
        end

        local descAddedConn = WS.DescendantAdded:Connect(function(inst)
            if inst:IsA("Model") then
                addCandidateFromModel(inst)
            elseif inst:IsA("BasePart") then
                addCandidateFromPart(inst)
            end
        end)

        local descRemovingConn = WS.DescendantRemoving:Connect(function(inst)
            if SmallCandidates[inst] then SmallCandidates[inst] = nil end
            if BigCandidates[inst] then BigCandidates[inst] = nil end
            if RecentSkipUntil[inst] then RecentSkipUntil[inst] = nil end
        end)

        local function tapSpace()
            pcall(function()
                VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.wait(0.05)
                VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
        end

        local function pivotCharacterTo(cf)
            local ch = lp.Character or lp.CharacterAdded:Wait()
            if not ch then return false end
            local ok = pcall(function()
                ch:PivotTo(cf)
            end)
            return ok
        end

        local moveSmall = false
        local moveBig = false

        local function enabledNow()
            return moveSmall or moveBig
        end

        local function isTreeValidForMode(tree)
            if not (tree and tree.Parent) then return false end
            if tree:IsDescendantOf(WS) == false then return false end
            if shouldSkipTree(tree) then return false end
            local part = bestTreeHitPart(tree)
            if not part or looksDestroyed(tree, part) then return false end

            local okSmall = moveSmall and isSmallTreeModel(tree)
            local okBig = moveBig and isBigTreeModel(tree)
            if not (okSmall or okBig) then return false end

            -- extra big-tree safeguard: skip maxed hit-count trees even if still present
            if okBig then
                if getCurrentHitCount(tree) >= BIG_MAX_HITS_BEFORE_SKIP then
                    markSkip(tree, DEAD_SKIP_SEC)
                    return false
                end
            end

            return true
        end

        -- This already satisfies:
        -- - only small toggle on => only scans SmallCandidates/isSmallTreeModel
        -- - only big toggle on   => only scans BigCandidates/isBigTreeModel
        -- - both on             => chooses nearest across both via shared bestD
        local function findNearestTree(rootPos)
            local bestTree, bestPart, bestD, bestIsBig = nil, nil, nil, false

            if moveSmall then
                for tree in pairs(SmallCandidates) do
                    if tree and tree.Parent and not shouldSkipTree(tree) and tree:IsDescendantOf(WS) then
                        if isSmallTreeModel(tree) then
                            local part = bestTreeHitPart(tree)
                            if part and not looksDestroyed(tree, part) then
                                local d = (part.Position - rootPos).Magnitude
                                if bestD == nil or d < bestD then
                                    bestTree, bestPart, bestD, bestIsBig = tree, part, d, false
                                end
                            end
                        end
                    end
                end
            end

            if moveBig then
                for tree in pairs(BigCandidates) do
                    if tree and tree.Parent and not shouldSkipTree(tree) and tree:IsDescendantOf(WS) then
                        if isBigTreeModel(tree) then
                            local part = bestTreeHitPart(tree)
                            if part and not looksDestroyed(tree, part) then
                                local d = (part.Position - rootPos).Magnitude
                                if bestD == nil or d < bestD then
                                    bestTree, bestPart, bestD, bestIsBig = tree, part, d, true
                                end
                            end
                        end
                    end
                end
            end

            return bestTree, bestPart, bestIsBig, bestD
        end

        local function teleportNearTree(root, part, standoff)
            local rootPos = root.Position
            local targetPos = part.Position

            local dir = Vector3.new(rootPos.X - targetPos.X, 0, rootPos.Z - targetPos.Z)
            if dir.Magnitude < 1e-6 then
                local cam = WS.CurrentCamera
                local look = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
                dir = Vector3.new(-look.X, 0, -look.Z)
            end
            if dir.Magnitude < 1e-6 then
                dir = Vector3.new(0, 0, 1)
            end
            dir = dir.Unit

            local posXZ = Vector3.new(targetPos.X, 0, targetPos.Z) + (dir * (standoff or ARRIVE_DIST))

            -- ensure we never go below target tree's Y
            local newY = math.max(rootPos.Y, targetPos.Y + Y_ABOVE_TARGET_PAD)
            local newPos = Vector3.new(posXZ.X, newY, posXZ.Z)

            local cf = CFrame.new(newPos, Vector3.new(targetPos.X, newY, targetPos.Z))
            pivotCharacterTo(cf)
        end

        local function teleportRandomStep(root)
            local ang = math.random() * math.pi * 2
            local dx = math.cos(ang) * NO_CANDIDATE_STEP
            local dz = math.sin(ang) * NO_CANDIDATE_STEP
            local step = Vector3.new(dx, 0, dz)
            local cf = root.CFrame + step
            pivotCharacterTo(cf)
        end

        local running = false
        local loopConn = nil
        local acc = 0
        local lastScanAt = 0
        local lastNoCandStepAt = 0
        local lastSpaceTapAt = 0
        local lastDebugAt = 0

        local currentTarget = nil
        local currentIsBig = false

        local function startTeleportLoop()
            if loopConn then loopConn:Disconnect() loopConn = nil end
            running = true
            acc = 0
            lastScanAt = 0
            lastNoCandStepAt = 0
            lastSpaceTapAt = os.clock()
            lastDebugAt = 0
            currentTarget = nil
            currentIsBig = false

            loopConn = RunService.Heartbeat:Connect(function(dt)
                if not running then return end
                if not enabledNow() then
                    currentTarget = nil
                    currentIsBig = false
                    return
                end

                acc += (dt or 0)
                if acc < TELEPORT_TICK then return end
                acc = 0

                local root = hrp()
                if not root then
                    currentTarget = nil
                    currentIsBig = false
                    return
                end

                local now = os.clock()
                if (now - lastSpaceTapAt) >= SPACE_TAP_EVERY then
                    lastSpaceTapAt = now
                    tapSpace()
                end

                if currentTarget and (not isTreeValidForMode(currentTarget)) then
                    currentTarget = nil
                    currentIsBig = false
                end

                if (now - lastScanAt) >= RESCAN_COOLDOWN then
                    lastScanAt = now
                    local pickedTree, pickedPart, pickedIsBig, pickedD = findNearestTree(root.Position)
                    if pickedTree and pickedPart then
                        currentTarget = pickedTree
                        currentIsBig = pickedIsBig
                    else
                        currentTarget = nil
                        currentIsBig = false
                    end
                end

                if not currentTarget then
                    if (now - lastNoCandStepAt) >= NO_CANDIDATE_STEP_COOLDOWN then
                        lastNoCandStepAt = now
                        teleportRandomStep(root)
                    end
                    return
                end

                local part = bestTreeHitPart(currentTarget)
                if not part or looksDestroyed(currentTarget, part) then
                    markSkip(currentTarget, DEAD_SKIP_SEC)
                    currentTarget = nil
                    currentIsBig = false
                    return
                end

                local rootPos = root.Position
                local targetPos = part.Position

                local dXZ = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(rootPos.X, 0, rootPos.Z)).Magnitude
                local dY = (targetPos.Y - rootPos.Y)

                if currentIsBig and dXZ <= BIG_GIVEUP_DIST then
                    local hits = getCurrentHitCount(currentTarget)
                    if hits >= BIG_MAX_HITS_BEFORE_SKIP then
                        markSkip(currentTarget, DEAD_SKIP_SEC)
                        currentTarget = nil
                        currentIsBig = false
                        return
                    end
                end

                if DEBUG_DISTANCE and (now - lastDebugAt) >= DEBUG_PRINT_EVERY then
                    lastDebugAt = now
                    local hits = (currentIsBig and getCurrentHitCount(currentTarget)) or 0
                    warn(("[FarmTP] target=%s isBig=%s d=%.1f dXZ=%.1f dY=%.1f arrive=%d hits=%d"):format(
                        tostring(currentTarget.Name),
                        tostring(currentIsBig),
                        ((targetPos - rootPos).Magnitude),
                        dXZ,
                        dY,
                        ARRIVE_DIST,
                        hits
                    ))
                end

                if dXZ > ARRIVE_DIST then
                    teleportNearTree(root, part, ARRIVE_DIST)
                end
            end)
        end

        local function stopTeleportLoop()
            running = false
            if loopConn then loopConn:Disconnect() loopConn = nil end
            currentTarget = nil
            currentIsBig = false
        end

        local function cleanupAll()
            stopTeleportLoop()
            if descAddedConn then pcall(function() descAddedConn:Disconnect() end) descAddedConn = nil end
            if descRemovingConn then pcall(function() descRemovingConn:Disconnect() end) descRemovingConn = nil end
        end

        C.Farm._cleanup = cleanupAll

        tab:Section({ Title = "Tree Teleport (Nearest Candidate)" })

        tab:Toggle({
            Title = "Teleport to Small Trees",
            Value = false,
            Callback = function(state)
                moveSmall = (state == true)
                if enabledNow() then
                    startTeleportLoop()
                else
                    stopTeleportLoop()
                end
            end
        })

        tab:Toggle({
            Title = "Teleport to Big Trees",
            Value = false,
            Callback = function(state)
                moveBig = (state == true)
                if enabledNow() then
                    startTeleportLoop()
                else
                    stopTeleportLoop()
                end
            end
        })
    end

    local ok, err = pcall(run)
    if not ok then warn("[Farm] module error: " .. tostring(err)) end
end
