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
        local TELEPORT_THROTTLE = 0.15

        local CIRCLE_RESCAN_EVERY = 2.5
        local CIRCLE_START_RADIUS = 90
        local CIRCLE_RADIUS_STEP = 70
        local CIRCLE_RADIUS_MAX = 1200

        local MAX_TREE_QUEUE = 250

        -- Small-tree dense-patch fix:
        -- Hit only a small batch per step, round-robin through the list.
        local SMALL_STEP_INTERVAL = 0.05
        local SMALL_HITS_PER_STEP = 10

        C.State = C.State or {}
        if C.State.FarmTeleportWaitSec == nil then C.State.FarmTeleportWaitSec = 1 end
        if type(C.State.FarmOrbPoints) ~= "table" then C.State.FarmOrbPoints = {} end

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
            local bucket = attrBucket(treeModel)
            if bucket and bucket.SetAttribute then
                pcall(function() bucket:SetAttribute(hitId, true) end)
            end
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

        local function hrpPosOrZero()
            local ch = lp.Character
            local h = ch and ch:FindFirstChild("HumanoidRootPart")
            return h and h.Position or Vector3.new(0, 0, 0)
        end

        local smallRunning = false
        local smallLoopConn = nil
        local smallTreeList = {}
        local smallHitCounts = {}
        local smallStartPos = Vector3.new(0, 0, 0)
        local smallCursor = 1
        local smallAcc = 0

        local function scanForAllSmallTrees()
            local origin = smallStartPos
            local list = {}
            for _, inst in ipairs(WS:GetDescendants()) do
                if inst:IsA("Model") and isSmallTreeModel(inst) then
                    list[#list + 1] = inst
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
            smallTreeList = list
            smallHitCounts = {}
            for _, m in ipairs(smallTreeList) do smallHitCounts[m] = 0 end
            smallCursor = 1
        end

        local function removeSmallTreeAt(idx)
            local t = smallTreeList[idx]
            table.remove(smallTreeList, idx)
            if t then
                smallHitCounts[t] = nil
                TreeImpactCF[t] = nil
                TreeHitSeed[t] = nil
            end
            if smallCursor > #smallTreeList then smallCursor = 1 end
            if idx < smallCursor then
                smallCursor = math.max(1, smallCursor - 1)
            end
        end

        local function startSmallLoop()
            if smallLoopConn then smallLoopConn:Disconnect() smallLoopConn = nil end
            smallAcc = 0
            smallLoopConn = RunService.Heartbeat:Connect(function(dt)
                if not smallRunning then return end
                smallAcc += (dt or 0)
                if smallAcc < SMALL_STEP_INTERVAL then return end
                smallAcc = 0

                local char = lp.Character
                if not char then return end
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if not hrp then return end

                local axe = getPreferredAxe()
                if not axe then return end
                ensureEquipped(axe)
                local axeName = axe.Name
                local neededDefault = AXE_HITS[axeName] or 13

                if #smallTreeList == 0 then
                    scanForAllSmallTrees()
                    return
                end

                if smallCursor < 1 then smallCursor = 1 end
                if smallCursor > #smallTreeList then smallCursor = 1 end

                -- If our next candidate is far, teleport toward it (keeps behavior snappy without scanning everything).
                local candidate = smallTreeList[smallCursor]
                if candidate and candidate.Parent then
                    local part = bestTreeHitPart(candidate)
                    if part then
                        local d = (part.Position - hrp.Position).Magnitude
                        if d > CHOP_RADIUS then
                            teleportNearTree(candidate)
                            return
                        end
                    end
                end

                local hitsDone = 0
                local listSize = #smallTreeList
                if listSize == 0 then return end
                local steps = math.min(SMALL_HITS_PER_STEP, listSize)

                for _ = 1, steps do
                    if #smallTreeList == 0 then break end
                    if smallCursor > #smallTreeList then smallCursor = 1 end

                    local idx = smallCursor
                    local tree = smallTreeList[idx]
                    smallCursor = smallCursor + 1
                    if smallCursor > #smallTreeList then smallCursor = 1 end

                    if not (tree and tree.Parent and isSmallTreeModel(tree)) then
                        removeSmallTreeAt(idx)
                        continue
                    end

                    local hitPart = bestTreeHitPart(tree)
                    if not hitPart then
                        removeSmallTreeAt(idx)
                        continue
                    end

                    local dist = (hitPart.Position - hrp.Position).Magnitude
                    if dist > CHOP_RADIUS then
                        continue
                    end

                    local needed = AXE_HITS[axeName] or neededDefault
                    local count = smallHitCounts[tree] or 0
                    if count >= needed then
                        removeSmallTreeAt(idx)
                        continue
                    end

                    local hitId = nextPerTreeHitId(tree)
                    local impactCF = impactCFForTree(tree, hitPart)
                    HitTreeRemote(tree, axe, hitId, impactCF)
                    smallHitCounts[tree] = count + 1
                    hitsDone += 1

                    if (count + 1) >= needed then
                        removeSmallTreeAt(idx)
                    end
                end
            end)
        end

        local function startSmallFarm()
            if smallRunning then return end
            smallRunning = true
            smallStartPos = hrpPosOrZero()
            scanForAllSmallTrees()
            startSmallLoop()
        end

        local function stopSmallFarm()
            smallRunning = false
            if smallLoopConn then smallLoopConn:Disconnect() smallLoopConn = nil end
            smallTreeList = {}
            smallHitCounts = {}
            smallCursor = 1
            smallAcc = 0
        end

        local bigRunning = false
        local bigLoopConn = nil
        local bigTreeList = {}
        local bigCurrentIndex = 1
        local bigTargetTree = nil
        local bigTargetEndAt = 0
        local bigNextSwingAt = 0
        local bigTargetWaitOnly = false
        local bigStartPos = Vector3.new(0, 0, 0)

        local function buildBigTreeList(requiredHits)
            bigTreeList = {}
            bigCurrentIndex = 1
            local origin = bigStartPos
            for _, inst in ipairs(WS:GetDescendants()) do
                if inst:IsA("Model") and isBigTreeModel(inst) then
                    local existing = getCurrentHitCount(inst)
                    if existing < requiredHits then
                        bigTreeList[#bigTreeList + 1] = inst
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
                if switchSec and switchSec > 0 then
                    bigTargetEndAt = now + switchSec
                else
                    bigTargetEndAt = 0
                end
                bigNextSwingAt = 0
            end

            if switchSec and switchSec > 0 then
                if now >= bigTargetEndAt and bigNextSwingAt ~= 0 then
                    bigTargetTree = nil
                    bigNextSwingAt = 0
                    bigCurrentIndex = bigCurrentIndex + 1
                    return
                end
            end

            if now < bigNextSwingAt then return end

            local tree = bigTargetTree
            if (not tree) or (not tree.Parent) or (not isBigTreeModel(tree)) then
                if tree then removeBigTree(tree) end
                bigTargetTree = nil
                bigTargetWaitOnly = true
                bigTargetEndAt = now + 0.10
                return
            end

            local hitPart = bestTreeHitPart(tree)
            if not hitPart then
                removeBigTree(tree)
                bigTargetTree = nil
                bigTargetWaitOnly = true
                bigTargetEndAt = now + 0.10
                return
            end

            if getCurrentHitCount(tree) >= requiredHits then
                removeBigTree(tree)
                bigTargetTree = nil
                bigTargetWaitOnly = true
                bigTargetEndAt = now + 0.10
                bigCurrentIndex = bigCurrentIndex + 1
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

        local ORB_SPEED = 50

        local orbEdgeEnabled = false
        local orbRunning = false
        local orbDir = 1
        local orbIdx = 1
        local orbRenderBound = false
        local orbGui = nil
        local orbBtnSet = nil
        local orbBtnStart = nil
        local orbCountLabel = nil
        local prevPlatformStand = nil
        local orbBG = nil
        local orbBV = nil
        local orbCharConn = nil

        local overlayRoot = nil
        local overlayFolder = nil
        local orbMarkers = {}

        local function clearInstance(x) if x then pcall(function() x:Destroy() end) end end

        local function humanoid()
            local ch = lp.Character
            return ch and ch:FindFirstChildOfClass("Humanoid")
        end

        local function hrp()
            local ch = lp.Character
            return ch and ch:FindFirstChild("HumanoidRootPart")
        end

        local function orbPoints()
            if type(C.State.FarmOrbPoints) ~= "table" then C.State.FarmOrbPoints = {} end
            return C.State.FarmOrbPoints
        end

        local function ensureOverlayFolders()
            if not overlayRoot or not overlayRoot.Parent then
                overlayRoot = WS:FindFirstChild("__Local_Overlays__")
                if not overlayRoot then
                    overlayRoot = Instance.new("Folder")
                    overlayRoot.Name = "__Local_Overlays__"
                    overlayRoot.Parent = WS
                end
            end
            if not overlayFolder or not overlayFolder.Parent then
                overlayFolder = overlayRoot:FindFirstChild("FarmOrbs")
                if not overlayFolder then
                    overlayFolder = Instance.new("Folder")
                    overlayFolder.Name = "FarmOrbs"
                    overlayFolder.Parent = overlayRoot
                end
            end
        end

        local function clearOrbMarkers()
            for _, inst in ipairs(orbMarkers) do
                clearInstance(inst)
            end
            orbMarkers = {}
        end

        local function rebuildOrbMarkers()
            ensureOverlayFolders()
            clearOrbMarkers()
            local pts = orbPoints()
            for i = 1, #pts do
                local p = pts[i]
                if typeof(p) == "Vector3" then
                    local part = Instance.new("Part")
                    part.Name = "Orb_" .. tostring(i)
                    part.Shape = Enum.PartType.Ball
                    part.Size = Vector3.new(0.7, 0.7, 0.7)
                    part.Anchored = true
                    part.CanCollide = false
                    part.Transparency = 0.15
                    part.Material = Enum.Material.Neon
                    part.CFrame = CFrame.new(p)
                    part.Parent = overlayFolder

                    local bb = Instance.new("BillboardGui")
                    bb.Name = "Idx"
                    bb.AlwaysOnTop = true
                    bb.Size = UDim2.new(0, 60, 0, 20)
                    bb.StudsOffset = Vector3.new(0, 1.1, 0)
                    bb.Parent = part

                    local tl = Instance.new("TextLabel")
                    tl.Size = UDim2.fromScale(1, 1)
                    tl.BackgroundTransparency = 1
                    tl.Text = tostring(i)
                    tl.TextColor3 = Color3.fromRGB(255, 255, 255)
                    tl.TextStrokeTransparency = 0.4
                    tl.Font = Enum.Font.SourceSansBold
                    tl.TextSize = 16
                    tl.Parent = bb

                    orbMarkers[#orbMarkers + 1] = part
                end
            end
        end

        local function setStartText(txt)
            if orbBtnStart and orbBtnStart.Parent then
                orbBtnStart.Text = txt
            end
        end

        local function setCountText()
            if orbCountLabel and orbCountLabel.Parent then
                orbCountLabel.Text = "Orbs: " .. tostring(#orbPoints())
            end
        end

        local function ensureOrbMovers(root)
            if not root then return end
            if not orbBG or not orbBG.Parent or orbBG.Parent ~= root then
                clearInstance(orbBG); orbBG = nil
                orbBG = Instance.new("BodyGyro")
                orbBG.Name = "FarmOrbBG"
                orbBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                orbBG.P = 1000
                orbBG.D = 50
                orbBG.Parent = root
            end
            if not orbBV or not orbBV.Parent or orbBV.Parent ~= root then
                clearInstance(orbBV); orbBV = nil
                orbBV = Instance.new("BodyVelocity")
                orbBV.Name = "FarmOrbBV"
                orbBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                orbBV.Velocity = Vector3.zero
                orbBV.Parent = root
            end
        end

        local function nextOrbIndex()
            local pts = orbPoints()
            local n = #pts
            if n < 2 then return 1 end
            if orbDir == 1 then
                if orbIdx >= n then
                    orbDir = -1
                    orbIdx = math.max(1, orbIdx - 1)
                else
                    orbIdx += 1
                end
            else
                if orbIdx <= 1 then
                    orbDir = 1
                    orbIdx = math.min(n, orbIdx + 1)
                else
                    orbIdx -= 1
                end
            end
            return orbIdx
        end

        local function unbindOrbRender()
            if orbRenderBound then
                orbRenderBound = false
                pcall(function()
                    RunService:UnbindFromRenderStep("FarmOrbPath")
                end)
            end
        end

        local function stopOrbRunner()
            orbRunning = false
            unbindOrbRender()
            if orbBV then orbBV.Velocity = Vector3.zero end
            clearInstance(orbBV); orbBV = nil
            clearInstance(orbBG); orbBG = nil
            local h = humanoid()
            if h and prevPlatformStand ~= nil then
                h.PlatformStand = prevPlatformStand
            end
            prevPlatformStand = nil
            setStartText("Start")
        end

        local function startOrbRunner()
            if orbRunning then return end
            local pts = orbPoints()
            if #pts < 2 then
                setStartText("Need 2+")
                task.delay(0.8, function()
                    if not orbRunning then setStartText("Start") end
                end)
                return
            end
            local root = hrp()
            local h = humanoid()
            if not root or not h then return end

            orbRunning = true
            orbDir = 1
            orbIdx = 1

            prevPlatformStand = h.PlatformStand
            h.PlatformStand = true

            setStartText("Stop")

            unbindOrbRender()
            orbRenderBound = true
            RunService:BindToRenderStep("FarmOrbPath", Enum.RenderPriority.Last.Value, function()
                if not orbRunning then return end
                local root2 = hrp()
                local h2 = humanoid()
                if not root2 or not h2 then return end

                ensureOrbMovers(root2)

                local pts2 = orbPoints()
                local n = #pts2
                if n < 2 then
                    stopOrbRunner()
                    return
                end
                if orbIdx < 1 then orbIdx = 1 end
                if orbIdx > n then orbIdx = n end

                local target = pts2[orbIdx]
                if typeof(target) ~= "Vector3" then
                    stopOrbRunner()
                    return
                end

                local pos = root2.Position
                local delta = target - pos
                local dist = delta.Magnitude

                if dist <= 2.5 then
                    nextOrbIndex()
                    return
                end

                local dir = (dist > 0.0001) and (delta / dist) or Vector3.zero
                orbBV.Velocity = dir * ORB_SPEED
                orbBG.CFrame = CFrame.new(pos, pos + dir)
            end)
        end

        local function toggleOrbRunner()
            if orbRunning then stopOrbRunner() else startOrbRunner() end
        end

        local function destroyOrbGui()
            if orbRunning then stopOrbRunner() end
            orbBtnSet = nil
            orbBtnStart = nil
            orbCountLabel = nil
            clearInstance(orbGui); orbGui = nil
            clearOrbMarkers()
        end

        local function createOrbGui()
            destroyOrbGui()

            local pg = lp:FindFirstChildOfClass("PlayerGui")
            if not pg then return end

            orbGui = Instance.new("ScreenGui")
            orbGui.Name = "FarmOrbEdgeGui"
            orbGui.ResetOnSpawn = false
            orbGui.Parent = pg

            local frame = Instance.new("Frame")
            frame.Name = "EdgeFrame"
            frame.Parent = orbGui
            frame.AnchorPoint = Vector2.new(1, 0.5)
            frame.Position = UDim2.new(1, -10, 0.5, 0)
            frame.Size = UDim2.new(0, 150, 0, 112)
            frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            frame.BorderSizePixel = 0
            frame.Active = true

            local uic = Instance.new("UICorner")
            uic.CornerRadius = UDim.new(0, 10)
            uic.Parent = frame

            local list = Instance.new("UIListLayout")
            list.Parent = frame
            list.FillDirection = Enum.FillDirection.Vertical
            list.HorizontalAlignment = Enum.HorizontalAlignment.Center
            list.VerticalAlignment = Enum.VerticalAlignment.Center
            list.Padding = UDim.new(0, 8)

            local function mkBtn(name, text)
                local b = Instance.new("TextButton")
                b.Name = name
                b.Size = UDim2.new(1, -16, 0, 32)
                b.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
                b.BorderSizePixel = 0
                b.Text = text
                b.TextColor3 = Color3.fromRGB(235, 235, 235)
                b.Font = Enum.Font.SourceSansSemibold
                b.TextSize = 16
                b.Parent = frame
                local c = Instance.new("UICorner")
                c.CornerRadius = UDim.new(0, 10)
                c.Parent = b
                return b
            end

            local function mkLabel()
                local l = Instance.new("TextLabel")
                l.Name = "Count"
                l.Size = UDim2.new(1, -16, 0, 18)
                l.BackgroundTransparency = 1
                l.Text = ""
                l.TextColor3 = Color3.fromRGB(200, 200, 200)
                l.Font = Enum.Font.SourceSans
                l.TextSize = 14
                l.Parent = frame
                return l
            end

            orbBtnSet = mkBtn("SetOrb", "Set Orb")
            orbBtnStart = mkBtn("StartStop", "Start")
            orbCountLabel = mkLabel()

            setCountText()
            rebuildOrbMarkers()

            local lastSetAt = 0
            local lastStartAt = 0

            local function onSetOrb()
                local now = os.clock()
                if (now - lastSetAt) < 0.08 then return end
                lastSetAt = now

                local root = hrp()
                if not root then return end
                local pts = orbPoints()
                pts[#pts + 1] = root.Position
                setCountText()
                rebuildOrbMarkers()
            end

            local function onStartStop()
                local now = os.clock()
                if (now - lastStartAt) < 0.12 then return end
                lastStartAt = now
                toggleOrbRunner()
            end

            orbBtnSet.Activated:Connect(onSetOrb)
            orbBtnStart.Activated:Connect(onStartStop)
        end

        if orbCharConn then pcall(function() orbCharConn:Disconnect() end) end
        orbCharConn = lp.CharacterAdded:Connect(function()
            task.defer(function()
                if orbRunning then
                    stopOrbRunner()
                    startOrbRunner()
                elseif orbEdgeEnabled then
                    rebuildOrbMarkers()
                end
            end)
        end)

        local function cleanupAll()
            stopCircleFarm()
            stopSmallFarm()
            stopBigFarm()
            destroyOrbGui()
            unbindOrbRender()
            if orbCharConn then pcall(function() orbCharConn:Disconnect() end) end
            orbCharConn = nil
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

        tab:Divider()
        tab:Section({ Title = "Orb Path" })

        tab:Toggle({
            Title = "Orb Path Edge Buttons (Set Orb / Start)",
            Value = false,
            Callback = function(state)
                orbEdgeEnabled = state and true or false
                if orbEdgeEnabled then
                    createOrbGui()
                else
                    C.State.FarmOrbPoints = {}
                    destroyOrbGui()
                end
            end
        })
    end

    local ok, err = pcall(run)
    if not ok then warn("[Farm] module error: " .. tostring(err)) end
end
