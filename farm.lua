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
            if not m then return nil end
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

            local path = PF:CreatePath({
                AgentRadius = 2,
                AgentHeight = 5,
                AgentCanJump = true,
                AgentCanClimb = true,
            })

            path:ComputeAsync(root.Position, pos)

            if path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                for _, wp in ipairs(waypoints) do
                    h:MoveTo(wp.Position)
                    local reached = h.MoveToFinished:Wait()
                    if not reached then break end
                end
            else
                h:MoveTo(pos)
                if maxWait and maxWait > 0 then
                    local t0 = os.clock()
                    repeat
                        if (os.clock() - t0) > maxWait then break end
                        Run.Heartbeat:Wait()
                    until (root.Position - pos).Magnitude <= 4
                else
                    h.MoveToFinished:Wait()
                end
            end
        end

        local function equipBestAxe()
            local ch = lp.Character
            if not ch then return nil end

            local priorities = {
                ["GoldenAxe"] = 3,
                ["SteelAxe"]  = 2,
                ["BasicAxe"]  = 1,
            }

            local bestTool, bestPrio = nil, -1
            for _, t in ipairs(ch:GetChildren()) do
                if t:IsA("Tool") then
                    local p = priorities[t.Name]
                    if p and p > bestPrio then
                        bestPrio = p
                        bestTool = t
                    end
                end
            end

            if bestTool then
                local h = hum()
                if h then
                    pcall(function() h:EquipTool(bestTool) end)
                end
            end

            return bestTool
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

            local mp = mainPart(tree)
            if not mp then return end

            local targetPos = mp.Position
            if (targetPos - root.Position).Magnitude > 7 then
                moveToPosition(targetPos, 4)
                root = hrp()
                if not root then return end
            end

            local tool = equipBestAxe() or tree:FindFirstChildOfClass("Tool")
            if not tool then
                return
            end

            swings = swings or 14

            for _ = 1, swings do
                if not lp.Character or not lp.Character.Parent then break end
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
            ["BigTree"]      = true,
            ["Big Tree"]     = true,
            ["TreeBig1"]     = true,
            ["TreeBig2"]     = true,
            ["TreeBig3"]     = true,
            ["WebbedTreeBig"] = true,
        }

        local smallFarmOn      = false
        local smallFarmThread  = nil
        local bigFarmOn        = false
        local bigFarmThread    = nil

        local SMALL_MAX_DIST   = 160
        local BIG_MAX_DIST     = 220
        local IDLE_WAIT        = 0.35

        local function smallFarmLoop()
            smallFarmOn = true
            while smallFarmOn do
                local tree, dist = getClosestModelByNames(SMALL_TREE_NAMES, SMALL_MAX_DIST)
                if tree and dist < SMALL_MAX_DIST then
                    chopModel(tree, 14)
                else
                    Run.Heartbeat:Wait()
                    task.wait(IDLE_WAIT)
                end
            end
        end

        local function bigFarmLoop()
            bigFarmOn = true
            while bigFarmOn do
                local tree, dist = getClosestModelByNames(BIG_TREE_NAMES, BIG_MAX_DIST)
                if tree and dist < BIG_MAX_DIST then
                    chopModel(tree, 18)
                else
                    Run.Heartbeat:Wait()
                    task.wait(IDLE_WAIT)
                end
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
                        smallFarmThread = task.spawn(smallFarmLoop)
                    end
                else
                    smallFarmOn = false
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
                        bigFarmThread = task.spawn(bigFarmLoop)
                    end
                else
                    bigFarmOn = false
                end
            end
        })

        lp.CharacterAdded:Connect(function()
            if smallFarmOn and not smallFarmThread then
                smallFarmThread = task.spawn(smallFarmLoop)
            end
            if bigFarmOn and not bigFarmThread then
                bigFarmThread = task.spawn(bigFarmLoop)
            end
        end)
    end

    local ok, err = pcall(run)
    if not ok then
        warn("[Farm] module error: " .. tostring(err))
    end
end
