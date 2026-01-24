return function(C, R, UI)
    local function run()
        C = C or _G.C
        UI = UI or _G.UI

        local Services = (C and C.Services) or {}
        local Players = Services.Players or game:GetService("Players")
        local RS = Services.RS or game:GetService("ReplicatedStorage")
        local WS = Services.WS or game:GetService("Workspace")
        local RunService = Services.Run or game:GetService("RunService")

        local Tabs = (UI and UI.Tabs) or {}
        local tab = Tabs.Farm
        if not tab then return end

        local lp = Players.LocalPlayer
        if not lp then return end

        C.Farm = C.Farm or {}
        if type(C.Farm._cleanup) == "function" then
            pcall(C.Farm._cleanup)
        end

        local RemoteEvents = RS:WaitForChild("RemoteEvents")
        local ToolDamageObject = RemoteEvents:WaitForChild("ToolDamageObject")
        local EquipItemHandle = RemoteEvents:WaitForChild("EquipItemHandle")

        local CHOP_RADIUS = 60
        local TELEPORT_DISTANCE = 30
        local UID_SUFFIX = "0000000000"

        local SWING_COOLDOWN_BIG = 0.5
        local TELEPORT_THROTTLE = 0.06

        local CIRCLE_RESCAN_EVERY = 2.5
        local CIRCLE_START_RADIUS = 90
        local CIRCLE_RADIUS_STEP = 70
        local CIRCLE_RADIUS_MAX = 1200

        local MAX_TREE_QUEUE = 250

        local SMALL_STEP_INTERVAL = 0.05
        local SMALL_HITS_PER_STEP = 10
        local SMALL_NEXT_TREE_DELAY = 0.25

        local BIG_ZERO_PACE_DELAY = 0.0

        local BIG_MAX_TOTAL_HITS = 40
        local BIG_MAX_NO_PROGRESS_TRIES = 2

        local SMALL_MAX_TOTAL_HITS = 80
        local SMALL_REBUILD_COOLDOWN = 1.5

        local CIRCLE_SMALL_MAX_TOTAL_HITS = 80

        local DEAD_SKIP_SEC = 6.0
        local RecentSkipUntil = setmetatable({}, { __mode = "k" })

        C.State = C.State or {}
        if C.State.FarmTeleportWaitSec == nil then C.State.FarmTeleportWaitSec = 1 end

        local function getSwitchTreeSec()
            local v = tonumber(C.State.FarmTeleportWaitSec)
            if v == nil then v = 1 end
            if v < 0 then v = 0 end
            if v > 10 then v = 10 end
            return v
        end

        local lastTeleportAt = 0

        local function findInInventory(name)
            local inv = lp:FindFirstChild("Inventory")
            if not inv then return nil end
            return inv:FindFirstChild(name)
        end

        local function equippedToolName()
            local ch = lp.Character
            if not ch then return nil end
            local tool = ch:FindFirstChildOfClass("Tool")
            return tool and tool.Name or nil
        end

        local function ensureEquipped(tool)
            if not tool then return end
            if equippedToolName() == tool.Name then return end
            EquipItemHandle:FireServer("FireAllClients", tool)
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

        local function nextPerTreeHitId(treeModel)
            local bucket = attrBucket(treeModel)
            local maxN = 0
            local attrs = bucket and bucket:GetAttributes() or nil
            if attrs then
                for key, _ in pairs(attrs) do
                    local n = parseHitAttrKey(key)
                    if n and n > maxN then maxN = n end
                end
            end
            local nextN = maxN + 1
            return tostring(nextN) .. "_" .. UID_SUFFIX
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

        local function shouldSkipTree(treeModel)
            local untilT = RecentSkipUntil[treeModel]
            return untilT ~= nil and os.clock() < untilT
        end

        local function markSkip(treeModel, sec)
            if not treeModel then return end
            RecentSkipUntil[treeModel] = os.clock() + (sec or DEAD_SKIP_SEC)
        end

        local function computeImpactCFrame(model, hitPart)
            if not (model and hitPart and hitPart:IsA("BasePart")) then
                return hitPart and CFrame.new(hitPart.Position) or CFrame.new()
            end
            local outward = hitPart.CFrame.LookVector
            if outward.Magnitude == 0 then outward = Vector3.new(0, 0, -1) end
            outward = outward.Unit
            local origin = hitPart.Position + outward * 1.0
            local dir = -outward * 5.0
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances = { model }
            local result = WS:Raycast(origin, dir, params)
            local pos
            if result then
                pos = result.Position + result.Normal * 0.02
            else
                pos = origin + dir * 0.6
            end
            local rot = hitPart.CFrame - hitPart.CFrame.Position
            return CFrame.new(pos) * rot
        end

        local TreeImpactCF = setmetatable({}, { __mode = "k" })
        local TreeHitSeed = setmetatable({}, { __mode = "k" })

        local function jittered(cf, k)
            local r = 0.05 + 0.015 * (k % 5)
            local ang = k * 2.3999632297
            local off = Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
            local rot = cf - cf.Position
            return CFrame.new(cf.Position + off) * rot
        end

        local function impactCFForTree(treeModel, hitPart)
            local base = TreeImpactCF[treeModel]
            if not base then
                base = computeImpactCFrame(treeModel, hitPart)
                TreeImpactCF[treeModel] = base
            end
            local k = (TreeHitSeed[treeModel] or 0) + 1
            TreeHitSeed[treeModel] = k
            return jittered(base, k)
        end

        local HitQueue = {}
        local HITQ_MAX = 150
        local HITQ_WORKERS = 3
        local hitWorkers = 0

        local function pumpHitQueue()
            while hitWorkers < HITQ_WORKERS and #HitQueue > 0 do
                local job = table.remove(HitQueue, 1)
                if not job then break end
                hitWorkers += 1
                task.spawn(function()
                    pcall(function()
                        ToolDamageObject:InvokeServer(job.treeModel, job.tool, job.hitId, job.impactCF)
                    end)
                    hitWorkers -= 1
                    pumpHitQueue()
                end)
            end
        end

        local function HitTreeRemote(treeModel, tool, hitId, impactCF)
            if not (treeModel and tool and hitId and impactCF) then return end
            local bucket = attrBucket(treeModel)
            if bucket and bucket.SetAttribute then
                pcall(function() bucket:SetAttribute(hitId, true) end)
            end
            if #HitQueue >= HITQ_MAX then
                table.remove(HitQueue, 1)
            end
            HitQueue[#HitQueue + 1] = { treeModel = treeModel, tool = tool, hitId = hitId, impactCF = impactCF }
            pumpHitQueue()
        end

        local function teleportNearTree(treeModel)
            if not treeModel or shouldSkipTree(treeModel) then return false end
            local now = os.clock()
            if (now - lastTeleportAt) < TELEPORT_THROTTLE then return false end
            local char = lp.Character
            if not char then return false end
            local hrp2 = char:FindFirstChild("HumanoidRootPart")
            if not hrp2 then return false end
            local hitPart = bestTreeHitPart(treeModel)
            if not hitPart then markSkip(treeModel, DEAD_SKIP_SEC) return false end
            if looksDestroyed(treeModel, hitPart) then markSkip(treeModel, DEAD_SKIP_SEC) return false end
            local treePos = hitPart.Position
            local hrpPos = hrp2.Position
            local dir = (hrpPos - treePos)
            if dir.Magnitude < 0.001 then dir = Vector3.new(1, 0, 0) else dir = dir.Unit end
            local targetPos = Vector3.new(treePos.X + dir.X * TELEPORT_DISTANCE, treePos.Y + 3, treePos.Z + dir.Z * TELEPORT_DISTANCE)
            hrp2.CFrame = CFrame.new(targetPos, Vector3.new(treePos.X, targetPos.Y, treePos.Z))
            lastTeleportAt = now
            return true
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

        local AXE_HITS = { ["Old Axe"] = 13, ["Good Axe"] = 5, ["Strong Axe"] = 1, ["Chainsaw"] = 2 }
        local AXE_PREFER = { "Strong Axe", "Chainsaw", "Good Axe", "Old Axe" }

        local TREE_NAMES_BASE = { ["Small Tree"] = true, ["Snowy Small Tree"] = true, ["Small Webbed Tree"] = true }
        local EXTRA_SMALL_TREE_NAMES = { ["Christmas Pine"] = true }
        local EXTRA_BIG_TREE_NAMES = { ["Northern Pine"] = true }
        local TREE_NAMES = buildNameSet(TREE_NAMES_BASE, EXTRA_SMALL_TREE_NAMES)

        local BIG_TREE_NAMES_BASE = { TreeBig1 = true, TreeBig2 = true, TreeBig3 = true }
        local BIG_TREE_NAMES = buildNameSet(BIG_TREE_NAMES_BASE, EXTRA_BIG_TREE_NAMES)
        local REQUIRED_HITS = { ["Strong Axe"] = 35, ["Chainsaw"] = 35 }

        local function isBigTreeName(name)
            if BIG_TREE_NAMES[name] then return true end
            if type(name) ~= "string" then return false end
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
            if not isBigTreeName(model.Name) then return false end
            local p = bestTreeHitPart(model)
            return p ~= nil and not looksDestroyed(model, p)
        end

        local function getPreferredAxe()
            for _, name in ipairs(AXE_PREFER) do
                local item = findInInventory(name)
                if item then return item end
            end
            return nil
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

        local function getBigTreeTool()
            local chainsaw = findInInventory("Chainsaw")
            if chainsaw then return chainsaw end
            local strongAxe = findInInventory("Strong Axe")
            if strongAxe then return strongAxe end
            return nil
        end

        local function hrpPosOrZero()
            local ch = lp.Character
            local h = ch and ch:FindFirstChild("HumanoidRootPart")
            return h and h.Position or Vector3.new(0, 0, 0)
        end

        local function hrp()
            local ch = lp.Character
            return ch and ch:FindFirstChild("HumanoidRootPart")
        end

        local SmallCandidates = setmetatable({}, { __mode = "k" })
        local BigCandidates = setmetatable({}, { __mode = "k" })
        local CampfireCandidates = setmetatable({}, { __mode = "k" })

        local function addCandidateFromModel(m)
            if not (m and m:IsA("Model")) then return end
            if maybeSmallTreeName(m.Name) then SmallCandidates[m] = true end
            if maybeBigTreeName(m.Name) then BigCandidates[m] = true end
            local ln = string.lower(m.Name or "")
            if ln:find("campfire", 1, true) then CampfireCandidates[m] = true end
        end

        local function addCandidateFromPart(p)
            if not (p and p:IsA("BasePart")) then return end
            local ln = string.lower(p.Name or "")
            if ln:find("campfire", 1, true) then CampfireCandidates[p] = true end
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
            if CampfireCandidates[inst] then CampfireCandidates[inst] = nil end
            if RecentSkipUntil[inst] then RecentSkipUntil[inst] = nil end
        end)

        local smallRunning = false
        local smallLoopConn = nil
        local smallTreeList = {}
        local smallHitCounts = {}
        local smallCursor = 1
        local smallAcc = 0
        local smallNextTreeAt = 0
        local smallLastRebuildAt = 0

        local function rebuildSmallTreeList(origin)
            local list = {}
            for m in pairs(SmallCandidates) do
                if m and m.Parent and m:IsA("Model") and isSmallTreeModel(m) then
                    list[#list + 1] = m
                end
            end
            table.sort(list, function(a, b)
                local pa = bestTreeHitPart(a)
                local pb = bestTreeHitPart(b)
                local da = pa and (pa.Position - origin).Magnitude or math.huge
                local db = pb and (pb.Position - origin).Magnitude or math.huge
                if da == db then return (a.Name or "") < (b.Name or "") end
                return da < db
            end)
            if #list > MAX_TREE_QUEUE then
                local trimmed = {}
                for i = 1, MAX_TREE_QUEUE do trimmed[i] = list[i] end
                list = trimmed
            end
            local newCounts = {}
            for _, m in ipairs(list) do
                newCounts[m] = smallHitCounts[m] or 0
            end
            smallTreeList = list
            smallHitCounts = newCounts
            smallCursor = 1
            smallLastRebuildAt = os.clock()
        end

        local function removeSmallTreeAt(idx, markDead)
            local t = smallTreeList[idx]
            table.remove(smallTreeList, idx)
            if t then
                smallHitCounts[t] = nil
                TreeImpactCF[t] = nil
                TreeHitSeed[t] = nil
                if markDead then markSkip(t, DEAD_SKIP_SEC) end
            end
            if smallCursor > #smallTreeList then smallCursor = 1 end
            if idx < smallCursor then
                smallCursor = math.max(1, smallCursor - 1)
            end
        end

        local function smallRequiredHitsForTool(toolName)
            return AXE_HITS[toolName] or 5
        end

        local function startSmallLoop()
            if smallLoopConn then smallLoopConn:Disconnect() smallLoopConn = nil end
            smallAcc = 0
            smallNextTreeAt = 0
            smallLoopConn = RunService.Heartbeat:Connect(function(dt)
                if not smallRunning then return end
                smallAcc += (dt or 0)
                if smallAcc < SMALL_STEP_INTERVAL then return end
                smallAcc = 0

                local now = os.clock()
                if now < smallNextTreeAt then return end

                local root = hrp()
                if not root then return end

                local axe = getPreferredAxe()
                if not axe then return end
                ensureEquipped(axe)

                local reqHits = smallRequiredHitsForTool(axe.Name)

                if #smallTreeList == 0 then
                    rebuildSmallTreeList(root.Position)
                    return
                end

                if smallCursor < 1 then smallCursor = 1 end
                if smallCursor > #smallTreeList then smallCursor = 1 end

                local function findAnyInRangeIndex()
                    local n = #smallTreeList
                    if n == 0 then return nil end
                    local start = smallCursor
                    if start < 1 then start = 1 end
                    if start > n then start = 1 end
                    for i = 0, n - 1 do
                        local idx = ((start + i - 1) % n) + 1
                        local t = smallTreeList[idx]
                        if t and t.Parent and isSmallTreeModel(t) then
                            local p = bestTreeHitPart(t)
                            if p and (p.Position - root.Position).Magnitude <= CHOP_RADIUS then
                                local c = smallHitCounts[t] or 0
                                if c < SMALL_MAX_TOTAL_HITS then
                                    return idx
                                end
                            end
                        end
                    end
                    return nil
                end

                local inRangeIdx = findAnyInRangeIndex()
                if not inRangeIdx then
                    if (now - smallLastRebuildAt) >= SMALL_REBUILD_COOLDOWN then
                        rebuildSmallTreeList(root.Position)
                        if #smallTreeList == 0 then return end
                    end
                    local bestTree, bestIdx, bestD
                    for idx, t in ipairs(smallTreeList) do
                        if t and t.Parent and isSmallTreeModel(t) then
                            local p = bestTreeHitPart(t)
                            if p then
                                local d = (p.Position - root.Position).Magnitude
                                if (not bestD) or d < bestD then
                                    bestD, bestTree, bestIdx = d, t, idx
                                end
                            end
                        end
                    end
                    if bestTree then
                        smallCursor = bestIdx or smallCursor
                        teleportNearTree(bestTree)
                    end
                    return
                end

                smallCursor = inRangeIdx

                local listSize = #smallTreeList
                if listSize == 0 then return end
                local steps = math.min(SMALL_HITS_PER_STEP, listSize)

                local didHit = false
                for _ = 1, steps do
                    if #smallTreeList == 0 then break end
                    if smallCursor > #smallTreeList then smallCursor = 1 end

                    local idx = smallCursor
                    local tree = smallTreeList[idx]
                    smallCursor = smallCursor + 1
                    if smallCursor > #smallTreeList then smallCursor = 1 end

                    if not (tree and tree.Parent and isSmallTreeModel(tree)) then
                        removeSmallTreeAt(idx, true)
                        continue
                    end

                    local hitPart = bestTreeHitPart(tree)
                    if not hitPart or looksDestroyed(tree, hitPart) then
                        removeSmallTreeAt(idx, true)
                        continue
                    end

                    local dist = (hitPart.Position - root.Position).Magnitude
                    if dist > CHOP_RADIUS then
                        continue
                    end

                    local count = smallHitCounts[tree] or 0
                    if count >= SMALL_MAX_TOTAL_HITS then
                        removeSmallTreeAt(idx, true)
                        continue
                    end

                    local hitId = nextPerTreeHitId(tree)
                    local impactCF = impactCFForTree(tree, hitPart)
                    HitTreeRemote(tree, axe, hitId, impactCF)
                    count += 1
                    smallHitCounts[tree] = count
                    didHit = true

                    if count >= reqHits then
                        removeSmallTreeAt(idx, true)
                    end
                end

                if didHit then
                    smallNextTreeAt = now + SMALL_NEXT_TREE_DELAY
                end
            end)
        end

        local function startSmallFarm()
            if smallRunning then return end
            smallRunning = true
            local root = hrp()
            rebuildSmallTreeList(root and root.Position or hrpPosOrZero())
            startSmallLoop()
        end

        local function stopSmallFarm()
            smallRunning = false
            if smallLoopConn then smallLoopConn:Disconnect() smallLoopConn = nil end
            smallTreeList = {}
            smallHitCounts = {}
            smallCursor = 1
            smallAcc = 0
            smallNextTreeAt = 0
        end

        local bigRunning = false
        local bigLoopConn = nil
        local bigTreeList = {}
        local bigCurrentIndex = 1
        local bigTargetTree = nil
        local bigTargetEndAt = 0
        local bigTargetWaitOnly = false
        local bigStartPos = Vector3.new(0, 0, 0)
        local bigNextTreeAt = 0

        local BigAttemptedHits = setmetatable({}, { __mode = "k" })
        local BigLastSeenHits = setmetatable({}, { __mode = "k" })
        local BigNoProgress = setmetatable({}, { __mode = "k" })
        local BigNextHitAt = setmetatable({}, { __mode = "k" })

        local function clearBigTrack(tree)
            if not tree then return end
            BigAttemptedHits[tree] = nil
            BigLastSeenHits[tree] = nil
            BigNoProgress[tree] = nil
            BigNextHitAt[tree] = nil
        end

        local function bigCheckProgressOrCull(tree)
            if not tree then return false end
            local hitPart = bestTreeHitPart(tree)
            if not hitPart or looksDestroyed(tree, hitPart) then
                return true
            end
            local seen = getCurrentHitCount(tree)
            local last = BigLastSeenHits[tree]
            if last ~= nil then
                if seen > last then
                    BigNoProgress[tree] = 0
                else
                    BigNoProgress[tree] = (BigNoProgress[tree] or 0) + 1
                    if (BigNoProgress[tree] or 0) >= BIG_MAX_NO_PROGRESS_TRIES then
                        return true
                    end
                end
            end
            local attempted = BigAttemptedHits[tree] or 0
            if seen >= BIG_MAX_TOTAL_HITS or attempted >= BIG_MAX_TOTAL_HITS then
                return true
            end
            return false
        end

        local function bigRecordAttempt(tree)
            if not tree then return end
            BigAttemptedHits[tree] = (BigAttemptedHits[tree] or 0) + 1
            BigLastSeenHits[tree] = getCurrentHitCount(tree)
            BigNextHitAt[tree] = os.clock() + SWING_COOLDOWN_BIG
        end

        local function buildBigTreeList(requiredHits, origin)
            bigTreeList = {}
            bigCurrentIndex = 1
            for m in pairs(BigCandidates) do
                if m and m.Parent and m:IsA("Model") and isBigTreeModel(m) then
                    local existing = getCurrentHitCount(m)
                    if existing < requiredHits then
                        bigTreeList[#bigTreeList + 1] = m
                    end
                end
            end
            table.sort(bigTreeList, function(a, b)
                local pa = bestTreeHitPart(a)
                local pb = bestTreeHitPart(b)
                local da = pa and (pa.Position - origin).Magnitude or math.huge
                local db = pb and (pb.Position - origin).Magnitude or math.huge
                if da == db then return (a.Name or "") < (b.Name or "") end
                return da < db
            end)
            if #bigTreeList > 10 then
                local trimmed = {}
                for i = 1, 10 do trimmed[i] = bigTreeList[i] end
                bigTreeList = trimmed
            end
        end

        local function removeBigTree(tree, markDead)
            if not tree then return end
            for i = #bigTreeList, 1, -1 do
                if bigTreeList[i] == tree then table.remove(bigTreeList, i) end
            end
            TreeImpactCF[tree] = nil
            TreeHitSeed[tree] = nil
            clearBigTrack(tree)
            if markDead then markSkip(tree, DEAD_SKIP_SEC) end
        end

        local function pickNextBigTree(requiredHits, origin, now)
            if #bigTreeList == 0 then buildBigTreeList(requiredHits, origin) end
            if #bigTreeList == 0 then return nil end
            if bigCurrentIndex > #bigTreeList then bigCurrentIndex = 1 end
            local total = #bigTreeList
            local tries = 0
            while tries < total do
                tries += 1
                local tree = bigTreeList[bigCurrentIndex]
                bigCurrentIndex += 1
                if bigCurrentIndex > #bigTreeList then bigCurrentIndex = 1 end

                if tree and tree.Parent and isBigTreeModel(tree) and getCurrentHitCount(tree) < requiredHits then
                    local nextAt = BigNextHitAt[tree]
                    if not nextAt or now >= nextAt then
                        return tree
                    end
                else
                    if tree then removeBigTree(tree, true) end
                    total = #bigTreeList
                    if total == 0 then return nil end
                    if bigCurrentIndex > total then bigCurrentIndex = 1 end
                end
            end
            return nil
        end

        local function findAnyBigInRange(requiredHits, rootPos, now)
            for idx, t in ipairs(bigTreeList) do
                if t and t.Parent and isBigTreeModel(t) and getCurrentHitCount(t) < requiredHits then
                    local p = bestTreeHitPart(t)
                    if p and (p.Position - rootPos).Magnitude <= CHOP_RADIUS then
                        local nextAt = BigNextHitAt[t]
                        if not nextAt or now >= nextAt then
                            return t, idx
                        end
                    end
                end
            end
            return nil
        end

        local function tryHitBigTree(tree, tool, requiredHits, rootPos, now)
            if not tree or not tree.Parent or not isBigTreeModel(tree) then
                if tree then removeBigTree(tree, true) end
                return false
            end

            if bigCheckProgressOrCull(tree) then
                removeBigTree(tree, true)
                return false
            end

            if getCurrentHitCount(tree) >= requiredHits then
                removeBigTree(tree, true)
                return false
            end

            local nextAt = BigNextHitAt[tree]
            if nextAt and now < nextAt then
                return false
            end

            local hitPart = bestTreeHitPart(tree)
            if not hitPart or looksDestroyed(tree, hitPart) then
                removeBigTree(tree, true)
                return false
            end

            local dist = (hitPart.Position - rootPos).Magnitude
            if dist > CHOP_RADIUS then
                return false
            end

            local hitId = nextPerTreeHitId(tree)
            local impactCF = impactCFForTree(tree, hitPart)
            HitTreeRemote(tree, tool, hitId, impactCF)
            bigRecordAttempt(tree)
            return true
        end

        local function stepBigChopper()
            local now = os.clock()
            local root = hrp()
            if not root then return end

            local tool = getBigTreeTool()
            if not tool then return end
            ensureEquipped(tool)

            local requiredHits = REQUIRED_HITS[tool.Name] or 35
            local switchSec = getSwitchTreeSec()

            if switchSec == 0 then
                if now < bigNextTreeAt then return end
                if #bigTreeList == 0 then buildBigTreeList(requiredHits, root.Position) end
                if #bigTreeList == 0 then return end

                local didWork = false
                local maxPerTick = 6

                for _ = 1, maxPerTick do
                    local inRangeTree, inRangeIdx = findAnyBigInRange(requiredHits, root.Position, now)
                    if inRangeTree then
                        if inRangeIdx then bigCurrentIndex = inRangeIdx end
                        if tryHitBigTree(inRangeTree, tool, requiredHits, root.Position, now) then
                            didWork = true
                        else
                            now = os.clock()
                        end
                    else
                        local tree = pickNextBigTree(requiredHits, root.Position, now)
                        if not tree then break end
                        local hitPart = bestTreeHitPart(tree)
                        if not hitPart or looksDestroyed(tree, hitPart) then
                            removeBigTree(tree, true)
                        else
                            local dist = (hitPart.Position - root.Position).Magnitude
                            if dist > CHOP_RADIUS then
                                teleportNearTree(tree)
                                didWork = true
                                break
                            else
                                if tryHitBigTree(tree, tool, requiredHits, root.Position, now) then
                                    didWork = true
                                end
                            end
                        end
                    end
                end

                if didWork then
                    bigNextTreeAt = os.clock() + BIG_ZERO_PACE_DELAY
                end
                return
            end

            if bigTargetTree == nil and bigTargetWaitOnly then
                if now >= bigTargetEndAt then
                    bigTargetWaitOnly = false
                    bigTargetEndAt = 0
                end
                return
            end

            if not bigTargetTree then
                if #bigTreeList == 0 then buildBigTreeList(requiredHits, root.Position) end
                local inRangeTree, inRangeIdx = findAnyBigInRange(requiredHits, root.Position, now)
                local t = inRangeTree or pickNextBigTree(requiredHits, root.Position, now)
                if not t then return end
                bigTargetTree = t
                if inRangeIdx then bigCurrentIndex = inRangeIdx end
                if switchSec and switchSec > 0 then
                    bigTargetEndAt = now + switchSec
                else
                    bigTargetEndAt = 0
                end
            end

            local tree = bigTargetTree
            if tree and bigCheckProgressOrCull(tree) then
                removeBigTree(tree, true)
                bigTargetTree = nil
                bigTargetWaitOnly = true
                bigTargetEndAt = now + 0.08
                return
            end

            if switchSec and switchSec > 0 and now >= bigTargetEndAt then
                bigTargetTree = nil
                bigTargetEndAt = 0
                return
            end

            if (not tree) or (not tree.Parent) or (not isBigTreeModel(tree)) then
                if tree then removeBigTree(tree, true) end
                bigTargetTree = nil
                bigTargetWaitOnly = true
                bigTargetEndAt = now + 0.08
                return
            end

            local nextAt = BigNextHitAt[tree]
            if nextAt and now < nextAt then
                local inRangeTree = select(1, findAnyBigInRange(requiredHits, root.Position, now))
                if inRangeTree and inRangeTree ~= tree then
                    bigTargetTree = inRangeTree
                end
                return
            end

            local hitPart = bestTreeHitPart(tree)
            if not hitPart or looksDestroyed(tree, hitPart) then
                removeBigTree(tree, true)
                bigTargetTree = nil
                bigTargetWaitOnly = true
                bigTargetEndAt = now + 0.08
                return
            end

            if getCurrentHitCount(tree) >= requiredHits then
                removeBigTree(tree, true)
                bigTargetTree = nil
                bigTargetWaitOnly = true
                bigTargetEndAt = now + 0.08
                return
            end

            local dist = (hitPart.Position - root.Position).Magnitude
            if dist > CHOP_RADIUS then
                local inRangeTree, inRangeIdx = findAnyBigInRange(requiredHits, root.Position, now)
                if inRangeTree then
                    bigTargetTree = inRangeTree
                    if inRangeIdx then bigCurrentIndex = inRangeIdx end
                    return
                end
                teleportNearTree(tree)
                return
            end

            local hitId = nextPerTreeHitId(tree)
            local impactCF = impactCFForTree(tree, hitPart)
            HitTreeRemote(tree, tool, hitId, impactCF)
            bigRecordAttempt(tree)
        end

        local function startBigFarm()
            if bigRunning then return end
            bigRunning = true
            bigStartPos = hrpPosOrZero()
            if bigLoopConn then bigLoopConn:Disconnect() bigLoopConn = nil end
            bigTreeList = {}
            bigCurrentIndex = 1
            bigTargetTree = nil
            bigTargetEndAt = 0
            bigTargetWaitOnly = false
            bigNextTreeAt = 0
            BigAttemptedHits = setmetatable({}, { __mode = "k" })
            BigLastSeenHits = setmetatable({}, { __mode = "k" })
            BigNoProgress = setmetatable({}, { __mode = "k" })
            BigNextHitAt = setmetatable({}, { __mode = "k" })
            bigLoopConn = RunService.Heartbeat:Connect(function()
                if not bigRunning then return end
                stepBigChopper()
            end)
        end

        local function stopBigFarm()
            bigRunning = false
            if bigLoopConn then bigLoopConn:Disconnect() bigLoopConn = nil end
            bigTreeList = {}
            bigCurrentIndex = 1
            bigTargetTree = nil
            bigTargetEndAt = 0
            bigTargetWaitOnly = false
            bigNextTreeAt = 0
        end

        local circleRunning = false
        local circleLoopConn = nil
        local circleLastScan = 0
        local circleRadius = CIRCLE_START_RADIUS
        local circleTreeList = {}
        local circleIndex = 1
        local circleSmallHitCounts = {}
        local circleBigNextHitAt = setmetatable({}, { __mode = "k" })

        local function campfireCandidatePos(inst)
            if not inst then return nil end
            if inst:IsA("BasePart") then return inst.Position end
            if inst:IsA("Model") then
                if inst.PrimaryPart and inst.PrimaryPart:IsA("BasePart") then return inst.PrimaryPart.Position end
                local p = inst:FindFirstChildWhichIsA("BasePart")
                return p and p.Position or nil
            end
            return nil
        end

        local function findCampfireCenter()
            local root = hrp()
            local rootPos = root and root.Position or nil
            local bestPos, bestD
            for inst in pairs(CampfireCandidates) do
                if inst and inst.Parent then
                    local p = campfireCandidatePos(inst)
                    if p then
                        local d = rootPos and (p - rootPos).Magnitude or (p - Vector3.new(0, 0, 0)).Magnitude
                        if (not bestPos) or d < bestD then bestPos, bestD = p, d end
                    end
                end
            end
            return bestPos or Vector3.new(0, 0, 0)
        end

        local function rebuildCircleTreeList(centerPos)
            local list = {}
            local rMax = circleRadius
            for m in pairs(SmallCandidates) do
                if m and m.Parent and m:IsA("Model") and isSmallTreeModel(m) then
                    local part = bestTreeHitPart(m)
                    if part then
                        local d = (part.Position - centerPos).Magnitude
                        if d <= rMax then
                            list[#list + 1] = m
                        end
                    end
                end
            end
            for m in pairs(BigCandidates) do
                if m and m.Parent and m:IsA("Model") and isBigTreeModel(m) then
                    local part = bestTreeHitPart(m)
                    if part then
                        local d = (part.Position - centerPos).Magnitude
                        if d <= rMax then
                            list[#list + 1] = m
                        end
                    end
                end
            end
            table.sort(list, function(a, b)
                local pa = bestTreeHitPart(a)
                local pb = bestTreeHitPart(b)
                local da = pa and (pa.Position - centerPos).Magnitude or math.huge
                local db = pb and (pb.Position - centerPos).Magnitude or math.huge
                if da == db then return (a.Name or "") < (b.Name or "") end
                return da < db
            end)
            if #list > MAX_TREE_QUEUE then
                local trimmed = {}
                for i = 1, MAX_TREE_QUEUE do trimmed[i] = list[i] end
                list = trimmed
            end
            local newCounts = {}
            for _, m in ipairs(list) do
                newCounts[m] = circleSmallHitCounts[m] or 0
            end
            circleTreeList = list
            circleSmallHitCounts = newCounts
            if circleIndex < 1 then circleIndex = 1 end
            if circleIndex > #circleTreeList then circleIndex = 1 end
        end

        local function circleRemoveAt(idx, markDead)
            local t = circleTreeList[idx]
            table.remove(circleTreeList, idx)
            if circleIndex > #circleTreeList then circleIndex = 1 end
            if t then
                circleSmallHitCounts[t] = nil
                TreeImpactCF[t] = nil
                TreeHitSeed[t] = nil
                circleBigNextHitAt[t] = nil
                if markDead then markSkip(t, DEAD_SKIP_SEC) end
            end
        end

        local function circleAdvanceIndex()
            circleIndex = circleIndex + 1
            if circleIndex > #circleTreeList then circleIndex = 1 end
        end

        local function circleEnsureList(centerPos)
            if (os.clock() - circleLastScan) >= CIRCLE_RESCAN_EVERY then
                circleLastScan = os.clock()
                rebuildCircleTreeList(centerPos)
            end
            if #circleTreeList == 0 then
                if circleRadius < CIRCLE_RADIUS_MAX then
                    circleRadius = math.min(CIRCLE_RADIUS_MAX, circleRadius + CIRCLE_RADIUS_STEP)
                    rebuildCircleTreeList(centerPos)
                end
            end
        end

        local function findAnyCircleInRangeIndex(rootPos, now)
            local toolBig = getBigTreeTool()
            local requiredBig = toolBig and (REQUIRED_HITS[toolBig.Name] or 35) or 35

            for idx, tree in ipairs(circleTreeList) do
                if tree and tree.Parent then
                    local isSmall = isSmallTreeModel(tree)
                    local isBig = isBigTreeModel(tree)
                    if isSmall or isBig then
                        local part = bestTreeHitPart(tree)
                        if part and (part.Position - rootPos).Magnitude <= CHOP_RADIUS then
                            if isSmall then
                                local count = circleSmallHitCounts[tree] or 0
                                if count < CIRCLE_SMALL_MAX_TOTAL_HITS then
                                    return idx
                                end
                            else
                                local nextAt = circleBigNextHitAt[tree]
                                if getCurrentHitCount(tree) < requiredBig and (not nextAt or now >= nextAt) then
                                    return idx
                                end
                            end
                        end
                    end
                end
            end
            return nil
        end

        local function stepCircleFarm()
            local now = os.clock()
            local root = hrp()
            if not root then return end

            local centerPos = findCampfireCenter()
            circleEnsureList(centerPos)
            if #circleTreeList == 0 then return end

            if circleIndex < 1 then circleIndex = 1 end
            if circleIndex > #circleTreeList then circleIndex = 1 end

            for _attempt = 1, 2 do
                if #circleTreeList == 0 then return end
                if circleIndex < 1 then circleIndex = 1 end
                if circleIndex > #circleTreeList then circleIndex = 1 end

                local tree = circleTreeList[circleIndex]
                if not tree or not tree.Parent then
                    circleRemoveAt(circleIndex, true)
                    return
                end

                local isSmall = isSmallTreeModel(tree)
                local isBig = isBigTreeModel(tree)
                if (not isSmall) and (not isBig) then
                    circleRemoveAt(circleIndex, true)
                    return
                end

                local hitPart = bestTreeHitPart(tree)
                if not hitPart or looksDestroyed(tree, hitPart) then
                    circleRemoveAt(circleIndex, true)
                    return
                end

                local dist = (hitPart.Position - root.Position).Magnitude
                if dist > CHOP_RADIUS then
                    local inIdx = findAnyCircleInRangeIndex(root.Position, now)
                    if inIdx then
                        circleIndex = inIdx
                        continue
                    end
                    teleportNearTree(tree)
                    return
                end

                if isSmall then
                    local tool = getPreferredAxe()
                    if not tool then return end
                    ensureEquipped(tool)

                    local reqHits = smallRequiredHitsForTool(tool.Name)
                    local count = circleSmallHitCounts[tree] or 0
                    if count >= CIRCLE_SMALL_MAX_TOTAL_HITS then
                        circleRemoveAt(circleIndex, true)
                        return
                    end

                    local hitId = nextPerTreeHitId(tree)
                    local impactCF = impactCFForTree(tree, hitPart)
                    HitTreeRemote(tree, tool, hitId, impactCF)
                    count += 1
                    circleSmallHitCounts[tree] = count

                    if count >= reqHits then
                        circleRemoveAt(circleIndex, true)
                    else
                        circleAdvanceIndex()
                    end
                    return
                end

                if isBig then
                    local tool = getBigTreeTool()
                    if not tool then
                        circleAdvanceIndex()
                        return
                    end
                    ensureEquipped(tool)

                    local requiredHits = REQUIRED_HITS[tool.Name] or 35
                    if getCurrentHitCount(tree) >= requiredHits then
                        circleRemoveAt(circleIndex, true)
                        circleAdvanceIndex()
                        return
                    end

                    local nextAt = circleBigNextHitAt[tree]
                    if nextAt and now < nextAt then
                        circleAdvanceIndex()
                        return
                    end

                    local hitId = nextPerTreeHitId(tree)
                    local impactCF = impactCFForTree(tree, hitPart)
                    HitTreeRemote(tree, tool, hitId, impactCF)
                    circleBigNextHitAt[tree] = now + SWING_COOLDOWN_BIG

                    circleAdvanceIndex()
                    return
                end
            end
        end

        local function startCircleFarm()
            if circleRunning then return end
            circleRunning = true
            circleLastScan = 0
            circleRadius = CIRCLE_START_RADIUS
            circleTreeList = {}
            circleIndex = 1
            circleSmallHitCounts = {}
            circleBigNextHitAt = setmetatable({}, { __mode = "k" })
            if circleLoopConn then circleLoopConn:Disconnect() circleLoopConn = nil end
            circleLoopConn = RunService.Heartbeat:Connect(function()
                if not circleRunning then return end
                stepCircleFarm()
            end)
        end

        local function stopCircleFarm()
            circleRunning = false
            if circleLoopConn then circleLoopConn:Disconnect() circleLoopConn = nil end
            circleTreeList = {}
            circleIndex = 1
            circleSmallHitCounts = {}
            circleBigNextHitAt = setmetatable({}, { __mode = "k" })
        end

        local function cleanupAll()
            stopCircleFarm()
            stopSmallFarm()
            stopBigFarm()
            if descAddedConn then pcall(function() descAddedConn:Disconnect() end) descAddedConn = nil end
            if descRemovingConn then pcall(function() descRemovingConn:Disconnect() end) descRemovingConn = nil end
            HitQueue = {}
            hitWorkers = 0
        end

        C.Farm._cleanup = cleanupAll

        tab:Section({ Title = "Tree Farming" })

        if tab.Slider then
            tab:Slider({
                Title = "Switch big tree after (sec)",
                Value = { Min = 0, Max = 10, Default = getSwitchTreeSec() },
                Rounding = 2,
                Callback = function(v)
                    local nv = v
                    if type(v) == "table" then nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max end
                    C.State.FarmTeleportWaitSec = tonumber(nv) or 0
                end
            })
        end

        tab:Toggle({
            Title = "Circle Clear (Campfire/Origin) - Small+Big",
            Value = false,
            Callback = function(state)
                if state then
                    stopSmallFarm()
                    stopBigFarm()
                    startCircleFarm()
                else
                    stopCircleFarm()
                end
            end
        })

        tab:Toggle({
            Title = "Tree Farm (Small Trees)",
            Value = false,
            Callback = function(state)
                if state then
                    stopCircleFarm()
                    stopBigFarm()
                    startSmallFarm()
                else
                    stopSmallFarm()
                end
            end
        })

        tab:Toggle({
            Title = "Big Tree Farm",
            Value = false,
            Callback = function(state)
                if state then
                    stopCircleFarm()
                    stopSmallFarm()
                    startBigFarm()
                else
                    stopBigFarm()
                end
            end
        })
    end

    local ok, err = pcall(run)
    if not ok then warn("[Farm] module error: " .. tostring(err)) end
end
