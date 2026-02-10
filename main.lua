repeat task.wait() until game:IsLoaded()

-------------------------------------------------------
-- Load UI (WindUI wrapper)
-------------------------------------------------------
local function httpget(u) return game:HttpGet(u) end

local UI = (function()
    local ok, ret = pcall(function()
        return loadstring(httpget("https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/ui.lua"))()
    end)
    if ok and type(ret) == "table" then return ret end
    error("ui.lua failed to load")
end)()

-------------------------------------------------------
-- Environment + Config
-------------------------------------------------------
local C = _G.C or {}
C.Services = C.Services or {
    Players = game:GetService("Players"),
    RS      = game:GetService("ReplicatedStorage"),
    WS      = game:GetService("Workspace"),
    Run     = game:GetService("RunService"),
}
C.LocalPlayer = C.Services.Players.LocalPlayer

C.Config = C.Config or {
    CHOP_SWING_DELAY = 0.55,                 -- Delay between tree hits
    TREE_NAME        = "Small Tree",         -- Model name to detect
    UID_SUFFIX       = "0000000000",         -- Unique ID suffix for hit tracking
    ChopPrefer       = { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" }, -- Tool priority
}

C.State = C.State or { AuraRadius = 150, Toggles = {} }

-- expose to global env for other modules
_G.C  = C
_G.R  = _G.R or {}
_G.UI = UI

-------------------------------------------------------
-- Main tab biome detector (Volcanic vs Snow)
-------------------------------------------------------
local function findBiomeName()
    local WS = C.Services.WS or game:GetService("Workspace")
    local map = WS:FindFirstChild("Map")
    local biomes = map and map:FindFirstChild("Biomes")
    if not biomes then return "Unknown (Biomes folder missing)" end

    if biomes:FindFirstChild("Volcanic") then
        return "Volcanic"
    end
    if biomes:FindFirstChild("Snow") then
        return "Snow"
    end
    return "Unknown (neither Volcanic nor Snow found)"
end

local function setMainText(txt)
    local Tabs = (UI and UI.Tabs) or {}
    local tab = Tabs.Main
    if not tab then return end

    -- Try common WindUI APIs (best-effort, no hard dependency on exact method names).
    local ok

    -- Preferred: Paragraph/Label-style widget
    ok = pcall(function()
        if type(tab.Paragraph) == "function" then
            tab:Paragraph({ Title = "Biome", Desc = tostring(txt) })
            return
        end
        error("no Paragraph")
    end)
    if ok then return end

    ok = pcall(function()
        if type(tab.Label) == "function" then
            tab:Label("Biome: " .. tostring(txt))
            return
        end
        error("no Label")
    end)
    if ok then return end

    ok = pcall(function()
        if type(tab.Text) == "function" then
            tab:Text("Biome: " .. tostring(txt))
            return
        end
        error("no Text")
    end)
    if ok then return end

    -- Fallback: use a Section then try Paragraph/Label inside it
    pcall(function()
        if type(tab.Section) == "function" then
            tab:Section({ Title = "Biome" })
        end
    end)
    pcall(function()
        if type(tab.Paragraph) == "function" then
            tab:Paragraph({ Title = "Detected", Desc = tostring(txt) })
        elseif type(tab.Label) == "function" then
            tab:Label("Detected: " .. tostring(txt))
        end
    end)
end

task.spawn(function()
    local last
    while true do
        local now = findBiomeName()
        if now ~= last then
            last = now
            setMainText(now)
        end
        task.wait(1.0)
    end
end)

-------------------------------------------------------
-- Force GameplayPaused to always stay false
-- (exactly your original script behavior)
-------------------------------------------------------
local Players = game:GetService("Players")
local lp = Players.LocalPlayer

local function forceUnpaused()
    pcall(function()
        if lp.GameplayPaused then
            lp.GameplayPaused = false
        end
    end)
end

-- Clear it once on start
forceUnpaused()

-- React whenever Roblox / the game toggles it
pcall(function()
    lp:GetPropertyChangedSignal("GameplayPaused"):Connect(forceUnpaused)
end)

-- Extra safety: periodic watchdog
task.spawn(function()
    while true do
        forceUnpaused()
        task.wait(0.25) -- same cadence as your original
    end
end)

-------------------------------------------------------
-- 🔧 MODULE LOADER SECTION
-------------------------------------------------------
-- Each module attaches its features to the corresponding tab
-- defined in ui.lua (Tabs.Main, Tabs.Combat, Tabs.Bring, Tabs.Auto, Tabs.Visuals)

local paths = {
    Combat  = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/combat.lua",
    Bring   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/bring.lua",
    Gather  = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/gather.lua",
    Player  = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/player.lua",
    Auto    = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/auto.lua",
    Visuals = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/visuals.lua",
    TPBring = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/tpbring.lua",
    Debug   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/debug.lua",
    Troll   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/troll.lua",
    Nudge   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/nudge.lua",
    Memory   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/memory.lua",
    Farm   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/farm.lua",
    Esp   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/esp.lua",
    Extra   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/extra.lua",
    PlayerInspector   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/player_inspector.lua",
    Diamonds   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/diamonds.lua",
    More   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/more.lua"
}

for name, url in pairs(paths) do
    local ok, mod = pcall(function()
        return loadstring(game:HttpGet(url))()
    end)
    if ok and type(mod) == "function" then
        pcall(mod, _G.C, _G.R, _G.UI)
    else
        warn(("Failed to load module %s from %s"):format(name, url))
    end
end
