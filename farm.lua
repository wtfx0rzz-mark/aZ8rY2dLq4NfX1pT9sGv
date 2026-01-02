-- farm.lua
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
        local RequestPlantItem = RemoteEvents:WaitForChild("RequestPlantItem")

        local CHOP_RADIUS = 60
        local TELEPORT_DISTANCE = 30
        local UID_SUFFIX = "0000000000"

        local SWING_COOLDOWN_BIG = 0.5
        local TELEPORT_THROTTLE = 0.15

        local CIRCLE_RESCAN_EVERY = 2.5
        local CIRCLE_START_RADIUS = 90
        local CIRCLE_RADIUS_STEP = 70
        local CIRCLE_RADIUS_MAX = 1200

        local MAX_TREE_QUEUE = 250

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

        local function HitTreeRemote(treeModel, tool, hitId, impactCF)
            if not (treeModel and tool and hitId and impactCF) then return end
            ToolDamageObject:InvokeServer(treeModel, tool, hitId, impactCF)
        end

        local function teleportNearTree(treeModel)
            local now = os.clock()
            if (now - lastTeleportAt) < TELEPORT_THROTTLE then return false end
            local char = lp.Character
            if not char then return false end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return false end
            local hitPart = bestTreeHitPart(treeModel)
            if not hitPart then return false end
            local treePos = hitPart.Position
            local hrpPos = hrp.Position
            local dir = (hrpPos - treePos)
            if dir.Magnitude < 0.001 then dir = Vector3.new(1, 0, 0) else dir = dir.Unit end
            local targetPos = Vector3.new(treePos.X + dir.X * TELEPORT_DISTANCE, treePos.Y + 3, treePos.Z + dir.Z * TELEPORT_DISTANCE)
            hrp.CFrame = CFrame.new(targetPos, Vector3.new(treePos.X, targetPos.Y, treePos.Z))
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

        local function isSmallTreeModel(model)
            if not (model and model:IsA("Model")) then return false end
            local name = model.Name
            if TREE_NAMES[name] then return bestTreeHitPart(model) ~= nil end
            local lower = string.lower(name or "")
            if lower:find("small", 1, true) and lower:find("tree", 1, true) then
                return bestTreeHitPart(model) ~= nil
            end
            return false
        end

        local function getPreferredAxe()
            for _, name in ipairs(AXE_PREFER) do
                local item = findInInventory(name)
                if item then return item end
            end
            return nil
        end

        local BIG_TREE_NAMES_BASE = { TreeBig1 = true, TreeBig2 = true, TreeBig3 = true }
        local BIG_TREE_NAMES = buildNameSet(BIG_TREE_NAMES_BASE, EXTRA_BIG_TREE_NAMES)
        local REQUIRED_HITS = { ["Strong Axe"] = 35, ["Chainsaw"] = 35 }

        local function isBigTreeName(name)
            if BIG_TREE_NAMES[name] then return true end
            if type(name) ~= "string" then return false end
            return name:match("^WebbedTreeBig%d*$") ~= nil
        end

        local function isBigTreeModel(model)
            return model and model:IsA("Model") and isBigTreeName(model.Name) and (bestTreeHitPart(model) ~= nil)
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

        local smallRunning = false
        local smallLoopConn = nil
        local smallTreeList = {}
        local smallHitCounts = {}

        local function scanForAllSmallTrees()
            local list = {}
            for _, inst in ipairs(WS:GetDescendants()) do
                if inst:IsA("Model") and isSmallTreeModel(inst) then
                    list[#list + 1] = inst
                end
            end
            if #list > MAX_TREE_QUEUE then
                local trimmed = {}
                for i = 1, MAX_TREE_QUEUE do trimmed[i] = list[i] end
                list = trimmed
            end
            smallTreeList = list
            smallHitCounts = {}
            for _, m in ipairs(smallTreeList) do smallHitCounts[m] = 0 end
        end

        local function startSmallLoop()
            if smallLoopConn then smallLoopConn:Disconnect() smallLoopConn = nil end
            smallLoopConn = RunService.Heartbeat:Connect(function()
                if not smallRunning then return end
                local char = lp.Character
                if not char then return end
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if not hrp then return end
                local axe = getPreferredAxe()
                if not axe then return end
                ensureEquipped(axe)
                local axeName = axe.Name
                local baseNeeded = AXE_HITS[axeName] or 13
                if #smallTreeList == 0 then
                    scanForAllSmallTrees()
                    return
                end
                local nearest, nearestDist
                for _, tree in ipairs(smallTreeList) do
                    local part = bestTreeHitPart(tree)
                    if part then
                        local d = (part.Position - hrp.Position).Magnitude
                        if not nearest or d < nearestDist then
                            nearest = tree
                            nearestDist = d
                        end
                    end
                end
                if not nearest then scanForAllSmallTrees() return end
                if nearestDist > CHOP_RADIUS then teleportNearTree(nearest) return end
                local treesInRange = {}
                for _, tree in ipairs(smallTreeList) do
                    local part = bestTreeHitPart(tree)
                    if part and (part.Position - hrp.Position).Magnitude <= CHOP_RADIUS then
                        treesInRange[#treesInRange + 1] = tree
                    end
                end
                for _, tree in ipairs(treesInRange) do
                    if tree.Parent and isSmallTreeModel(tree) then
                        local needed = AXE_HITS[axeName] or baseNeeded
                        local count = smallHitCounts[tree] or 0
                        if count >= needed then
                            for i = #smallTreeList, 1, -1 do
                                if smallTreeList[i] == tree then table.remove(smallTreeList, i) end
                            end
                            smallHitCounts[tree] = nil
                        else
                            local hitPart = bestTreeHitPart(tree)
                            if hitPart then
                                local hitId = nextPerTreeHitId(tree)
                                local impactCF = impactCFForTree(tree, hitPart)
                                HitTreeRemote(tree, axe, hitId, impactCF)
                                smallHitCounts[tree] = count + 1
                            else
                                for i = #smallTreeList, 1, -1 do
                                    if smallTreeList[i] == tree then table.remove(smallTreeList, i) end
                                end
                                smallHitCounts[tree] = nil
                            end
                        end
                    else
                        for i = #smallTreeList, 1, -1 do
                            if smallTreeList[i] == tree then table.remove(smallTreeList, i) end
                        end
                        smallHitCounts[tree] = nil
                    end
                end
            end)
        end

        local function startSmallFarm()
            if smallRunning then return end
            smallRunning = true
            scanForAllSmallTrees()
            startSmallLoop()
        end

        local function stopSmallFarm()
            smallRunning = false
            if smallLoopConn then smallLoopConn:Disconnect() smallLoopConn = nil end
            smallTreeList = {}
            smallHitCounts = {}
        end

        local bigRunning = false
        local bigLoopConn = nil
        local bigTreeList = {}
        local bigCurrentIndex = 1
        local bigTargetTree = nil
        local bigTargetEndAt = 0
        local bigNextSwingAt = 0
        local bigTargetWaitOnly = false

        local function buildBigTreeList(requiredHits)
            bigTreeList = {}
            bigCurrentIndex = 1
            for _, inst in ipairs(WS:GetDescendants()) do
                if inst:IsA("Model") and isBigTreeModel(inst) then
                    local existing = getCurrentHitCount(inst)
                    if existing < requiredHits then
                        bigTreeList[#bigTreeList + 1] = inst
                        if #bigTreeList >= MAX_TREE_QUEUE then break end
                    end
                end
            end
            table.sort(bigTreeList, function(a, b) return (a.Name or "") < (b.Name or "") end)
        end

        local function removeBigTree(tree)
            if not tree then return end
            for i = #bigTreeList, 1, -1 do
                if bigTreeList[i] == tree then table.remove(bigTreeList, i) end
            end
            TreeImpactCF[tree] = nil
            TreeHitSeed[tree] = nil
        end

        local function pickNextBigTree(requiredHits)
            if #bigTreeList == 0 then buildBigTreeList(requiredHits) end
            if #bigTreeList == 0 then return nil end
            if bigCurrentIndex > #bigTreeList then bigCurrentIndex = 1 end
            local total = #bigTreeList
            local tries = 0
            while tries < total do
                tries += 1
                local tree = bigTreeList[bigCurrentIndex]
                if tree and tree.Parent and isBigTreeModel(tree) then
                    if getCurrentHitCount(tree) < requiredHits then
                        return tree
                    else
                        removeBigTree(tree)
                        total = #bigTreeList
                        if total == 0 then return nil end
                        if bigCurrentIndex > total then bigCurrentIndex = 1 end
                    end
                else
                    removeBigTree(tree)
                    total = #bigTreeList
                    if total == 0 then return nil end
                    if bigCurrentIndex > total then bigCurrentIndex = 1 end
                end
            end
            return nil
        end

        local function stepBigChopper()
            local now = os.clock()
            local char = lp.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local tool = getBigTreeTool()
            if not tool then return end
            ensureEquipped(tool)
            local requiredHits = REQUIRED_HITS[tool.Name] or 35
            local switchSec = getSwitchTreeSec()

            if bigTargetTree == nil and bigTargetWaitOnly then
                if now >= bigTargetEndAt then
                    bigTargetWaitOnly = false
                    bigTargetEndAt = 0
                    bigNextSwingAt = 0
                end
                return
            end

            if not bigTargetTree then
                local t = pickNextBigTree(requiredHits)
                if not t then return end
                bigTargetTree = t
                bigTargetEndAt = now + math.max(0, switchSec)
                bigNextSwingAt = 0
            end

            if now >= bigTargetEndAt and bigNextSwingAt ~= 0 then
                bigTargetTree = nil
                bigNextSwingAt = 0
                bigCurrentIndex = bigCurrentIndex + 1
                return
            end

            if now < bigNextSwingAt then return end

            local tree = bigTargetTree
            if (not tree) or (not tree.Parent) or (not isBigTreeModel(tree)) then
                bigTargetTree = nil
                bigTargetWaitOnly = true
                return
            end

            local hitPart = bestTreeHitPart(tree)
            if not hitPart then
                removeBigTree(tree)
                bigTargetTree = nil
                bigTargetWaitOnly = true
                return
            end

            if getCurrentHitCount(tree) >= requiredHits then
                removeBigTree(tree)
                bigTargetTree = nil
                bigTargetWaitOnly = true
                return
            end

            if (hitPart.Position - hrp.Position).Magnitude > CHOP_RADIUS then
                teleportNearTree(tree)
                bigNextSwingAt = now + 0.05
                return
            end

            local hitId = nextPerTreeHitId(tree)
            local impactCF = impactCFForTree(tree, hitPart)
            HitTreeRemote(tree, tool, hitId, impactCF)
            bigNextSwingAt = now + SWING_COOLDOWN_BIG

            if switchSec == 0 then
                bigTargetTree = nil
                bigCurrentIndex = bigCurrentIndex + 1
            end
        end

        local function startBigFarm()
            if bigRunning then return end
            bigRunning = true
            if bigLoopConn then bigLoopConn:Disconnect() bigLoopConn = nil end
            bigTreeList = {}
            bigCurrentIndex = 1
            bigTargetTree = nil
            bigTargetEndAt = 0
            bigNextSwingAt = 0
            bigTargetWaitOnly = false
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
            bigNextSwingAt = 0
            bigTargetWaitOnly = false
        end

        local circleRunning = false
        local circleLoopConn = nil
        local circleLastScan = 0
        local circleRadius = CIRCLE_START_RADIUS
        local circleTreeList = {}
        local circleIndex = 1
        local circleSmallHitCounts = {}
        local circleNextBigHitAt = 0

        local function getHRP()
            local ch = lp.Character
            if not ch then return nil end
            return ch:FindFirstChild("HumanoidRootPart")
        end

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
            local hrp = getHRP()
            local hrpPos = hrp and hrp.Position or nil
            local bestPos, bestD
            for _, inst in ipairs(WS:GetDescendants()) do
                local n = inst.Name
                if type(n) == "string" then
                    local ln = string.lower(n)
                    if ln:find("campfire", 1, true) then
                        local p = campfireCandidatePos(inst)
                        if p then
                            local d = hrpPos and (p - hrpPos).Magnitude or (p - Vector3.new(0, 0, 0)).Magnitude
                            if (not bestPos) or d < bestD then bestPos, bestD = p, d end
                        end
                    end
                end
            end
            return bestPos or Vector3.new(0, 0, 0)
        end

        local function rebuildCircleTreeList(centerPos)
            local list = {}
            local rMax = circleRadius
            for _, inst in ipairs(WS:GetDescendants()) do
                if inst:IsA("Model") and (isSmallTreeModel(inst) or isBigTreeModel(inst)) then
                    local part = bestTreeHitPart(inst)
                    if part then
                        local d = (part.Position - centerPos).Magnitude
                        if d <= rMax then
                            list[#list + 1] = inst
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
            circleTreeList = list
            if circleIndex < 1 then circleIndex = 1 end
            if circleIndex > #circleTreeList then circleIndex = 1 end
        end

        local function circleRemoveAt(idx)
            local t = circleTreeList[idx]
            table.remove(circleTreeList, idx)
            if circleIndex > #circleTreeList then circleIndex = 1 end
            if t then
                circleSmallHitCounts[t] = nil
                TreeImpactCF[t] = nil
                TreeHitSeed[t] = nil
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

        local function stepCircleFarm()
            local now = os.clock()
            local char = lp.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            local centerPos = findCampfireCenter()
            circleEnsureList(centerPos)
            if #circleTreeList == 0 then return end

            if circleIndex < 1 then circleIndex = 1 end
            if circleIndex > #circleTreeList then circleIndex = 1 end

            local tree = circleTreeList[circleIndex]
            if not tree or not tree.Parent then
                circleRemoveAt(circleIndex)
                return
            end

            local isSmall = isSmallTreeModel(tree)
            local isBig = isBigTreeModel(tree)
            if (not isSmall) and (not isBig) then
                circleRemoveAt(circleIndex)
                return
            end

            local hitPart = bestTreeHitPart(tree)
            if not hitPart then
                circleRemoveAt(circleIndex)
                return
            end

            if (hitPart.Position - hrp.Position).Magnitude > CHOP_RADIUS then
                teleportNearTree(tree)
                return
            end

            if isSmall then
                local tool = getPreferredAxe()
                if not tool then return end
                ensureEquipped(tool)
                local needed = AXE_HITS[tool.Name] or 13
                local count = circleSmallHitCounts[tree] or 0
                local hitId = nextPerTreeHitId(tree)
                local impactCF = impactCFForTree(tree, hitPart)
                HitTreeRemote(tree, tool, hitId, impactCF)
                count += 1
                circleSmallHitCounts[tree] = count
                if count >= needed then
                    circleRemoveAt(circleIndex)
                else
                    circleAdvanceIndex()
                end
                return
            end

            if isBig then
                if now < circleNextBigHitAt then
                    circleAdvanceIndex()
                    return
                end

                local tool = getBigTreeTool()
                if not tool then
                    circleAdvanceIndex()
                    return
                end
                ensureEquipped(tool)

                local requiredHits = REQUIRED_HITS[tool.Name] or 35
                if getCurrentHitCount(tree) >= requiredHits then
                    circleRemoveAt(circleIndex)
                    circleAdvanceIndex()
                    return
                end

                local hitId = nextPerTreeHitId(tree)
                local impactCF = impactCFForTree(tree, hitPart)
                HitTreeRemote(tree, tool, hitId, impactCF)

                circleNextBigHitAt = now + SWING_COOLDOWN_BIG
                circleAdvanceIndex()
                return
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
            circleNextBigHitAt = 0
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
            circleNextBigHitAt = 0
        end

        local SAPLING_RING_RADIUS = 132.168
        local SAPLING_RING_POINTS = 340
        local SAPLING_RING_INTERVAL = 0
        local SAPLING_FIND_RADIUS = 60
        local SAPLING_LAYER_Y_OFFSET = 10

        local SAPLING_HOUSE_N = 10
        local SAPLING_HOUSE_ROOF_Y_OFFSET = 12
        local SAPLING_HOUSE_INTERVAL = 0
        local SAPLING_HOUSE_SPACING = (2 * SAPLING_RING_RADIUS * math.sin(math.pi / SAPLING_RING_POINTS))

        local function hrpForSapling()
            local ch = lp.Character or lp.CharacterAdded:Wait()
            return ch:WaitForChild("HumanoidRootPart", 5)
        end

        local function characterFootY()
            local ch = lp.Character
            if not ch then return nil end
            local minY = nil
            for _, d in ipairs(ch:GetDescendants()) do
                if d:IsA("BasePart") then
                    local y = d.Position.Y - (d.Size.Y * 0.5)
                    if minY == nil or y < minY then
                        minY = y
                    end
                end
            end
            return minY
        end

        local function findNearestSapling(radius)
            local r = hrpForSapling()
            if not r then return nil end
            local pos = r.Position
            local items = WS:FindFirstChild("Items")
            if not items then return nil end
            local best, bestD = nil, (tonumber(radius) or 25)
            for _, m in ipairs(items:GetChildren()) do
                if m:IsA("Model") and m.Name == "Sapling" then
                    local ok, pv = pcall(function() return m:GetPivot() end)
                    if ok then
                        local d = (pv.Position - pos).Magnitude
                        if d <= bestD then
                            bestD = d
                            best = m
                        end
                    end
                end
            end
            return best
        end

        local function findMapGround()
            local map = WS:FindFirstChild("Map")
            if not map then return nil end
            return map:FindFirstChild("Ground")
        end

        local function groundYAt(x, z, fallbackY)
            local ground = findMapGround()
            if ground then
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Include
                params.FilterDescendantsInstances = { ground }
                local startY = (fallbackY or 0) + 800
                local start = Vector3.new(x, startY, z)
                local hit = WS:Raycast(start, Vector3.new(0, -4000, 0), params)
                if hit then return hit.Position.Y end
            end

            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            local ex = { lp.Character }
            local map = WS:FindFirstChild("Map")
            if map then
                local fol = map:FindFirstChild("Foliage")
                if fol then table.insert(ex, fol) end
            end
            local items = WS:FindFirstChild("Items")
            if items then table.insert(ex, items) end
            local chars = WS:FindFirstChild("Characters")
            if chars then table.insert(ex, chars) end
            params.FilterDescendantsInstances = ex
            local start = Vector3.new(x, (fallbackY or 50) + 250, z)
            local hit = WS:Raycast(start, Vector3.new(0, -1500, 0), params)
            if hit then return hit.Position.Y end
            return fallbackY or 0
        end

        local function waitInterval(sec)
            sec = tonumber(sec) or 0
            if sec <= 0 then
                RunService.Heartbeat:Wait()
            else
                task.wait(sec)
            end
        end

        C.Farm._plantCapture = C.Farm._plantCapture or {
            capArgs = nil,
            capPosIndex = 2,
            captured = false,
            armed = false,
            hookInstalled = false,
            oldNamecall = nil
        }
        local cap = C.Farm._plantCapture

        local function installPlantHook()
            if cap.hookInstalled then return true end
            if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" or type(checkcaller) ~= "function" then
                return false
            end
            local ok = pcall(function()
                local oldNamecall
                oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                    local method = getnamecallmethod()
                    if cap.armed and (not checkcaller()) and method == "InvokeServer" and self == RequestPlantItem then
                        local args = table.pack(...)
                        cap.capArgs = args
                        cap.capPosIndex = 2
                        if typeof(args[2]) ~= "Vector3" then
                            for i = 1, args.n do
                                if typeof(args[i]) == "Vector3" then
                                    cap.capPosIndex = i
                                    break
                                end
                            end
                        end
                        cap.captured = true
                        cap.armed = false
                    end
                    return oldNamecall(self, ...)
                end)
                cap.oldNamecall = oldNamecall
            end)
            cap.hookInstalled = ok
            return ok
        end

        local function capturePlantTemplate(timeoutSec)
            if cap.capArgs and cap.capArgs.n then return true end
            if not installPlantHook() then
                warn("[Farm] Plant capture unavailable (missing hook APIs).")
                return false
            end
            cap.captured = false
            cap.armed = true
            local deadline = os.clock() + (tonumber(timeoutSec) or 12)
            while cap.armed and (not cap.captured) and os.clock() < deadline do
                RunService.Heartbeat:Wait()
            end
            cap.armed = false
            return (cap.capArgs ~= nil and cap.capArgs.n ~= nil)
        end

        local function ensurePlantTemplateOrPrompt(seedSapling)
            if cap.capArgs and cap.capArgs.n then return true end
            warn("[Farm] Need to capture the game's real Plant signature. Plant ONE sapling manually now (you have ~12s)...")
            local ok = capturePlantTemplate(12)
            if not ok then
                warn("[Farm] Capture timed out. Plant one sapling manually, then press the button again.")
                return false
            end
            if not (cap.capArgs and cap.capArgs.n) then
                warn("[Farm] Capture failed; press the button again after planting once.")
                return false
            end
            return true
        end

        local function invokePlant(seedSapling, atPos)
            if not (seedSapling and typeof(seedSapling) == "Instance") then return false end
            if not (atPos and typeof(atPos) == "Vector3") then return false end
            if not (cap.capArgs and cap.capArgs.n) then
                local ok1, res1 = pcall(function()
                    return RequestPlantItem:InvokeServer(seedSapling, atPos)
                end)
                return ok1 and (res1 == nil or (type(res1) ~= "table") or (res1.Success ~= false))
            end
            local args = {}
            for i = 1, cap.capArgs.n do args[i] = cap.capArgs[i] end
            args[1] = seedSapling
            args[cap.capPosIndex] = atPos
            local ok, res = pcall(function()
                return RequestPlantItem:InvokeServer(unpack(args))
            end)
            return ok and (res == nil or (type(res) ~= "table") or (res.Success ~= false))
        end

        local saplingRingRunning = false
        local saplingRingToken = 0

        local function stopSaplingRing()
            saplingRingRunning = false
            saplingRingToken += 1
        end

        local function startSaplingRingPreset()
            if saplingRingRunning then return end
            saplingRingRunning = true
            saplingRingToken += 1
            local myToken = saplingRingToken

            task.spawn(function()
                local r = hrpForSapling()
                if not r then
                    saplingRingRunning = false
                    return
                end

                local center = r.Position
                local baseFootY = characterFootY()
                if not baseFootY then baseFootY = center.Y - 3 end

                local seedSapling = findNearestSapling(SAPLING_FIND_RADIUS)
                if not seedSapling then
                    warn("[Farm] Sapling ring: no Sapling found within radius " .. tostring(SAPLING_FIND_RADIUS))
                    saplingRingRunning = false
                    return
                end

                if not ensurePlantTemplateOrPrompt(seedSapling) then
                    saplingRingRunning = false
                    return
                end

                for i = 1, SAPLING_RING_POINTS do
                    if (not saplingRingRunning) or (myToken ~= saplingRingToken) then break end

                    local theta = (2 * math.pi) * ((i - 1) / SAPLING_RING_POINTS)
                    local x = center.X + math.cos(theta) * SAPLING_RING_RADIUS
                    local z = center.Z + math.sin(theta) * SAPLING_RING_RADIUS

                    local gy = groundYAt(x, z, baseFootY)
                    local pos1 = Vector3.new(x, gy, z)
                    local pos2 = Vector3.new(x, gy + SAPLING_LAYER_Y_OFFSET, z)

                    invokePlant(seedSapling, pos1)
                    waitInterval(SAPLING_RING_INTERVAL)
                    if (not saplingRingRunning) or (myToken ~= saplingRingToken) then break end
                    invokePlant(seedSapling, pos2)
                    waitInterval(SAPLING_RING_INTERVAL)
                end

                if myToken == saplingRingToken then
                    saplingRingRunning = false
                end
            end)
        end

        local saplingHouseRunning = false
        local saplingHouseToken = 0

        local function stopSaplingHouse()
            saplingHouseRunning = false
            saplingHouseToken += 1
        end

        local function startSaplingHousePreset()
            if saplingHouseRunning then return end
            saplingHouseRunning = true
            saplingHouseToken += 1
            local myToken = saplingHouseToken

            task.spawn(function()
                local r = hrpForSapling()
                if not r then
                    saplingHouseRunning = false
                    return
                end

                local center = r.Position
                local baseFootY = characterFootY()
                if not baseFootY then baseFootY = center.Y - 3 end

                local seedSapling = findNearestSapling(SAPLING_FIND_RADIUS)
                if not seedSapling then
                    warn("[Farm] Sapling house: no Sapling found within radius " .. tostring(SAPLING_FIND_RADIUS))
                    saplingHouseRunning = false
                    return
                end

                if not ensurePlantTemplateOrPrompt(seedSapling) then
                    saplingHouseRunning = false
                    return
                end

                local half = (SAPLING_HOUSE_N - 1) * 0.5
                for ix = 0, SAPLING_HOUSE_N - 1 do
                    for iz = 0, SAPLING_HOUSE_N - 1 do
                        if (not saplingHouseRunning) or (myToken ~= saplingHouseToken) then break end

                        local isEdge = (ix == 0) or (iz == 0) or (ix == SAPLING_HOUSE_N - 1) or (iz == SAPLING_HOUSE_N - 1)

                        local x = center.X + ((ix - half) * SAPLING_HOUSE_SPACING)
                        local z = center.Z + ((iz - half) * SAPLING_HOUSE_SPACING)
                        local gy = groundYAt(x, z, baseFootY)

                        if isEdge then
                            invokePlant(seedSapling, Vector3.new(x, gy, z))
                        else
                            invokePlant(seedSapling, Vector3.new(x, gy + SAPLING_HOUSE_ROOF_Y_OFFSET, z))
                        end

                        waitInterval(SAPLING_HOUSE_INTERVAL)
                    end
                    if (not saplingHouseRunning) or (myToken ~= saplingHouseToken) then break end
                end

                if myToken == saplingHouseToken then
                    saplingHouseRunning = false
                end
            end)
        end

        local function cleanupAll()
            stopSaplingHouse()
            stopSaplingRing()
            stopCircleFarm()
            stopSmallFarm()
            stopBigFarm()
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

        tab:Section({ Title = "Saplings" })

        if tab.Button then
            tab:Button({
                Title = "Plant Sapling Ring (2 layers) r=132.168 pts=340 +Y=10",
                Callback = function()
                    startSaplingRingPreset()
                end
            })

            tab:Button({
                Title = "Build Sapling House (10x10 walls + roof) roof +Y=12 (interior air only)",
                Callback = function()
                    startSaplingHousePreset()
                end
            })
        end
    end

    local ok, err = pcall(run)
    if not ok then warn("[Farm] module error: " .. tostring(err)) end
end
