local ADDON_NAME = ...

-- KewkyConsole: run Lua in game and see the result.
--   /kc                 open or close the console (or bind a key: Key Bindings > AddOns)
--   /kc <lua>           run it now; an expression shows its value ("/kc UnitLevel('player')")
--   /kc+ <text>         add text to a buffer, /kc! runs the buffer (long code in pieces), /kc clear empties it
-- In the window: paste code, Run or Ctrl+Enter. Output: print() lines, return values (tables expanded two
-- levels), errors in red. The last 200 lines are kept in KewkyConsoleDB.log.
-- Same power as /run: protected actions (targeting, casting, moving) stay blocked, and combat data the
-- game hides from addons stays hidden.

KewkyConsoleDB = KewkyConsoleDB or {}

local MAX_LOG = 200
local buffer = {}
local frame

BINDING_HEADER_KEWKYCONSOLE = "KewkyConsole"
BINDING_NAME_KEWKYCONSOLE_TOGGLE = "Open / close the console"

-- ── values to text ──

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function Show(v, depth, seen)
    if IsSecret(v) then return "<secret>" end
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t ~= "table" then return tostring(v) end
    depth, seen = depth or 0, seen or {}
    if seen[v] then return "<cycle>" end
    if depth >= 2 then return "{...}" end
    seen[v] = true
    local parts, n = {}, 0
    for k, val in pairs(v) do
        n = n + 1
        if n > 25 then parts[#parts + 1] = "..." break end
        local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. Show(k, 2, seen) .. "]")
        parts[#parts + 1] = key .. "=" .. Show(val, depth + 1, seen)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- ── output ──

local function Out(text, r, g, b)
    KewkyConsoleDB.log = KewkyConsoleDB.log or {}
    local log = KewkyConsoleDB.log
    log[#log + 1] = date("%H:%M:%S ") .. text
    while #log > MAX_LOG do table.remove(log, 1) end
    if frame then frame.out:AddMessage(text, r or 1, g or 1, b or 1) end
end

local function Pack(...) return { n = select("#", ...), ... } end

local function Run(code)
    code = (code or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if code == "" then return end
    if frame and not frame:IsShown() then frame:Show() end
    Out("> " .. (#code > 300 and code:sub(1, 300) .. " ..." or code), 0.6, 0.8, 1)
    -- an expression shows its value; otherwise run it as statements
    local chunk, err = loadstring("return " .. code, "kc")
    if not chunk then chunk, err = loadstring(code, "kc") end
    if not chunk then
        Out("syntax error: " .. tostring(err), 1, 0.3, 0.3)
        return
    end
    -- print() inside the code lands here; globals still read and write _G
    local env = setmetatable({
        print = function(...)
            local p, parts = Pack(...), {}
            for i = 1, p.n do parts[i] = type(p[i]) == "string" and p[i] or Show(p[i]) end
            Out(table.concat(parts, "  "))
        end,
    }, { __index = _G, __newindex = _G })
    setfenv(chunk, env)
    local res = Pack(pcall(chunk))
    if not res[1] then
        Out("error: " .. tostring(res[2]), 1, 0.3, 0.3)
        return
    end
    if res.n > 1 then
        local parts = {}
        for i = 2, res.n do parts[#parts + 1] = Show(res[i]) end
        Out("= " .. table.concat(parts, ", "), 0.5, 1, 0.5)
    end
end

-- ── window ──

local function Build()
    frame = CreateFrame("Frame", "KewkyConsoleFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(620, 460)
    frame:SetPoint("CENTER", 0, 60)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "KewkyConsoleFrame")
    local title = frame.TitleText or frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetText("KewkyConsole")
    if not frame.TitleText then title:SetPoint("TOP", 0, -5) end

    -- code box
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -30)
    scroll:SetPoint("TOPRIGHT", -32, -30)
    scroll:SetHeight(130)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(570)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnKeyDown", function(self, key)
        if key == "ENTER" and IsControlKeyDown() then Run(self:GetText()) end
    end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    frame.edit = edit

    local run = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    run:SetSize(110, 22)
    run:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -6)
    run:SetText("Run (Ctrl+Enter)")
    run:SetScript("OnClick", function() Run(edit:GetText()) end)
    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(80, 22)
    clear:SetPoint("LEFT", run, "RIGHT", 6, 0)
    clear:SetText("Clear code")
    clear:SetScript("OnClick", function() edit:SetText("") edit:SetFocus() end)
    local clearOut = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearOut:SetSize(90, 22)
    clearOut:SetPoint("LEFT", clear, "RIGHT", 6, 0)
    clearOut:SetText("Clear output")
    clearOut:SetScript("OnClick", function() frame.out:Clear() end)

    -- output
    local out = CreateFrame("ScrollingMessageFrame", nil, frame)
    out:SetPoint("TOPLEFT", run, "BOTTOMLEFT", 0, -8)
    out:SetPoint("BOTTOMRIGHT", -14, 12)
    out:SetFontObject(ChatFontNormal)
    out:SetJustifyH("LEFT")
    out:SetMaxLines(400)
    out:SetFading(false)
    out:SetInsertMode("BOTTOM")
    out:EnableMouseWheel(true)
    out:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    frame.out = out

    -- show the saved log tail so a /reload keeps context
    local log = KewkyConsoleDB.log or {}
    for i = math.max(1, #log - 40), #log do out:AddMessage(log[i], 0.7, 0.7, 0.7) end
    frame:Hide()
end

function KewkyConsole_Toggle()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
    if frame:IsShown() then frame.edit:SetFocus() end
end

-- ── slash commands ──

SLASH_KEWKYCONSOLE1 = "/kc"
SlashCmdList.KEWKYCONSOLE = function(msg)
    if not frame then Build() end
    msg = msg or ""
    local trimmed = msg:gsub("^%s+", "")
    if trimmed == "" then
        KewkyConsole_Toggle()
    elseif trimmed == "clear" then
        wipe(buffer)
        Out("buffer cleared", 0.6, 0.6, 0.6)
    else
        Run(trimmed)
    end
end

SLASH_KEWKYCONSOLEADD1 = "/kc+"
SlashCmdList.KEWKYCONSOLEADD = function(msg)
    buffer[#buffer + 1] = msg or ""
end

SLASH_KEWKYCONSOLERUN1 = "/kc!"
SlashCmdList.KEWKYCONSOLERUN = function()
    if not frame then Build() end
    local code = table.concat(buffer, " ")
    wipe(buffer)
    Run(code)
end
