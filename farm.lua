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
        local MOVE_TICK = 0.08
        local RESCAN_COOLDOWN = 0.35

        local RecentSkipUntil = setmetatable({}, { __mode = "k" })

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
            local a = treeModel.GetAttribute and (treeModel:GetAttribute("Destroyed") or treeModel:GetAttribute("IsDestroyed") or treeModel:GetAttribute("Dead"))
            if a == true then return true end
            if hitPart and hitPart.GetAttribute then
                local b = hitPart:GetAttribute("Destroyed") or hitPart:GetAttribute("IsDestroyed") or hitPart:GetAttribute("Dead")
                if b == true then return true end
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

            if getCurrentHitCount(model) >= BIG_MAX_HITS_BEFORE_SKIP then
                return false
            end

            return true
        end

        local SmallCandidates = setmetatable({}, { __mode = "k" })
        local BigCandidates = setmetatable({}, { __mode = "k" })

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

        -- Key simulation (same approach as diamonds.lua: VirtualInputManager:SendKeyEvent)
        local keyHeld = { W = false, A = false, S = false, D = false }

        local function sendKey(keyName, down)
            local code = Enum.KeyCode[keyName]
            pcall(function()
                VIM:SendKeyEvent(down, code, false, game)
            end)
        end

        local function setKey(keyName, down)
            if keyHeld[keyName] == down then return end
            keyHeld[keyName] = down
            sendKey(keyName, down)
        end

        local function releaseAllKeys()
            setKey("W", false)
            setKey("A", false)
            setKey("S", false)
            setKey("D", false)
        end

        local function applyMoveToward(targetPos, rootPos)
            local delta = targetPos - rootPos
            local desired = Vector3.new(delta.X, 0, delta.Z)
            if desired.Magnitude < 1e-6 then
                releaseAllKeys()
                return
            end
            desired = desired.Unit

            local cam = WS.CurrentCamera
            local f = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
            local r = cam and cam.CFrame.RightVector or Vector3.new(1, 0, 0)
            f = Vector3.new(f.X, 0, f.Z)
            r = Vector3.new(r.X, 0, r.Z)
            if f.Magnitude < 1e-6 then f = Vector3.new(0, 0, -1) end
            if r.Magnitude < 1e-6 then r = Vector3.new(1, 0, 0) end
            f = f.Unit
            r = r.Unit

            local fd = desired:Dot(f)
            local rd = desired:Dot(r)
            local th = 0.25

            -- Press/hold keys as needed; release when not needed
            setKey("W", fd > th)
            setKey("S", fd < -th)
            setKey("D", rd > th)
            setKey("A", rd < -th)
        end

        local moveSmall = false
        local moveBig = false

        local function enabledNow()
            return moveSmall or moveBig
        end

        local function isTreeValidForMode(tree)
            if not (tree and tree.Parent) then return false end
            if shouldSkipTree(tree) then return false end
            local part = bestTreeHitPart(tree)
            if not part or looksDestroyed(tree, part) then return false end

            local isSmall = moveSmall and isSmallTreeModel(tree)
            local isBig = moveBig and isBigTreeModel(tree)
            if not (isSmall or isBig) then return false end

            if isBig then
                local hits = getCurrentHitCount(tree)
                if hits >= BIG_MAX_HITS_BEFORE_SKIP then
                    markSkip(tree, DEAD_SKIP_SEC)
                    BigCandidates[tree] = nil
                    return false
                end
            end

            return true
        end

        local function findNearestTree(rootPos)
            local bestTree, bestPart, bestD, bestIsBig = nil, nil, nil, false

            if moveSmall then
                for tree in pairs(SmallCandidates) do
                    if tree and tree.Parent and not shouldSkipTree(tree) then
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
                    if tree and tree.Parent and not shouldSkipTree(tree) then
                        if isBigTreeModel(tree) then
                            local part = bestTreeHitPart(tree)
                            if part and not looksDestroyed(tree, part) then
                                local hits = getCurrentHitCount(tree)
                                if hits >= BIG_MAX_HITS_BEFORE_SKIP then
                                    markSkip(tree, DEAD_SKIP_SEC)
                                    BigCandidates[tree] = nil
                                else
                                    local d = (part.Position - rootPos).Magnitude
                                    if bestD == nil or d < bestD then
                                        bestTree, bestPart, bestD, bestIsBig = tree, part, d, true
                                    end
                                end
                            end
                        end
                    end
                end
            end

            return bestTree, bestPart, bestIsBig
        end

        local moving = false
        local moveConn = nil
        local acc = 0
        local lastScanAt = 0

        local currentTarget = nil
        local currentIsBig = false

        local function startMoveLoop()
            if moveConn then moveConn:Disconnect() moveConn = nil end
            moving = true
            acc = 0
            lastScanAt = 0
            currentTarget = nil
            currentIsBig = false
            releaseAllKeys()

            moveConn = RunService.Heartbeat:Connect(function(dt)
                if not moving then return end
                if not enabledNow() then
                    currentTarget = nil
                    currentIsBig = false
                    releaseAllKeys()
                    return
                end

                acc += (dt or 0)
                if acc < MOVE_TICK then return end
                acc = 0

                local root = hrp()
                if not root then
                    currentTarget = nil
                    currentIsBig = false
                    releaseAllKeys()
                    return
                end

                if currentTarget and (not isTreeValidForMode(currentTarget)) then
                    currentTarget = nil
                    currentIsBig = false
                end

                local now = os.clock()
                if (not currentTarget) and (now - lastScanAt) >= RESCAN_COOLDOWN then
                    lastScanAt = now
                    local t, part, isBig = findNearestTree(root.Position)
                    if t and part then
                        currentTarget = t
                        currentIsBig = isBig
                    else
                        currentTarget = nil
                        currentIsBig = false
                        releaseAllKeys()
                        return
                    end
                end

                if not currentTarget then
                    releaseAllKeys()
                    return
                end

                local part = bestTreeHitPart(currentTarget)
                if not part or looksDestroyed(currentTarget, part) then
                    markSkip(currentTarget, DEAD_SKIP_SEC)
                    currentTarget = nil
                    currentIsBig = false
                    releaseAllKeys()
                    return
                end

                if currentIsBig then
                    local hits = getCurrentHitCount(currentTarget)
                    if hits >= BIG_MAX_HITS_BEFORE_SKIP then
                        markSkip(currentTarget, DEAD_SKIP_SEC)
                        BigCandidates[currentTarget] = nil
                        currentTarget = nil
                        currentIsBig = false
                        releaseAllKeys()
                        return
                    end
                end

                local rootPos = root.Position
                local targetPos = part.Position

                local dXZ = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(rootPos.X, 0, rootPos.Z)).Magnitude
                if dXZ <= ARRIVE_DIST then
                    releaseAllKeys()
                    return
                end

                applyMoveToward(targetPos, rootPos)
            end)
        end

        local function stopMoveLoop()
            moving = false
            if moveConn then moveConn:Disconnect() moveConn = nil end
            currentTarget = nil
            currentIsBig = false
            releaseAllKeys()
        end

        local function cleanupAll()
            stopMoveLoop()
            if descAddedConn then pcall(function() descAddedConn:Disconnect() end) descAddedConn = nil end
            if descRemovingConn then pcall(function() descRemovingConn:Disconnect() end) descRemovingConn = nil end
        end

        C.Farm._cleanup = cleanupAll

        tab:Section({ Title = "Tree Move (WASD via VIM)" })

        tab:Toggle({
            Title = "Move to Small Trees",
            Value = false,
            Callback = function(state)
                moveSmall = (state == true)
                if enabledNow() then
                    startMoveLoop()
                else
                    stopMoveLoop()
                end
            end
        })

        tab:Toggle({
            Title = "Move to Big Trees",
            Value = false,
            Callback = function(state)
                moveBig = (state == true)
                if enabledNow() then
                    startMoveLoop()
                else
                    stopMoveLoop()
                end
            end
        })
    end

    local ok, err = pcall(run)
    if not ok then warn("[Farm] module error: " .. tostring(err)) end
end
