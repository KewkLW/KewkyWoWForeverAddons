local ADDON_NAME = ...

-- Right-click a name in chat -> "Target". Blizzard's own Target entry needs a unit token,
-- which chat names don't have, and TargetUnit is protected, so the menu entry gets a
-- secure macro button (/targetexact) laid over it. Out of combat only.

-- menus opened from a name with no unit token (chat links, guild/community rosters)
local TAGS = {
    "MENU_UNIT_FRIEND",
    "MENU_UNIT_GUILD",
    "MENU_UNIT_COMMUNITIES_WOW_MEMBER",
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_CHAT_ROSTER",
    "MENU_UNIT_RECENT_ALLY",
}

KewkyChatTargetDB = KewkyChatTargetDB or {}

local overlay, pendingName
local hideAfterCombat = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffKewkyChatTarget|r " .. msg)
end

-- Forever names are first name + unique surname, and the surname sits in the realm slot:
-- chat gives "Name-Surname" (or a real "Name-Realm"). Returns the name for display and the
-- macro, which tries both the dash and the space form since the client's name lookup
-- isn't confirmed for either.
local function FullName(ctx)
    local name = ctx.name
    if not name or name == "" then return nil end
    name = name:gsub("[\r\n]", "")
    if not name:find("[- ]") and ctx.surname and ctx.surname ~= "" and ctx.surname ~= GetNormalizedRealmName() then
        name = name .. "-" .. ctx.surname
    end
    local first, rest = name:match("^([^- ]+)[- ](.+)$")
    local lines = { "/targetexact " .. name }
    if first then
        lines[1] = "/targetexact " .. first .. "-" .. rest
        lines[2] = "/targetexact " .. first .. " " .. rest
    end
    return name, table.concat(lines, "\n")
end

local function BaseName(name)
    return name and (name:match("^([^- ]+)") or name)
end

local function HideOverlay()
    if not overlay then return end
    if InCombatLockdown() then
        hideAfterCombat = true
        return
    end
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay:SetAttribute("macrotext", nil)
    pendingName = nil
end

local function BuildOverlay()
    overlay = CreateFrame("Button", "KewkyChatTargetButton", UIParent, "SecureActionButtonTemplate")
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetToplevel(true)
    overlay:RegisterForClicks("AnyUp", "AnyDown")
    overlay:SetAttribute("type", "macro")
    overlay:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    overlay:Hide()

    overlay:SetScript("PostClick", function(self, button, down)
        if down then return end
        local name = pendingName
        if Menu and Menu.GetManager then Menu.GetManager():CloseMenus() end
        if not name then return end
        local tname = UnitExists("target") and UnitIsPlayer("target") and UnitName("target")
        if not (tname and BaseName(tname) == BaseName(name)) then
            Print(name .. " is not in range.")
        end
    end)

    -- positioned in absolute UIParent coordinates rather than anchored to the pooled menu
    -- button, so the menu frames never pick up a protected dependent
    function overlay:Cover(region, name, macrotext)
        local left, bottom, width, height = region:GetRect()
        if not left then return end
        local scale = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
        self:SetSize(width * scale, height * scale)
        self:SetAttribute("macrotext", macrotext)
        pendingName = name
        self:Show()
    end
end

local function AddTarget(tag, rootDescription, contextData)
    if KewkyChatTargetDB.debug then
        Print(string.format("%s name=%s unit=%s", tag, tostring(contextData and contextData.name), tostring(contextData and contextData.unit)))
    end
    if InCombatLockdown() or not contextData or contextData.unit then return end
    local name, macrotext = FullName(contextData)
    if not name or BaseName(name) == UnitName("player") then return end

    rootDescription:CreateDivider()
    local btn = rootDescription:CreateButton(TARGET or "Target", function() end)
    btn:AddInitializer(function(button)
        if InCombatLockdown() then return end
        -- menu layout settles after initializers run
        C_Timer.After(0, function()
            if not InCombatLockdown() and button:IsVisible() then overlay:Cover(button, name, macrotext) end
        end)
    end)
    btn:AddResetter(HideOverlay)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        BuildOverlay()
        if not (Menu and Menu.ModifyMenu) then
            Print("Menu.ModifyMenu missing, disabled.")
            return
        end
        for _, tag in ipairs(TAGS) do
            Menu.ModifyMenu(tag, function(owner, rootDescription, contextData)
                AddTarget(tag, rootDescription, contextData)
            end)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        HideOverlay()   -- still allowed: lockdown starts after this event
    elseif event == "PLAYER_REGEN_ENABLED" and hideAfterCombat then
        hideAfterCombat = false
        HideOverlay()
    end
end)

SLASH_KEWKYCHATTARGET1 = "/kct"
SlashCmdList.KEWKYCHATTARGET = function(msg)
    if msg == "debug" then
        KewkyChatTargetDB.debug = not KewkyChatTargetDB.debug
        Print("debug " .. (KewkyChatTargetDB.debug and "on: each hooked menu prints its tag" or "off"))
    else
        Print("right-click a name in chat -> Target. /kct debug prints the menu tag.")
    end
end
