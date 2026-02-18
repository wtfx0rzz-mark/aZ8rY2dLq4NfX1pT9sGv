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

    local function parseUid(choice)
      if type(choice) == "table" then
        local v = choice.Value or choice[1]
        return tonumber((tostring(v or ""):match("#(%d+)$") or ""))
      end
      return tonumber((tostring(choice or ""):match("#(%d+)$") or ""))
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
        if dst[k] == nil then dst[k] = v end
      end
    end

    local function collectValueObjects(root, out, limit)
      if not root or not root.Parent then return end
      limit = tonumber(limit) or 800
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

      for _, d in ipairs(root:GetDescendants()) do
        if not consider(d) then return end
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
        if ls then collectValueObjects(ls, stats, 400) end

        for _, name in ipairs({ "Stats", "stats", "Data", "data", "Profile", "profile" }) do
          local folder = p:FindFirstChild(name)
          if folder then collectValueObjects(folder, stats, 800) end
        end
      end

      return stats
    end

    local function getAny(stats, keys)
      for _, k in ipairs(keys) do
        if stats[k] ~= nil then return k, stats[k] end
      end
      return keys[1], nil
    end

    local function buildInfoText(p)
      if not p then
        return "Player: N/A\n"
      end

      local stats = collectAllStats(p)

      local lines = {}
      local function addKV(k, v)
        lines[#lines + 1] = tostring(k) .. ": " .. (v == nil and "N/A" or tostring(v))
      end

      addKV("Player", p.Name)
      addKV("DisplayName", p.DisplayName)
      addKV("UserId", p.UserId)
      addKV("AccountAge", p.AccountAge)
      lines[#lines + 1] = ""

      local classK, classV = getAny(stats, { "Class", "class", "PlayerClass" })
      local lvlK,   lvlV   = getAny(stats, { "ClassLevel", "classLevel", "Level", "lvl" })
      local diaK,   diaV   = getAny(stats, { "Diamonds", "diamonds", "Gems", "Gem" })
      local coinK,  coinV  = getAny(stats, { "Coins", "coins", "Gold", "gold" })
      local hunK,   hunV   = getAny(stats, { "Hunger", "hunger" })

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

      return table.concat(lines, "\n") .. "\n"
    end

    local function openInfoWindow(text)
      local old = playerGui:FindFirstChild("PlayerInspectorWindow")
      if old then
        pcall(function() old:Destroy() end)
      end

      local sg = Instance.new("ScreenGui")
      sg.Name = "PlayerInspectorWindow"
      sg.ResetOnSpawn = false
      sg.Parent = playerGui

      local conns = {}
      local cleaned = false

      local function trackConn(c)
        if c then conns[#conns + 1] = c end
        return c
      end

      local function cleanup()
        if cleaned then return end
        cleaned = true
        for i = #conns, 1, -1 do
          local c = conns[i]
          conns[i] = nil
          pcall(function()
            if c and c.Disconnect then c:Disconnect() end
          end)
        end
      end

      -- Ensure teardown always runs (explicit close, external destroy, or parent nil).
      if sg.Destroying then
        trackConn(sg.Destroying:Connect(function()
          cleanup()
        end))
      end

      trackConn(sg.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
          cleanup()
        end
      end))

      local frame = Instance.new("Frame")
      frame.Size = UDim2.new(0, 460, 0, 320)
      frame.Position = UDim2.new(0.5, -230, 0.5, -160)
      frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
      frame.BorderSizePixel = 0
      frame.Active = true
      frame.Parent = sg

      local titleBar = Instance.new("Frame")
      titleBar.Size = UDim2.new(1, 0, 0, 36)
      titleBar.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
      titleBar.BorderSizePixel = 0
      titleBar.Parent = frame

      local title = Instance.new("TextLabel")
      title.Size = UDim2.new(1, -50, 1, 0)
      title.Position = UDim2.new(0, 10, 0, 0)
      title.BackgroundTransparency = 1
      title.Text = "Player Inspector"
      title.TextColor3 = Color3.fromRGB(235, 235, 235)
      title.Font = Enum.Font.SourceSansBold
      title.TextSize = 18
      title.TextXAlignment = Enum.TextXAlignment.Left
      title.Parent = titleBar

      local close = Instance.new("TextButton")
      close.Size = UDim2.new(0, 32, 0, 26)
      close.Position = UDim2.new(1, -40, 0, 5)
      close.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
      close.BorderSizePixel = 0
      close.Text = "X"
      close.TextColor3 = Color3.fromRGB(255, 255, 255)
      close.Font = Enum.Font.SourceSansBold
      close.TextSize = 16
      close.Parent = titleBar
      trackConn(close.MouseButton1Click:Connect(function()
        cleanup() -- critical: disconnect UIS handlers immediately
        sg:Destroy()
      end))

      local scroll = Instance.new("ScrollingFrame")
      scroll.Size = UDim2.new(1, -16, 1, -46)
      scroll.Position = UDim2.new(0, 8, 0, 40)
      scroll.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
      scroll.BorderSizePixel = 0
      scroll.ScrollBarThickness = 6
      scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
      scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
      scroll.Parent = frame

      local body = Instance.new("TextLabel")
      body.BackgroundTransparency = 1
      body.Position = UDim2.new(0, 8, 0, 8)
      body.Size = UDim2.new(1, -16, 0, 0)
      body.AutomaticSize = Enum.AutomaticSize.Y
      body.TextWrapped = true
      body.TextXAlignment = Enum.TextXAlignment.Left
      body.TextYAlignment = Enum.TextYAlignment.Top
      body.Font = Enum.Font.Code
      body.TextSize = 14
      body.TextColor3 = Color3.fromRGB(215, 215, 215)
      body.Text = text or ""
      body.Parent = scroll

      do
        local UIS = game:GetService("UserInputService")
        local dragging = false
        local startPos, startFrame

        local function inTitle(inputPos)
          local fx, fy = titleBar.AbsolutePosition.X, titleBar.AbsolutePosition.Y
          local fw, fh = titleBar.AbsoluteSize.X, titleBar.AbsoluteSize.Y
          return inputPos.X >= fx and inputPos.X <= fx + fw and inputPos.Y >= fy and inputPos.Y <= fy + fh
        end

        trackConn(UIS.InputBegan:Connect(function(input)
          if cleaned or not sg.Parent then return end
          if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if inTitle(input.Position) then
              dragging = true
              startPos = Vector2.new(input.Position.X, input.Position.Y)
              startFrame = frame.Position
            end
          end
        end))

        trackConn(UIS.InputEnded:Connect(function(input)
          if cleaned or not sg.Parent then return end
          if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
          end
        end))

        trackConn(UIS.InputChanged:Connect(function(input)
          if cleaned or not sg.Parent then return end
          if not dragging then return end
          if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
          if not startPos or not startFrame then return end
          local dx = input.Position.X - startPos.X
          local dy = input.Position.Y - startPos.Y
          frame.Position = UDim2.new(startFrame.X.Scale, startFrame.X.Offset + dx, startFrame.Y.Scale, startFrame.Y.Offset + dy)
        end))
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
          selectedUid = parseUid(choice)
        end
      })

      if (not selectedUid) and #vals > 0 then
        selectedUid = parseUid(vals[1])
      end
    end

    local function tryUpdateDropdownValues()
      if not playerDD then return end
      local vals = playersList()

      if type(playerDD) == "table" then
        if type(playerDD.SetValues) == "function" then
          pcall(playerDD.SetValues, playerDD, vals)
        elseif type(playerDD.Refresh) == "function" then
          pcall(playerDD.Refresh, playerDD, vals)
        elseif type(playerDD.Update) == "function" then
          pcall(playerDD.Update, playerDD, vals)
        end
      end

      if selectedUid then
        local stillThere = false
        for _, s in ipairs(vals) do
          if tonumber((tostring(s):match("#(%d+)$") or "")) == selectedUid then
            stillThere = true
            break
          end
        end
        if not stillThere then
          selectedUid = (#vals > 0) and parseUid(vals[1]) or nil
        end
      elseif #vals > 0 then
        selectedUid = parseUid(vals[1])
      end
    end

    ensureDropdown()

    tab:Button({
      Title = "View Selected Player",
      Callback = function()
        ensureDropdown()
        tryUpdateDropdownValues()
        local p = findPlayerByUid(selectedUid)
        local text = buildInfoText(p)
        openInfoWindow(text)
      end
    })
  end

  main()
end
