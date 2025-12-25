-- player_inspector.lua
return function(C, R, UI)
  local function main()
    C  = C  or _G.C
    UI = UI or _G.UI

    local Services = (C and C.Services) or {}
    local Players  = Services.Players or game:GetService("Players")
    local UIS      = game:GetService("UserInputService")

    local lp = (C and C.LocalPlayer) or Players.LocalPlayer
    local playerGui = lp:WaitForChild("PlayerGui")

    local function getPlayerNames()
      local t = {}
      for _, p in ipairs(Players:GetPlayers()) do
        t[#t+1] = p.Name
      end
      table.sort(t)
      return t
    end

    local function findPlayerByName(name)
      if type(name) ~= "string" or name == "" then return nil end
      return Players:FindFirstChild(name)
    end

    local function buildInfoText(p)
      local lines = {}
      lines[#lines+1] = "Player: " .. (p and p.Name or "N/A")
      if p then lines[#lines+1] = "UserId: " .. tostring(p.UserId) end
      lines[#lines+1] = ""

      local attrs = p and p:GetAttributes() or {}
      local function addKey(k)
        local v = attrs[k]
        lines[#lines+1] = k .. ": " .. (v == nil and "N/A" or tostring(v))
      end

      addKey("Class")
      addKey("ClassLevel")
      addKey("Diamonds")
      addKey("Coins")
      addKey("Hunger")

      local ammoKeys = {}
      for k, _ in pairs(attrs) do
        if type(k) == "string" and string.find(string.lower(k), "ammo", 1, true) then
          ammoKeys[#ammoKeys+1] = k
        end
      end
      table.sort(ammoKeys)

      lines[#lines+1] = ""
      lines[#lines+1] = "Ammo Attributes:"
      if #ammoKeys == 0 then
        lines[#lines+1] = "(none)"
      else
        for _, k in ipairs(ammoKeys) do
          local v = attrs[k]
          lines[#lines+1] = "  " .. k .. ": " .. (v == nil and "N/A" or tostring(v))
        end
      end

      return table.concat(lines, "\n")
    end

    local function openInfoWindow(text)
      local old = playerGui:FindFirstChild("PlayerInfoWindow")
      if old then old:Destroy() end

      local sg = Instance.new("ScreenGui")
      sg.Name = "PlayerInfoWindow"
      sg.ResetOnSpawn = false
      sg.Parent = playerGui

      local frame = Instance.new("Frame")
      frame.Name = "Window"
      frame.Size = UDim2.new(0, 360, 0, 260)
      frame.Position = UDim2.new(0.5, -180, 0.5, -130)
      frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
      frame.BorderSizePixel = 0
      frame.Parent = sg

      local title = Instance.new("TextLabel")
      title.Name = "Title"
      title.Size = UDim2.new(1, -40, 0, 28)
      title.Position = UDim2.new(0, 10, 0, 6)
      title.BackgroundTransparency = 1
      title.Text = "Player Attributes"
      title.TextColor3 = Color3.fromRGB(235, 235, 235)
      title.Font = Enum.Font.SourceSansBold
      title.TextSize = 18
      title.TextXAlignment = Enum.TextXAlignment.Left
      title.Parent = frame

      local close = Instance.new("TextButton")
      close.Name = "Close"
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
      sep.Name = "Sep"
      sep.Size = UDim2.new(1, -20, 0, 1)
      sep.Position = UDim2.new(0, 10, 0, 40)
      sep.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
      sep.BorderSizePixel = 0
      sep.Parent = frame

      local scroll = Instance.new("ScrollingFrame")
      scroll.Name = "Scroll"
      scroll.Size = UDim2.new(1, -20, 1, -58)
      scroll.Position = UDim2.new(0, 10, 0, 48)
      scroll.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
      scroll.BorderSizePixel = 0
      scroll.ScrollBarThickness = 6
      scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
      scroll.Parent = frame

      local txt = Instance.new("TextLabel")
      txt.Name = "Body"
      txt.Size = UDim2.new(1, -12, 0, 0)
      txt.Position = UDim2.new(0, 6, 0, 6)
      txt.BackgroundTransparency = 1
      txt.Text = text or ""
      txt.TextColor3 = Color3.fromRGB(215, 215, 215)
      txt.Font = Enum.Font.Code
      txt.TextSize = 14
      txt.TextXAlignment = Enum.TextXAlignment.Left
      txt.TextYAlignment = Enum.TextYAlignment.Top
      txt.TextWrapped = true
      txt.Parent = scroll

      local function relayout()
        local h = txt.TextBounds.Y + 12
        txt.Size = UDim2.new(1, -12, 0, h)
        scroll.CanvasSize = UDim2.new(0, 0, 0, h + 6)
      end
      relayout()

      local dragging = false
      local dragStartPos, frameStartPos

      local function inputBegan(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
          local x, y = input.Position.X, input.Position.Y
          local fx, fy = frame.AbsolutePosition.X, frame.AbsolutePosition.Y
          local fw, fh = frame.AbsoluteSize.X, frame.AbsoluteSize.Y
          if x >= fx and x <= fx + fw and y >= fy and y <= fy + 40 then
            dragging = true
            dragStartPos = Vector2.new(x, y)
            frameStartPos = frame.Position
          end
        end
      end

      local function inputEnded(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
          dragging = false
        end
      end

      local function inputChanged(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local dx = input.Position.X - dragStartPos.X
        local dy = input.Position.Y - dragStartPos.Y
        frame.Position = UDim2.new(frameStartPos.X.Scale, frameStartPos.X.Offset + dx, frameStartPos.Y.Scale, frameStartPos.Y.Offset + dy)
      end

      UIS.InputBegan:Connect(inputBegan)
      UIS.InputEnded:Connect(inputEnded)
      UIS.InputChanged:Connect(inputChanged)
    end

    local function safeCall(obj, methodName, ...)
      if not obj then return nil end
      local fn = obj[methodName]
      if type(fn) ~= "function" then return nil end
      local ok, res = pcall(fn, obj, ...)
      if ok then return res end
      return nil
    end

    local function addButton(tab, title, cb)
      return safeCall(tab, "Button", title, cb)
          or safeCall(tab, "AddButton", title, cb)
          or safeCall(tab, "CreateButton", { Title = title, Callback = cb })
          or safeCall(tab, "Add", "Button", { Title = title, Callback = cb })
    end

    local function addDropdown(tab, title, values, default, cb)
      return safeCall(tab, "Dropdown", title, values, cb)
          or safeCall(tab, "AddDropdown", title, values, cb)
          or safeCall(tab, "CreateDropdown", { Title = title, Values = values, Default = default, Callback = cb })
          or safeCall(tab, "Add", "Dropdown", { Title = title, Values = values, Default = default, Callback = cb })
    end

    local Tabs = (UI and UI.Tabs) or {}
    local tab = Tabs.PlayerInspector or Tabs.Players or Tabs.Debug or Tabs.Main

    if not tab and UI and UI.Window then
      tab = safeCall(UI.Window, "Tab", "PlayerInspector")
        or safeCall(UI.Window, "AddTab", "PlayerInspector")
    end
    if not tab then return end

    local state = (C and C.State) or {}
    if C then C.State = state end
    if state.SelectedInspectPlayer == nil then
      state.SelectedInspectPlayer = lp and lp.Name or ""
    end

    local names = getPlayerNames()
    if #names > 0 and (state.SelectedInspectPlayer == "" or not findPlayerByName(state.SelectedInspectPlayer)) then
      state.SelectedInspectPlayer = names[1]
    end

    local dd = addDropdown(tab, "Player", names, state.SelectedInspectPlayer, function(v)
      if type(v) == "string" then
        state.SelectedInspectPlayer = v
      elseif type(v) == "table" then
        local pick = v.Value or v[1]
        if type(pick) == "string" then state.SelectedInspectPlayer = pick end
      end
    end)

    addButton(tab, "View Selected Player", function()
      local selected = state.SelectedInspectPlayer
      local p = findPlayerByName(selected)
      local text = buildInfoText(p)
      openInfoWindow(text)
    end)

    local function tryUpdateDropdown()
      local newNames = getPlayerNames()
      if dd and type(dd) == "table" then
        if type(dd.SetValues) == "function" then pcall(dd.SetValues, dd, newNames) end
        if type(dd.Set) == "function" and state.SelectedInspectPlayer and state.SelectedInspectPlayer ~= "" then
          pcall(dd.Set, dd, state.SelectedInspectPlayer)
        end
      end
    end

    Players.PlayerAdded:Connect(function() tryUpdateDropdown() end)
    Players.PlayerRemoving:Connect(function() tryUpdateDropdown() end)
  end

  main()
end
