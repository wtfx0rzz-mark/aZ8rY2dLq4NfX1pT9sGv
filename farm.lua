return function(C, R, UI)
    local function run()
        C = C or _G.C
        UI = UI or _G.UI

        local Services = (C and C.Services) or {}
        local Players = Services.Players or game:GetService("Players")
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

        local TELEPORT_TICK = 0.10
        local RESCAN_COOLDOWN = 0.15

        local ARRIVE_DIST = 7.5
        local Y_ABOVE_TARGET_PAD = 0.5

        local NO_CANDIDATE_STEP = 30
        local NO_CANDIDATE_STEP_COOLDOWN = 0.35

        local SKIP_SEC = 2.5
        local NO_PROGRESS_SEC = 1.25

        -- Farm jump input: match diamonds.lua behavior (space tap every 5s while enabled)
        local SPACE_TAP_EVERY = 5.0

        -- Big-tree group mode: rotate among nearest 5 big trees, switching once per second
        local BIG_GROUP_SIZE = 5
        local BIG_GROUP_SWITCH_EVERY = 1.0

        local RecentSkipUntil = {}

        local function shouldSkipTree(treeModel)
            local untilT = RecentSkipUntil[treeModel]
            return untilT ~= nil and os.clock() < untilT
        end

        local function markSkip(treeModel, sec)
            if not treeModel then return end
            RecentSkipUntil[treeModel] = os.clock() + (sec or SKIP_SEC)
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

        local function findTrunkPart(tree)
            if not (tree and tree:IsA("Model")) then return nil end
            local hr = tree:FindFirstChild("HitRegisters")
            if hr then
                local t = hr:FindFirstChild("Trunk")
                if t and t:IsA("BasePart") then return t end
            end
            local t2 = tree:FindFirstChild("Trunk")
            if t2 and t2:IsA("BasePart") then return t2 end
            return nil
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
            return tree:FindFirstChildWhichIsA("BasePart", true)
        end

        local function looksDestroyed(treeModel, hitPart)
            if not treeModel then return true end
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

        local function isSmallTreeModel(model)
            if not (model and model:IsA("Model")) then return false end
            if model:IsDescendantOf(WS) == false then return false end
            if shouldSkipTree(model) then return false end
            if not maybeSmallTreeName(model.Name) then return false end
            local p = bestTreeHitPart(model)
            if not p or looksDestroyed(model, p) then return false end
            if not findTrunkPart(model) then return false end
            return true
        end

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
            local p = bestTreeHitPart(model)
            if not p or looksDestroyed(model, p) then return false end
            if not findTrunkPart(model) then return false end
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

        local function farmJumpSendSpaceTap()
            local ok, err = pcall(function()
                VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.wait(0.05)
                VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
            end)
            return ok, err
        end

        local function pivotCharacterTo(cf)
            local ch = lp.Character or lp.CharacterAdded:Wait()
            if not ch then return false end
            local ok = pcall(function()
                ch:PivotTo(cf)
            end)
            return ok
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

            local dist = standoff or ARRIVE_DIST
            local posXZ = Vector3.new(targetPos.X, 0, targetPos.Z) + (dir * dist)
            local newY = math.max(rootPos.Y, targetPos.Y + Y_ABOVE_TARGET_PAD)
            local newPos = Vector3.new(posXZ.X, newY, posXZ.Z)

            local cf = CFrame.new(newPos, Vector3.new(targetPos.X, newY, targetPos.Z))
            pivotCharacterTo(cf)
            return newPos
        end

        local function teleportRandomStep(root)
            local ang = math.random() * math.pi * 2
            local dx = math.cos(ang) * NO_CANDIDATE_STEP
            local dz = math.sin(ang) * NO_CANDIDATE_STEP
            local step = Vector3.new(dx, 0, dz)
            pivotCharacterTo(root.CFrame + step)
        end

        local moveSmall = false
        local moveBig = false

        local function enabledNow()
            return moveSmall or moveBig
        end

        local function isTreeValid(tree, isBig)
            if not (tree and tree.Parent) then return false end
            if tree:IsDescendantOf(WS) == false then return false end
            if shouldSkipTree(tree) then return false end
            local part = bestTreeHitPart(tree)
            if not part or looksDestroyed(tree, part) then return false end
            if not findTrunkPart(tree) then return false end
            if isBig then
                if not isBigTreeModel(tree) then return false end
            else
                if not isSmallTreeModel(tree) then return false end
            end
            return true
        end

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

        local function findNearestBigTrees(rootPos, maxCount)
            local list = {}
            for tree in pairs(BigCandidates) do
                if tree and tree.Parent and not shouldSkipTree(tree) and tree:IsDescendantOf(WS) then
                    if isBigTreeModel(tree) then
                        local part = bestTreeHitPart(tree)
                        if part and not looksDestroyed(tree, part) then
                            local d = (part.Position - rootPos).Magnitude
                            list[#list + 1] = { tree = tree, part = part, d = d }
                        end
                    end
                end
            end
            table.sort(list, function(a, b) return a.d < b.d end)
            local out = {}
            local n = math.min(#list, maxCount or BIG_GROUP_SIZE)
            for i = 1, n do
                out[#out + 1] = list[i].tree
            end
            return out
        end

        local running = false
        local loopConn = nil
        local acc = 0
        local lastScanAt = 0
        local lastNoCandStepAt = 0
        local lastSpaceTapAt = 0

        local currentTarget = nil
        local currentIsBig = false
        local targetSetAt = 0
        local trunkWasPresent = false
        local hitBaseline = 0

        -- Big-tree group rotation state
        local bigGroup = nil
        local bigGroupIndex = 1
        local bigGroupLastSwitchAt = 0
        local bigTreeHitBaseline = setmetatable({}, { __mode = "k" })
        local bigTreeSetAt = setmetatable({}, { __mode = "k" })
        local bigTreeTrunkWasPresent = setmetatable({}, { __mode = "k" })

        local function clearTarget(_reason, doSkip)
            if currentTarget and doSkip then
                markSkip(currentTarget, SKIP_SEC)
            end
            currentTarget = nil
            currentIsBig = false
            targetSetAt = 0
            trunkWasPresent = false
            hitBaseline = 0
        end

        local function clearBigGroup(_reason)
            bigGroup = nil
            bigGroupIndex = 1
            bigGroupLastSwitchAt = 0
            bigTreeHitBaseline = setmetatable({}, { __mode = "k" })
            bigTreeSetAt = setmetatable({}, { __mode = "k" })
            bigTreeTrunkWasPresent = setmetatable({}, { __mode = "k" })
        end

        local function pickNewTarget(root)
            local nowT = os.clock()
            if (nowT - lastScanAt) < RESCAN_COOLDOWN then
                return false
            end
            lastScanAt = nowT

            local tree, part, isBig = findNearestTree(root.Position)
            if tree and part then
                currentTarget = tree
                currentIsBig = isBig
                targetSetAt = nowT

                trunkWasPresent = (findTrunkPart(tree) ~= nil)
                hitBaseline = getCurrentHitCount(tree)

                teleportNearTree(root, part, ARRIVE_DIST)
                return true
            end
            return false
        end

        local function ensureBigGroup(root)
            local nowT = os.clock()
            if (nowT - lastScanAt) < RESCAN_COOLDOWN then
                return false
            end
            lastScanAt = nowT

            local grp = findNearestBigTrees(root.Position, BIG_GROUP_SIZE)
            if #grp == 0 then
                clearBigGroup("none")
                return false
            end

            bigGroup = grp
            bigGroupIndex = 1
            bigGroupLastSwitchAt = 0

            bigTreeHitBaseline = setmetatable({}, { __mode = "k" })
            bigTreeSetAt = setmetatable({}, { __mode = "k" })
            bigTreeTrunkWasPresent = setmetatable({}, { __mode = "k" })

            for i = 1, #bigGroup do
                local t = bigGroup[i]
                if t then
                    bigTreeTrunkWasPresent[t] = (findTrunkPart(t) ~= nil)
                    bigTreeHitBaseline[t] = getCurrentHitCount(t)
                    bigTreeSetAt[t] = nowT
                end
            end

            return true
        end

        local function pickNextBigFromGroup(root)
            if not bigGroup or #bigGroup == 0 then
                if not ensureBigGroup(root) then return false end
            end

            local alive = 0
            for i = 1, #bigGroup do
                local t = bigGroup[i]
                if t and isTreeValid(t, true) then
                    alive += 1
                end
            end
            if alive <= 0 then
                clearBigGroup("dead")
                return ensureBigGroup(root)
            end

            local tries = #bigGroup
            for _ = 1, tries do
                if bigGroupIndex > #bigGroup then bigGroupIndex = 1 end
                local t = bigGroup[bigGroupIndex]
                bigGroupIndex += 1
                if t and isTreeValid(t, true) then
                    currentTarget = t
                    currentIsBig = true
                    targetSetAt = os.clock()
                    trunkWasPresent = (findTrunkPart(t) ~= nil)
                    hitBaseline = getCurrentHitCount(t)
                    return true
                end
            end

            clearBigGroup("no_valid")
            return ensureBigGroup(root)
        end

        local function startTeleportLoop()
            if loopConn then loopConn:Disconnect() loopConn = nil end
            running = true
            acc = 0
            lastScanAt = 0
            lastNoCandStepAt = 0
            lastSpaceTapAt = os.clock()
            clearTarget("start", false)
            clearBigGroup("start")

            loopConn = RunService.Heartbeat:Connect(function(dt)
                if not running then return end
                if not enabledNow() then
                    clearTarget("disabled", false)
                    clearBigGroup("disabled")
                    return
                end

                acc += (dt or 0)
                if acc < TELEPORT_TICK then return end
                acc = 0

                local root = hrp()
                if not root then
                    clearTarget("no_hrp", false)
                    clearBigGroup("no_hrp")
                    return
                end

                local nowT = os.clock()
                if (nowT - lastSpaceTapAt) >= SPACE_TAP_EVERY then
                    lastSpaceTapAt = nowT
                    farmJumpSendSpaceTap()
                end

                -- Big-tree group mode: rotate once per second among nearest 5 big trees
                if moveBig then
                    if (nowT - bigGroupLastSwitchAt) >= BIG_GROUP_SWITCH_EVERY or (not currentTarget) or (currentIsBig ~= true) then
                        bigGroupLastSwitchAt = nowT
                        if not pickNextBigFromGroup(root) then
                            if (not moveSmall) and (nowT - lastNoCandStepAt) >= NO_CANDIDATE_STEP_COOLDOWN then
                                lastNoCandStepAt = nowT
                                teleportRandomStep(root)
                            end
                        end
                    end
                elseif currentIsBig then
                    clearTarget("big_off", false)
                    clearBigGroup("big_off")
                end

                -- Small trees keep single-target behavior
                if moveSmall then
                    if not currentTarget or currentIsBig then
                        clearTarget("small_takeover", false)
                        local okPick = pickNewTarget(root)
                        if not okPick then
                            if (not moveBig) and (nowT - lastNoCandStepAt) >= NO_CANDIDATE_STEP_COOLDOWN then
                                lastNoCandStepAt = nowT
                                teleportRandomStep(root)
                            end
                        end
                        return
                    end
                else
                    if currentTarget and currentIsBig == false then
                        clearTarget("small_off", false)
                    end
                end

                if not currentTarget then
                    if moveSmall then
                        local okPick = pickNewTarget(root)
                        if not okPick and (not moveBig) then
                            if (nowT - lastNoCandStepAt) >= NO_CANDIDATE_STEP_COOLDOWN then
                                lastNoCandStepAt = nowT
                                teleportRandomStep(root)
                            end
                        end
                    end
                    return
                end

                if not isTreeValid(currentTarget, currentIsBig) then
                    clearTarget("invalid", true)
                    if currentIsBig then
                        bigTreeHitBaseline[currentTarget] = nil
                        bigTreeSetAt[currentTarget] = nil
                        bigTreeTrunkWasPresent[currentTarget] = nil
                    end
                    return
                end

                if trunkWasPresent and findTrunkPart(currentTarget) == nil then
                    clearTarget("trunk_removed", true)
                    return
                end

                local hits = getCurrentHitCount(currentTarget)
                local noHitProgress = (hits <= hitBaseline)
                local trunkStill = (findTrunkPart(currentTarget) ~= nil)

                -- Keep the same no-progress + hit-cap behavior per tree (works for both, but big trees rotate so it’s less sticky)
                if (nowT - targetSetAt) >= NO_PROGRESS_SEC and noHitProgress and trunkStill then
                    clearTarget("no_progress", true)
                    return
                end

                if currentIsBig and hits >= BIG_MAX_HITS_BEFORE_SKIP then
                    clearTarget("big_hit_cap", true)
                    return
                end

                local part = bestTreeHitPart(currentTarget)
                if not part or looksDestroyed(currentTarget, part) then
                    clearTarget("no_part", true)
                    return
                end

                local rootPos = root.Position
                local tPos = part.Position
                local dXZ = (Vector3.new(tPos.X, 0, tPos.Z) - Vector3.new(rootPos.X, 0, rootPos.Z)).Magnitude

                if dXZ > ARRIVE_DIST then
                    teleportNearTree(root, part, ARRIVE_DIST)
                end
            end)
        end

        local function stopTeleportLoop()
            running = false
            if loopConn then loopConn:Disconnect() loopConn = nil end
            clearTarget("stop", false)
            clearBigGroup("stop")
        end

        local function cleanupAll()
            stopTeleportLoop()
            if descAddedConn then pcall(function() descAddedConn:Disconnect() end) descAddedConn = nil end
            if descRemovingConn then pcall(function() descRemovingConn:Disconnect() end) descRemovingConn = nil end
        end

        C.Farm._cleanup = cleanupAll

        tab:Section({ Title = "Tree Teleport (Single Target, Fast)" })

        tab:Toggle({
            Title = "Teleport to Small Trees",
            Value = false,
            Callback = function(state)
                moveSmall = (state == true)
                clearTarget("toggle_small", false)
                if enabledNow() then
                    startTeleportLoop()
                else
                    stopTeleportLoop()
                end
            end
        })

        tab:Toggle({
            Title = "Teleport to Big Trees (Rotate 5)",
            Value = false,
            Callback = function(state)
                moveBig = (state == true)
                clearTarget("toggle_big", false)
                clearBigGroup("toggle_big")
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
