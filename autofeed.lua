-- autofish.lua

return function(C, R, UI)
    local function run()
        local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
        local RunService = (C and C.Services and C.Services.Run) or game:GetService("RunService")
        local RS = (C and C.Services and C.Services.ReplicatedStorage) or game:GetService("ReplicatedStorage")
        local WS = (C and C.Services and C.Services.Workspace) or game:GetService("Workspace")
        local VirtualInputManager = game:GetService("VirtualInputManager")

        local lp = Players.LocalPlayer
        local playerGui = lp:WaitForChild("PlayerGui")
        local camera = WS.CurrentCamera

        local Tabs = (UI and UI.Tabs) or {}
        local tab = Tabs.AutoFish
        if not tab then return end

        local frame = playerGui:WaitForChild("Interface"):WaitForChild("FishingCatchFrame")
        local timingBarFrame = frame.TimingBar
        local bar = timingBarFrame.Bar
        local successArea = timingBarFrame.SuccessArea

        local autoFishEnabled = false
        local autoRecastEnabled = false
        local lastTapTime = 0
        local TAP_MIN_INTERVAL = 0.05
        local recastToken = 0

        local fishConn = nil

        local TAKE_ON_CATCH_NAMES = {
            ["Bandage"] = true,
            ["MedKit"] = true,
        }
        local TAKE_ON_CATCH_RADIUS = 15.0
        local TAKE_ON_CATCH_DELAY = 0.5

        local function itemsFolder()
            local items = WS:FindFirstChild("Items")
            if items then return items end
            local ugc = game:FindFirstChild("Ugc") or WS:FindFirstChild("Ugc")
            if ugc and ugc.Parent then
                local wroot = ugc:FindFirstChild("Workspace")
                if wroot and wroot.Parent then
                    local it = wroot:FindFirstChild("Items")
                    if it then return it end
                end
                local it2 = ugc:FindFirstChild("Items")
                if it2 then return it2 end
            end
            return nil
        end

        local function mainPart(obj)
            if not obj or not obj.Parent then return nil end
            if obj:IsA("BasePart") then return obj end
            if obj:IsA("Model") then
                if obj.PrimaryPart then return obj.PrimaryPart end
                return obj:FindFirstChildWhichIsA("BasePart", true)
            end
            return nil
        end

        local function takeItemToInventory(itemInst)
            if not (itemInst and itemInst.Parent) then return false end
            local rf = RS:FindFirstChild("RemoteEvents")
            if not rf then return false end
            local hotbarX = rf:FindFirstChild("RequestHotbarItem")
            local stopDragRE = rf:FindFirstChild("StopDraggingItem")
            if not hotbarX then return false end
            if not (stopDragRE and stopDragRE:IsA("RemoteEvent")) then return false end

            local okHotbar = pcall(function()
                if hotbarX:IsA("RemoteFunction") then
                    hotbarX:InvokeServer(itemInst)
                else
                    hotbarX:FireServer(itemInst)
                end
            end)
            if not okHotbar then return false end

            pcall(function() stopDragRE:FireServer(itemInst) end)
            RunService.Heartbeat:Wait()
            pcall(function() stopDragRE:FireServer(itemInst) end)
            return true
        end

        local function tryTakeCaughtItems()
            local items = itemsFolder()
            local char = lp.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if not (items and root) then return end

            for _, ch in ipairs(items:GetChildren()) do
                if TAKE_ON_CATCH_NAMES[ch.Name] then
                    local mp = mainPart(ch)
                    if mp and (mp.Position - root.Position).Magnitude <= TAKE_ON_CATCH_RADIUS then
                        takeItemToInventory(ch)
                    end
                end
            end
        end

        local humanoid = nil
        local lockConn = nil
        local lockedRootRotation = nil
        local lockedCamCFrame = nil
        local prevAutoRotate = nil
        local prevCameraType = nil

        local function getHumanoid()
            local char = lp.Character
            return char and char:FindFirstChildOfClass("Humanoid")
        end

        local function beginFacingLock()
            local char = lp.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            humanoid = getHumanoid()
            if not (root and humanoid) then return end

            lockedRootRotation = root.CFrame - root.CFrame.Position
            lockedCamCFrame = camera.CFrame

            prevAutoRotate = humanoid.AutoRotate
            humanoid.AutoRotate = false

            prevCameraType = camera.CameraType
            camera.CameraType = Enum.CameraType.Scriptable

            if lockConn then lockConn:Disconnect() end
            lockConn = RunService.Heartbeat:Connect(function()
                local ch = lp.Character
                local r = ch and ch:FindFirstChild("HumanoidRootPart")
                if r and lockedRootRotation then
                    r.CFrame = CFrame.new(r.Position) * lockedRootRotation
                end
                if lockedCamCFrame then
                    camera.CFrame = lockedCamCFrame
                end
            end)
        end

        local function endFacingLock()
            if lockConn then
                lockConn:Disconnect()
                lockConn = nil
            end
            if humanoid then
                pcall(function()
                    humanoid.AutoRotate = (prevAutoRotate == nil) and true or prevAutoRotate
                end)
            end
            pcall(function()
                camera.CameraType = prevCameraType or Enum.CameraType.Custom
            end)
            lockedRootRotation = nil
            lockedCamCFrame = nil
            humanoid = nil
        end

        local function getScreenTapPosition()
            local viewportSize = workspace.CurrentCamera.ViewportSize
            return viewportSize.X / 2, viewportSize.Y / 2
        end

        local function performTap()
            local x, y = getScreenTapPosition()
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
        end

        local function waitForBite(myToken)
            task.spawn(function()
                local waited = 0
                local checkInterval = 0.25
                while waited < 20 do
                    if myToken ~= recastToken or not autoRecastEnabled then
                        return
                    end
                    if frame.Visible then
                        return
                    end
                    task.wait(checkInterval)
                    waited = waited + checkInterval
                end

                if myToken ~= recastToken or not autoRecastEnabled then
                    return
                end

                performTap()
                task.wait(2)

                if myToken ~= recastToken or not autoRecastEnabled then
                    return
                end

                performTap()
                waitForBite(myToken)
            end)
        end

        frame:GetPropertyChangedSignal("Visible"):Connect(function()
            if not frame.Visible then
                task.delay(TAKE_ON_CATCH_DELAY, function()
                    tryTakeCaughtItems()
                end)

                if autoRecastEnabled then
                    task.delay(2, function()
                        if autoRecastEnabled then
                            performTap()
                            recastToken = recastToken + 1
                            local myToken = recastToken
                            waitForBite(myToken)
                        end
                    end)
                end
            end
        end)

        local function enableAutoFish()
            if fishConn then return end
            autoFishEnabled = true
            fishConn = RunService.Heartbeat:Connect(function()
                if not autoFishEnabled then return end
                if not frame.Visible then return end

                local barY = bar.Position.Y.Scale
                local areaTop = successArea.Position.Y.Scale
                local areaBottom = areaTop + successArea.Size.Y.Scale
                local inZone = barY >= areaTop and barY <= areaBottom

                if inZone and (tick() - lastTapTime) >= TAP_MIN_INTERVAL then
                    performTap()
                    lastTapTime = tick()
                end
            end)
        end

        local function disableAutoFish()
            autoFishEnabled = false
            if fishConn then
                fishConn:Disconnect()
                fishConn = nil
            end
        end

        local function enableAutoRecast()
            autoRecastEnabled = true
            beginFacingLock()
        end

        local function disableAutoRecast()
            autoRecastEnabled = false
            recastToken = recastToken + 1
            endFacingLock()
        end

        lp.CharacterAdded:Connect(function()
            if autoRecastEnabled then
                task.wait(0.5)
                beginFacingLock()
            end
        end)

        tab:Toggle({
            Title = "Auto Fish",
            Value = false,
            Callback = function(state)
                if state then enableAutoFish() else disableAutoFish() end
            end
        })

        tab:Toggle({
            Title = "Auto Recast",
            Value = false,
            Callback = function(state)
                if state then enableAutoRecast() else disableAutoRecast() end
            end
        })

        local tameFrame = playerGui:WaitForChild("Interface"):WaitForChild("TamingFluteFrame")
        local tameTimingBarFrame = tameFrame.TimingBar
        local tameBar = tameTimingBarFrame.Bar
        local tameSuccessArea = tameTimingBarFrame.SuccessArea

        local autoTameEnabled = false
        local tameLastTapTime = 0
        local TAME_TAP_MIN_INTERVAL_NORMAL = 0.05
        local TAME_TAP_MIN_INTERVAL_RECOVERY = 0.03
        local TAME_BOTTOM_MARGIN = 0.05
        local tameLastBarY = nil

        local tameConn = nil

        local function enableAutoTame()
            if tameConn then return end
            autoTameEnabled = true
            tameConn = RunService.Heartbeat:Connect(function()
                if not autoTameEnabled then return end
                if not tameFrame.Visible then
                    tameLastBarY = nil
                    return
                end

                local barY = tameBar.Position.Y.Scale
                local areaTop = tameSuccessArea.Position.Y.Scale
                local areaBottom = areaTop + tameSuccessArea.Size.Y.Scale
                local falling = tameLastBarY ~= nil and barY > tameLastBarY

                local belowZone = barY > areaBottom
                local aboveZone = barY < areaTop
                local nearBottomEdge = barY >= (areaBottom - TAME_BOTTOM_MARGIN) and barY <= areaBottom

                if belowZone then
                    if (tick() - tameLastTapTime) >= TAME_TAP_MIN_INTERVAL_RECOVERY then
                        performTap()
                        tameLastTapTime = tick()
                    end
                elseif aboveZone then
                elseif falling and nearBottomEdge then
                    if (tick() - tameLastTapTime) >= TAME_TAP_MIN_INTERVAL_NORMAL then
                        performTap()
                        tameLastTapTime = tick()
                    end
                end

                tameLastBarY = barY
            end)
        end

        local function disableAutoTame()
            autoTameEnabled = false
            if tameConn then
                tameConn:Disconnect()
                tameConn = nil
            end
            tameLastBarY = nil
        end

        tab:Toggle({
            Title = "Auto Tame",
            Value = false,
            Callback = function(state)
                if state then enableAutoTame() else disableAutoTame() end
            end
        })
    end
    local ok, err = pcall(run)
    if not ok then warn("[AutoFeed] module error: " .. tostring(err)) end
end
