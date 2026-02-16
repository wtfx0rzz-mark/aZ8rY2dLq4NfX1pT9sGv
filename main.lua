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
    CHOP_SWING_DELAY = 0.55,
    TREE_NAME        = "Small Tree",
    UID_SUFFIX       = "0000000000",
    ChopPrefer       = { "Chainsaw", "Strong Axe", "Good Axe", "Old Axe" },
}

C.State = C.State or { AuraRadius = 150, Toggles = {} }
C.State._MainBiomeRendered = C.State._MainBiomeRendered or false
C.State._MainEventRendered = C.State._MainEventRendered or false

_G.C  = C
_G.R  = _G.R or {}
_G.UI = UI

-------------------------------------------------------
-- Main tab biome + event detector (Main tab text only)
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

local function findEventName()
    local WS = C.Services.WS or game:GetService("Workspace")
    local map = WS:FindFirstChild("Map")
    local landmarks = map and map:FindFirstChild("Landmarks")
    if not landmarks then return nil end

    if landmarks:FindFirstChild("HalloweenMaze") then
        return "Halloween Event"
    end
    if landmarks:FindFirstChild("FrogCave") then
        return "Frog Event"
    end
    if landmarks:FindFirstChild("AlienMothership") then
        return "Alien Event"
    end
    if landmarks:FindFirstChild("ToolWorkshopMeteorShower") then
        return "Meteor Event"
    end

    return nil
end

local function setMainText(biomeTxt, eventTxt, renderBiome, renderEvent)
    local Tabs = (UI and UI.Tabs) or {}
    local tab = Tabs.Main
    if not tab then return end

    local ok

    ok = pcall(function()
        if type(tab.Paragraph) == "function" then
            if renderBiome then
                tab:Paragraph({ Title = "Biome", Desc = tostring(biomeTxt) })
            end
            if renderEvent and eventTxt and eventTxt ~= "" then
                tab:Paragraph({ Title = "Event", Desc = tostring(eventTxt) })
            end
            return
        end
        error("no Paragraph")
    end)
    if ok then return end

    ok = pcall(function()
        if type(tab.Label) == "function" then
            if renderBiome then
                tab:Label("Biome: " .. tostring(biomeTxt))
            end
            if renderEvent and eventTxt and eventTxt ~= "" then
                tab:Label("Event: " .. tostring(eventTxt))
            end
            return
        end
        error("no Label")
    end)
    if ok then return end

    ok = pcall(function()
        if type(tab.Text) == "function" then
            if renderBiome then
                tab:Text("Biome: " .. tostring(biomeTxt))
            end
            if renderEvent and eventTxt and eventTxt ~= "" then
                tab:Text("Event: " .. tostring(eventTxt))
            end
            return
        end
        error("no Text")
    end)
    if ok then return end

    pcall(function()
        if type(tab.Section) == "function" then
            tab:Section({ Title = "World Status" })
        end
    end)
    pcall(function()
        if type(tab.Paragraph) == "function" then
            if renderBiome then
                tab:Paragraph({ Title = "Biome", Desc = tostring(biomeTxt) })
            end
            if renderEvent and eventTxt and eventTxt ~= "" then
                tab:Paragraph({ Title = "Event", Desc = tostring(eventTxt) })
            end
        elseif type(tab.Label) == "function" then
            if renderBiome then
                tab:Label("Biome: " .. tostring(biomeTxt))
            end
            if renderEvent and eventTxt and eventTxt ~= "" then
                tab:Label("Event: " .. tostring(eventTxt))
            end
        end
    end)
end

local currentBiome
local currentEvent

local function refreshUI(reason)
    local renderBiome = false
    local renderEvent = false

    if reason == "biome" then
        if not C.State._MainBiomeRendered then
            renderBiome = true
            C.State._MainBiomeRendered = true
        end
        if currentEvent and currentEvent ~= "" and not C.State._MainEventRendered then
            renderEvent = true
            C.State._MainEventRendered = true
        end
    elseif reason == "event" then
        if currentEvent and currentEvent ~= "" and not C.State._MainEventRendered then
            renderEvent = true
            C.State._MainEventRendered = true
        end
    else
        if (not C.State._MainBiomeRendered) and currentBiome then
            renderBiome = true
            C.State._MainBiomeRendered = true
        end
        if (not C.State._MainEventRendered) and currentEvent and currentEvent ~= "" then
            renderEvent = true
            C.State._MainEventRendered = true
        end
    end

    if renderBiome or renderEvent then
        setMainText(currentBiome or "Unknown", currentEvent or "", renderBiome, renderEvent)
    end
end

-- Biome: resolve once, then stop
task.spawn(function()
    local tries = 0
    local maxTries = 60
    while true do
        local b = findBiomeName()
        tries += 1

        if b == "Volcanic" or b == "Snow" then
            currentBiome = b
            refreshUI("biome")
            break
        end

        if tries >= maxTries then
            currentBiome = b
            refreshUI("biome")
            break
        end

        task.wait(0.5)
    end
end)

-- Event checks: now, +10m, +20m total (only retries while none found)
task.spawn(function()
    local waits = { 0, 600, 600 }
    for i = 1, #waits do
        if currentEvent then break end
        local d = waits[i]
        if d > 0 then task.wait(d) end

        if not currentEvent then
            local ev = findEventName()
            if ev then
                currentEvent = ev
                refreshUI("event")
                break
            end
        end
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

forceUnpaused()

pcall(function()
    lp:GetPropertyChangedSignal("GameplayPaused"):Connect(forceUnpaused)
end)

task.spawn(function()
    while true do
        forceUnpaused()
        task.wait(0.25)
    end
end)

-------------------------------------------------------
-- 🔧 MODULE LOADER SECTION
-------------------------------------------------------
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
    Memory  = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/memory.lua",
    Farm    = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/farm.lua",
    Esp     = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/esp.lua",
    Extra   = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/extra.lua",
    PlayerInspector = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/player_inspector.lua",
    Diamonds = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/diamonds.lua",
    More     = "https://raw.githubusercontent.com/wtfx0rzz-mark/aZ8rY2dLq4NfX1pT9sGv/refs/heads/main/more.lua"
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
