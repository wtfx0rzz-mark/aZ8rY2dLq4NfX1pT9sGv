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

    local function mergeInto(dst, src)
      if type(src) ~= "table" then return end
      for k, v in pairs(src) do
        if dst[k] == nil then
          dst[k] = v
        end
      end
    end

    local function collectValueObjects(root, out, limit)
      if not root or not root.Parent then return end
      limit = tonumber(limit) or 600
      local n = 0

      local function consider(obj)
        if n >= limit then return false end
        if obj:IsA("ValueBase") then
          local name = obj.Name
          if out[name] == nil then
            local ok, val = pcall(function() return obj.Value end)
            if ok then out[name] = val end
          end
        end
        n += 1
        return n < limit
      end

      for _, child in ipairs(root:GetChildren()) do
        if not consider(child) then return end
      end

      local desc = root:GetDescendants()
      for i = 1, #desc do
        if not consider(desc[i]) then return end
      end
    end

    local function collectAllStats(p)
      local stats = {}

      if p then
        mergeInto(stats, p:GetAttributes() or {})

        local ch = p.Character
        if ch then
          mergeInto(stats, ch:GetAttributes() or {})
        end

        local ls = p:FindFirstChild("leaderstats")
        if ls then
          collectValueObjects(ls, stats, 300)
        end

        local common = { "Stats", "stats", "Data", "data", "Profile", "profile" }
        for _, name in ipairs(common) do
          local folder = p:FindFirstChild(name)
          if folder then
            collectValueObjects(folder, stats, 600)
          end
        end
      end

      return stats
    end

    local function pickKey(stats, candidates)
      for _, k in ipairs(candidates) do
        if stats[k] ~= nil then return k, stats[k] end
      end
      return candidates[1], nil
    end

    local function buildInfoText(p)
      local lines = {}

      if not p then
        lines[#lines + 1] = "Player: N/A"
        return table.concat(lines, "\n")
      end

      local stats = collectAllStats(p)

      local function addKV(k, v)
        lines[#lines + 1] = tostring(k) .. ": " .. (v == nil and "N/A" or tostring(v))
      end

      addKV("Player", p.Name)
      addKV("UserId", p.UserId)
      lines[#lines + 1] = ""

      local classK, classV = pickKey(stats, { "Class", "PlayerClass", "class" })
      local lvlK,   lvlV   = pickKey(stats, { "ClassLevel", "Level", "classLevel", "lvl" })
      local diaK,   diaV   = pickKey(stats, { "Diamonds", "Diamond", "Gems", "diamonds" })
      local coinK,  coinV  = pickKey(stats, { "Coins", "Coin", "Gold", "coins" })
      local hunK,   hunV   = pickKey(stats, { "Hunger", "hunger" })

      addKV(classK, classV)
      addKV(lvlK, lvlV)
      addKV(diaK, diaV)
      addKV(coinK, coinV)
      addKV(hunK, hunV)

      local ammoKeys = {}
      for k, _ in pairs(stats) do
        if type(k) == "string" and string.find(string.lower(k), "ammo", 1, true) then
          ammoKeys[#ammoKeys + 1] = k
        end
      end
      table.sort(ammoKeys)

      lines[#lines + 1] = ""
      lines[#lines + 1] = "Ammo:"
      if #ammoKeys == 0 then
        lines[#lines + 1] = "(none found)"
      else
        for _, k in ipairs(ammoKeys) do
          addKV("  " .. k, stats[k])
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

      task.defer(relayout)

      do
        local dragging = false
        local startPos, startFrame
        local UIS = game:GetService("UserInputService")

        local function inHeader(inputPos)
          local fx, fy = frame.AbsolutePosition.X, frame.AbsolutePosition.Y
          local fw = frame.AbsoluteSize.X
          return inputPos.X >= fx and inputPos.X <= fx + fw and inputPos.Y >= fy and inputPos.Y <= fy + 40
        end

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

    local function ensureDropdown()
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

      if (not selectedUid) and #vals > 0 then
        selectedUid = parseSelectionSingle(vals[1])
      end
    end

    local function updateDropdownValues()
      if not playerDD then return end
      local vals = playersList()

      local ok = false
      if type(playerDD) == "table" then
        if type(playerDD.SetValues) == "function" then
          ok = pcall(playerDD.SetValues, playerDD, vals)
        elseif type(playerDD.Refresh) == "function" then
          ok = pcall(playerDD.Refresh, playerDD, vals)
        elseif type(playerDD.Update) == "function" then
          ok = pcall(playerDD.Update, playerDD, vals)
        end
      end

      if selectedUid then
        local stillThere = false
        for _, s in ipairs(vals) do
          local uid = tonumber((tostring(s):match("#(%d+)$") or ""))
          if uid == selectedUid then
            stillThere = true
            break
          end
        end
        if not stillThere then
          selectedUid = (#vals > 0) and parseSelectionSingle(vals[1]) or nil
        end
      elseif #vals > 0 then
        selectedUid = parseSelectionSingle(vals[1])
      end

      return ok
    end

    ensureDropdown()

    tab:Button({
      Title = "View Selected Player",
      Callback = function()
        ensureDropdown()
        updateDropdownValues()
        local p = findPlayerByUid(selectedUid)
        local text = buildInfoText(p)
        openInfoWindow(text)
      end
    })
  end

  main()
end
