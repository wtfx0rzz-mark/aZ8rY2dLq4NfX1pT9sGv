if isLockedAttribute(m) then
else
    local ln = (m.Name or ""):lower()
    local skipItem = false

    if excludeCorpse and ln:find("corpse", 1, true) then
        skipItem = true
    end

    if not skipItem and skipFoodRot then
        local rot = m:GetAttribute("FoodRot")
        if rot ~= nil then
            local nm0 = tostring(m.Name or "")
            local rk = "Rotten " .. nm0
            local allow = false
            if selectedSet["Rotten"] and foodSet[nm0] then allow = true end
            if selectedSet[rk] then allow = true end
            if not allow then skipItem = true end
        end
    end

    if not skipItem and m.Name == "Stew" then
        if isModelWeldedToOutside(m) or isStewOnCrockpot(m) then
            skipItem = true
        end
    end

    if not skipItem and not isExcludedModel(m) and not isLogWallBlocked(m, selectedSet) then
        local mp = mainPart(m)
        if mp then
            perNameCount[m.Name] = (perNameCount[m.Name] or 0) + 1
            if (not limitOn) or perNameCount[m.Name] <= maxPerName then
                queue[#queue+1] = m
            end
        end
    end
end
