-- extra.lua

return function(C, R, UI)
    C  = C  or _G.C
    UI = UI or _G.UI
    assert(C and UI and UI.Tabs and UI.Tabs.Extra, "extra.lua: missing context or Extra tab")

    local Players = game:GetService("Players")
    local lp = C.LocalPlayer or Players.LocalPlayer
    local ExtraTab = UI.Tabs.Extra

    C.State = C.State or { Toggles = {} }
    C.State.Toggles = C.State.Toggles or {}

    if C.State.Toggles.RifleZeroReload == nil then
        C.State.Toggles.RifleZeroReload = true
    end

    local running = false
    local invChildConn
    local lpChildConn
    local attrConns = setmetatable({}, { __mode = "k" })
    local nvConns   = setmetatable({}, { __mode = "k" })

    local function disconnectSignal(conn)
        if conn then
            local ok, _ = pcall(function() conn:Disconnect() end)
        end
    end

    local function clearRifleSignals(rifle)
        local a = attrConns[rifle]
        if a then
            disconnectSignal(a)
            attrConns[rifle] = nil
        end
        local n = nvConns[rifle]
        if n then
            disconnectSignal(n)
            nvConns[rifle] = nil
        end
    end

    local function forceZero(rifle)
        if not (running and rifle and rifle.Parent) then return end
        local attr = rifle:GetAttribute("ReloadTime")
        if attr ~= nil then
            if attr ~= 0 then
                rifle:SetAttribute("ReloadTime", 0)
            end
        else
            local nv = rifle:FindFirstChild("ReloadTime")
            if nv and nv:IsA("NumberValue") and nv.Value ~= 0 then
                nv.Value = 0
            end
        end
    end

    local function setupRifle(rifle)
        if not (running and rifle and rifle:IsA("Instance")) then return end

        clearRifleSignals(rifle)
        forceZero(rifle)

        local ok, sig = pcall(function()
            return rifle:GetAttributeChangedSignal("ReloadTime")
        end)
        if ok and sig then
            attrConns[rifle] = sig:Connect(function()
                if running then
                    forceZero(rifle)
                end
            end)
        end

        local nv = rifle:FindFirstChild("ReloadTime")
        if nv and nv:IsA("NumberValue") then
            nvConns[rifle] = nv.Changed:Connect(function()
                if running and nv.Value ~= 0 then
                    nv.Value = 0
                end
            end)
        end
    end

    local function hookInventory(inv)
        if not inv then return end

        for _, child in ipairs(inv:GetChildren()) do
            if child.Name == "Rifle" then
                setupRifle(child)
            end
        end

        disconnectSignal(invChildConn)
        invChildConn = inv.ChildAdded:Connect(function(child)
            if not running then return end
            if child.Name == "Rifle" then
                setupRifle(child)
            end
        end)
    end

    local function startRifleZeroReload()
        if running then return end
        running = true

        local inv = lp:FindFirstChild("Inventory") or lp:WaitForChild("Inventory", 10)
        if inv then
            hookInventory(inv)
        end

        disconnectSignal(lpChildConn)
        lpChildConn = lp.ChildAdded:Connect(function(child)
            if not running then return end
            if child.Name == "Inventory" then
                hookInventory(child)
            end
        end)
    end

    local function stopRifleZeroReload()
        if not running then return end
        running = false

        disconnectSignal(invChildConn)
        invChildConn = nil
        disconnectSignal(lpChildConn)
        lpChildConn = nil

        for rifle, conn in pairs(attrConns) do
            disconnectSignal(conn)
            attrConns[rifle] = nil
        end
        for rifle, conn in pairs(nvConns) do
            disconnectSignal(conn)
            nvConns[rifle] = nil
        end
    end

    ExtraTab:Toggle({
        Title = "Zero Rifle Reload",
        Value = C.State.Toggles.RifleZeroReload,
        Callback = function(on)
            C.State.Toggles.RifleZeroReload = on
            if on then
                startRifleZeroReload()
            else
                stopRifleZeroReload()
            end
        end
    })

    if C.State.Toggles.RifleZeroReload then
        startRifleZeroReload()
    end
end
