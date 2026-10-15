--[[
Mi Español : écran plein pour KOReader.
Une seule fenêtre ; chaque action reconstruit l'écran puis demande un rafraîchissement
(rafraîchissement complet toutes les 8 actions pour effacer les traces de l'encre).
]]
local DIR = ...

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local ProgressWidget = require("ui/widget/progresswidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local Core = loadfile(DIR .. "/core.lua")(DIR)
local Brain = loadfile(DIR .. "/brain.lua")()

local WHITE = Blitbuffer.COLOR_WHITE
local BLACK = Blitbuffer.COLOR_BLACK
local LIGHT = Blitbuffer.COLOR_LIGHT_GRAY
local GRAY = Blitbuffer.COLOR_GRAY
local DARK = Blitbuffer.COLOR_DARK_GRAY

---------------------------------------------------------------- zone tactile
local TapBox = InputContainer:extend{ callback = nil }
function TapBox:init()
    local sz = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = sz.w, h = sz.h }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end
function TapBox:onTap()
    if self.callback then
        local cb = self.callback
        UIManager:nextTick(cb)
    end
    return true
end

---------------------------------------------------------------- application
local App = InputContainer:extend{
    name = "espanol",
    covers_fullscreen = true,
    stop_events_propagation = true, -- les touchers ne passent jamais à l'écran situé dessous
}

function App:init()
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.pad = Screen:scaleBySize(12)
    self.gap = Screen:scaleBySize(8)
    self.W = self.sw - 2 * self.pad
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/espanol.lua")
    self.core = Core.new(self.settings:readSetting("state"))
    self.S = self.core.S
    self.nrender = 0
    self.actions = 0
    self.pose = "wave"
    self.bubble = ""
    self.notice = nil
    self.Q, self.P, self.deck = nil, nil, nil
    self.revealed = false
    self.progLevel = nil
    self.confirmReset = false
    local t = self.core:cur()
    local st = self.core:stage(t)
    if st ~= "fini" then self.S.tab = st end
    local h = tonumber(os.date("%H"))
    if h >= 23 or h < 6 then
        self.pose = "sleep"; self.bubble = Brain.line("night", self:ctx(), self.S.mem)
    else
        self.bubble = Brain.line("hello", self:ctx(), self.S.mem)
    end
    self:render(nil, true)
end

function App:ctx(extra)
    local t = self.core:cur()
    local c = { theme = t.name, known = self.core:knownTotal(), carrots = self.S.carrots, tier = self.S.tier,
        run = self.S.mem.run, lvl = Core.LEVELS[self.core:level()].code }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
end

function App:save()
    self.settings:saveSetting("state", self.S)
    self.settings:flush()
end

function App:act(fn)
    fn()
    self.actions = self.actions + 1
    if self.actions % 3 == 0 then self:save() end
    self:render()
end

function App:onClose()
    self:save()
    UIManager:close(self, "full")
    return true
end
function App:onCloseWidget() self:save() end
function App:onSuspend() self:save() end

---------------------------------------------------------------- Kobi
local HAPPY = { "happy1", "happy2", "happy3", "happy4", "happy5", "happy6", "happy7", "happy8", "happy9", "happy10" }
function App:react(ok, ev, extra)
    local mem = self.S.mem
    if ok then
        mem.run = (mem.run or 0) + 1; mem.errs = 0
        local p
        repeat p = HAPPY[math.random(#HAPPY)] until p ~= mem.last
        mem.last = p; self.pose = p
        if mem.run > 0 and mem.run % 5 == 0 then ev = "run" end
    else
        mem.run = 0; mem.errs = (mem.errs or 0) + 1
        self.pose = (mem.errs >= 3) and "oops" or "sad"
        if mem.errs >= 3 then ev = "tired" end
    end
    self.bubble = Brain.line(ev, self:ctx(extra), mem)
end
function App:say(ev, pose, extra)
    if pose then self.pose = pose end
    self.bubble = Brain.line(ev, self:ctx(extra), self.S.mem)
end

function App:afterProgress()
    local r = self.core:advance()
    if not r then return end
    self.Q, self.P, self.deck = nil, nil, nil
    self.pose = "party"
    if r.kind == "end" then
        self:say("end")
        self.notice = { title = "Tous les niveaux sont terminés !", text = "Tu peux continuer à t'entraîner dans chaque onglet." }
    elseif r.kind == "level" then
        self:say("level", nil, { lvl = r.level.code })
        self.notice = { title = "Niveau " .. r.level.code .. " · " .. r.level.name .. " débloqué !",
            text = "Nouveau thème : " .. r.theme.name .. " (+" .. #r.theme.words .. " mots). Tu gagnes 10 étoiles." }
    else
        self:say("theme", nil, { theme = r.theme.name, n = #r.theme.words })
        self.notice = { title = "Thème « " .. r.done.name .. " » terminé !",
            text = "Nouveau thème : " .. r.theme.name .. " (+" .. #r.theme.words .. " mots). Tu gagnes 10 étoiles." }
    end
    self:save()
end

---------------------------------------------------------------- briques d'interface
function App:face(size, bold) return Font:getFace(bold and "tfont" or "cfont", size) end

function App:text(text, size, opts)
    opts = opts or {}
    return TextBoxWidget:new{
        text = text, face = self:face(size, opts.bold), width = opts.w or self.W,
        alignment = opts.align or "left", fgcolor = opts.fg or BLACK,
    }
end

-- boîte encadrée, éventuellement tactile
function App:box(o)
    local pad = o.pad or Screen:scaleBySize(10)
    local bw = o.border or Screen:scaleBySize(2)
    local w = o.w or self.W
    local cw = w - 2 * pad - 2 * bw
    local inner = o.content or TextBoxWidget:new{
        text = o.text, face = self:face(o.size or 20, o.bold), width = cw,
        alignment = o.align or "center", fgcolor = o.fg or BLACK,
    }
    local ih = inner:getSize().h
    if o.minh then ih = math.max(ih, o.minh - 2 * pad - 2 * bw) end
    local frame = FrameContainer:new{
        bordersize = bw, radius = o.radius or Screen:scaleBySize(10), padding = pad, margin = 0,
        background = o.bg or WHITE, color = o.bcolor or BLACK,
        CenterContainer:new{ dimen = Geom:new{ w = cw, h = ih }, inner },
    }
    if not o.cb then return frame end
    return TapBox:new{ frame, callback = o.cb }
end

-- bouton dont la largeur suit le texte (pour les tuiles de mots)
function App:tile(text, cb, opts)
    opts = opts or {}
    if self.compact and not opts.size then opts.size = 18 end
    local face = self:face(opts.size or 20, true)
    local probe = TextWidget:new{ text = text, face = face }
    local tw = math.min(probe:getWidth() + Screen:scaleBySize(4), self.W - Screen:scaleBySize(40))
    probe:free()
    local pad = Screen:scaleBySize(self.compact and 6 or 8)
    local bw = Screen:scaleBySize(2)
    return self:box{ text = text, w = tw + 2 * pad + 2 * bw, size = opts.size or 20, bold = true, pad = pad, border = bw,
        cb = cb, bg = opts.bg, radius = Screen:scaleBySize(8) }
end

function App:wrap(items, width)
    local rows = { align = "left" }
    local row, rw = { align = "center" }, 0
    for _, it in ipairs(items) do
        local iw = it:getSize().w
        if rw > 0 and rw + self.gap + iw > width then
            rows[#rows + 1] = HorizontalGroup:new(row)
            rows[#rows + 1] = VerticalSpan:new{ width = self.gap }
            row, rw = { align = "center" }, 0
        end
        if rw > 0 then row[#row + 1] = HorizontalSpan:new{ width = self.gap }; rw = rw + self.gap end
        row[#row + 1] = it; rw = rw + iw
    end
    if rw > 0 then rows[#rows + 1] = HorizontalGroup:new(row) end
    return VerticalGroup:new(rows)
end

-- rangée de boutons de même largeur
function App:buttons(list, opts)
    opts = opts or {}
    local n = #list
    local bw = math.floor((self.W - (n - 1) * self.gap) / n)
    local row = { align = "center" }
    for i, b in ipairs(list) do
        if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = self.gap } end
        row[#row + 1] = self:box{ text = b[1], cb = b[2], w = bw, size = opts.size or 21, bold = true,
            bg = b.primary and LIGHT or WHITE, border = b.primary and Screen:scaleBySize(3) or nil,
            minh = opts.minh or Screen:scaleBySize(56), fg = b.disabled and GRAY or BLACK }
    end
    return HorizontalGroup:new(row)
end

function App:vspace(n) return VerticalSpan:new{ width = Screen:scaleBySize(n or 10) } end

function App:progressBar(frac, w, h)
    return ProgressWidget:new{
        width = w or self.W, height = h or Screen:scaleBySize(12), percentage = math.max(0, math.min(1, frac)),
        margin_h = 0, margin_v = 0, radius = 0, bordersize = Screen:scaleBySize(1),
        fillcolor = BLACK, bgcolor = WHITE, ticks = nil, last = nil,
    }
end

---------------------------------------------------------------- écran
function App:render(mode, nodirty)
    self.compact = false
    local body = self:buildBody()
    if body.overflow then
        self.compact = true
        body = self:buildBody()
    end
    self[1] = FrameContainer:new{
        width = self.sw, height = self.sh, bordersize = 0, margin = 0, padding = self.pad,
        background = WHITE, body,
    }
    self.nrender = self.nrender + 1
    if nodirty then return end
    if not mode then mode = (self.nrender % 8 == 0) and "full" or "ui" end
    UIManager:setDirty(self, mode)
end

function App:buildBody()
    local top = { align = "left" }
    top[#top + 1] = self:header()
    top[#top + 1] = self:vspace(8)
    top[#top + 1] = self:kobiRow()
    top[#top + 1] = self:vspace(10)
    if self.S.tab ~= "progres" then
        top[#top + 1] = self:stepper()
        top[#top + 1] = self:vspace(12)
    end
    local main
    if self.notice then main = self:noticeBox()
    elseif self.S.tab == "quiz" then main = self:viewQuiz()
    elseif self.S.tab == "phrases" then main = self:viewPhrases()
    elseif self.S.tab == "cartes" then main = self:viewCards()
    else main = self:viewProgress() end
    top[#top + 1] = main
    local topw = VerticalGroup:new(top)
    local nav = self:nav()
    local fill = self.sh - 2 * self.pad - topw:getSize().h - nav:getSize().h
    local g = VerticalGroup:new{ align = "left", topw, VerticalSpan:new{ width = math.max(0, fill) }, nav }
    g.overflow = fill < 0
    return g
end

function App:header()
    local L = Core.LEVELS[self.core:level()]
    local close = self:box{ text = "Fermer", cb = function() self:onClose() end, w = Screen:scaleBySize(110), size = 18, bold = true,
        pad = Screen:scaleBySize(8) }
    local cw = close:getSize().w
    local title = self:text("Mi Español", 30, { bold = true, w = math.floor((self.W - cw) * 0.45) })
    local info = self:text("Niveau " .. L.code .. " · " .. L.name .. "\n" .. self.S.carrots .. " étoiles · " .. self.core:streakDays() .. " j de suite",
        16, { w = self.W - cw - title:getSize().w - self.gap, align = "right", fg = DARK })
    return HorizontalGroup:new{ align = "center", title, info, HorizontalSpan:new{ width = self.gap }, close }
end

function App:kobiRow()
    local kh = math.floor(self.sh * ((self.compact or self.S.tab == "progres") and 0.075 or 0.14))
    local kw = math.floor(kh * 300 / 380)
    local img = ImageWidget:new{ file = DIR .. "/images/kobi_" .. self.pose .. ".png", width = kw, height = kh, alpha = true }
    local kobi = TapBox:new{ img, callback = function()
        self:act(function()
            self.pose = HAPPY[math.random(#HAPPY)]
            self:say("tap")
        end)
    end }
    local bw = self.W - kw - self.gap
    local bubble = self:box{ text = self.bubble, w = bw, size = self.compact and 15 or 17, align = "left", radius = Screen:scaleBySize(16),
        minh = math.floor(kh * 0.6) }
    return HorizontalGroup:new{ align = "center", kobi, HorizontalSpan:new{ width = self.gap }, bubble }
end

function App:stepper()
    local t = self.core:cur()
    local st = self.core:stage(t)
    local c = self.core
    local w = math.floor((self.W - 2 * self.gap) / 3)
    local function step(key, num, label, val, done)
        local active = (st == key)
        return self:box{ text = num .. ". " .. label .. "\n" .. val, w = w, size = 17, bold = active,
            bg = done and LIGHT or WHITE, border = active and Screen:scaleBySize(4) or Screen:scaleBySize(1),
            pad = Screen:scaleBySize(6), fg = (not done and not active) and DARK or BLACK,
            cb = function() self:act(function() self.S.tab = key; self.deck = nil end) end }
    end
    local L = Core.LEVELS[t.li]
    local head = self:text(t.name .. "   ·   thème " .. t.ti .. "/" .. #L.themes .. " du niveau " .. L.code, 20, { bold = true })
    return VerticalGroup:new{ align = "left", head, self:vspace(6), HorizontalGroup:new{ align = "center",
        step("quiz", 1, "Quiz", c:quizCount(t) .. "/" .. #t.words, c:quizDone(t)), HorizontalSpan:new{ width = self.gap },
        step("phrases", 2, "Phrases", math.min(c:tp(t.id).p, Core.PGOAL) .. "/" .. Core.PGOAL, c:phrDone(t)), HorizontalSpan:new{ width = self.gap },
        step("cartes", 3, "Cartes", c:knownCount(t) .. "/" .. #t.words, c:cardDone(t)) } }
end

function App:noticeBox()
    local n = self.notice
    local content = VerticalGroup:new{ align = "center",
        self:text(n.title, 24, { bold = true, align = "center", w = self.W - Screen:scaleBySize(40) }),
        self:vspace(6),
        self:text(n.text, 19, { align = "center", w = self.W - Screen:scaleBySize(40) }),
        self:vspace(10),
        self:box{ text = "Continuer", w = Screen:scaleBySize(220), bold = true, size = 20, bg = LIGHT,
            cb = function() self:act(function() self.notice = nil end) end },
    }
    return self:box{ content = content, border = Screen:scaleBySize(4), bg = WHITE, pad = Screen:scaleBySize(14) }
end

function App:nav()
    local tabs = { { "quiz", "1. Quiz" }, { "phrases", "2. Phrases" }, { "cartes", "3. Cartes" }, { "progres", "Progrès" } }
    local list = {}
    for _, tb in ipairs(tabs) do
        local key = tb[1]
        list[#list + 1] = { tb[2], function() self:act(function() self.S.tab = key; self.deck = nil; self.confirmReset = false end) end,
            primary = (self.S.tab == key) }
    end
    return self:buttons(list, { size = 19, minh = Screen:scaleBySize(60) })
end

function App:lockedPanel(title, msg, label, tab)
    return VerticalGroup:new{ align = "left",
        self:box{ content = VerticalGroup:new{ align = "center",
            self:text("Étape verrouillée", 16, { align = "center", w = self.W - Screen:scaleBySize(40), fg = DARK }),
            self:text(title, 24, { bold = true, align = "center", w = self.W - Screen:scaleBySize(40) }),
            self:vspace(6),
            self:text(msg, 19, { align = "center", w = self.W - Screen:scaleBySize(40) }) }, pad = Screen:scaleBySize(16) },
        self:vspace(12),
        self:buttons{ { label, function() self:act(function() self.S.tab = tab end) end, primary = true } },
    }
end

---------------------------------------------------------------- 1. QUIZ
function App:viewQuiz()
    local c, t = self.core, self.core:cur()
    if c:quizDone(t) then
        return self:lockedPanel("Quiz réussi : " .. #t.words .. " mots sur " .. #t.words,
            "Passe à l'étape 2 pour construire des phrases avec ces mots.", "Passer aux phrases", "phrases")
    end
    if not self.Q or self.Q.t ~= t then self.Q = c:newQuiz(t) end
    local Q = self.Q
    local left = #t.words - c:quizCount(t)
    local g = { align = "left" }
    g[#g + 1] = self:text((Q.toFr and "Que veut dire…" or "Comment dit-on…") .. "      (reste " .. left .. ")", 18, { fg = DARK })
    g[#g + 1] = self:vspace(6)
    g[#g + 1] = self:progressBar(c:quizCount(t) / #t.words)
    g[#g + 1] = self:vspace(14)
    local shown = Q.toFr and Q.w.es or Core.frClean(Q.w.fr)
    g[#g + 1] = self:text(shown, #shown > 28 and 24 or 32, { bold = true, align = "center" })
    g[#g + 1] = self:vspace(12)
    local longest = 0
    for _, o in ipairs(Q.opts) do longest = math.max(longest, #(Q.toFr and o.fr or o.es)) end
    local osize = longest > 60 and 16 or (longest > 34 and 18 or 21)
    for i, o in ipairs(Q.opts) do
        local label = Q.toFr and o.fr or o.es
        local bg, border = WHITE, nil
        if Q.answered then
            if o == Q.w then bg = LIGHT; border = Screen:scaleBySize(4); label = "✓  " .. label
            elseif i == Q.answered then label = "✗  " .. label; border = Screen:scaleBySize(4) end
        end
        g[#g + 1] = self:box{ text = label, size = osize, minh = Screen:scaleBySize(self.compact and 40 or 50), bg = bg, border = border,
            pad = Screen:scaleBySize(self.compact and 6 or 10),
            cb = (not Q.answered) and function() self:act(function() self:answerQuiz(i) end) end or nil }
        g[#g + 1] = self:vspace(self.compact and 5 or 8)
    end
    if Q.answered then
        g[#g + 1] = self:vspace(4)
        g[#g + 1] = self:buttons{ { c:quizDone(t) and "Terminer le quiz" or "Suivant", function()
            self:act(function() self.Q = c:newQuiz(t, Q.w) end) end, primary = true } }
    end
    return VerticalGroup:new(g)
end

function App:answerQuiz(i)
    local c, Q = self.core, self.Q
    local t = Q.t
    local ok = c:answerQuiz(Q, i)
    local left = #t.words - c:quizCount(t)
    self:react(ok, ok and "quiz_ok" or "quiz_ko", { word = Q.w.es, fr = Core.frClean(Q.w.fr), left = left, s = left > 1 and "s" or "" })
    if c:quizDone(t) then self.pose = "party"; self:say("stage_quiz") end
end

---------------------------------------------------------------- 2. PHRASES
function App:viewPhrases()
    local c, t = self.core, self.core:cur()
    if not c:quizDone(t) then
        return self:lockedPanel("Termine d'abord le quiz",
            "Les phrases se débloquent quand tu as réussi les " .. #t.words .. " mots du quiz de ce thème.", "Aller au quiz", "quiz")
    end
    if c:phrDone(t) and not (self.P and self.P.practice and self.P.t == t) then
        local g = { align = "left",
            self:box{ content = VerticalGroup:new{ align = "center",
                self:text("Étape 2 terminée", 16, { align = "center", w = self.W - Screen:scaleBySize(40), fg = DARK }),
                self:text(Core.PGOAL .. " phrases réussies", 24, { bold = true, align = "center", w = self.W - Screen:scaleBySize(40) }),
                self:vspace(6),
                self:text(c:cardDone(t) and "Toutes les cartes sont aussi validées." or
                    "Dernière étape : valide les cartes de ce thème pour débloquer les 30 mots suivants.", 19,
                    { align = "center", w = self.W - Screen:scaleBySize(40) }) }, pad = Screen:scaleBySize(16) },
            self:vspace(12),
            self:buttons{ { "Passer aux cartes", function() self:act(function() self.S.tab = "cartes"; self.deck = nil end) end, primary = true } },
            self:vspace(8),
            self:buttons{ { "S'entraîner encore (sans compter)", function() self:act(function() self.P = c:newPhrase(t, true) end) end } },
        }
        return VerticalGroup:new(g)
    end
    if not self.P or self.P.t ~= t then self.P = c:newPhrase(t, false) end
    local P = self.P
    local g = { align = "left" }
    local dots = ""
    for i = 1, 5 do dots = dots .. (i <= self.S.sstreak and "●" or "○") end
    local kind = P.practice and "Entraînement libre" or (P.q.curated and "Phrase du niveau" or "Phrase d'entraînement")
    g[#g + 1] = self:text(kind .. "  ·  " .. math.min(c:tp(t.id).p, Core.PGOAL) .. "/" .. Core.PGOAL ..
        "  ·  complexité " .. self.S.tier .. "/5  " .. dots, 17, { fg = DARK })
    g[#g + 1] = self:vspace(8)
    g[#g + 1] = self:text(P.q.fr, self.compact and 19 or 22, { bold = true })
    g[#g + 1] = self:vspace(10)
    -- zone réponse
    local zoneBorder = (P.state == "play") and Screen:scaleBySize(2) or Screen:scaleBySize(5)
    local inw = self.W - 2 * Screen:scaleBySize(10) - 2 * zoneBorder
    local ansTiles = {}
    for _, id in ipairs(P.ans) do
        ansTiles[#ansTiles + 1] = self:tile(P.tiles[id].text, P.state == "play" and function()
            self:act(function() c:moveTile(P, id) end) end or nil, { bg = LIGHT })
    end
    local ansContent
    if #ansTiles == 0 then
        ansContent = self:text("Touche les mots dans l'ordre pour former la phrase.", 18, { w = inw, align = "center", fg = DARK })
    else
        ansContent = self:wrap(ansTiles, inw)
    end
    g[#g + 1] = self:box{ content = ansContent, minh = Screen:scaleBySize(self.compact and 70 or 100),
        border = zoneBorder, align = "left" }
    g[#g + 1] = self:vspace(12)
    if P.state == "play" then
        local bankTiles = {}
        for _, id in ipairs(P.bank) do
            bankTiles[#bankTiles + 1] = self:tile(P.tiles[id].text, function() self:act(function() c:moveTile(P, id) end) end)
        end
        if #bankTiles > 0 then g[#g + 1] = self:wrap(bankTiles, self.W) end
        g[#g + 1] = self:vspace(16)
        g[#g + 1] = self:buttons{
            { "Effacer", function() self:act(function() c:clearAnswer(P) end) end },
            { "Vérifier", function() if #P.ans > 0 then self:act(function() self:checkPhrase() end) end end, primary = true, disabled = #P.ans == 0 },
        }
    else
        local msg
        if P.state == "ok" then
            msg = "Correct !  " .. P.q.es
        else
            msg = "Pas tout à fait. Réponse : " .. P.q.es
            if P.added and #P.added > 0 then
                msg = msg .. "\n" .. #P.added .. " mot" .. (#P.added > 1 and "s" or "") .. " ajouté" .. (#P.added > 1 and "s" or "") .. " aux cartes à revoir."
            end
        end
        g[#g + 1] = self:text(msg, 21, { bold = P.state == "ok" })
        g[#g + 1] = self:vspace(14)
        local nextFn = function()
            self:act(function()
                local pr = P.practice
                self.P = nil
                if pr then self.P = c:newPhrase(t, true) end
            end)
        end
        if P.state == "ok" then
            g[#g + 1] = self:buttons{ { "Continuer", nextFn, primary = true } }
        else
            g[#g + 1] = self:buttons{
                { "Ma réponse était juste", function() self:act(function() c:phraseSuccess(P); self:afterPhraseOk(P) end) end },
                { "Continuer", nextFn, primary = true },
            }
        end
    end
    return VerticalGroup:new(g)
end

function App:checkPhrase()
    local P = self.P
    local ok = self.core:checkPhrase(P)
    if ok then self:afterPhraseOk(P) else self:react(false, "phr_ko", {}) end
end

function App:afterPhraseOk(P)
    local left = math.max(0, Core.PGOAL - self.core:tp(P.t.id).p)
    self:react(true, "phr_ok", { pleft = left, ps = left > 1 and "s" or "" })
    if P.tierUp then self:say("tier") end
    if P.stageDone then self.pose = "party"; self:say("stage_phr") end
    self:afterProgress()
end

---------------------------------------------------------------- 3. CARTES
function App:viewCards()
    local c, t = self.core, self.core:cur()
    local nrev = c:reviewCount()
    if self.S.cardMode == "review" and nrev == 0 then self.S.cardMode = "theme" end
    local canTheme = c:phrDone(t)
    if not canTheme and self.S.cardMode == "theme" then
        local g = { align = "left",
            self:lockedPanel("Les cartes du thème arrivent après les phrases",
                c:quizDone(t) and ("Réussis encore " .. (Core.PGOAL - c:tp(t.id).p) .. " phrase(s) pour débloquer les cartes.")
                    or "Commence par le quiz, puis les phrases.",
                c:quizDone(t) and "Aller aux phrases" or "Aller au quiz", c:quizDone(t) and "phrases" or "quiz") }
        if nrev > 0 then
            g[#g + 1] = self:vspace(8)
            g[#g + 1] = self:buttons{ { "Réviser mes " .. nrev .. " mots à revoir", function()
                self:act(function() self.S.cardMode = "review"; self.deck = nil; self.revealed = false end) end } }
        end
        return VerticalGroup:new(g)
    end
    if not self.deck or #self.deck == 0 then self.deck = c:buildDeck(t); self.revealed = false end
    local g = { align = "left" }
    local chips = {}
    if canTheme then
        chips[#chips + 1] = self:tile(t.name, function() self:act(function() self.S.cardMode = "theme"; self.deck = nil end) end,
            { size = 18, bg = self.S.cardMode == "theme" and LIGHT or WHITE })
    end
    if nrev > 0 then
        chips[#chips + 1] = self:tile("À revoir (" .. nrev .. ")", function() self:act(function() self.S.cardMode = "review"; self.deck = nil end) end,
            { size = 18, bg = self.S.cardMode == "review" and LIGHT or WHITE })
    end
    if #chips > 0 then g[#g + 1] = self:wrap(chips, self.W); g[#g + 1] = self:vspace(12) end
    if #self.deck == 0 then
        g[#g + 1] = self:box{ text = "Tout est validé ici.\nContinue avec le thème suivant.", size = 22, pad = Screen:scaleBySize(20) }
        return VerticalGroup:new(g)
    end
    local w = self.deck[1]
    local cardH = math.floor(self.sh * (self.compact and 0.18 or 0.24))
    local inner = { align = "center",
        self:text("Espagnol" .. (self.S.review[w.es] and "  ·  à revoir" or ""), 16, { align = "center", fg = DARK, w = self.W - Screen:scaleBySize(60) }),
        self:vspace(8),
        self:text(w.es, 36, { bold = true, align = "center", w = self.W - Screen:scaleBySize(60) }) }
    if self.revealed then
        inner[#inner + 1] = self:vspace(16)
        inner[#inner + 1] = self:text(w.fr, 26, { align = "center", w = self.W - Screen:scaleBySize(60) })
        inner[#inner + 1] = self:vspace(6)
        inner[#inner + 1] = self:text(Core.THEMES[w.theme].name, 15, { align = "center", fg = DARK, w = self.W - Screen:scaleBySize(60) })
    end
    g[#g + 1] = self:box{ content = VerticalGroup:new(inner), minh = cardH, border = Screen:scaleBySize(3), radius = Screen:scaleBySize(18),
        cb = function() self:act(function() self.revealed = not self.revealed end) end }
    g[#g + 1] = self:vspace(12)
    if not self.revealed then
        g[#g + 1] = self:buttons{ { "Voir la traduction", function() self:act(function() self.revealed = true end) end, primary = true } }
    else
        g[#g + 1] = self:buttons{
            { "À revoir", function() self:act(function()
                c:cardAgain(w); table.insert(self.deck, table.remove(self.deck, 1)); self.revealed = false
                self:say("card_again", "think")
            end) end },
            { "Je le sais", function() self:act(function()
                c:cardKnown(w); table.remove(self.deck, 1); self.revealed = false
                self:react(true, "card_ok", { word = w.es, known = c:knownTotal() })
                if c:complete(t) then self:afterProgress() end
            end) end, primary = true },
        }
    end
    g[#g + 1] = self:vspace(8)
    g[#g + 1] = self:text(#self.deck .. " carte" .. (#self.deck > 1 and "s" or "") .. " restante" .. (#self.deck > 1 and "s" or ""), 16, { align = "center", fg = DARK })
    return VerticalGroup:new(g)
end

---------------------------------------------------------------- PROGRÈS
function App:viewProgress()
    local c = self.core
    local S = self.S
    local cur = c:level()
    local li = self.progLevel or cur
    local L = Core.LEVELS[li]
    local g = { align = "left" }
    local pct = S.sTotal > 0 and math.floor(S.sOk / S.sTotal * 100) or 0
    local qpct = S.qTotal > 0 and math.floor(S.qOk / S.qTotal * 100) or 0
    g[#g + 1] = self:box{ content = VerticalGroup:new{ align = "left",
        self:text(c:knownTotal() .. " mots sus sur " .. c:unlockedWords() .. " débloqués (" .. Core.TOTAL .. " au total)", 19, { bold = true, w = self.W - Screen:scaleBySize(30) }),
        self:text(S.carrots .. " étoiles · " .. c:streakDays() .. " jour(s) de suite · " .. c:reviewCount() .. " mots à revoir", 16, { w = self.W - Screen:scaleBySize(30) }),
        self:text("Quiz : " .. S.qOk .. " bonnes réponses (" .. qpct .. " %) · Phrases : " .. S.sOk .. " réussies (" .. pct .. " %) · complexité " .. S.tier .. "/5", 16, { w = self.W - Screen:scaleBySize(30) }),
    }, border = Screen:scaleBySize(1), align = "left" }
    g[#g + 1] = self:vspace(10)
    -- navigation entre niveaux
    local status = li < cur and "terminé" or (li == cur and "en cours" or "verrouillé")
    g[#g + 1] = self:buttons({
        { "< Niveau", function() self:act(function() self.progLevel = math.max(1, li - 1) end) end, disabled = li == 1 },
        { "Niveau >", function() self:act(function() self.progLevel = math.min(#Core.LEVELS, li + 1) end) end, disabled = li == #Core.LEVELS },
    }, { size = 17, minh = Screen:scaleBySize(40) })
    g[#g + 1] = self:vspace(6)
    g[#g + 1] = self:text("Niveau " .. L.code .. " · " .. L.name .. "  (" .. status .. ")", 18, { bold = true })
    g[#g + 1] = self:text("Q = quiz réussi /30 · P = phrases /8 · C = cartes sues /30", 13, { fg = DARK })
    g[#g + 1] = self:vspace(6)
    local curT = c:cur()
    local colw = math.floor((self.W - self.gap) / 2)
    local cells = {}
    for _, th in ipairs(Core.THEMES) do
        if th.li == li then
            local unlocked = th.id <= S.nunlocked
            local st
            if not unlocked then st = "verrouillé"
            elseif c:complete(th) then st = "terminé"
            else st = "Q" .. c:quizCount(th) .. " P" .. math.min(c:tp(th.id).p, Core.PGOAL) .. " C" .. c:knownCount(th) end
            cells[#cells + 1] = self:text((th == curT and "> " or "") .. th.name .. " : " .. st, 15,
                { w = colw, fg = unlocked and BLACK or GRAY, bold = th == curT })
        end
    end
    for i = 1, #cells, 2 do
        g[#g + 1] = HorizontalGroup:new{ align = "top", cells[i], HorizontalSpan:new{ width = self.gap }, cells[i + 1] or HorizontalSpan:new{ width = colw } }
    end
    g[#g + 1] = self:vspace(12)
    if self.confirmReset then
        g[#g + 1] = self:text("Effacer toute ta progression ? Cette action est définitive.", 19, { bold = true })
        g[#g + 1] = self:vspace(6)
        g[#g + 1] = self:buttons{
            { "Annuler", function() self:act(function() self.confirmReset = false end) end, primary = true },
            { "Oui, effacer", function() self:act(function()
                c:reset(); self.S = c.S; self.Q, self.P, self.deck = nil, nil, nil
                self.confirmReset = false; self.progLevel = nil; self.S.tab = "progres"
                self.bubble = "On repart de zéro. ¡Vamos!"; self.pose = "wave"
            end) end },
        }
    else
        g[#g + 1] = self:buttons({ { "Remettre à zéro", function() self:act(function() self.confirmReset = true end) end } },
            { size = 17, minh = Screen:scaleBySize(44) })
    end
    return VerticalGroup:new(g)
end

return App
