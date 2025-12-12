-- farm.lua

return function(C, R, UI)
    local function run()
        local Services = (C and C.Services) or {}
        local Players  = Services.Players  or game:GetService("Players")
        local WS       = Services.WS       or game:GetService("Workspace")
        local Run      = Services.Run      or game:GetService("RunService")
        local PF       = Services.PF       or game:GetService("PathfindingService")

        local Tabs = (UI and UI.Tabs) or {}
        local tab  = Tabs.Farm
        if not tab then return end

        local lp = Players.LocalPlayer

        local function hrp()
            local ch = lp.Character or lp.CharacterAdded:Wait()
            return ch and ch:FindFirstChild("HumanoidRootPart")
        end

        local function hum()
            local ch = lp.Character
            return ch and ch:FindFirstChildOfClass("Humanoid")
        end

        local function mainPart(m)
            if not m or not m.Parent then return nil end
            if m:IsA("BasePart") then return m end
            if m:IsA("Model") then
                if m.PrimaryPart then return m.PrimaryPart end
                return m:FindFirstChildWhichIsA("BasePart")
            end
            return nil
        end

        local function moveToPosition(pos, maxWait)
            local root = hrp()
            local h    = hum()
            if not (root and h and pos) then return end
            if h.Health <= 0 then return end

            local okPath, path = pcall(function()
                return PF:CreatePath({
                    AgentRadius = 2,
                    AgentHeight = 5,
                    AgentCanJump = true,
                    AgentCanClimb = true,
                })
            end)

            if okPath and path then
                local okCompute = pcall(function()
                    path:ComputeAsync(root.Position, pos)
                end)

                if okCompute and path.Status == Enum.PathStatus.Success then
                    local waypoints = path:GetWaypoints()
                    for _, wp in ipairs(waypoints) do
                        if not lp.Character or not lp.Character.Parent then break end
                        if h.Health <= 0 then break end
                        if wp.Action == Enum.PathWaypointAction.Jump then
                            h.Jump = true
                        end
                        h:MoveTo(wp.Position)
                        local reached = h.MoveToFinished:Wait()
                        if not reached then break end
                    end
                    return
                end
            end

            h:MoveTo(pos)
            if maxWait and maxWait > 0 then
                local t0 = os.clock()
                repeat
                    if (os.clock() - t0) > maxWait then break end
                    Run.Heartbeat:Wait()
                    root = hrp()
                    if not root then break end
                until (root.Position - pos).Magnitude <= 4
            else
                h.MoveToFinished:Wait()
            end
        end

        local function equipBestAxe()
            local ch = lp.Character
            if not ch then return nil end
            local h = hum()
            if not h then return nil end

            local bp = lp:FindFirstChildOfClass("Backpack")

            local priorities = {
                ["Strong Axe"] = 3,
                ["Good Axe"]  = 2,
                ["Old Axe"]  = 1,
            }

            local bestTool, bestPrio = nil, -1

            local function considerTool(t)
                if not t or not t:IsA("Tool") then return end
                local p = priorities[t.Name]
                if p and p > bestPrio then
                    bestPrio = p
                    bestTool = t
                end
            end

            for _, t in ipairs(ch:GetChildren()) do
                considerTool(t)
            end
            if bp then
                for _, t in ipairs(bp:GetChildren()) do
                    considerTool(t)
                end
            end

            if bestTool then
                pcall(function()
                    h:EquipTool(bestTool)
                end)
                Run.Heartbeat:Wait()
                if bestTool.Parent ~= ch then
                    Run.Heartbeat:Wait()
                end
            end

            return (bestTool and bestTool.Parent == ch) and bestTool or nil
        end

        local function getClosestModelByNames(nameSet, maxDist)
            local root = hrp()
            if not root then return nil, math.huge end

            local best, bestD = nil, math.huge
            maxDist = maxDist or math.huge

            for _, inst in ipairs(WS:GetDescendants()) do
                if inst:IsA("Model") and nameSet[inst.Name] then
                    local mp = mainPart(inst)
                    if mp then
                        local d = (mp.Position - root.Position).Magnitude
                        if d < bestD and d <= maxDist then
                            bestD = d
                            best  = inst
                        end
                    end
                end
            end

            return best, bestD
        end

        local function chopModel(tree, swings)
            local root = hrp()
            local h    = hum()
            if not (tree and root and h) then return end
            if h.Health <= 0 then return end

            local mp = mainPart(tree)
            if not mp then return end

            local targetPos = mp.Position
            if (targetPos - root.Position).Magnitude > 7 then
                moveToPosition(targetPos, 4)
                root = hrp()
                h = hum()
                if not (root and h) then return end
                if h.Health <= 0 then return end
            end

            local tool = equipBestAxe()
            if not tool then return end

            swings = swings or 14
            for _ = 1, swings do
                if not lp.Character or not lp.Character.Parent then break end
                h = hum()
                if not h or h.Health <= 0 then break end
                pcall(function() tool:Activate() end)
                Run.Heartbeat:Wait()
            end
        end

        local SMALL_TREE_NAMES = {
            ["Tree"]       = true,
            ["SmallTree"]  = true,
            ["Small Tree"] = true,
        }

        local BIG_TREE_NAMES = {
            ["BigTree"]       = true,
            ["Big Tree"]      = true,
            ["TreeBig1"]      = true,
            ["TreeBig2"]      = true,
            ["TreeBig3"]      = true,
            ["WebbedTreeBig"] = true,
        }

        local SMALL_MAX_DIST = 160
        local BIG_MAX_DIST   = 220
        local IDLE_WAIT      = 0.35

        local smallFarmOn = false
        local smallFarmThread = nil
        local smallFarmToken = 0

        local bigFarmOn = false
        local bigFarmThread = nil
        local bigFarmToken = 0

        local function smallFarmLoop(token)
            local ok, err = pcall(function()
                while smallFarmOn and smallFarmToken == token do
                    local tree, dist = getClosestModelByNames(SMALL_TREE_NAMES, SMALL_MAX_DIST)
                    if tree and dist < SMALL_MAX_DIST then
                        chopModel(tree, 14)
                    else
                        Run.Heartbeat:Wait()
                        task.wait(IDLE_WAIT)
                    end
                end
            end)
            if not ok then
                warn("[Farm] smallFarmLoop error: " .. tostring(err))
            end
            if smallFarmToken == token then
                smallFarmThread = nil
            end
        end

        local function bigFarmLoop(token)
            local ok, err = pcall(function()
                while bigFarmOn and bigFarmToken == token do
                    local tree, dist = getClosestModelByNames(BIG_TREE_NAMES, BIG_MAX_DIST)
                    if tree and dist < BIG_MAX_DIST then
                        chopModel(tree, 18)
                    else
                        Run.Heartbeat:Wait()
                        task.wait(IDLE_WAIT)
                    end
                end
            end)
            if not ok then
                warn("[Farm] bigFarmLoop error: " .. tostring(err))
            end
            if bigFarmToken == token then
                bigFarmThread = nil
            end
        end

        tab:Section({ Title = "Tree Farming" })

        tab:Toggle({
            Title = "Tree Farm (Small Trees)",
            Value = false,
            Callback = function(state)
                if state then
                    if not smallFarmOn then
                        smallFarmOn = true
                        smallFarmToken = smallFarmToken + 1
                        local token = smallFarmToken
                        smallFarmThread = task.spawn(function()
                            smallFarmLoop(token)
                        end)
                    end
                else
                    smallFarmOn = false
                    smallFarmToken = smallFarmToken + 1
                end
            end
        })

        tab:Toggle({
            Title = "Big Tree Farm",
            Value = false,
            Callback = function(state)
                if state then
                    if not bigFarmOn then
                        bigFarmOn = true
                        bigFarmToken = bigFarmToken + 1
                        local token = bigFarmToken
                        bigFarmThread = task.spawn(function()
                            bigFarmLoop(token)
                        end)
                    end
                else
                    bigFarmOn = false
                    bigFarmToken = bigFarmToken + 1
                end
            end
        })

        lp.CharacterAdded:Connect(function()
            if smallFarmOn and not smallFarmThread then
                smallFarmToken = smallFarmToken + 1
                local token = smallFarmToken
                smallFarmThread = task.spawn(function()
                    smallFarmLoop(token)
                end)
            end
            if bigFarmOn and not bigFarmThread then
                bigFarmToken = bigFarmToken + 1
                local token = bigFarmToken
                bigFarmThread = task.spawn(function()
                    bigFarmLoop(token)
                end)
            end
        end)
    end

    local ok, err = pcall(run)
    if not ok then
        warn("[Farm] module error: " .. tostring(err))
    end
end
