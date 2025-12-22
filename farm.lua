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

        local UIS    = game:GetService("UserInputService")
        local Debris = game:GetService("Debris")

        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Farm
        if not tab then return end

        local lp = Players.LocalPlayer
        if not lp then return end

        local RemoteEvents     = RS:WaitForChild("RemoteEvents")
        local ToolDamageObject = RemoteEvents:WaitForChild("ToolDamageObject")
        local EquipItemHandle  = RemoteEvents:WaitForChild("EquipItemHandle")

        local CHOP_RADIUS       = 60
        local TELEPORT_DISTANCE = 30
        local UID_SUFFIX        = "0000000000"

        local SWING_RADIUS    = 75
        local SWING_DEBOUNCE  = 0.10
        local SWING_EQUIP_GUARD = 0.20
        local SWING_MAX_TREES = 80

        local ORB_LIFETIME = 0.7
        local ORB_COOLDOWN = 0.08

        local function findInInventory(name)
            local inv = lp:FindFirstChild("Inventory")
            if not inv then return nil end
            return inv:FindFirstChild(name)
        end

        local function findItemAnywhere(name)
            if not (lp and name) then return nil end
            local inv = lp:FindFirstChild("Inventory")
            if inv then
                local it = inv:FindFirstChild(name)
                if it then return it end
            end
            local bp = lp:FindFirstChild("Backpack")
            if bp then
                local it = bp:FindFirstChild(name)
                if it then return it end
            end
            local ch = lp.Character
            if ch then
                local it = ch:FindFirstChild(name)
                if it then return it end
            end
            return nil
        end

        local function equippedToolName()
            local ch = lp.Character
            if not ch then return nil end
            local tool = ch:FindFirstChildOfClass("Tool")
            return tool and tool.Name or nil
        end

        local function equippedTool()
            local ch = lp.Character
            if not ch then return nil end
            return ch:FindFirstChildOfClass("Tool")
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

        local function computeImpactCFrameNoRaycast(hitPart)
            if not (hitPart and hitPart:IsA("BasePart")) then
                return CFrame.new()
            end
            local rot = hitPart.CFrame - hitPart.CFrame.Position
            return CFrame.new(hitPart.Position + Vector3.new(0, 0.02, 0)) * rot
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

        local function swingImpactCFForTree(treeModel, hitPart)
            local base = TreeImpactCF[treeModel]
            if not base then
                base = computeImpactCFrameNoRaycast(hitPart)
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
            local char = lp.Character
            if not char then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local hitPart = bestTreeHitPart(treeModel)
            if not hitPart then return end

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
        local EXTRA_SMALL_TREE_NAMES = {["Christmas Pine"] = true}
        local EXTRA_BIG_TREE_NAMES = {["Northern Pine"] = true}

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
                if not char then
                    return
                end

                local hrp = char:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    return
                end

                local axe = getPreferredAxe()
                if not axe then
                    return
                end

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
                                local impactCF = swingImpactCFForTree(tree, hitPart)
                                pcall(function()
                                    local bucket = attrBucket(tree)
                                    if bucket then bucket:SetAttribute(hitId, true) end
                                end)
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
            if smallRunning then
                return
            end
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

            local axeName       = tool.Name
            local requiredHits  = REQUIRED_HITS[axeName] or 35

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
            local impactCF = swingImpactCFForTree(selectedTree, hitPart)
            pcall(function()
                local bucket = attrBucket(selectedTree)
                if bucket then bucket:SetAttribute(hitId, true) end
            end)
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
            if bigRunning then
                return
            end
            bigRunning = true
            if bigLoopConn then
                bigLoopConn:Disconnect()
                bigLoopConn = nil
            end
            bigLoopConn = RunService.Heartbeat:Connect(function()
                if not bigRunning then
                    return
                end
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

        -- SWING HIT MODE (matching combat module tree hit method)
        local function getRayOriginFromChar(ch)
            if not ch then return nil end
            local head = ch:FindFirstChild("Head")
            if head and head:IsA("BasePart") then return head.Position end
            local r = ch:FindFirstChild("HumanoidRootPart")
            if r and r:IsA("BasePart") then return r.Position + Vector3.new(0, 2.5, 0) end
            return nil
        end

        local function findTreeModelFromPart(part)
            local current = part and part.Parent
            while current do
                if current:IsA("Model") then
                    if isSmallTreeModel(current) or isBigTreeModel(current) then
                        return current
                    end
                end
                current = current.Parent
            end
            return nil
        end

        local function collectTreesInRadius(origin, radius)
            local out = {}
            if not origin or not radius or radius <= 0 then return out end

            local roots = { WS, RS:FindFirstChild("Assets"), RS:FindFirstChild("CutsceneSets") }
            local includeRoots = {}
            for _, r in ipairs(roots) do
                if r then includeRoots[#includeRoots + 1] = r end
            end
            if #includeRoots == 0 then includeRoots[1] = WS end

            local params = OverlapParams.new()
            params.FilterType = Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances = includeRoots

            local parts = WS:GetPartBoundsInRadius(origin, radius, params)
            if not parts then return out end

            local seen = {}
            for _, p in ipairs(parts) do
                if p and p:IsA("BasePart") then
                    local tree = findTreeModelFromPart(p)
                    if tree and tree.Parent and not seen[tree] then
                        seen[tree] = true
                        out[#out + 1] = tree
                        if #out >= SWING_MAX_TREES then break end
                    end
                end
            end
            return out
        end

        local lastOrbAt = 0
        local function spawnSwingOrb()
            local now = os.clock()
            if (now - lastOrbAt) < ORB_COOLDOWN then return end
            lastOrbAt = now

            local ch = lp.Character
            if not ch then return end
            local head = ch:FindFirstChild("Head")
            local hrp  = ch:FindFirstChild("HumanoidRootPart")
            local attachPart = (head and head:IsA("BasePart")) and head or ((hrp and hrp:IsA("BasePart")) and hrp or nil)
            if not attachPart then return end

            local orb = Instance.new("Part")
            orb.Name = "__SwingOrb__"
            orb.Shape = Enum.PartType.Ball
            orb.Size = Vector3.new(1.25, 1.25, 1.25)
            orb.Material = Enum.Material.Neon
            orb.Color = Color3.fromRGB(0, 255, 255)
            orb.Transparency = 0.05
            orb.Anchored = false
            orb.Massless = true
            orb.CanCollide = false
            orb.CanTouch = false
            orb.CanQuery = false
            orb.Parent = WS
            orb.CFrame = attachPart.CFrame * CFrame.new(0, 2.6, 0)

            local weld = Instance.new("WeldConstraint")
            weld.Part0 = attachPart
            weld.Part1 = orb
            weld.Parent = orb

            local light = Instance.new("PointLight")
            light.Brightness = 6
            light.Range = 14
            light.Shadows = false
            light.Parent = orb

            Debris:AddItem(orb, ORB_LIFETIME)
        end

        local swingEnabled = false
        local lastSwingAt = 0

        local swingCharConn, swingToolConn, swingChildAddConn, swingChildRemConn = nil, nil, nil, nil
        local equippedAt = setmetatable({}, { __mode = "k" })

        local function unbindSwingTool()
            if swingToolConn then swingToolConn:Disconnect() swingToolConn = nil end
        end

        local function bindSwingToEquippedTool()
            unbindSwingTool()
            local tool = equippedTool()
            if not (tool and tool:IsA("Tool") and tool.Parent) then return end
            equippedAt[tool] = os.clock()
            swingToolConn = tool.Activated:Connect(function()
                if not swingEnabled then return end
                local now = os.clock()
                if (now - (equippedAt[tool] or 0)) < SWING_EQUIP_GUARD then return end
                if (now - lastSwingAt) < SWING_DEBOUNCE then return end
                lastSwingAt = now

                local toolName = tool.Name
                local toolRef = findItemAnywhere(toolName) or tool
                spawnSwingOrb()

                local ch = lp.Character
                if not ch then return end
                local origin = getRayOriginFromChar(ch)
                if not origin then return end

                local trees = collectTreesInRadius(origin, SWING_RADIUS)
                if #trees == 0 then return end

                for _, tree in ipairs(trees) do
                    if tree and tree.Parent then
                        local hitPart = bestTreeHitPart(tree)
                        if hitPart then
                            local hitId = nextPerTreeHitId(tree)
                            local impactCF = swingImpactCFForTree(tree, hitPart)
                            task.spawn(function()
                                if not (swingEnabled and tree and tree.Parent) then return end
                                pcall(function()
                                    local bucket = attrBucket(tree)
                                    if bucket then bucket:SetAttribute(hitId, true) end
                                end)
                                pcall(function()
                                    HitTreeRemote(tree, toolRef, hitId, impactCF)
                                end)
                            end)
                        end
                    end
                end
            end)
        end

        local function disconnectSwingDetection()
            unbindSwingTool()
            if swingCharConn then swingCharConn:Disconnect() swingCharConn = nil end
            if swingChildAddConn then swingChildAddConn:Disconnect() swingChildAddConn = nil end
            if swingChildRemConn then swingChildRemConn:Disconnect() swingChildRemConn = nil end
        end

        local function connectSwingDetection()
            disconnectSwingDetection()
            lastSwingAt = 0
            lastOrbAt = 0

            local function onCharacter(ch)
                if swingChildAddConn then swingChildAddConn:Disconnect() swingChildAddConn = nil end
                if swingChildRemConn then swingChildRemConn:Disconnect() swingChildRemConn = nil end
                if not ch then return end

                swingChildAddConn = ch.ChildAdded:Connect(function(inst)
                    if not swingEnabled then return end
                    if inst and inst:IsA("Tool") then
                        task.wait()
                        bindSwingToEquippedTool()
                    end
                end)

                swingChildRemConn = ch.ChildRemoved:Connect(function(inst)
                    if inst and inst:IsA("Tool") then
                        unbindSwingTool()
                        task.wait()
                        if swingEnabled then bindSwingToEquippedTool() end
                    end
                end)

                task.spawn(function()
                    task.wait()
                    if swingEnabled then bindSwingToEquippedTool() end
                end)
            end

            swingCharConn = lp.CharacterAdded:Connect(onCharacter)
            onCharacter(lp.Character)
        end

        tab:Section({ Title = "Tree Farming" })

        tab:Toggle({
            Title = "Tree Farm (Small Trees)",
            Value = false,
            Callback = function(state)
                if state then
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
                    startBigFarm()
                else
                    stopBigFarm()
                end
            end
        })

        tab:Toggle({
            Title = "Swing Hits All Trees (Radius 75) + Orb",
            Value = false,
            Callback = function(state)
                swingEnabled = (state == true)
                if swingEnabled then
                    connectSwingDetection()
                else
                    disconnectSwingDetection()
                end
            end
        })
    end

    local ok, err = pcall(run)
    if not ok then
        warn("[Farm] module error: " .. tostring(err))
    end
end
