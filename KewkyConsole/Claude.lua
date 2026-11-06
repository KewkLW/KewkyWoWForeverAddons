local ADDON_NAME = ...

-- Claude chat: a chat window wired to Claude on Kewk's PC.
--   You -> Claude: what you type here goes out on a private, password-protected chat channel that only you
--   are in, and the game's own chat log (/chatlog, switched on here) writes it to Logs/WoWChatLog.txt, where a
--   bridge service on the PC picks it up (wow-tracker systemd/wow-claude-bridge.service).
--   Claude -> you: replies arrive as /kcr <text>, typed into the game by the bridge's wowsay tool.
-- /claude opens the window; /claude <text> sends from the normal chat box.

local CHANNEL_BASE = "KewkClaude"
local MAX_LOG = 150
local win, channelID

local function DB()
    KewkyConsoleDB.claude = KewkyConsoleDB.claude or {}
    local c = KewkyConsoleDB.claude
    if not c.channel then
        -- a name nobody stumbles into, and a password
        c.channel = CHANNEL_BASE .. math.random(1000, 9999)
        c.password = tostring(math.random(100000, 999999))
    end
    c.log = c.log or {}
    return c
end

local function IsOurs(name)
    return type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name:find(CHANNEL_BASE, 1, true) ~= nil
end

local function Log(who, text)
    local c = DB()
    c.log[#c.log + 1] = { t = time(), who = who, text = text }
    while #c.log > MAX_LOG do table.remove(c.log, 1) end
end

local function Add(who, text)
    if not win then return end
    if who == "Claude" then
        win.out:AddMessage("|cffd97757Claude:|r " .. text, 1, 1, 1)
    elseif who == "you" then
        win.out:AddMessage("|cff8fb8ffYou:|r " .. text, 0.85, 0.85, 0.85)
    else
        win.out:AddMessage(text, 0.6, 0.6, 0.6)
    end
end

-- ── channel and chat log ──

local function Join()
    local c = DB()
    local id = GetChannelName(c.channel)
    if id and id > 0 then channelID = id return end
    pcall(JoinTemporaryChannel, c.channel, c.password)
    C_Timer.After(2, function()
        local id2 = GetChannelName(c.channel)
        if id2 and id2 > 0 then channelID = id2 end
    end)
end

local function EnsureChatLog()
    if LoggingChat and not LoggingChat() then LoggingChat(true) end
end

local function Send(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    EnsureChatLog()
    if not channelID then
        Join()
        Add(nil, "not connected yet: try again in a moment")
        return
    end
    for i = 1, #text, 240 do
        local piece = text:sub(i, i + 239)
        local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        local ok, err = pcall(send, piece, "CHANNEL", nil, channelID)
        if not ok then Add(nil, "could not send: " .. tostring(err)) return end
    end
    Add("you", text)
    Log("you", text)
end

-- your channel's lines and join notices stay out of the normal chat tabs
local function HideOurs(_, _, _, _, _, channelName, _, _, _, _, baseName)
    if IsOurs(channelName) or IsOurs(baseName) then return true end
end
local function HideNotice(_, _, _, _, _, channelName, _, _, _, _, baseName)
    if IsOurs(channelName) or IsOurs(baseName) then return true end
end

-- ── window ──

local function Build()
    win = CreateFrame("Frame", "KewkyClaudeFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(460, 320)
    win:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 30, 260)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:SetResizable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    local title = win.TitleText or win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetText("Claude")
    if not win.TitleText then title:SetPoint("TOP", 0, -5) end

    local input = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    input:SetHeight(22)
    input:SetPoint("BOTTOMLEFT", 16, 10)
    input:SetPoint("BOTTOMRIGHT", -12, 10)
    input:SetAutoFocus(false)
    input:SetMaxLetters(1000)
    input:SetScript("OnEnterPressed", function(self)
        Send(self:GetText())
        self:SetText("")
        self:ClearFocus()            -- nothing keeps focus while you wait, so the reply can come in
    end)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    win.input = input

    local out = CreateFrame("ScrollingMessageFrame", nil, win)
    out:SetPoint("TOPLEFT", 12, -28)
    out:SetPoint("BOTTOMRIGHT", input, "TOPRIGHT", 0, 6)
    out:SetFontObject(ChatFontNormal)
    out:SetJustifyH("LEFT")
    out:SetMaxLines(500)
    out:SetFading(false)
    out:SetInsertMode("BOTTOM")
    out:EnableMouseWheel(true)
    out:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    win.out = out

    for _, e in ipairs(DB().log) do
        if e.who == "Claude" then
            out:AddMessage("|cffd97757Claude:|r " .. e.text, 0.8, 0.8, 0.8)
        else
            out:AddMessage("|cff8fb8ffYou:|r " .. e.text, 0.7, 0.7, 0.7)
        end
    end
    if KewkyConsoleDB.claudeShown == false then win:Hide() end
    win:SetScript("OnShow", function() KewkyConsoleDB.claudeShown = true end)
    win:SetScript("OnHide", function() KewkyConsoleDB.claudeShown = false end)
end

-- ── commands ──

SLASH_KEWKYCLAUDE1 = "/claude"
SlashCmdList.KEWKYCLAUDE = function(msg)
    if not win then Build() end
    msg = (msg or ""):gsub("^%s+", "")
    if msg == "" then
        win:SetShown(not win:IsShown())
        if win:IsShown() then win.input:SetFocus() end
    else
        win:Show()
        Send(msg)
    end
end

-- a reply from Claude, typed in by the bridge
SLASH_KEWKYCLAUDEREPLY1 = "/kcr"
SlashCmdList.KEWKYCLAUDEREPLY = function(msg)
    if not win then Build() end
    msg = (msg or ""):gsub("^%s+", "")
    if msg == "" then return end
    win:Show()
    Add("Claude", msg)
    Log("Claude", msg)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    KewkyConsoleDB = KewkyConsoleDB or {}
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL", HideOurs)
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", HideNotice)
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE_USER", HideNotice)
    end
    Build()
    EnsureChatLog()
    C_Timer.After(6, Join)                     -- channels aren't ready right at login
end)
