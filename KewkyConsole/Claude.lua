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

-- the conversation is drawn by the overlay on the PC; in game only problems are reported, in chat
local function Add(who, text)
    if who == nil then DEFAULT_CHAT_FRAME:AddMessage("|cffd97757Claude|r " .. text) end
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

-- the input bar sits where the Claude overlay (wow/claude_overlay.py BAR_X / BAR_TOP / BAR_W) draws the
-- conversation just above it, as fractions of the game window, so the two read as one chat window
local BAR_X, BAR_TOP, BAR_W = 0.015, 0.66, 0.24

local function Place()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    win:ClearAllPoints()
    win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", BAR_X * w, -BAR_TOP * h)
    win:SetWidth(BAR_W * w)
end

local function Build()
    win = CreateFrame("Frame", "KewkyClaudeFrame", UIParent, "BackdropTemplate")
    win:SetHeight(30)
    win:SetFrameStrata("MEDIUM")
    -- WoW's chat edit box look: dark chat background, tooltip-style edge
    win:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    win:SetBackdropColor(0, 0, 0, 0.55)
    win:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
    Place()
    win:RegisterEvent("UI_SCALE_CHANGED")
    win:RegisterEvent("DISPLAY_SIZE_CHANGED")
    win:SetScript("OnEvent", Place)

    local tag = win:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    tag:SetPoint("LEFT", 10, 0)
    tag:SetText("|cffff80ffTell Claude:|r")       -- as WoW shows a whisper being typed

    local input = CreateFrame("EditBox", nil, win)
    input:SetPoint("LEFT", tag, "RIGHT", 4, 0)
    input:SetPoint("RIGHT", -8, 0)
    input:SetHeight(24)
    input:SetFontObject(ChatFontNormal)
    input:SetTextColor(1, 1, 1)
    input:SetAutoFocus(false)
    input:SetMaxLetters(1000)
    local hint = input:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("click here to type")
    input:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
    input:SetScript("OnEnterPressed", function(self)
        Send(self:GetText())
        self:SetText("")
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    win:EnableMouse(true)
    win:SetScript("OnMouseDown", function() input:SetFocus() end)
    win.input = input

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
