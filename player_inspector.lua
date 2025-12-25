-- player_inspector.lua
return function(C, R, UI)
  local function main()
    C  = C  or _G.C
    UI = UI or _G.UI

    local Players = (C and C.Services and C.Services.Players) or game:GetService("Players")
    local lp = Players.LocalPlayer
    local playerGui = lp:WaitForChild("PlayerGui")

    local Tabs = (UI and UI.Tabs) or {}
    local tab  = Tabs.PlayerInspector
    assert(tab, "PlayerInspector tab not found (UI.Tabs.PlayerInspector)")

    local selectedUid = nil
    local playerDD = nil

    local function playersList()
      local vals = {}
      for _, p in ipairs(Players:GetPlayers()) do
        vals[#vals + 1] = string.format("%s#%d", p.Name, p.UserId)
      end
      table.sort(vals)
      return vals
    end

    local function parseSelectionSingle(choice)
      if type(choice) == "table" then
        local v = choice.Value or choice[1]
        local uid = tonumber((tostring(v or ""):match("#(%d+)$") or ""))
        return uid
      end
      local uid = tonumber((tostring(choice or ""):match("#(%d+)$") or ""))
      return uid
    end

    local function findPlayerByUid(uid)
      if not uid then return nil end
      for _, p in ipairs(Players:GetPlayers()) do
        if p.UserId == uid then return p end
      end
      return nil
    end

    local function buildInfoText(p)
      local lines = {}
      if not p then
        lines[#lines + 1] = "Player: N/A"
        return table.concat(lines, "\n")
      end

      local attrs = p:GetAttributes() or {}

      local function addKV(k, v)
        lines[#lines + 1] = tostring(k) .. ": " .. (v == nil and "N/A" or tostring(v))
      end

      addKV("Player", p.Name)
      addKV("UserId", p.UserId)
      lines[#lines + 1] = ""

      addKV("Class", attrs.Class)
      addKV("ClassLevel", attrs.ClassLevel)
      addKV("Diamonds", attrs.Diamonds)
      addKV("Coins", attrs.Coins)
      addKV("Hunger", attrs.Hunger)

      local ammoKeys = {}
      for k, _ in pairs(attrs) do
        if type(k) == "string" and string.find(string.lower(k), "ammo", 1, true) then
          ammoKeys[#ammoKeys + 1] = k
        end
      end
      table.sort(ammoKeys)

      lines[#lines + 1] = ""
      lines[#lines + 1] = "Ammo Attributes:"
      if #ammoKeys == 0 then
        lines[#lines + 1] = "(none)"
      else
        for _, k in ipairs(ammoKeys) do
          addKV("  " .. k, attrs[k])
        end
      end

      return table.concat(lines, "\n")
    end

    local function openInfoWindow(text)
      local old = playerGui:FindFirstChild("PlayerInspectorWindow")
      if old then old:Destroy() end

      local sg = Instance.new("ScreenGui")
      sg.Name = "PlayerInspectorWindow"
      sg.ResetOnSpawn = false
      sg.Parent = playerGui

      local frame = Instance.new("Frame")
      frame.Size = UDim2.new(0, 420, 0, 300)
      frame.Position = UDim2.new(0.5, -210, 0.5, -150)
      frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
      frame.BorderSizePixel = 0
      frame.Active = true
      frame.Parent = sg

      local title = Instance.new("TextLabel")
      title.Size = UDim2.new(1, -44, 0, 28)
      title.Position = UDim2.new(0, 10, 0, 6)
      title.BackgroundTransparency = 1
      title.Text = "Player Inspector"
      title.TextColor3 = Color3.fromRGB(235, 235, 235)
      title.Font = Enum.Font.SourceSansBold
      title.TextSize = 18
      title.TextXAlignment = Enum.TextXAlignment.Left
      title.Parent = frame

      local close = Instance.new("TextButton")
      close.Size = UDim2.new(0, 28, 0, 28)
      close.Position = UDim2.new(1, -34, 0, 6)
      close.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
      close.BorderSizePixel = 0
      close.Text = "X"
      close.TextColor3 = Color3.fromRGB(255, 255, 255)
      close.Font = Enum.Font.SourceSansBold
      close.TextSize = 18
      close.Parent = frame
      close.MouseButton1Click:Connect(function()
        sg:Destroy()
      end)

      local sep = Instance.new("Frame")
      sep.Size = UDim2.new(1, -20, 0, 1)
      sep.Position = UDim2.new(0, 10, 0, 40)
      sep.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
      sep.BorderSizePixel = 0
      sep.Parent = frame

      local scroll = Instance.new("ScrollingFrame")
      scroll.Size = UDim2.new(1, -20, 1, -58)
      scroll.Position = UDim2.new(0, 10, 0, 48)
      scroll.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
      scroll.BorderSizePixel = 0
      scroll.ScrollBarThickness = 6
      scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
      scroll.Parent = frame

      local body = Instance.new("TextLabel")
      body.Size = UDim2.new(1, -12, 0, 0)
      body.Position = UDim2.new(0, 6, 0, 6)
      body.BackgroundTransparency = 1
      body.Text = text or ""
      body.TextColor3 = Color3.fromRGB(215, 215, 215)
      body.Font = Enum.Font.Code
      body.TextSize = 14
      body.TextXAlignment = Enum.TextXAlignment.Left
      body.TextYAlignment = Enum.TextYAlignment.Top
      body.TextWrapped = true
      body.Parent = scroll

      local function relayout()
        local h = body.TextBounds.Y + 12
        body.Size = UDim2.new(1, -12, 0, h)
        scroll.CanvasSize = UDim2.new(0, 0, 0, h + 6)
      end
      relayout()

      do
        local dragging = false
        local startPos, startFrame

        local function inHeader(inputPos)
          local fx, fy = frame.AbsolutePosition.X, frame.AbsolutePosition.Y
          local fw = frame.AbsoluteSize.X
          return inputPos.X >= fx and inputPos.X <= fx + fw and inputPos.Y >= fy and inputPos.Y <= fy + 40
        end

        local UIS = game:GetService("UserInputService")

        UIS.InputBegan:Connect(function(input)
          if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if inHeader(input.Position) then
              dragging = true
              startPos = Vector2.new(input.Position.X, input.Position.Y)
              startFrame = frame.Position
            end
          end
        end)

        UIS.InputEnded:Connect(function(input)
          if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
          end
        end)

        UIS.InputChanged:Connect(function(input)
          if not dragging then return end
          if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
          local dx = input.Position.X - startPos.X
          local dy = input.Position.Y - startPos.Y
          frame.Position = UDim2.new(startFrame.X.Scale, startFrame.X.Offset + dx, startFrame.Y.Scale, startFrame.Y.Offset + dy)
        end)
      end
    end

    local function buildPlayerDropdownOnce()
      if playerDD then return end
      local vals = playersList()
      playerDD = tab:Dropdown({
        Title = "Player",
        Values = vals,
        Multi = false,
        AllowNone = true,
        Callback = function(choice)
          selectedUid = parseSelectionSingle(choice)
        end
      })
      if not selectedUid and #vals > 0 then
        selectedUid = parseSelectionSingle(vals[1])
      end
    end

    buildPlayerDropdownOnce()

    tab:Button({
      Title = "View Selected Player",
      Callback = function()
        if not playerDD then
          buildPlayerDropdownOnce()
        end
        local p = findPlayerByUid(selectedUid)
        local text = buildInfoText(p)
        openInfoWindow(text)
      end
    })

    tab:Button({
      Title = "Refresh Player List",
      Callback = function()
        playerDD = nil
        selectedUid = nil
        buildPlayerDropdownOnce()
      end
    })
  end

  main()
end
