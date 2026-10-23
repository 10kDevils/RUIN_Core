-- RUIN Core: feedback
-- WoW addons can't reach the internet, so feedback travels inside the game:
-- the Feedback page sends it on the org channel to the org admin (any of the
-- admin's characters), whose RUIN keeps it in the account-wide RUIN_DB. On
-- the admin's computer, tools/feedback_to_github.py turns new feedback into
-- GitHub issues. Until the admin's RUIN confirms it got a message, the sender
-- keeps it and sends again later. Players can also copy a link that opens a
-- new GitHub issue with their text filled in.
local ADDON, ns = ...

local FB = {}
ns.Feedback = FB

FB.REPO = "10kDevils/RUIN_Suite"         -- where feedback issues go
FB.LABEL = "feedback"
FB.CATEGORIES = { "Bug", "Idea", "Question", "Other" }
FB.MIN, FB.MAX = 5, 1000
local INBOX_MAX, RESEND = 300, 300

local lastTry = -999

local function store()
    if not ns.db then return nil end
    local f = ns.db.feedback
    if type(f) ~= "table" then f = {}; ns.db.feedback = f end
    f.outbox = type(f.outbox) == "table" and f.outbox or {}
    f.inbox = type(f.inbox) == "table" and f.inbox or {}
    return f
end

local function now() return GetServerTime and GetServerTime() or time() end

local function clean(text)
    text = tostring(text or ""):gsub("|", "/"):gsub("\r", "")
    return ns.Trim(text):sub(1, FB.MAX)
end

local function validCat(c)
    for _, x in ipairs(FB.CATEGORIES) do if x == c then return c end end
    return "Other"
end

-- Keep one message in the admin's inbox (no duplicates).
local function keep(e)
    local f = store()
    if not f or type(e) ~= "table" or type(e.id) ~= "string" then return false end
    for _, x in ipairs(f.inbox) do if x.id == e.id then return true end end
    f.inbox[#f.inbox + 1] = { id = e.id, t = tonumber(e.t) or now(), cat = validCat(e.cat), text = clean(e.text),
                              by = tostring(e.by or "?"):sub(1, 48), gu = type(e.gu) == "string" and e.gu:sub(1, 48) or nil,
                              v = type(e.v) == "string" and e.v:sub(1, 12) or nil, cl = type(e.cl) == "string" and e.cl:sub(1, 12) or nil,
                              got = now() }
    while #f.inbox > INBOX_MAX do table.remove(f.inbox, 1) end
    ns:Fire("FEEDBACK_CHANGED")
    return true
end

-- Send what's waiting to the admin (on the org channel).
function FB:Flush(force)
    local f = store()
    if not f or #f.outbox == 0 then return end
    if not force and GetTime() - lastTry < RESEND then return end
    if not ns.Comms:IsJoined("ORG") then return end
    lastTry = GetTime()
    for _, e in ipairs(f.outbox) do
        ns.Comms:Send("FB", e, "ORG", nil, ns.Comms.PRIORITY.BULK)
    end
end

-- Returns true, or false and why.
function FB:Send(cat, text)
    text = clean(text)
    if #text < FB.MIN then return false, "Write a little more first." end
    local f = store()
    if not f then return false, "RUIN isn't ready yet." end
    local e = { id = (ns.playerGUID or "?"):sub(-8) .. "-" .. now() .. "-" .. math.random(100, 999), t = now(), cat = validCat(cat),
                text = text, by = ns.playerName, gu = ns.guildName, v = ns.VERSION, cl = ns.CLIENT }
    if ns.Org:IsAdmin() then
        keep(e)                                   -- the admin's own feedback goes straight in
        return true, "saved"
    end
    f.outbox[#f.outbox + 1] = e
    FB:Flush(true)
    ns:Fire("FEEDBACK_CHANGED")
    return true, ns.Comms:IsJoined("ORG") and "sent" or "queued"
end

function FB:Waiting() local f = store(); return f and #f.outbox or 0 end
function FB:Inbox() local f = store(); return f and f.inbox or {} end

function FB:NewCount()
    local n = 0
    for _, e in ipairs(FB:Inbox()) do if not e.posted then n = n + 1 end end
    return n
end

-- The admin marks feedback as copied to GitHub (or the script does).
function FB:MarkAllPosted()
    for _, e in ipairs(FB:Inbox()) do e.posted = e.posted or now() end
    ns:Fire("FEEDBACK_CHANGED")
end

function FB:ClearPosted()
    local f = store()
    if not f then return end
    local keepList = {}
    for _, e in ipairs(f.inbox) do if not e.posted then keepList[#keepList + 1] = e end end
    f.inbox = keepList
    ns:Fire("FEEDBACK_CHANGED")
end

-- New feedback as Markdown, ready to paste into GitHub issues.
function FB:MarkdownNew()
    local out = {}
    for _, e in ipairs(FB:Inbox()) do
        if not e.posted then
            out[#out + 1] = ("### [%s] from %s%s, %s\n\n%s\n\n_RUIN Core %s on %s_\n"):format(e.cat, e.by,
                e.gu and (" (" .. e.gu .. ")") or "", date("%Y-%m-%d %H:%M", e.t), e.text, e.v or "?", e.cl or "?")
        end
    end
    return table.concat(out, "\n---\n\n")
end

---------------------------------------------------------------------------
-- A link that opens a new GitHub issue with the text filled in
---------------------------------------------------------------------------
local function urlEncode(s)
    return (tostring(s):gsub("\n", "\r\n"):gsub("([^%w%-%._~])", function(c) return ("%%%02X"):format(c:byte()) end))
end
FB.UrlEncode = urlEncode

function FB.IssueLink(cat, text)
    text = clean(text)
    cat = validCat(cat)
    local first = text:gsub("%s+", " "):sub(1, 60)
    local body = text .. ("\n\n---\nRUIN Core %s on %s"):format(ns.VERSION or "?", ns.CLIENT or "?")
    return ("https://github.com/%s/issues/new?labels=%s&title=%s&body=%s"):format(FB.REPO, urlEncode(FB.LABEL),
        urlEncode("[" .. cat .. "] " .. first), urlEncode(body))
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
ns.Comms:Register("FB", function(d, sender, scope)
    if scope ~= "ORG" or not ns.Org:IsAdmin() then return end
    d.by = sender
    if keep(d) then
        ns.Comms:Send("FBACK", { id = d.id }, "ORG", nil, ns.Comms.PRIORITY.BULK)
        ns:Print(("New feedback from %s (Settings > Feedback)."):format(ns.ShortName(sender)))
    end
end)

ns.Comms:Register("FBACK", function(d, sender, scope)
    if scope ~= "ORG" or type(d.id) ~= "string" then return end
    local f = store()
    if not f then return end
    for i = #f.outbox, 1, -1 do
        if f.outbox[i].id == d.id then
            table.remove(f.outbox, i)
            ns:Print("Your feedback reached the org admin. Thank you!")
            ns:Fire("FEEDBACK_CHANGED")
        end
    end
end)

ns:Subscribe("CHANNELS_CHANGED", function()
    if ns.Comms:IsJoined("ORG") then C_Timer.After(30, function() FB:Flush(true) end) end
end)
C_Timer.NewTicker(60, function() FB:Flush(false) end)
