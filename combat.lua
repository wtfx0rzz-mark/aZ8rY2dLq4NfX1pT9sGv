return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Combat, "combat.lua: missing context or Combat tab")

    local Services = C.Services or {}
    local RS       = Services.RS       or game:GetService("ReplicatedStorage")
    local WS       = Services.WS       or game:GetService("Workspace")
    local Players  = Services.Players  or game:GetService("Players")
    local Run      = Services.Run      or game:GetService("RunService")
    local lp       = C.LocalPlayer     or Players.LocalPlayer

    local CombatTab = UI.Tabs.Combat

    C.State  = C.State  or { Toggles = {} }
    C.State.Toggles = C.State.Toggles or {}
    if C.State.AuraRadius == nil then C.State.AuraRadius = 75 end
    C.Config = C.Config or {}

    local TUNE = C.Config
    TUNE.CHOP_SWING_DELAY         = TUNE.CHOP_SWING_DELAY         or 0.50
    TUNE.TREE_NAME                = TUNE.TREE_NAME                or "Small Tree"
    TUNE.UID_SUFFIX               = TUNE.UID_SUFFIX               or "0000000000"
    TUNE.ChopPrefer               = TUNE.ChopPrefer               or { "Admin Axe", "Chainsaw", "Strong Axe", "Ice Axe", "Good Axe", "Old Axe" }
    TUNE.MAX_TARGETS_PER_WAVE     = TUNE.MAX_TARGETS_PER_WAVE     or 20
    TUNE.CHAR_MAX_PER_WAVE        = TUNE.CHAR_MAX_PER_WAVE        or 20
    TUNE.CHAR_DEBOUNCE_SEC        = TUNE.CHAR_DEBOUNCE_SEC        or 0.5
    TUNE.CHAR_HIT_STEP_WAIT       = TUNE.CHAR_HIT_STEP_WAIT       or 0.0
    TUNE.CHAR_SORT                = (TUNE.CHAR_SORT ~= false)
    TUNE.EQUIP_VERIFY_TIMEOUT_SEC = TUNE.EQUIP_VERIFY_TIMEOUT_SEC or 0.08
    TUNE.EQUIP_VERIFY_STEP_SEC    = TUNE.EQUIP_VERIFY_STEP_SEC    or 0.02

    local TRAP_MAX_RADIUS = 20

    --------------------------------------------------------------------
    -- AURA VISUAL (CIRCLE) (NO RAYCASTS)
    --------------------------------------------------------------------

    local auraVis = {
        enabled = false,
        conn = nil,
        charConn = nil,
        gui = nil,
        folder = nil,
        anchor = nil,
        adorn = nil,
        character = nil,
        hrp = nil,
        acc = 0,
        _groundRoot = nil,
        _groundLastTryAt = 0,
    }

    local function auraVis_getPlayerGui()
        return lp and lp:FindFirstChildOfClass("PlayerGui") or (lp and lp:WaitForChild("PlayerGui"))
    end

    function auraVis:cleanupLegacy()
        local pg = auraVis_getPlayerGui()
        if pg then
            for _, child in ipairs(pg:GetChildren()) do
                if child:IsA("ScreenGui") then
                    if child.Name == "AuraCircleGui_v4" or child.Name:match("^AuraCircleGui") or child.Name == "CombatAuraCircleGui" then
                        pcall(function() child:Destroy() end)
                    end
                end
            end
        end
        local rf = WS:FindFirstChild("__Aura__")
        if rf then
            local a = rf:FindFirstChild("AuraAnchor_" .. tostring(lp.UserId))
            if a then pcall(function() a:Destroy() end) end
        end
    end

    function auraVis:ensure()
        local pg = auraVis_getPlayerGui()
        if not pg then return false end

        if not self.gui or not self.gui.Parent then
            local g = Instance.new("ScreenGui")
            g.Name = "CombatAuraCircleGui"
            g.ResetOnSpawn = false
            g.IgnoreGuiInset = true
            g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            g.DisplayOrder = 999999
            g.Parent = pg
            self.gui = g
        end

        if not self.folder or not self.folder.Parent then
            local rf = WS:FindFirstChild("__Aura__")
            if not rf then
                rf = Instance.new("Folder")
                rf.Name = "__Aura__"
                rf.Parent = WS
            end
            self.folder = rf
        end

        if not self.anchor or not self.anchor.Parent then
            local oldAnchor = self.folder:FindFirstChild("AuraAnchor_" .. tostring(lp.UserId))
            if oldAnchor then pcall(function() oldAnchor:Destroy() end) end

            local a = Instance.new("Part")
            a.Name = "AuraAnchor_" .. tostring(lp.UserId)
            a.Anchored = true
            a.CanCollide = false
            a.CanQuery = false
            a.CanTouch = false
            a.Transparency = 1
            a.Size = Vector3.new(0.2, 0.2, 0.2)
            a.Parent = self.folder
            self.anchor = a
        end

        if not self.adorn or not self.adorn.Parent then
            local ad = Instance.new("CylinderHandleAdornment")
            ad.Name = "AuraRing"
            ad.Adornee = self.anchor
            ad.AlwaysOnTop = true
            ad.ZIndex = 1
            ad.Color3 = Color3.fromRGB(0, 255, 255)
            ad.Transparency = 0.25
            ad.Height = 0.12
            ad.Angle = 360
            ad.CFrame = CFrame.Angles(-math.pi/2, 0, 0)
            ad.Parent = self.gui
            self.adorn = ad
        end

        return true
    end

    function auraVis:applyRadius(r)
        if not self.adorn then return end
        r = tonumber(r) or 0
        if r <= 0 then
            pcall(function() self.adorn.Visible = false end)
            self.adorn.Radius = 0
            self.adorn.InnerRadius = 0
            return
        end
        pcall(function() self.adorn.Visible = true end)
        self.adorn.Radius = r
        local inner = r - 0.6
        if inner < 0 then inner = 0 end
        self.adorn.InnerRadius = inner
    end

    function auraVis:refreshCharRefs()
        local ch = lp.Character
        if not ch then return end
        local hrp = ch:FindFirstChild("HumanoidRootPart")
        self.character = ch
        self.hrp = hrp
    end

    function auraVis:_resolveGroundRoot()
        local now = os.clock()
        if self._groundRoot and self._groundRoot.Parent then return self._groundRoot end
        if (now - (self._groundLastTryAt or 0)) < 1.0 then return nil end
        self._groundLastTryAt = now

        local map = WS:FindFirstChild("Map")
        if not map then return nil end
        local ground = map:FindFirstChild("Ground")
        if not ground then return nil end
        self._groundRoot = ground
        return ground
    end

    function auraVis:_groundYAtXZ(x, z, fallbackY)
        local ground = self:_resolveGroundRoot()
        if not ground then return fallbackY end

        local origin = Vector3.new(x, (fallbackY or 0) + 200, z)
        local dir = Vector3.new(0, -600, 0)

        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Include
        rp.FilterDescendantsInstances = { ground }
        rp.IgnoreWater = true

        local res = WS:Raycast(origin, dir, rp)
        if res and res.Position then
            return res.Position.Y
        end
        return fallbackY
    end

    function auraVis:updateAnchor()
        if not (self.hrp and self.hrp.Parent and self.anchor and self.anchor.Parent) then return end
        local pos = self.hrp.Position
        local groundY = self:_groundYAtXZ(pos.X, pos.Z, pos.Y - 3.0)
        local y = (groundY or (pos.Y - 3.0)) + 0.05
        self.anchor.CFrame = CFrame.new(pos.X, y, pos.Z)
    end

    function auraVis:start()
        if self.enabled then
            self:applyRadius(C.State.AuraRadius)
            return
        end
        self.enabled = true
        self:cleanupLegacy()
        if not self:ensure() then
            self.enabled = false
            return
        end
        self:refreshCharRefs()
        self:applyRadius(C.State.AuraRadius)
        self.acc = 0

        if self.charConn then pcall(function() self.charConn:Disconnect() end) end
        self.charConn = lp.CharacterAdded:Connect(function(ch)
            self.character = ch
            self.hrp = ch:WaitForChild("HumanoidRootPart")
        end)

        if self.conn then pcall(function() self.conn:Disconnect() end) end
        self.conn = Run.Heartbeat:Connect(function(dt)
            if not self.enabled then return end
            self.acc += dt
            if self.acc >= 0.05 then
                self.acc = 0
                self:updateAnchor()
            end
        end)
    end

    function auraVis:stop()
        self.enabled = false
        if self.conn then pcall(function() self.conn:Disconnect() end) end
        if self.charConn then pcall(function() self.charConn:Disconnect() end) end
        self.conn = nil
        self.charConn = nil
        if self.gui then pcall(function() self.gui:Destroy() end) end
        self.gui = nil
        self.adorn = nil
        if self.anchor then pcall(function() self.anchor:Destroy() end) end
        self.anchor = nil
        self._groundRoot = nil
        self._groundLastTryAt = 0
    end

    local function syncAuraVisualRadius()
        if auraVis.enabled then
            auraVis:applyRadius(C.State.AuraRadius)
        end
    end

    --------------------------------------------------------------------
    -- CHARACTER AURA (SELF-CONTAINED)
    --------------------------------------------------------------------

    local CharacterAura = {}
    CharacterAura.running = false

    do
        local lastHitAt = setmetatable({}, { __mode = "k" })
        local characterHitSeq = 0

        local CHAR_WEAPON_PREF = {
            { "Admin Axe",         0.5 },
            { "Cultist King Mace", 1.0 },
            { "Obsidiron Hammer",  1.0 },
            { "Infernal Sword",    0.51 },
            { "Morningstar",       1.0 },
            { "Ice Sword",         0.5 },
            { "Scythe",            0.7 },
            { "Katana",            0.4 },
            { "Trident",           0.6 },
            { "Laser Sword",       0.5 },
            { "Poison Spear",      0.5 },
            { "Spear",             0.5 },
            { "Strong Axe",        0.5 },
            { "Chainsaw",          0.5 },
            { "Ice Axe",           0.5 },
            { "Good Axe",          0.5 },
            { "Old Axe",           0.5 },
        }

        local function char_findItem(name)
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
            local sg = lp:FindFirstChild("StarterGear")
            if sg then
                local it = sg:FindFirstChild(name)
                if it then return it end
            end
            local ch = lp.Character
            if ch then
                local it = ch:FindFirstChild(name)
                if it then return it end
            end
            return nil
        end

        local function char_equippedToolName()
            local ch = lp and lp.Character
            if not ch then return nil end
            local t = ch:FindFirstChildOfClass("Tool")
            return t and t.Name or nil
        end

        local function char_SafeEquip(tool)
            if not tool then return end
            local ev = RS:FindFirstChild("RemoteEvents")
            ev = ev and ev:FindFirstChild("EquipItemHandle")
            if ev then ev:FireServer("FireAllClients", tool) end
        end

        local function char_ensureEquipped(wantedName)
            if not wantedName then return nil end
            if char_equippedToolName() == wantedName then
                return char_findItem(wantedName)
            end
            local tool = char_findItem(wantedName)
            if tool then
                char_SafeEquip(tool)
                local timeout = tonumber(TUNE.EQUIP_VERIFY_TIMEOUT_SEC) or 0.08
                local step = tonumber(TUNE.EQUIP_VERIFY_STEP_SEC) or 0.02
                local t0 = os.clock()
                while os.clock() - t0 < timeout do
                    if char_equippedToolName() == wantedName then break end
                    task.wait(step)
                end
            end
            return tool
        end

        local function char_bestAvailableWeapon()
            for _, pair in ipairs(CHAR_WEAPON_PREF) do
                local name, cd = pair[1], pair[2]
                if char_findItem(name) then
                    return name, (tonumber(cd) or TUNE.CHAR_DEBOUNCE_SEC)
                end
            end
            for _, n in ipairs(TUNE.ChopPrefer) do
                if char_findItem(n) then
                    return n, TUNE.CHAR_DEBOUNCE_SEC
                end
            end
            return nil, nil
        end

        local function char_getRayOriginFromChar(ch)
            if not ch then return nil end
            local head = ch:FindFirstChild("Head")
            if head and head:IsA("BasePart") then return head.Position end
            local r = ch:FindFirstChild("HumanoidRootPart")
            if r and r:IsA("BasePart") then return r.Position + Vector3.new(0, 2.5, 0) end
            return nil end

        local function char_modelOf(inst)
            if not inst then return nil end
            if inst:IsA("Model") then return inst end
            return inst:FindFirstAncestorOfClass("Model")
        end

        local function char_isCharacterModel(m)
            return m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") ~= nil
        end

        local function char_charDistancePart(m)
            if not (m and m:IsA("Model")) then return nil end
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then return hrp end
            local pp = m.PrimaryPart
            if pp and pp:IsA("BasePart") then return pp end
            return nil
        end

        local function char_characterHeadPart(model)
            if not (model and model:IsA("Model")) then return nil end
            local head = model:FindFirstChild("Head")
            if head and head:IsA("BasePart") then return head end
            local hrp = model:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then return hrp end
            if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
            return model:FindFirstChildWhichIsA("BasePart")
        end

        local function char_computeImpactCFrame(hitPart)
            if not (hitPart and hitPart:IsA("BasePart")) then
                return CFrame.new()
            end
            local rot = hitPart.CFrame - hitPart.CFrame.Position
            return CFrame.new(hitPart.Position + Vector3.new(0, 0.02, 0)) * rot
        end

        local function char_nextHitId()
            characterHitSeq += 1
            return tostring(characterHitSeq) .. "_" .. TUNE.UID_SUFFIX
        end

        local function char_canHitWithWeapon(target, weaponName, cooldownSec)
            if not target then return false, nil end
            local cd = tonumber(cooldownSec) or TUNE.CHAR_DEBOUNCE_SEC
            local bucket = lastHitAt[target]
            if not bucket or type(bucket) ~= "table" then return true, nil end
            local t = bucket[weaponName]
            if not t then return true, nil end
            local elapsed = os.clock() - t
            if elapsed >= cd then return true, nil end
            return false, cd - elapsed
        end

        local function char_markHitWithWeapon(target, weaponName)
            if not (target and weaponName) then return end
            local bucket = lastHitAt[target]
            if type(bucket) ~= "table" then
                bucket = {}
                lastHitAt[target] = bucket
            end
            bucket[weaponName] = os.clock()
        end

        local function char_HitTarget(targetModel, tool, hitId, impactCF)
            local evs = RS:FindFirstChild("RemoteEvents")
            local dmg = evs and evs:FindFirstChild("ToolDamageObject")
            if not dmg then return end
            dmg:InvokeServer(targetModel, tool, hitId, impactCF)
        end

        local function char_collectCharactersInRadius(charsFolder, origin, radius)
            local out = {}
            if not charsFolder or not origin or not radius or radius <= 0 then return out end

            local params = OverlapParams.new()
            params.FilterType = Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances = { charsFolder }

            local parts = WS:GetPartBoundsInRadius(origin, radius, params)
            if not parts then return out end

            local seen = {}
            for _, part in ipairs(parts) do
                if part and part:IsA("BasePart") then
                    local mdl = char_modelOf(part)
                    if mdl and char_isCharacterModel(mdl) and not seen[mdl] then
                        repeat
                            local n = mdl.Name or ""
                            local nameLower = n:lower()
                            if string.find(nameLower, "horse", 1, true) then break end
                            if n == "Deer" or n == "Ram" or n == "Owl" or n == "Pelt Trader" or n == "Furniture Trader" or n == "Horse" then break end
                            seen[mdl] = true
                            out[#out + 1] = mdl
                        until true
                    end
                end
            end

            if TUNE.CHAR_SORT then
                table.sort(out, function(a, b)
                    local pa, pb = char_charDistancePart(a), char_charDistancePart(b)
                    local da = pa and (pa.Position - origin).Magnitude or math.huge
                    local db = pb and (pb.Position - origin).Magnitude or math.huge
                    if da == db then return (a.Name or "") < (b.Name or "") end
                    return da < db
                end)
            end

            return out
        end

        local function char_chopWave(targetModels)
            if not CharacterAura.running then return end
            local toolName, cd = char_bestAvailableWeapon()
            if not toolName then
                task.wait(0.2)
                return
            end

            local tool = char_ensureEquipped(toolName)
            if not tool then
                task.wait(0.2)
                return
            end

            local cap = math.min(#targetModels, TUNE.CHAR_MAX_PER_WAVE)
            local anySent = false
            local soonest = math.huge
            local hitsLaunched = 0

            for i = 1, cap do
                if not CharacterAura.running then return end
                local mdl = targetModels[i]
                if mdl and mdl.Parent then
                    local head = char_characterHeadPart(mdl)
                    if head then
                        local ok, waitFor = char_canHitWithWeapon(mdl, toolName, cd)
                        if ok then
                            local impactCF = char_computeImpactCFrame(head)
                            local hitId = char_nextHitId()
                            char_markHitWithWeapon(mdl, toolName)
                            anySent = true
                            hitsLaunched += 1

                            task.spawn(function()
                                if not (CharacterAura.running and mdl and mdl.Parent) then return end
                                pcall(function()
                                    char_HitTarget(mdl, tool, hitId, impactCF)
                                end)
                            end)

                            if (TUNE.CHAR_HIT_STEP_WAIT and TUNE.CHAR_HIT_STEP_WAIT > 0) then
                                task.wait(TUNE.CHAR_HIT_STEP_WAIT)
                            else
                                if hitsLaunched % 6 == 0 then task.wait() end
                            end
                        elseif waitFor and waitFor < soonest then
                            soonest = waitFor
                        end
                    end
                end
            end

            if anySent then
                local waitT = cd
                if soonest < math.huge then
                    waitT = math.min(cd, soonest)
                end
                task.wait(math.max(0.02, waitT))
            else
                if soonest < math.huge then
                    task.wait(math.max(0.02, soonest))
                else
                    task.wait(0.15)
                end
            end
        end

        function CharacterAura.Start()
            if CharacterAura.running then return end
            CharacterAura.running = true
            task.spawn(function()
                while CharacterAura.running do
                    local ch = lp.Character or lp.CharacterAdded:Wait()
                    local hrp = ch:FindFirstChild("HumanoidRootPart")
                    if not hrp then
                        task.wait(0.2)
                    else
                        local origin = (char_getRayOriginFromChar(ch) or hrp.Position)
                        local radius = tonumber(C.State.AuraRadius) or 75
                        local charsFolder = WS:FindFirstChild("Characters")
                        local targets = char_collectCharactersInRadius(charsFolder, origin, radius)
                        if #targets > 0 then
                            char_chopWave(targets)
                        else
                            task.wait(0.1)
                        end
                    end
                end
            end)
        end

        function CharacterAura.Stop()
            CharacterAura.running = false
        end
    end

    --------------------------------------------------------------------
    -- SMALL TREE AURA (SELF-CONTAINED)
    --------------------------------------------------------------------

    local SmallTreeAura = {}
    SmallTreeAura.running = false
    SmallTreeAura._cursor = 1

    do
        local TREE_NAMES = {
            ["Small Tree"] = true,
            ["Snowy Small Tree"] = true,
            ["Small Webbed Tree"] = true,
            ["Christmas Pine"] = true,
            ["Northern Pine"] = true,
            ["Brightwood Tree"] = true
        }

        local TreeImpactCF = setmetatable({}, { __mode = "k" })
        local TreeHitSeed  = setmetatable({}, { __mode = "k" })
        local TreeLastHitAt = setmetatable({}, { __mode = "k" })

        local function st_findItem(name)
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
            local sg = lp:FindFirstChild("StarterGear")
            if sg then
                local it = sg:FindFirstChild(name)
                if it then return it end
            end
            local ch = lp.Character
            if ch then
                local it = ch:FindFirstChild(name)
                if it then return it end
            end
            return nil
        end

        local function st_equippedToolName()
            local ch = lp and lp.Character
            if not ch then return nil end
            local t = ch:FindFirstChildOfClass("Tool")
            return t and t.Name or nil
        end

        local function st_SafeEquip(tool)
            if not tool then return end
            local ev = RS:FindFirstChild("RemoteEvents")
            ev = ev and ev:FindFirstChild("EquipItemHandle")
            if ev then ev:FireServer("FireAllClients", tool) end
        end

        local function st_ensureEquipped(wantedName)
            if not wantedName then return nil end
            if st_equippedToolName() == wantedName then
                return st_findItem(wantedName)
            end
            local tool = st_findItem(wantedName)
            if tool then
                st_SafeEquip(tool)
                local timeout = tonumber(TUNE.EQUIP_VERIFY_TIMEOUT_SEC) or 0.08
                local step = tonumber(TUNE.EQUIP_VERIFY_STEP_SEC) or 0.02
                local t0 = os.clock()
                while os.clock() - t0 < timeout do
                    if st_equippedToolName() == wantedName then break end
                    task.wait(step)
                end
            end
            return tool
        end

        local function st_getRayOriginFromChar(ch)
            if not ch then return nil end
            local head = ch:FindFirstChild("Head")
            if head and head:IsA("BasePart") then return head.Position end
            local r = ch:FindFirstChild("HumanoidRootPart")
            if r and r:IsA("BasePart") then return r.Position + Vector3.new(0, 2.5, 0) end
            return nil
        end

        local function st_bestTreeHitPart(tree)
            if not tree or not tree:IsA("Model") then return nil end
            local hr = tree:FindFirstChild("HitRegisters")
            if hr then
                local t = hr:FindFirstChild("Trunk")
                if t and t:IsA("BasePart") then return t end
                local any = hr:FindFirstChildWhichIsA("BasePart")
                if any then return any end
            end
            local t2 = tree:FindFirstChild("Trunk")
            if t2 and t2:IsA("BasePart") then return t2 end
            return tree.PrimaryPart or tree:FindFirstChildWhichIsA("BasePart")
        end

        local function st_isSmallTreeModel(model)
            if not (model and model:IsA("Model")) then return false end
            local name = model.Name
            if TREE_NAMES[name] then
                return st_bestTreeHitPart(model) ~= nil
            end
            if type(name) ~= "string" then return false end
            local lower = name:lower()
            if lower:find("small", 1, true) and lower:find("tree", 1, true) then
                return st_bestTreeHitPart(model) ~= nil
            end
            return false
        end

        local function st_findTreeModelFromPart(part)
            local current = part and part.Parent
            while current do
                if current:IsA("Model") then
                    if st_isSmallTreeModel(current) then
                        return current
                    end
                end
                current = current.Parent
            end
            return nil
        end

        local function st_attrBucket(treeModel)
            local hr = treeModel and treeModel:FindFirstChild("HitRegisters")
            return (hr and hr:IsA("Instance")) and hr or treeModel
        end

        local function st_parseHitAttrKey(k)
            local n = string.match(k or "", "^(%d+)_" .. TUNE.UID_SUFFIX .. "$")
            return n and tonumber(n) or nil
        end

        local function st_nextPerTreeHitId(treeModel)
            local bucket = st_attrBucket(treeModel)
            local maxN = 0
            local attrs = bucket and bucket:GetAttributes() or nil
            if attrs then
                for k, _ in pairs(attrs) do
                    local n = st_parseHitAttrKey(k)
                    if n and n > maxN then maxN = n end
                end
            end
            local nextN = maxN + 1
            return tostring(nextN) .. "_" .. TUNE.UID_SUFFIX
        end

        local function st_computeImpactCFrame(hitPart)
            if not (hitPart and hitPart:IsA("BasePart")) then
                return CFrame.new()
            end
            local rot = hitPart.CFrame - hitPart.CFrame.Position
            return CFrame.new(hitPart.Position + Vector3.new(0, 0.02, 0)) * rot
        end

        local function st_jittered(cf, k)
            local r = 0.05 + 0.015 * (k % 5)
            local ang = k * 2.3999632297
            local off = Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
            local rot = cf - cf.Position
            return CFrame.new(cf.Position + off) * rot
        end

        local function st_impactCFForTree(treeModel, hitPart)
            local base = TreeImpactCF[treeModel]
            if not base then
                base = st_computeImpactCFrame(hitPart)
                TreeImpactCF[treeModel] = base
            end
            local k = (TreeHitSeed[treeModel] or 0) + 1
            TreeHitSeed[treeModel] = k
            return st_jittered(base, k)
        end

        local function st_HitTarget(targetModel, tool, hitId, impactCF)
            local evs = RS:FindFirstChild("RemoteEvents")
            local dmg = evs and evs:FindFirstChild("ToolDamageObject")
            if not dmg then return end
            dmg:InvokeServer(targetModel, tool, hitId, impactCF)
        end

        local function st_collectSmallTreesInRadius(origin, radius)
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
            for _, part in ipairs(parts) do
                if part and part:IsA("BasePart") then
                    local tree = st_findTreeModelFromPart(part)
                    if tree and tree.Parent and st_isSmallTreeModel(tree) and not seen[tree] then
                        seen[tree] = true
                        out[#out + 1] = tree
                    end
                end
            end

            table.sort(out, function(a, b)
                local pa, pb = st_bestTreeHitPart(a), st_bestTreeHitPart(b)
                local da = pa and (pa.Position - origin).Magnitude or math.huge
                local db = pb and (pb.Position - origin).Magnitude or math.huge
                if da == db then return (a.Name or "") < (b.Name or "") end
                return da < db
            end)

            return out
        end

        local function st_pickToolName()
            if st_findItem("Admin Axe") then return "Admin Axe" end
            if st_findItem("Strong Axe") then return "Strong Axe" end
            for _, n in ipairs(TUNE.ChopPrefer) do
                if n ~= "Admin Axe" and n ~= "Strong Axe" then
                    if st_findItem(n) then return n end
                end
            end
            return nil
        end

        local function st_chopWaveTrees(targetModels, swingDelay)
            swingDelay = tonumber(swingDelay) or 0.5

            local toolName = st_pickToolName()
            if not toolName then
                task.wait(0.35)
                return
            end

            local tool = st_ensureEquipped(toolName)
            if not tool then
                task.wait(0.35)
                return
            end

            local now = os.clock()
            local anySent = false
            local soonest = math.huge

            for _, mdl in ipairs(targetModels) do
                if mdl and mdl.Parent then
                    local last = TreeLastHitAt[mdl] or 0
                    local elapsed = now - last
                    if elapsed >= swingDelay then
                        TreeLastHitAt[mdl] = now
                        anySent = true

                        task.spawn(function()
                            if not SmallTreeAura.running then return end
                            if not (mdl and mdl.Parent) then return end
                            local hitPart = st_bestTreeHitPart(mdl)
                            if not hitPart then return end
                            local impactCF = st_impactCFForTree(mdl, hitPart)
                            local hitId = st_nextPerTreeHitId(mdl)
                            pcall(function()
                                local bucket = st_attrBucket(mdl)
                                if bucket then bucket:SetAttribute(hitId, true) end
                            end)
                            if not SmallTreeAura.running then return end
                            st_HitTarget(mdl, tool, hitId, impactCF)
                        end)
                    else
                        local remain = swingDelay - elapsed
                        if remain > 0 and remain < soonest then
                            soonest = remain
                        end
                    end
                end
            end

            if anySent then
                task.wait()
            else
                if soonest < math.huge then
                    task.wait(math.max(0.02, soonest))
                else
                    task.wait(0.15)
                end
            end
        end

        function SmallTreeAura.Start()
            if SmallTreeAura.running then return end
            SmallTreeAura.running = true
            task.spawn(function()
                while SmallTreeAura.running do
                    local ch = lp.Character or lp.CharacterAdded:Wait()
                    local hrp = ch:FindFirstChild("HumanoidRootPart")
                    if not hrp then
                        task.wait(0.2)
                    else
                        local origin = (st_getRayOriginFromChar(ch) or hrp.Position)
                        local radius = tonumber(C.State.AuraRadius) or 75
                        local allTrees = st_collectSmallTreesInRadius(origin, radius)
                        local total = #allTrees
                        if total > 0 then
                            local batchSize = math.min(TUNE.MAX_TARGETS_PER_WAVE, total)
                            if SmallTreeAura._cursor > total then SmallTreeAura._cursor = 1 end
                            local batch = table.create(batchSize)
                            for i = 1, batchSize do
                                local idx = ((SmallTreeAura._cursor + i - 2) % total) + 1
                                batch[i] = allTrees[idx]
                            end
                            SmallTreeAura._cursor = SmallTreeAura._cursor + batchSize
                            st_chopWaveTrees(batch, TUNE.CHOP_SWING_DELAY)
                        else
                            task.wait(0.2)
                        end
                    end
                end
            end)
        end

        function SmallTreeAura.Stop()
            SmallTreeAura.running = false
        end
    end

    --------------------------------------------------------------------
    -- BIG TREE AURA (SELF-CONTAINED)
    --------------------------------------------------------------------

    local BigTreeAura = {}
    BigTreeAura.running = false
    BigTreeAura._cursor = 1

    do
        local BIG_TREE_NAMES = {
            TreeBig1 = true,
            TreeBig2 = true,
            TreeBig3 = true,
        }

        local TreeImpactCF = setmetatable({}, { __mode = "k" })
        local TreeHitSeed  = setmetatable({}, { __mode = "k" })
        local TreeLastHitAt = setmetatable({}, { __mode = "k" })

        local function bt_isBigTreeName(n)
            if BIG_TREE_NAMES[n] then return true end
            if type(n) ~= "string" then return false end
            return (n:match("^WebbedTreeBig%d*$") ~= nil)
                or (n:match("^FairyTreeBig%d+$") ~= nil)
                or (n:match("^Corrupted%s+TreeBig%d+$") ~= nil)
        end

        local function bt_findItem(name)
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
            local sg = lp:FindFirstChild("StarterGear")
            if sg then
                local it = sg:FindFirstChild(name)
                if it then return it end
            end
            local ch = lp.Character
            if ch then
                local it = ch:FindFirstChild(name)
                if it then return it end
            end
            return nil
        end

        local function bt_hasStrongAxe()
            return bt_findItem("Strong Axe") ~= nil
        end

        local function bt_hasChainsaw()
            return bt_findItem("Chainsaw") ~= nil
        end

        local function bt_hasBigTreeTool()
            if bt_findItem("Admin Axe") then return "Admin Axe" end
            if bt_hasStrongAxe() then return "Strong Axe" end
            if bt_hasChainsaw() then return "Chainsaw" end
            return nil
        end

        function BigTreeAura.HasTool()
            return bt_hasBigTreeTool()
        end

        local function bt_equippedToolName()
            local ch = lp and lp.Character
            if not ch then return nil end
            local t = ch:FindFirstChildOfClass("Tool")
            return t and t.Name or nil
        end

        local function bt_SafeEquip(tool)
            if not tool then return end
            local ev = RS:FindFirstChild("RemoteEvents")
            ev = ev and ev:FindFirstChild("EquipItemHandle")
            if ev then ev:FireServer("FireAllClients", tool) end
        end

        local function bt_ensureEquipped(wantedName)
            if not wantedName then return nil end
            if bt_equippedToolName() == wantedName then
                return bt_findItem(wantedName)
            end
            local tool = bt_findItem(wantedName)
            if tool then
                bt_SafeEquip(tool)
                local timeout = tonumber(TUNE.EQUIP_VERIFY_TIMEOUT_SEC) or 0.08
                local step = tonumber(TUNE.EQUIP_VERIFY_STEP_SEC) or 0.02
                local t0 = os.clock()
                while os.clock() - t0 < timeout do
                    if bt_equippedToolName() == wantedName then break end
                    task.wait(step)
                end
            end
            return tool
        end

        local function bt_getRayOriginFromChar(ch)
            if not ch then return nil end
            local head = ch:FindFirstChild("Head")
            if head and head:IsA("BasePart") then return head.Position end
            local r = ch:FindFirstChild("HumanoidRootPart")
            if r and r:IsA("BasePart") then return r.Position + Vector3.new(0, 2.5, 0) end
            return nil
        end

        local function bt_bestTreeHitPart(tree)
            if not tree or not tree:IsA("Model") then return nil end
            local hr = tree:FindFirstChild("HitRegisters")
            if hr then
                local t = hr:FindFirstChild("Trunk")
                if t and t:IsA("BasePart") then return t end
                local any = hr:FindFirstChildWhichIsA("BasePart")
                if any then return any end
            end
            local t2 = tree:FindFirstChild("Trunk")
            if t2 and t2:IsA("BasePart") then return t2 end
            return tree.PrimaryPart or tree:FindFirstChildWhichIsA("BasePart")
        end

        local function bt_findTreeModelFromPart(part)
            local current = part and part.Parent
            while current do
                if current:IsA("Model") then
                    if bt_isBigTreeName(current.Name) then
                        return current
                    end
                end
                current = current.Parent
            end
            return nil
        end

        local function bt_attrBucket(treeModel)
            local hr = treeModel and treeModel:FindFirstChild("HitRegisters")
            return (hr and hr:IsA("Instance")) and hr or treeModel
        end

        local function bt_parseHitAttrKey(k)
            local n = string.match(k or "", "^(%d+)_" .. TUNE.UID_SUFFIX .. "$")
            return n and tonumber(n) or nil
        end

        local function bt_nextPerTreeHitId(treeModel)
            local bucket = bt_attrBucket(treeModel)
            local maxN = 0
            local attrs = bucket and bucket:GetAttributes() or nil
            if attrs then
                for k, _ in pairs(attrs) do
                    local n = bt_parseHitAttrKey(k)
                    if n and n > maxN then maxN = n end
                end
            end
            local nextN = maxN + 1
            return tostring(nextN) .. "_" .. TUNE.UID_SUFFIX
        end

        local function bt_computeImpactCFrame(hitPart)
            if not (hitPart and hitPart:IsA("BasePart")) then
                return CFrame.new()
            end
            local rot = hitPart.CFrame - hitPart.CFrame.Position
            return CFrame.new(hitPart.Position + Vector3.new(0, 0.02, 0)) * rot
        end

        local function bt_jittered(cf, k)
            local r = 0.05 + 0.015 * (k % 5)
            local ang = k * 2.3999632297
            local off = Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
            local rot = cf - cf.Position
            return CFrame.new(cf.Position + off) * rot
        end

        local function bt_impactCFForTree(treeModel, hitPart)
            local base = TreeImpactCF[treeModel]
            if not base then
                base = bt_computeImpactCFrame(hitPart)
                TreeImpactCF[treeModel] = base
            end
            local k = (TreeHitSeed[treeModel] or 0) + 1
            TreeHitSeed[treeModel] = k
            return bt_jittered(base, k)
        end

        local function bt_HitTarget(targetModel, tool, hitId, impactCF)
            local evs = RS:FindFirstChild("RemoteEvents")
            local dmg = evs and evs:FindFirstChild("ToolDamageObject")
            if not dmg then return end
            dmg:InvokeServer(targetModel, tool, hitId, impactCF)
        end

        local function bt_getBigTreesInRadius(origin, radius)
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
            for _, part in ipairs(parts) do
                if part and part:IsA("BasePart") then
                    local tree = bt_findTreeModelFromPart(part)
                    if tree and tree.Parent and bt_isBigTreeName(tree.Name) and not seen[tree] then
                        seen[tree] = true
                        out[#out + 1] = tree
                    end
                end
            end

            table.sort(out, function(a, b)
                local pa, pb = bt_bestTreeHitPart(a), bt_bestTreeHitPart(b)
                local da = pa and (pa.Position - origin).Magnitude or math.huge
                local db = pb and (pb.Position - origin).Magnitude or math.huge
                if da == db then return (a.Name or "") < (b.Name or "") end
                return da < db
            end)

            return out
        end

        local function bt_chopWaveTrees(targetModels, swingDelay)
            swingDelay = tonumber(swingDelay) or 0.5

            local toolName = bt_hasBigTreeTool()
            if not toolName then
                task.wait(0.5)
                return
            end

            local tool = bt_ensureEquipped(toolName)
            if not tool then
                task.wait(0.35)
                return
            end

            local now = os.clock()
            local anySent = false
            local soonest = math.huge

            for _, mdl in ipairs(targetModels) do
                if mdl and mdl.Parent then
                    local last = TreeLastHitAt[mdl] or 0
                    local elapsed = now - last
                    if elapsed >= swingDelay then
                        TreeLastHitAt[mdl] = now
                        anySent = true

                        task.spawn(function()
                            if not BigTreeAura.running then return end
                            if not (mdl and mdl.Parent) then return end
                            local hitPart = bt_bestTreeHitPart(mdl)
                            if not hitPart then return end
                            local impactCF = bt_impactCFForTree(mdl, hitPart)
                            local hitId = bt_nextPerTreeHitId(mdl)
                            pcall(function()
                                local bucket = bt_attrBucket(mdl)
                                if bucket then bucket:SetAttribute(hitId, true) end
                            end)
                            if not BigTreeAura.running then return end
                            bt_HitTarget(mdl, tool, hitId, impactCF)
                        end)
                    else
                        local remain = swingDelay - elapsed
                        if remain > 0 and remain < soonest then
                            soonest = remain
                        end
                    end
                end
            end

            if anySent then
                task.wait()
            else
                if soonest < math.huge then
                    task.wait(math.max(0.02, soonest))
                else
                    task.wait(0.15)
                end
            end
        end

        function BigTreeAura.Start()
            if BigTreeAura.running then return end
            BigTreeAura.running = true
            task.spawn(function()
                while BigTreeAura.running do
                    local ch = lp.Character or lp.CharacterAdded:Wait()
                    local hrp = ch:FindFirstChild("HumanoidRootPart")
                    if not hrp then
                        task.wait(0.2)
                    else
                        local origin = (bt_getRayOriginFromChar(ch) or hrp.Position)
                        local radius = tonumber(C.State.AuraRadius) or 75
                        local allTrees = bt_getBigTreesInRadius(origin, radius)
                        local total = #allTrees
                        if total > 0 then
                            local batchSize = math.min(TUNE.MAX_TARGETS_PER_WAVE, total)
                            if BigTreeAura._cursor > total then BigTreeAura._cursor = 1 end
                            local batch = table.create(batchSize)
                            for i = 1, batchSize do
                                local idx = ((BigTreeAura._cursor + i - 2) % total) + 1
                                batch[i] = allTrees[idx]
                            end
                            BigTreeAura._cursor = BigTreeAura._cursor + batchSize
                            bt_chopWaveTrees(batch, TUNE.CHOP_SWING_DELAY)
                        else
                            task.wait(0.35)
                        end
                    end
                end
            end)
        end

        function BigTreeAura.Stop()
            BigTreeAura.running = false
        end
    end

    --------------------------------------------------------------------
    -- TRAP AURA + MANUAL CONTROLS (SELF-CONTAINED)
    --------------------------------------------------------------------

    local TrapAura = {}
    TrapAura.running = false

    do
        local TRAP_REMOTES = { StartDrag = nil, StopDrag = nil, SetTrap = nil }
        local trapCache, trapCacheAt = nil, 0
        local trapCooldownSec = 2.0
        local charCooldownSec = 2.0
        local lastTrapUse = {}
        local lastCharSnap = {}

        local function ta_trapsRoot()
            return WS:FindFirstChild("Structures") or WS:FindFirstChild("structures") or WS
        end

        local function ta_resolveTrapRemotes()
            local re = RS:FindFirstChild("RemoteEvents")
            if not re then return end
            if not TRAP_REMOTES.StartDrag then
                TRAP_REMOTES.StartDrag = re:FindFirstChild("RequestStartDraggingItem") or re:FindFirstChild("StartDraggingItem")
            end
            if not TRAP_REMOTES.StopDrag then
                TRAP_REMOTES.StopDrag = re:FindFirstChild("RequestStopDraggingItem") or re:FindFirstChild("StopDraggingItem")
            end
            if not TRAP_REMOTES.SetTrap then
                TRAP_REMOTES.SetTrap = re:FindFirstChild("RequestSetTrap") or re:FindFirstChild("SetTrap")
            end
        end

        local function ta_getTrapPart(trap)
            if trap:IsA("Model") then
                return trap.PrimaryPart or trap:FindFirstChildWhichIsA("BasePart")
            elseif trap:IsA("BasePart") then
                return trap
            end
            return nil
        end

        local function ta_getAllBearTraps()
            local now = os.clock()
            if trapCache and (now - trapCacheAt) < 2.0 then
                return trapCache
            end
            trapCacheAt = now
            trapCache = {}

            local root = ta_trapsRoot()
            if not root then return trapCache end

            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("Model") and d.Name == "Bear Trap" then
                    trapCache[#trapCache + 1] = d
                end
            end
            return trapCache
        end

        local function ta_moveTrapToCF(trap, cf, setNow)
            if not trap or not trap.Parent or not cf then return end
            ta_resolveTrapRemotes()

            task.spawn(function()
                if TRAP_REMOTES.StartDrag then pcall(function() TRAP_REMOTES.StartDrag:FireServer(trap) end) end
                task.wait(0.03)
                pcall(function()
                    if trap:IsA("Model") then
                        trap:PivotTo(cf)
                    else
                        local bp = trap:FindFirstChildWhichIsA("BasePart")
                        if bp then bp.CFrame = cf end
                    end
                end)
                if TRAP_REMOTES.StopDrag then pcall(function() TRAP_REMOTES.StopDrag:FireServer(trap) end) end
                if setNow and TRAP_REMOTES.SetTrap then pcall(function() TRAP_REMOTES.SetTrap:FireServer(trap) end) end
            end)
        end

        local function ta_modelOf(inst)
            if not inst then return nil end
            if inst:IsA("Model") then return inst end
            return inst:FindFirstAncestorOfClass("Model")
        end

        local function ta_isCharacterModel(m)
            return m and m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") ~= nil
        end

        local function ta_charDistancePart(m)
            if not (m and m:IsA("Model")) then return nil end
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if hrp and hrp:IsA("BasePart") then return hrp end
            local pp = m.PrimaryPart
            if pp and pp:IsA("BasePart") then return pp end
            return nil
        end

        local function ta_getRayOriginFromChar(ch)
            if not ch then return nil end
            local head = ch:FindFirstChild("Head")
            if head and head:IsA("BasePart") then return head.Position end
            local r = ch:FindFirstChild("HumanoidRootPart")
            if r and r:IsA("BasePart") then return r.Position + Vector3.new(0, 2.5, 0) end
            return nil
        end

        local function ta_collectCharactersInRadius(charsFolder, origin, radius)
            local out = {}
            if not charsFolder or not origin or not radius or radius <= 0 then return out end

            local params = OverlapParams.new()
            params.FilterType = Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances = { charsFolder }

            local parts = WS:GetPartBoundsInRadius(origin, radius, params)
            if not parts then return out end

            local seen = {}
            for _, part in ipairs(parts) do
                if part and part:IsA("BasePart") then
                    local mdl = ta_modelOf(part)
                    if mdl and ta_isCharacterModel(mdl) and not seen[mdl] then
                        repeat
                            local n = mdl.Name or ""
                            local nameLower = n:lower()
                            if string.find(nameLower, "horse", 1, true) then break end
                            if n == "Deer" or n == "Ram" or n == "Owl" or n == "Pelt Trader" or n == "Furniture Trader" or n == "Horse" then break end
                            seen[mdl] = true
                            out[#out + 1] = mdl
                        until true
                    end
                end
            end

            table.sort(out, function(a, b)
                local pa, pb = ta_charDistancePart(a), ta_charDistancePart(b)
                local da = pa and (pa.Position - origin).Magnitude or math.huge
                local db = pb and (pb.Position - origin).Magnitude or math.huge
                if da == db then return (a.Name or "") < (b.Name or "") end
                return da < db
            end)

            return out
        end

        local function ta_moveTrapUnderCharacter(trap, mdl)
            if not trap or not mdl or not mdl.Parent then return end
            local root = ta_charDistancePart(mdl)
            if not root then return end

            local now = os.clock()
            local lt = lastTrapUse[trap] or 0
            if now - lt < trapCooldownSec then return end
            local lc = lastCharSnap[mdl] or 0
            if now - lc < charCooldownSec then return end

            lastTrapUse[trap] = now
            lastCharSnap[mdl] = now

            local targetCF = root.CFrame * CFrame.new(0, -3, 0)
            ta_moveTrapToCF(trap, targetCF, true)
        end

        local function ta_lockTrapsAroundPlayer(traps, hrp)
            if not hrp then return end
            local n = #traps
            if n == 0 then return end
            local center = hrp.Position
            local radius = 6
            local height = 2
            for i, trap in ipairs(traps) do
                if trap and trap.Parent then
                    local t = (i - 1) / n * math.pi * 2
                    local offset = Vector3.new(math.cos(t) * radius, height, math.sin(t) * radius)
                    local pos = center + offset
                    local cf = CFrame.new(pos, center)
                    ta_moveTrapToCF(trap, cf, false)
                end
            end
        end

        local trapPanelGui
        local selectedTrap
        local trapLabel

        local function ta_destroyTrapPanel()
            if trapPanelGui then
                trapPanelGui:Destroy()
                trapPanelGui = nil
                trapLabel = nil
                selectedTrap = nil
            end
        end

        local function ta_updateTrapLabel()
            if not trapLabel then return end
            if selectedTrap and selectedTrap.Parent then
                local txt = "Selected trap: Bear Trap"
                local tp = ta_getTrapPart(selectedTrap)
                local ch = lp.Character
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if tp and hrp then
                    local d = (tp.Position - hrp.Position).Magnitude
                    txt = string.format("Selected trap: Bear Trap (%.0f studs)", d)
                end
                trapLabel.Text = txt
            else
                trapLabel.Text = "Selected trap: <none>"
            end
        end

        local function ta_selectNearestTrap()
            local traps = ta_getAllBearTraps()
            local ch = lp.Character or lp.CharacterAdded:Wait()
            local hrp = ch:FindFirstChild("HumanoidRootPart")
            if not hrp or #traps == 0 then
                selectedTrap = nil
                ta_updateTrapLabel()
                return
            end
            local best, bestDist
            for _, t in ipairs(traps) do
                local tp = ta_getTrapPart(t)
                if tp then
                    local d = (tp.Position - hrp.Position).Magnitude
                    if not bestDist or d < bestDist then
                        bestDist = d
                        best = t
                    end
                end
            end
            selectedTrap = best
            ta_updateTrapLabel()
        end

        local function ta_bringTrapToPlayer()
            if not (selectedTrap and selectedTrap.Parent) then ta_selectNearestTrap() end
            if not (selectedTrap and selectedTrap.Parent) then return end
            local ch = lp.Character or lp.CharacterAdded:Wait()
            local hrp = ch:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local cf = hrp.CFrame * CFrame.new(0, -2, -3)
            ta_moveTrapToCF(selectedTrap, cf, false)
            ta_updateTrapLabel()
        end

        local function ta_sendTrapToNearestCharacter()
            if not (selectedTrap and selectedTrap.Parent) then ta_selectNearestTrap() end
            if not (selectedTrap and selectedTrap.Parent) then return end

            local ch = lp.Character or lp.CharacterAdded:Wait()
            local hrp = ch:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            local origin = ta_getRayOriginFromChar(ch) or hrp.Position
            local charsFolder = WS:FindFirstChild("Characters")
            if not charsFolder then return end

            local targets = ta_collectCharactersInRadius(charsFolder, origin, TRAP_MAX_RADIUS)
            if #targets == 0 then return end

            ta_moveTrapUnderCharacter(selectedTrap, targets[1])
            ta_updateTrapLabel()
        end

        local function ta_setTrapNow()
            if not (selectedTrap and selectedTrap.Parent) then ta_selectNearestTrap() end
            if not (selectedTrap and selectedTrap.Parent) then return end
            ta_resolveTrapRemotes()
            if TRAP_REMOTES.SetTrap then
                pcall(function() TRAP_REMOTES.SetTrap:FireServer(selectedTrap) end)
            end
        end

        local function ta_createTrapPanel()
            ta_destroyTrapPanel()

            local player = lp or Players.LocalPlayer
            if not player then return end
            local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
            if not playerGui then return end

            trapPanelGui = Instance.new("ScreenGui")
            trapPanelGui.Name = "TrapManualControls"
            trapPanelGui.ResetOnSpawn = false
            trapPanelGui.Parent = playerGui

            local frame = Instance.new("Frame")
            frame.Name = "TrapPanel"
            frame.Parent = trapPanelGui
            frame.Size = UDim2.new(0, 220, 0, 150)
            frame.Position = UDim2.new(1, -230, 1, -170)
            frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            frame.BackgroundTransparency = 0.25
            frame.BorderSizePixel = 0
            frame.Active = true
            frame.Draggable = true

            trapLabel = Instance.new("TextLabel")
            trapLabel.Name = "TrapLabel"
            trapLabel.Parent = frame
            trapLabel.Size = UDim2.new(1, -8, 0, 24)
            trapLabel.Position = UDim2.new(0, 4, 0, 4)
            trapLabel.BackgroundTransparency = 1
            trapLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            trapLabel.TextSize = 14
            trapLabel.Font = Enum.Font.SourceSansBold
            trapLabel.TextXAlignment = Enum.TextXAlignment.Left
            trapLabel.Text = "Selected trap: <none>"

            local function makeButton(yOffset, text, callback)
                local btn = Instance.new("TextButton")
                btn.Parent = frame
                btn.Size = UDim2.new(1, -8, 0, 26)
                btn.Position = UDim2.new(0, 4, 0, yOffset)
                btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
                btn.TextColor3 = Color3.fromRGB(255, 255, 255)
                btn.TextSize = 13
                btn.Font = Enum.Font.SourceSansBold
                btn.Text = text
                btn.AutoButtonColor = true
                btn.MouseButton1Click:Connect(function() callback() end)
                return btn
            end

            local baseY = 32
            makeButton(baseY,      "Select nearest trap", ta_selectNearestTrap)
            makeButton(baseY + 30, "Bring trap to me",    ta_bringTrapToPlayer)
            makeButton(baseY + 60, "Send to nearest",     ta_sendTrapToNearestCharacter)
            makeButton(baseY + 90, "Set trap now",        ta_setTrapNow)

            ta_updateTrapLabel()
        end

        function TrapAura.Start()
            if TrapAura.running then return end
            TrapAura.running = true
            task.spawn(function()
                ta_resolveTrapRemotes()
                while TrapAura.running do
                    local ch = lp.Character or lp.CharacterAdded:Wait()
                    local hrp = ch:FindFirstChild("HumanoidRootPart")
                    if not hrp then
                        task.wait(0.25)
                    else
                        local traps = ta_getAllBearTraps()
                        if #traps == 0 then
                            task.wait(1.5)
                        else
                            local origin = ta_getRayOriginFromChar(ch) or hrp.Position
                            local configured = tonumber(C.State.AuraRadius) or 75
                            local radius = math.min(configured, TRAP_MAX_RADIUS)

                            local charsFolder = WS:FindFirstChild("Characters")
                            local targets = ta_collectCharactersInRadius(charsFolder, origin, radius)
                            if #targets > 0 then
                                local idx = 1
                                for _, trap in ipairs(traps) do
                                    if idx > #targets then break end
                                    local mdl = targets[idx]
                                    idx = idx + 1
                                    ta_moveTrapUnderCharacter(trap, mdl)
                                end
                                task.wait(0.25)
                            else
                                ta_lockTrapsAroundPlayer(traps, hrp)
                                task.wait(0.4)
                            end
                        end
                    end
                end
            end)
        end

        function TrapAura.Stop()
            TrapAura.running = false
        end

        function TrapAura.CreatePanel()
            ta_createTrapPanel()
        end

        function TrapAura.DestroyPanel()
            ta_destroyTrapPanel()
        end
    end

    --------------------------------------------------------------------
    -- UI WIRING
    --------------------------------------------------------------------

    CombatTab:Toggle({
        Title = "Kill Aura",
        Value = C.State.Toggles.CharacterAura or false,
        Callback = function(on)
            C.State.Toggles.CharacterAura = on
            if on then CharacterAura.Start() else CharacterAura.Stop() end
        end
    })

    CombatTab:Toggle({
        Title = "Small Tree Aura",
        Value = C.State.Toggles.SmallTreeAura or false,
        Callback = function(on)
            C.State.Toggles.SmallTreeAura = on
            if on then SmallTreeAura.Start() else SmallTreeAura.Stop() end
        end
    })

    local bigToggle
    bigToggle = CombatTab:Toggle({
        Title = "Big Tree Aura",
        Value = C.State.Toggles.BigTreeAura or false,
        Callback = function(on)
            if on then
                local bt = BigTreeAura.HasTool()
                if bt then
                    C.State.Toggles.BigTreeAura = true
                    BigTreeAura.Start()
                else
                    C.State.Toggles.BigTreeAura = false
                    pcall(function() if bigToggle and bigToggle.Set then bigToggle:Set(false) end end)
                    pcall(function() if bigToggle and bigToggle.SetValue then bigToggle:SetValue(false) end end)
                end
            else
                C.State.Toggles.BigTreeAura = false
                BigTreeAura.Stop()
            end
        end
    })

    CombatTab:Slider({
        Title = "Distance",
        Value = { Min = 0, Max = 200, Default = 75 },
        Callback = function(v)
            local nv = v
            if type(v) == "table" then
                nv = v.Value or v.Current or v.CurrentValue or v.Default or v.min or v.max
            end
            nv = tonumber(nv)
            if nv then
                C.State.AuraRadius = math.clamp(nv, 0, 200)
                syncAuraVisualRadius()
            end
        end
    })

    CombatTab:Toggle({
        Title = "Trap Aura",
        Value = C.State.Toggles.TrapAura or false,
        Callback = function(on)
            C.State.Toggles.TrapAura = on
            if on then TrapAura.Start() else TrapAura.Stop() end
        end
    })

    CombatTab:Toggle({
        Title = "Trap Manual Controls",
        Value = C.State.Toggles.TrapManualControls or false,
        Callback = function(on)
            C.State.Toggles.TrapManualControls = on
            if on then TrapAura.CreatePanel() else TrapAura.DestroyPanel() end
        end
    })

    CombatTab:Toggle({
        Title = "Show Aura Circle",
        Value = C.State.Toggles.DrawAuraCircle or false,
        Callback = function(on)
            C.State.Toggles.DrawAuraCircle = on
            if on then
                auraVis:start()
            else
                auraVis:stop()
            end
        end
    })

    task.spawn(function()
        local inv = lp:WaitForChild("Inventory", 10)
        if not inv then return end
        local function check()
            if C.State.Toggles.BigTreeAura and not BigTreeAura.HasTool() then
                C.State.Toggles.BigTreeAura = false
                BigTreeAura.Stop()
                pcall(function() if bigToggle and bigToggle.Set then bigToggle:Set(false) end end)
                pcall(function() if bigToggle and bigToggle.SetValue then bigToggle:SetValue(false) end end)
            end
        end
        inv.ChildRemoved:Connect(check)
        while true do
            task.wait(2.0)
            check()
        end
    end)

    if C.State.Toggles.SmallTreeAura then SmallTreeAura.Start() end
    if C.State.Toggles.BigTreeAura then BigTreeAura.Start() end
    if C.State.Toggles.TrapAura then TrapAura.Start() end
    if C.State.Toggles.CharacterAura then CharacterAura.Start() end
    if C.State.Toggles.TrapManualControls then TrapAura.CreatePanel() end
    if C.State.Toggles.DrawAuraCircle then auraVis:start() else auraVis:cleanupLegacy() end
end
