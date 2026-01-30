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

        C.State = C.State or {}
        if C.State.HasStrongAxe == nil then C.State.HasStrongAxe = false end

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

        local function looksDestroyed(treeModel, hitPart)
            if not treeModel then return true end
            if treeModel:IsDescendantOf(WS) == false then return true end
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
                if not anyPart then return true end
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
            if getCurrentHitCount(model) >= BIG_MAX_HITS_BEFORE_SKIP then return false end
            local p = bestTreeHitPart(model)
            if not p or looksDestroyed(model, p) then return false end
            return true
        end

        local function normName(s)
            return string.lower(tostring(s or ""))
        end

        local function classifyAxeName(nameLower)
            if nameLower:find("strong", 1, true) and nameLower:find("axe", 1, true) then return "Strong" end
            if nameLower:find("good", 1, true) and nameLower:find("axe", 1, true) then return "Good" end
            if nameLower:find("old", 1, true) and nameLower:find("axe", 1, true) then return "Old" end
            return nil
        end

        local function findBestAxeTierIn(container)
            if not container then return nil end
            local best
            for _, inst in ipairs(container:GetChildren()) do
                local tier = classifyAxeName(normName(inst.Name))
                if tier == "Strong" then return "Strong" end
                if tier == "Good" then best = best or "Good" end
                if tier == "Old" then best = best or "Old" end
            end
            return best
        end

        local function detectAxeTier()
            if C.State.HasStrongAxe then return "Strong" end
            local ch = lp.Character
            local tool = ch and ch:FindFirstChildOfClass("Tool")
            local tier = tool and classifyAxeName(normName(tool.Name))
            if tier == "Strong" then C.State.HasStrongAxe = true return "Strong" end
            if tier then return tier end
            local bp = lp:FindFirstChild("Backpack")
            tier = findBestAxeTierIn(bp)
            if tier == "Strong" then C.State.HasStrongAxe = true return "Strong" end
            if tier then return tier end
            local inv = lp:FindFirstChild("Inventory")
            tier = findBestAxeTierIn(inv)
            if tier == "Strong" then C.State.HasStrongAxe = true return "Strong" end
            return tier
        end

        local function requiredHitsTotal(isBig, tier)
            if tier == "Strong" then return isBig and 35 or 1 end
            if tier == "Good" then return isBig and math.huge or 6 end
            if tier == "Old" then return isBig and math.huge or 13 end
            return math.huge
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
            local ok = pcall(function() ch:PivotTo(cf) end)
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
            if okBig and getCurrentHitCount(tree) >= BIG_MAX_HITS_BEFORE_SKIP then
                markSkip(tree, DEAD_SKIP_SEC)
                return false
            end
            return true
        end

        local function xzDist(a, b)
            return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
        end

        local function findNearestTree(rootPos, tier)
            local bestTree, bestPart, bestD, bestIsBig = nil, nil, nil, false

            if moveSmall then
                for tree in pairs(SmallCandidates) do
                    if tree and tree.Parent and not shouldSkipTree(tree) and tree:IsDescendantOf(WS) then
                        if isSmallTreeModel(tree) then
                            local part = bestTreeHitPart(tree)
                            if part and not looksDestroyed(tree, part) then
                                local d = xzDist(part.Position, rootPos)
                                if bestD == nil or d < bestD then
                                    bestTree, bestPart, bestD, bestIsBig = tree, part, d, false
                                end
                            end
                        end
                    end
                end
            end

            if moveBig and tier == "Strong" then
                for tree in pairs(BigCandidates) do
                    if tree and tree.Parent and not shouldSkipTree(tree) and tree:IsDescendantOf(WS) then
                        if isBigTreeModel(tree) then
                            local part = bestTreeHitPart(tree)
                            if part and not looksDestroyed(tree, part) then
                                local d = xzDist(part.Position, rootPos)
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
            if dir.Magnitude < 1e-6 then dir = Vector3.new(0, 0, 1) end
            dir = dir.Unit

            local posXZ = Vector3.new(targetPos.X, 0, targetPos.Z) + (dir * (standoff or ARRIVE_DIST))
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

        local currentTarget = nil
        local currentIsBig = false
        local currentTier = nil
        local currentNeedHits = math.huge

        local function clearTarget(skip)
            if currentTarget and skip then
                markSkip(currentTarget, DEAD_SKIP_SEC)
            end
            currentTarget = nil
            currentIsBig = false
            currentTier = nil
            currentNeedHits = math.huge
        end

        local function setTarget(tree, isBig, tier)
            currentTarget = tree
            currentIsBig = (isBig == true)
            currentTier = tier
            currentNeedHits = requiredHitsTotal(currentIsBig, tier)
            if currentNeedHits == math.huge then
                clearTarget(true)
                return false
            end
            if currentIsBig and currentNeedHits > BIG_MAX_HITS_BEFORE_SKIP then
                currentNeedHits = BIG_MAX_HITS_BEFORE_SKIP
            end
            return true
        end

        local function startTeleportLoop()
            if loopConn then loopConn:Disconnect() loopConn = nil end
            running = true
            acc = 0
            lastScanAt = 0
            lastNoCandStepAt = 0
            lastSpaceTapAt = os.clock()
            clearTarget(false)

            loopConn = RunService.Heartbeat:Connect(function(dt)
                if not running then return end
                if not enabledNow() then
                    clearTarget(false)
                    return
                end

                acc += (dt or 0)
                if acc < TELEPORT_TICK then return end
                acc = 0

                local root = hrp()
                if not root then
                    clearTarget(false)
                    return
                end

                local now = os.clock()
                if (now - lastSpaceTapAt) >= SPACE_TAP_EVERY then
                    lastSpaceTapAt = now
                    tapSpace()
                end

                if currentTarget and (not isTreeValidForMode(currentTarget)) then
                    clearTarget(true)
                end

                if not currentTarget then
                    if (now - lastScanAt) >= RESCAN_COOLDOWN then
                        lastScanAt = now
                        local tier = detectAxeTier()
                        local pickedTree, pickedPart, pickedIsBig = findNearestTree(root.Position, tier)
                        if pickedTree and pickedPart then
                            if setTarget(pickedTree, pickedIsBig, tier) then
                            else
                                clearTarget(true)
                            end
                        end
                    end

                    if not currentTarget then
                        if (now - lastNoCandStepAt) >= NO_CANDIDATE_STEP_COOLDOWN then
                            lastNoCandStepAt = now
                            teleportRandomStep(root)
                        end
                        return
                    end
                end

                local part = bestTreeHitPart(currentTarget)
                if not part or looksDestroyed(currentTarget, part) then
                    clearTarget(true)
                    return
                end

                local rootPos = root.Position
                local targetPos = part.Position
                local dXZ = xzDist(targetPos, rootPos)

                if currentIsBig and dXZ <= BIG_GIVEUP_DIST then
                    local hits = getCurrentHitCount(currentTarget)
                    if hits >= BIG_MAX_HITS_BEFORE_SKIP then
                        clearTarget(true)
                        return
                    end
                end

                if dXZ > ARRIVE_DIST then
                    teleportNearTree(root, part, ARRIVE_DIST)
                    return
                end

                local hitsNow = getCurrentHitCount(currentTarget)
                if hitsNow >= currentNeedHits then
                    clearTarget(false)
                    lastScanAt = 0
                    return
                end

                if looksDestroyed(currentTarget, part) then
                    clearTarget(true)
                    lastScanAt = 0
                    return
                end
            end)
        end

        local function stopTeleportLoop()
            running = false
            if loopConn then loopConn:Disconnect() loopConn = nil end
            clearTarget(false)
        end

        local function cleanupAll()
            stopTeleportLoop()
            if descAddedConn then pcall(function() descAddedConn:Disconnect() end) descAddedConn = nil end
            if descRemovingConn then pcall(function() descRemovingConn:Disconnect() end) descRemovingConn = nil end
        end

        C.Farm._cleanup = cleanupAll

        tab:Section({ Title = "Tree Teleport (Wait For Required Hits)" })

        tab:Toggle({
            Title = "Teleport to Small Trees",
            Value = false,
            Callback = function(state)
                moveSmall = (state == true)
                clearTarget(false)
                if enabledNow() then startTeleportLoop() else stopTeleportLoop() end
            end
        })

        tab:Toggle({
            Title = "Teleport to Big Trees",
            Value = false,
            Callback = function(state)
                moveBig = (state == true)
                clearTarget(false)
                if enabledNow() then startTeleportLoop() else stopTeleportLoop() end
            end
        })
    end

    local ok, err = pcall(run)
    if not ok then warn("[Farm] module error: " .. tostring(err)) end
end
