-- RUIN Core: feedback
-- WoW addons can't reach the internet, so Settings > Feedback builds a link
-- that opens a new GitHub issue with the player's text filled in; the player
-- copies it into a browser. Nothing is sent inside the game.
local ADDON, ns = ...

local FB = {}
ns.Feedback = FB

FB.REPO = "10kDevils/RUIN_Suite"         -- where feedback issues go
FB.LABEL = "feedback"
FB.CATEGORIES = { "Bug", "Idea", "Question", "Other" }
FB.MIN, FB.MAX = 5, 1000

local function clean(text)
    text = tostring(text or ""):gsub("|", "/"):gsub("\r", "")
    return ns.Trim(text):sub(1, FB.MAX)
end

local function validCat(c)
    for _, x in ipairs(FB.CATEGORIES) do if x == c then return c end end
    return "Other"
end

local function urlEncode(s)
    return (tostring(s):gsub("\n", "\r\n"):gsub("([^%w%-%._~])", function(c) return ("%%%02X"):format(c:byte()) end))
end
FB.UrlEncode = urlEncode

-- The link to a new issue with the text, the type and RUIN's version filled in.
function FB.IssueLink(cat, text)
    text = clean(text)
    cat = validCat(cat)
    local first = text:gsub("%s+", " "):sub(1, 60)
    local body = text .. ("\n\n---\nRUIN Core %s on %s"):format(ns.VERSION or "?", ns.CLIENT or "?")
    return ("https://github.com/%s/issues/new?labels=%s&title=%s&body=%s"):format(FB.REPO, urlEncode(FB.LABEL),
        urlEncode("[" .. cat .. "] " .. first), urlEncode(body))
end
