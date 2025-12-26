-- farm.lua

return function(C, R, UI)
    local function run()
        C  = C  or _G.C
        UI = UI or _G.UI

        local Services   = (C and C.Services) or {}
        local Players    = Services.Players or game:GetService("Players")
        local RS         = Services.RS or game:GetService("ReplicatedStorage")
        local WS         = Services.WS or game:GetService("Workspace")
        local RunService = Services.Run or game:GetService("RunService")

        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Farm
        if not tab then return end

        local lp = Players.LocalPlayer
        if not lp then return end

        local RemoteEvents     = RS:WaitForChild("RemoteEvents")
        local ToolDamageObject = RemoteEvents:WaitForChild("ToolDamageObject")
        local EquipItemHandle  = RemoteEvents:WaitForChild("EquipItemHandle")

        local CHOP_RADIUS            = 60
        local TELEPORT_DISTANCE      = 30
        local TELEPORT_WAIT_DEFAULT  = 1
        local UID_SUFFIX             = "0000000000"

        C.State = C.State or {}
        if C.State.FarmTeleportWaitSec == nil then
            C.State.FarmTeleportWaitSec = TELEPORT_WAIT_DEFAULT
        end

        local function getTeleportWaitSec()
            local v = tonumber(C.State.FarmTeleportWaitSec)
            if v == nil then v = TELEPORT_WAIT_DEFAULT end
            if v < 0 then v = 0 end
            if v > 30 then v = 30 end
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
                    if n and n > maxN then
                        maxN = n
                    end
                end
            end
            local nextN = maxN + 1
            return tostring(nextN) .. "_" .. UID_SUFFIX
        end

        local function bestTreeHitPart(tree)
            if not (tree and tree:IsA("Model")) then
                return nil
            end

            local hr = tree:FindFirstChild("HitRegisters")
            if hr then
                local t = hr:FindFirstChild("Trunk")
                if t and t:IsA("BasePart") then
                    return t
                end
                local any = hr:FindFirstChildWhichIsA("BasePart")
                if any then
                    return any
                end
            end

            local t2 = tree:FindFirstChild("Trunk")
            if t2 and t2:IsA("BasePart") then
                return t2
            end

            if tree.PrimaryPart and tree.PrimaryPart:IsA("BasePart") then
                return tree.PrimaryPart
            end

            return tree:FindFirstChildWhichIsA("BasePart")
        end

        local function computeImpactCFrame(model, hitPart)
            if not (model and hitPart and hitPart:IsA("BasePart")) then
                return hitPart and CFrame.new(hitPart.Position) or CFrame.new()
            end

            local outward = hitPart.CFrame.LookVector
            if outward.Magnitude == 0 then
                outward = Vector3.new(0, 0, -1)
            end
            outward = outward.Unit

            local origin = hitPart.Position + outward * 1.0
            local dir    = -outward * 5.0

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
        local TreeHitSeed  = setmetatable({}, { __mode = "k" })

        local function jittered(cf, k)
            local r   = 0.05 + 0.015 * (k % 5)
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

        local function HitTreeRemote(treeModel, tool, hitId, impactCF)
            if not (treeModel and tool and hitId and impactCF) then
                return
            end
            ToolDamageObject:InvokeServer(treeModel, tool, hitId, impactCF)
        end

        local function teleportNearTree(treeModel)
            local now = os.clock()
            if (now - lastTeleportAt) < getTeleportWaitSec() then
                return false
            end

            local char = lp.Character
            if not char then return false end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return false end
            local hitPart = bestTreeHitPart(treeModel)
            if not hitPart then return false end

            local treePos = hitPart.Position
            local hrpPos  = hrp.Position
            local dir     = (hrpPos - treePos)

            if dir.Magnitude < 0.001 then
                dir = Vector3.new(1, 0, 0)
            else
                dir = dir.Unit
            end

            local targetPos = Vector3.new(
                treePos.X + dir.X * TELEPORT_DISTANCE,
                treePos.Y + 3,
                treePos.Z + dir.Z * TELEPORT_DISTANCE
            )

            hrp.CFrame = CFrame.new(targetPos, Vector3.new(treePos.X, targetPos.Y, treePos.Z))
            lastTeleportAt = now
            return true
        end

        local function buildNameSet(baseSet, extra)
            local out = {}
            if type(baseSet) == "table" then
                for k, v in pairs(baseSet) do
                    if v == true and type(k) == "string" then
                        out[k] = true
                    end
                end
            end
            if type(extra) == "table" then
                for k, v in pairs(extra) do
                    if type(k) == "number" then
                        if type(v) == "string" then
                            out[v] = true
                        end
                    elseif type(k) == "string" and v == true then
                        out[k] = true
                    end
                end
            end
            return out
        end

        -- SMALL TREES
        local AXE_HITS   = { ["Old Axe"] = 13, ["Good Axe"] = 5, ["Strong Axe"] = 1, ["Chainsaw"] = 2 }
        local AXE_PREFER = { "Strong Axe", "Chainsaw", "Good Axe", "Old Axe" }

        local TREE_NAMES_BASE = { ["Small Tree"] = true, ["Snowy Small Tree"] = true, ["Small Webbed Tree"] = true }
        local EXTRA_SMALL_TREE_NAMES = { ["Christmas Pine"] = true }
        local EXTRA_BIG_TREE_NAMES   = { ["Northern Pine"] = true }

        local TREE_NAMES = buildNameSet(TREE_NAMES_BASE, EXTRA_SMALL_TREE_NAMES)

        local function isSmallTreeModel(model)
            if not (model and model:IsA("Model")) then
                return false
            end
            local name = model.Name
            if TREE_NAMES[name] then
                return bestTreeHitPart(model) ~= nil
            end
            local lower = string.lower(name or "")
            if lower:find("small", 1, true) and lower:find("tree", 1, true) then
                return bestTreeHitPart(model) ~= nil
            end
            return false
        end

        local function getPreferredAxe()
            for _, name in ipairs(AXE_PREFER) do
                local item = findInInventory(name)
                if item then
                    return item
                end
            end
            return nil
        end

        local smallTreeList     = {}
        local smallHitCounts    = {}
        local smallRunning      = false
        local smallLoopConn     = nil
        local smallSpawnConn    = nil
        local smallWaitingSpawn = false

        local function registerSmallTree(m)
            if not m then return end
            for _, t in ipairs(smallTreeList) do
                if t == m then return end
            end
            table.insert(smallTreeList, m)
            smallHitCounts[m] = 0
        end

        local function removeSmallTreeFromList(tree)
            for i = #smallTreeList, 1, -1 do
                if smallTreeList[i] == tree then
                    table.remove(smallTreeList, i)
                end
            end
            smallHitCounts[tree] = nil
        end

        local function scanForAllSmallTrees()
            local list = {}
            for _, inst in ipairs(WS:GetDescendants()) do
                if inst:IsA("Model") and isSmallTreeModel(inst) then
                    table.insert(list, inst)
                end
            end
            table.sort(list, function(a, b)
                return (a.Name or "") < (b.Name or "")
            end)
            smallTreeList  = list
            smallHitCounts = {}
            for _, m in ipairs(smallTreeList) do
                smallHitCounts[m] = 0
            end
        end

        local function ensureSmallSpawnListener()
            if smallSpawnConn or not smallRunning then
                return
            end
            smallWaitingSpawn = true
            smallSpawnConn = WS.DescendantAdded:Connect(function(inst)
                if not smallRunning then
                    return
                end
                if inst:IsA("Model") and isSmallTreeModel(inst) then
                    registerSmallTree(inst)
                    smallWaitingSpawn = false
                    if smallSpawnConn then
                        smallSpawnConn:Disconnect()
                        smallSpawnConn = nil
                    end
                end
            end)
        end

        local function clearSmallState()
            smallTreeList     = {}
            smallHitCounts    = {}
            smallWaitingSpawn = false
            if smallSpawnConn then
                smallSpawnConn:Disconnect()
                smallSpawnConn = nil
            end
        end

        local function refreshSmallTreeList()
            scanForAllSmallTrees()
            if #smallTreeList == 0 then
                ensureSmallSpawnListener()
            else
                smallWaitingSpawn = false
                if smallSpawnConn then
                    smallSpawnConn:Disconnect()
                    smallSpawnConn = nil
                end
            end
        end

        local function startSmallLoop()
            if smallLoopConn then
                smallLoopConn:Disconnect()
                smallLoopConn = nil
            end

            smallLoopConn = RunService.Heartbeat:Connect(function()
                if not smallRunning then
                    return
                end

                local char = lp.Character
                if not char then return end
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if not hrp then return end

                local axe = getPreferredAxe()
                if not axe then return end

                ensureEquipped(axe)
                local axeName    = axe.Name
                local baseNeeded = AXE_HITS[axeName] or 13

                if #smallTreeList == 0 then
                    if not smallWaitingSpawn then
                        refreshSmallTreeList()
                    end
                    return
                end

                local nearest, nearestDist
                for _, tree in ipairs(smallTreeList) do
                    local part = bestTreeHitPart(tree)
                    if part then
                        local d = (part.Position - hrp.Position).Magnitude
                        if not nearest or d < nearestDist then
                            nearest     = tree
                            nearestDist = d
                        end
                    end
                end

                if not nearest then
                    refreshSmallTreeList()
                    return
                end

                if nearestDist > CHOP_RADIUS then
                    teleportNearTree(nearest)
                    return
                end

                local treesInRange = {}
                for _, tree in ipairs(smallTreeList) do
                    local part = bestTreeHitPart(tree)
                    if part then
                        local d = (part.Position - hrp.Position).Magnitude
                        if d <= CHOP_RADIUS then
                            table.insert(treesInRange, tree)
                        end
                    end
                end

                if #treesInRange == 0 then
                    return
                end

                for _, tree in ipairs(treesInRange) do
                    if tree.Parent and isSmallTreeModel(tree) then
                        local needed = AXE_HITS[axeName] or baseNeeded
                        local count  = smallHitCounts[tree] or 0

                        if count >= needed then
                            removeSmallTreeFromList(tree)
                        else
                            local hitPart = bestTreeHitPart(tree)
                            if hitPart then
                                local hitId    = nextPerTreeHitId(tree)
                                local impactCF = impactCFForTree(tree, hitPart)
                                HitTreeRemote(tree, axe, hitId, impactCF)
                                smallHitCounts[tree] = count + 1
                            else
                                removeSmallTreeFromList(tree)
                            end
                        end
                    else
                        removeSmallTreeFromList(tree)
                    end
                end
            end)
        end

        local function startSmallFarm()
            if smallRunning then return end
            smallRunning = true
            clearSmallState()
            refreshSmallTreeList()
            startSmallLoop()
        end

        local function stopSmallFarm()
            smallRunning = false
            if smallLoopConn then
                smallLoopConn:Disconnect()
                smallLoopConn = nil
            end
            clearSmallState()
        end

        -- BIG TREES
        local BIG_TREE_NAMES_BASE = { TreeBig1 = true, TreeBig2 = true, TreeBig3 = true }
        local BIG_TREE_NAMES = buildNameSet(BIG_TREE_NAMES_BASE, EXTRA_BIG_TREE_NAMES)

        local REQUIRED_HITS     = { ["Strong Axe"] = 35, ["Chainsaw"] = 35 }
        local PER_TREE_COOLDOWN = 0.5

        local function isBigTreeName(name)
            if BIG_TREE_NAMES[name] then
                return true
            end
            if type(name) ~= "string" then
                return false
            end
            return name:match("^WebbedTreeBig%d*$") ~= nil
        end

        local function isBigTreeModel(model)
            return model
                and model:IsA("Model")
                and isBigTreeName(model.Name)
                and (bestTreeHitPart(model) ~= nil)
        end

        local function getCurrentHitCount(treeModel)
            local bucket = attrBucket(treeModel)
            if not (bucket and bucket.GetAttributes) then
                return 0
            end
            local attrs = bucket:GetAttributes()
            local maxN  = 0
            for key in pairs(attrs) do
                local n = parseHitAttrKey(key)
                if n and n > maxN then
                    maxN = n
                end
            end
            return maxN
        end

        local function getBigTreeTool()
            local chainsaw = findInInventory("Chainsaw")
            if chainsaw then
                return chainsaw
            end
            local strongAxe = findInInventory("Strong Axe")
            if strongAxe then
                return strongAxe
            end
            return nil
        end

        local bigTreeList     = {}
        local bigLocalHits    = {}
        local bigLastHitTime  = {}
        local bigCurrentIndex = 1
        local bigRunning      = false
        local bigLoopConn     = nil

        local function buildBigTreeList(requiredHits)
            bigTreeList     = {}
            bigLocalHits    = {}
            bigLastHitTime  = {}
            bigCurrentIndex = 1

            for _, inst in ipairs(WS:GetDescendants()) do
                if inst:IsA("Model") and isBigTreeModel(inst) then
                    local existing = getCurrentHitCount(inst)
                    if existing < requiredHits then
                        table.insert(bigTreeList, inst)
                        bigLocalHits[inst]   = existing
                        bigLastHitTime[inst] = 0
                    end
                end
            end

            table.sort(bigTreeList, function(a, b)
                return (a.Name or "") < (b.Name or "")
            end)
        end

        local function removeBigTree(tree)
            for i = #bigTreeList, 1, -1 do
                if bigTreeList[i] == tree then
                    table.remove(bigTreeList, i)
                end
            end
            bigLocalHits[tree]   = nil
            bigLastHitTime[tree] = nil
            TreeImpactCF[tree]   = nil
            TreeHitSeed[tree]    = nil
        end

        local function stepBigChopper()
            local char = lp.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            local tool = getBigTreeTool()
            if not tool then return end
            ensureEquipped(tool)

            local axeName      = tool.Name
            local requiredHits = REQUIRED_HITS[axeName] or 35

            if #bigTreeList == 0 then
                buildBigTreeList(requiredHits)
                if #bigTreeList == 0 then
                    return
                end
            end

            local total = #bigTreeList
            if total == 0 then return end
            if bigCurrentIndex > total then bigCurrentIndex = 1 end

            local selectedTree, selectedBaseCount
            local tries = 0

            while tries < total do
                tries += 1
                local tree = bigTreeList[bigCurrentIndex]

                if not tree or not tree.Parent or not isBigTreeModel(tree) then
                    removeBigTree(tree)
                    total = #bigTreeList
                    if total == 0 then return end
                    if bigCurrentIndex > total then bigCurrentIndex = 1 end
                else
                    local remoteCount = getCurrentHitCount(tree)
                    local base = math.max(remoteCount, bigLocalHits[tree] or 0)

                    if base >= requiredHits then
                        removeBigTree(tree)
                        total = #bigTreeList
                        if total == 0 then return end
                        if bigCurrentIndex > total then bigCurrentIndex = 1 end
                    else
                        local now  = os.clock()
                        local last = bigLastHitTime[tree] or 0

                        if (now - last) < PER_TREE_COOLDOWN then
                            bigCurrentIndex = bigCurrentIndex + 1
                            if bigCurrentIndex > total then bigCurrentIndex = 1 end
                        else
                            selectedTree = tree
                            selectedBaseCount = base
                            break
                        end
                    end
                end
            end

            if not selectedTree then
                return
            end

            local hitPart = bestTreeHitPart(selectedTree)
            if not hitPart then
                removeBigTree(selectedTree)
                return
            end

            if (hitPart.Position - hrp.Position).Magnitude > CHOP_RADIUS then
                teleportNearTree(selectedTree)
            end

            local remoteCount2 = getCurrentHitCount(selectedTree)
            local base2        = math.max(remoteCount2, selectedBaseCount or 0)
            if base2 >= requiredHits then
                removeBigTree(selectedTree)
                return
            end

            local hitId    = nextPerTreeHitId(selectedTree)
            local impactCF = impactCFForTree(selectedTree, hitPart)
            HitTreeRemote(selectedTree, tool, hitId, impactCF)

            bigLocalHits[selectedTree]   = base2 + 1
            bigLastHitTime[selectedTree] = os.clock()

            bigCurrentIndex = bigCurrentIndex + 1
            total = #bigTreeList
            if total > 0 and bigCurrentIndex > total then
                bigCurrentIndex = 1
            end
        end

        local function startBigFarm()
            if bigRunning then return end
            bigRunning = true
            if bigLoopConn then
                bigLoopConn:Disconnect()
                bigLoopConn = nil
            end
            bigLoopConn = RunService.Heartbeat:Connect(function()
                if not bigRunning then return end
                stepBigChopper()
            end)
        end

        local function stopBigFarm()
            bigRunning = false
            if bigLoopConn then
                bigLoopConn:Disconnect()
                bigLoopConn = nil
            end
            bigTreeList     = {}
            bigLocalHits    = {}
            bigLastHitTime  = {}
            bigCurrentIndex = 1
        end

        -- CIRCLE FARM (SMALL + BIG) AROUND CAMPFIRE/ORIGIN
        local circleRunning   = false
        local circleLoopConn  = nil
        local circleTreeList  = {}
        local circleIndex     = 1
        local circleLastScan  = 0
        local circleLastHitAt = setmetatable({}, { __mode = "k" })
        local circleSmallHits = setmetatable({}, { __mode = "k" })

        local CIRCLE_RESCAN_EVERY = 4.0

        local function getHRP()
            local ch = lp.Character
            if not ch then return nil end
            return ch:FindFirstChild("HumanoidRootPart")
        end

        local function campfireCandidatePos(inst)
            if not inst then return nil end
            if inst:IsA("BasePart") then
                return inst.Position
            end
            if inst:IsA("Model") then
                if inst.PrimaryPart and inst.PrimaryPart:IsA("BasePart") then
                    return inst.PrimaryPart.Position
                end
                local p = inst:FindFirstChildWhichIsA("BasePart")
                return p and p.Position or nil
            end
            return nil
        end

        local function findCampfireCenter()
            local hrp = getHRP()
            local hrpPos = hrp and hrp.Position or nil

            local bestPos = nil
            local bestD = nil

            for _, inst in ipairs(WS:GetDescendants()) do
                local n = inst.Name
                if type(n) == "string" then
                    local ln = string.lower(n)
                    if ln:find("campfire", 1, true) then
                        local p = campfireCandidatePos(inst)
                        if p then
                            local d
                            if hrpPos then
                                d = (p - hrpPos).Magnitude
                            else
                                d = (p - Vector3.new(0, 0, 0)).Magnitude
                            end
                            if (not bestPos) or (d < bestD) then
                                bestPos = p
                                bestD = d
                            end
                        end
                    end
                end
            end

            return bestPos or Vector3.new(0, 0, 0)
        end

        local function rebuildCircleTreeList(centerPos)
            local list = {}
            for _, inst in ipairs(WS:GetDescendants()) do
                if inst:IsA("Model") then
                    if isSmallTreeModel(inst) or isBigTreeModel(inst) then
                        local part = bestTreeHitPart(inst)
                        if part then
                            table.insert(list, inst)
                        end
                    end
                end
            end

            table.sort(list, function(a, b)
                local pa = bestTreeHitPart(a)
                local pb = bestTreeHitPart(b)
                local da = pa and (pa.Position - centerPos).Magnitude or math.huge
                local db = pb and (pb.Position - centerPos).Magnitude or math.huge
                if da == db then
                    return (a.Name or "") < (b.Name or "")
                end
                return da < db
            end)

            circleTreeList = list
            circleIndex = 1
        end

        local function stepCircleFarm()
            local char = lp.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            local centerPos = findCampfireCenter()

            local now = os.clock()
            if (#circleTreeList == 0) or ((now - circleLastScan) >= CIRCLE_RESCAN_EVERY) then
                circleLastScan = now
                rebuildCircleTreeList(centerPos)
                if #circleTreeList == 0 then
                    return
                end
            end

            if circleIndex > #circleTreeList then
                circleIndex = 1
            end

            local tree = circleTreeList[circleIndex]
            if not tree or not tree.Parent then
                table.remove(circleTreeList, circleIndex)
                return
            end

            local isSmall = isSmallTreeModel(tree)
            local isBig   = isBigTreeModel(tree)
            if (not isSmall) and (not isBig) then
                table.remove(circleTreeList, circleIndex)
                return
            end

            local hitPart = bestTreeHitPart(tree)
            if not hitPart then
                table.remove(circleTreeList, circleIndex)
                return
            end

            local distToPlayer = (hitPart.Position - hrp.Position).Magnitude
            if distToPlayer > CHOP_RADIUS then
                teleportNearTree(tree)
                return
            end

            if isBig then
                local tool = getBigTreeTool()
                if not tool then return end
                ensureEquipped(tool)

                local requiredHits = REQUIRED_HITS[tool.Name] or 35
                local remoteCount  = getCurrentHitCount(tree)

                if remoteCount >= requiredHits then
                    table.remove(circleTreeList, circleIndex)
                    circleLastHitAt[tree] = nil
                    TreeImpactCF[tree] = nil
                    TreeHitSeed[tree]  = nil
                    return
                end

                local lastHit = circleLastHitAt[tree] or 0
                if (now - lastHit) < PER_TREE_COOLDOWN then
                    circleIndex = circleIndex + 1
                    return
                end

                local hitId    = nextPerTreeHitId(tree)
                local impactCF = impactCFForTree(tree, hitPart)
                HitTreeRemote(tree, tool, hitId, impactCF)

                circleLastHitAt[tree] = now
                circleIndex = circleIndex + 1
                return
            end

            if isSmall then
                local tool = getPreferredAxe()
                if not tool then return end
                ensureEquipped(tool)

                local needed = AXE_HITS[tool.Name] or 13
                local count  = circleSmallHits[tree] or 0

                if count >= needed then
                    table.remove(circleTreeList, circleIndex)
                    circleSmallHits[tree] = nil
                    TreeImpactCF[tree] = nil
                    TreeHitSeed[tree]  = nil
                    return
                end

                local hitId    = nextPerTreeHitId(tree)
                local impactCF = impactCFForTree(tree, hitPart)
                HitTreeRemote(tree, tool, hitId, impactCF)
                circleSmallHits[tree] = count + 1

                circleIndex = circleIndex + 1
                return
            end
        end

        local function startCircleFarm()
            if circleRunning then return end
            circleRunning = true
            circleTreeList = {}
            circleIndex = 1
            circleLastScan = 0
            if circleLoopConn then
                circleLoopConn:Disconnect()
                circleLoopConn = nil
            end
            circleLoopConn = RunService.Heartbeat:Connect(function()
                if not circleRunning then return end
                stepCircleFarm()
            end)
        end

        local function stopCircleFarm()
            circleRunning = false
            if circleLoopConn then
                circleLoopConn:Disconnect()
                circleLoopConn = nil
            end
            circleTreeList = {}
            circleIndex = 1
            circleLastScan = 0
        end

        tab:Section({ Title = "Tree Farming" })

        if tab.Slider then
            tab:Slider({
                Title = "Teleport wait (sec)",
                Value = { Min = 0, Max = 10, Default = getTeleportWaitSec() },
                Rounding = 2,
                Callback = function(v)
                    local nv = v
                    if type(v) == "table" then
                        nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
                    end
                    nv = tonumber(nv)
                    if nv == nil then nv = TELEPORT_WAIT_DEFAULT end
                    if nv < 0 then nv = 0 end
                    if nv > 30 then nv = 30 end
                    C.State.FarmTeleportWaitSec = nv
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
                    startBigFarm()
                else
                    stopBigFarm()
                end
            end
        })
    end

    local ok, err = pcall(run)
    if not ok then
        warn("[Farm] module error: " .. tostring(err))
    end
end
