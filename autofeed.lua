local function isWallVariant(m)
        if not (m and m:IsA("Model")) then return false end
        local n = (m.Name or ""):lower()
        return n == "logwall" or n == "log wall" or (n:find("log", 1, true) and n:find("wall", 1, true))
    end

    local function isUnderLogWall(inst)
        local cur = inst
        while cur and cur ~= WS do
            local nm = (cur.Name or ""):lower()
            if nm == "logwall" or nm == "log wall" or (nm:find("log", 1, true) and nm:find("wall", 1, true)) then
                return true
            end
            cur = cur.Parent
        end
        return false
    end

    local function cfItemsFolder()
        return WS:FindFirstChild("Items")
    end

    local function cfIsItem(m)
        if not (m and m:IsA("Model") and CF_ALL_ITEMS[m.Name] and mainPart(m) ~= nil) then return false end
        local itemsFolder = cfItemsFolder()
        if itemsFolder then
            if not m:IsDescendantOf(itemsFolder) then return false end
            if m.Parent ~= itemsFolder then
                local parent = m.Parent
                while parent and parent ~= itemsFolder do
                    if parent:IsA("Model") then return false end
                    parent = parent.Parent
                end
            end
        end
        if m.Name == "Log" then
            if isWallVariant(m) or isUnderLogWall(m) then return false end
        end
        return true
    end

    local function cfGetItemsByPriority()
        local itemsFolder = cfItemsFolder()
        local foundByName = {}
        for _, name in ipairs(CF_PRIORITY) do
            foundByName[name] = {}
        end
        local seen = {}
        for _, d in ipairs(WS:GetDescendants()) do
            if cfIsItem(d) and cfIsWhitelisted(d) and not seen[d] and not cfActiveDrags[d] and not cfReserved[d] and cfIsNearFire(d) then
                if d.Name == "Biofuel" and cfIsInsideIgnore(d) then
                else
                    seen[d] = true
                    if foundByName[d.Name] then
                        foundByName[d.Name][#foundByName[d.Name] + 1] = d
                    end
                end
            end
        end
        if cfFireCenter then
            for _, name in ipairs(CF_PRIORITY) do
                table.sort(foundByName[name], function(a, b)
                    local ap = mainPart(a)
                    local bp = mainPart(b)
                    local ad = ap and (ap.Position - cfFireCenter).Magnitude or math.huge
                    local bd = bp and (bp.Position - cfFireCenter).Magnitude or math.huge
                    return ad < bd
                end)
            end
        end
        local out = {}
        for _, name in ipairs(CF_PRIORITY) do
            for _, item in ipairs(foundByName[name]) do
                out[#out + 1] = item
            end
        end
        return out
    end
