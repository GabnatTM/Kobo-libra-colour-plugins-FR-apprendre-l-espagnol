--[[
Mi Español : logique du jeu (sans interface)
Données, progression, quiz, phrases, cartes et petites phrases de Kobi.
Ce fichier n'utilise aucune fonction de KOReader : il peut être testé seul.
]]
local DIR = ...

local Core = {}
Core.__index = Core

local PGOAL = 8      -- phrases à réussir par thème
local STREAK_UP = 5  -- réussites d'affilée pour passer à des phrases plus complexes
Core.PGOAL = PGOAL

---------------------------------------------------------------- outils
local function pick(t) return t[math.random(#t)] end
local function shuffle(t)
    local a = {}
    for i, v in ipairs(t) do a[i] = v end
    for i = #a, 2, -1 do
        local j = math.random(i)
        a[i], a[j] = a[j], a[i]
    end
    return a
end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function startsWith(s, p) return s:sub(1, #p) == p end
local function endsWith(s, p) return p == "" or s:sub(-#p) == p end
Core.shuffle, Core.pick = shuffle, pick

local UP = { ["á"]="Á", ["é"]="É", ["í"]="Í", ["ó"]="Ó", ["ú"]="Ú", ["ñ"]="Ñ", ["à"]="À", ["è"]="È", ["ê"]="Ê", ["ç"]="Ç" }
local LOW = {}
for k, v in pairs(UP) do LOW[v] = k end

local function capFirst(s)
    if startsWith(s, "¿") then return "¿" .. capFirst(s:sub(3)) end
    if startsWith(s, "¡") then return "¡" .. capFirst(s:sub(3)) end
    local b = s:byte(1)
    if not b then return s end
    if b < 128 then return s:sub(1, 1):upper() .. s:sub(2) end
    local two = s:sub(1, 2)
    if UP[two] then return UP[two] .. s:sub(3) end
    return s
end
local function lowFirst(s)
    local b = s:byte(1)
    if not b then return s end
    if b < 128 then return s:sub(1, 1):lower() .. s:sub(2) end
    local two = s:sub(1, 2)
    if LOW[two] then return LOW[two] .. s:sub(3) end
    return s
end
Core.capFirst = capFirst

-- découpe une phrase en mots (sans ponctuation)
local function tokens(s)
    s = s:gsub("¿", " "):gsub("¡", " "):gsub("[%?%!%.,;:]", " ")
    local out = {}
    for w in s:gmatch("%S+") do out[#out + 1] = w end
    if out[1] then out[1] = lowFirst(out[1]) end
    return out
end
Core.tokens = tokens

-- « la carte (géographique) / le plan » -> « la carte »
local function frClean(fr)
    fr = fr:gsub("%s*%b()", "")
    local a = fr:find(" / ", 1, true)
    if a then fr = fr:sub(1, a - 1) end
    return trim(fr)
end
Core.frClean = frClean

local function isVowelStart(s)
    local b = s:byte(1)
    if not b then return false end
    if b == 195 then return true end -- é è ê à â î ô û…
    return ("aeiouyhAEIOUYH"):find(string.char(b), 1, true) ~= nil
end
-- je + aime -> j'aime ; ne + ai -> n'ai
local function elide(w, nxt)
    if isVowelStart(nxt) then return w:sub(1, -2) .. "'" .. nxt end
    return w .. " " .. nxt
end
-- « ai besoin de » + « le pain » -> « ai besoin du pain »
local function joinDe(phrase, np)
    if endsWith(phrase, " de") then
        local base = phrase:sub(1, -4)
        if startsWith(np, "le ") then return base .. " du " .. np:sub(4) end
        if startsWith(np, "les ") then return base .. " des " .. np:sub(5) end
        return base .. " " .. elide("de", np)
    end
    return phrase .. " " .. np
end

local function joinA(np)
    if startsWith(np, "le ") then return "au " .. np:sub(4) end
    if startsWith(np, "les ") then return "aux " .. np:sub(5) end
    return "à " .. np
end
local function deNP(np) return joinDe("x de", np):sub(3) end

---------------------------------------------------------------- données
local LEVELS = dofile(DIR .. "/data/words.lua")
local SENTS = dofile(DIR .. "/data/sentences.lua")
Core.LEVELS = LEVELS

local THEMES, WORDS = {}, {}
for li, L in ipairs(LEVELS) do
    for ti, th in ipairs(L.themes) do
        local t = { id = #THEMES + 1, li = li, ti = ti, name = th.name, kind = th.t, words = {} }
        for _, p in ipairs(th.w) do
            local w = { es = p[1], fr = p[2], theme = t.id }
            t.words[#t.words + 1] = w
            WORDS[w.es] = w
        end
        THEMES[#THEMES + 1] = t
    end
end
Core.THEMES, Core.WORDS = THEMES, WORDS
local TOTAL = 0
for _ in pairs(WORDS) do TOTAL = TOTAL + 1 end
Core.TOTAL = TOTAL

-- les 20 phrases de chaque niveau sont réparties entre ses thèmes
local CURATED = {}
for li, list in ipairs(SENTS) do
    local n = #LEVELS[li].themes
    for i, s in ipairs(list) do
        local ti = ((i - 1) % n) + 1
        local key = li .. "-" .. ti
        CURATED[key] = CURATED[key] or {}
        table.insert(CURATED[key], { es = s[1], fr = s[2], key = "c" .. i, len = #tokens(s[1]) })
    end
end

---------------------------------------------------------------- état
local function fresh()
    return {
        version = 1, known = {}, review = {}, nunlocked = 1, tp = {},
        tier = 1, sstreak = 0, sOk = 0, sTotal = 0, qOk = 0, qTotal = 0,
        carrots = 0, days = {}, tab = "quiz", cardMode = "theme",
        mem = { recent = {}, run = 0, errs = 0, last = "" },
    }
end

function Core.new(state)
    local self = setmetatable({}, Core)
    self.S = state or fresh()
    local f = fresh()
    for k, v in pairs(f) do if self.S[k] == nil then self.S[k] = v end end
    self.S.mem.recent = self.S.mem.recent or {}
    return self
end

function Core:reset() self.S = fresh() end

function Core:tp(id)
    local key = tostring(id)
    local t = self.S.tp[key]
    if not t then t = { q = {}, p = 0, c = {} }; self.S.tp[key] = t end
    return t
end

function Core:markToday()
    local d = os.date("%Y-%m-%d")
    local days = self.S.days
    if days[#days] ~= d then
        days[#days + 1] = d
        while #days > 120 do table.remove(days, 1) end
    end
end
function Core:streakDays()
    local set = {}
    for _, d in ipairs(self.S.days) do set[d] = true end
    local n, t = 0, os.time()
    while set[os.date("%Y-%m-%d", t)] do n = n + 1; t = t - 86400 end
    return n
end

function Core:quizCount(t) local n = 0; local q = self:tp(t.id).q; for _, w in ipairs(t.words) do if q[w.es] then n = n + 1 end end; return n end
function Core:knownCount(t) local n = 0; for _, w in ipairs(t.words) do if self.S.known[w.es] then n = n + 1 end end; return n end
function Core:quizDone(t) return self:quizCount(t) == #t.words end
function Core:phrDone(t) return self:tp(t.id).p >= PGOAL end
function Core:cardDone(t) return self:knownCount(t) == #t.words end
function Core:complete(t) return self:quizDone(t) and self:phrDone(t) and self:cardDone(t) end
function Core:stage(t)
    if not self:quizDone(t) then return "quiz" end
    if not self:phrDone(t) then return "phrases" end
    if not self:cardDone(t) then return "cartes" end
    return "fini"
end
function Core:cur()
    for i = 1, self.S.nunlocked do
        if not self:complete(THEMES[i]) then return THEMES[i] end
    end
    return THEMES[self.S.nunlocked]
end
function Core:level() return THEMES[self.S.nunlocked].li end
function Core:knownTotal() local n = 0; for k in pairs(self.S.known) do if WORDS[k] then n = n + 1 end end; return n end
function Core:reviewCount() local n = 0; for k in pairs(self.S.review) do if WORDS[k] then n = n + 1 end end; return n end
function Core:unlockedWords() return THEMES[self.S.nunlocked].id * 30 end

-- Thème fini (quiz + phrases + cartes) -> on débloque le suivant (+30 mots)
function Core:advance()
    local t = self:cur()
    if not self:complete(t) then return nil end
    local nx = THEMES[t.id + 1]
    if not nx then return { kind = "end" } end
    if self.S.nunlocked >= nx.id then return nil end
    self.S.nunlocked = nx.id
    self.S.tab = "quiz"; self.S.cardMode = "theme"
    self.S.carrots = self.S.carrots + 10
    if nx.li > t.li then return { kind = "level", theme = nx, level = LEVELS[nx.li] } end
    return { kind = "theme", theme = nx, done = t }
end

---------------------------------------------------------------- quiz
function Core:newQuiz(t, prev)
    local q = self:tp(t.id).q
    local pool = {}
    for _, w in ipairs(t.words) do if not q[w.es] then pool[#pool + 1] = w end end
    if #pool == 0 then return nil end
    local w = pick(pool)
    if prev and #pool > 1 then while w == prev do w = pick(pool) end end
    local others, seenfr = {}, { [frClean(w.fr)] = true }
    for _, x in ipairs(shuffle(t.words)) do
        local f = frClean(x.fr)
        if x ~= w and not seenfr[f] and #others < 3 then others[#others + 1] = x; seenfr[f] = true end
    end
    local opts = shuffle({ w, others[1], others[2], others[3] })
    return { w = w, t = t, toFr = math.random() < 0.5, opts = opts, answered = nil }
end

function Core:answerQuiz(Q, i)
    if Q.answered then return end
    Q.answered = i
    local ok = Q.opts[i] == Q.w
    self.S.qTotal = self.S.qTotal + 1
    self:markToday()
    if ok then
        self.S.qOk = self.S.qOk + 1
        self:tp(Q.t.id).q[Q.w.es] = true
        self.S.carrots = self.S.carrots + 1
    else
        self.S.review[Q.w.es] = true
    end
    Q.ok = ok
    return ok
end

---------------------------------------------------------------- générateur de phrases
local SUBJ = { {"yo","je"}, {"tú","tu"}, {"él","il"}, {"ella","elle"}, {"nosotros","nous"}, {"ellos","ils"} }
local VERBS = {
    { es={"busco","buscas","busca","busca","buscamos","buscan"}, fr={"cherche","cherches","cherche","cherche","cherchons","cherchent"} },
    { es={"compro","compras","compra","compra","compramos","compran"}, fr={"achète","achètes","achète","achète","achetons","achètent"} },
    { es={"miro","miras","mira","mira","miramos","miran"}, fr={"regarde","regardes","regarde","regarde","regardons","regardent"} },
    { es={"quiero","quieres","quiere","quiere","queremos","quieren"}, fr={"veux","veux","veut","veut","voulons","veulent"} },
    { es={"encuentro","encuentras","encuentra","encuentra","encontramos","encuentran"}, fr={"trouve","trouves","trouve","trouve","trouvons","trouvent"} },
    { es={"llevo","llevas","lleva","lleva","llevamos","llevan"}, fr={"emporte","emportes","emporte","emporte","emportons","emportent"} },
    { es={"vendo","vendes","vende","vende","vendemos","venden"}, fr={"vends","vends","vend","vend","vendons","vendent"} },
    { es={"tengo","tienes","tiene","tiene","tenemos","tienen"}, fr={"ai","as","a","a","avons","ont"} },
    { es={"necesito","necesitas","necesita","necesita","necesitamos","necesitan"}, fr={"ai besoin de","as besoin de","a besoin de","a besoin de","avons besoin de","ont besoin de"} },
    { es={"prefiero","prefieres","prefiere","prefiere","preferimos","prefieren"}, fr={"préfère","préfères","préfère","préfère","préférons","préfèrent"} },
}
local MODALS = {
    { es={"quiero","quieres","quiere","quiere","queremos","quieren"}, fr={"veux","veux","veut","veut","voulons","veulent"} },
    { es={"puedo","puedes","puede","puede","podemos","pueden"}, fr={"peux","peux","peut","peut","pouvons","peuvent"} },
    { es={"debo","debes","debe","debe","debemos","deben"}, fr={"dois","dois","doit","doit","devons","doivent"} },
    { es={"necesito","necesitas","necesita","necesita","necesitamos","necesitan"}, fr={"ai besoin de","as besoin de","a besoin de","a besoin de","avons besoin de","ont besoin de"} },
}
local OBJ = {
    {"el pan","le pain"},{"el agua","l'eau"},{"la leche","le lait"},{"el café","le café"},{"el queso","le fromage"},
    {"la manzana","la pomme"},{"el pescado","le poisson"},{"el arroz","le riz"},{"la sopa","la soupe"},{"el vino","le vin"},
    {"el pastel","le gâteau"},{"la llave","la clé"},{"el libro","le livre"},{"el vaso","le verre"},{"la taza","la tasse"},
    {"la lámpara","la lampe"},{"la silla","la chaise"},{"la camisa","la chemise"},{"los zapatos","les chaussures"},
    {"el abrigo","le manteau"},{"la chaqueta","la veste"},{"el sombrero","le chapeau"},{"las gafas","les lunettes"},
    {"el reloj","la montre"},{"la maleta","la valise"},{"el billete","le billet"},{"el pasaporte","le passeport"},
    {"el mapa","la carte"},{"el móvil","le portable"},{"el ordenador","l'ordinateur"},{"el cuaderno","le cahier"},
    {"el bolígrafo","le stylo"},{"el diccionario","le dictionnaire"},{"la bicicleta","le vélo"},{"la guitarra","la guitare"},
    {"el periódico","le journal"},{"la novela","le roman"},{"la partitura","la partition"},{"el cuchillo","le couteau"},
    {"el paraguas","le parapluie"},{"la mochila","le sac à dos"},{"la cámara","l'appareil photo"},{"el regalo","le cadeau"},
}
local TIME = { {"hoy","aujourd'hui"},{"mañana","demain"},{"ahora","maintenant"},{"el lunes","lundi"},{"el sábado","samedi"},
    {"cada día","chaque jour"},{"esta noche","ce soir"},{"a veces","parfois"},{"esta mañana","ce matin"} }
local PLACE = { {"en la cocina","dans la cuisine"},{"en casa","à la maison"},{"en el mercado","au marché"},{"en la tienda","au magasin"},
    {"en el jardín","dans le jardin"},{"en la oficina","au bureau"},{"en el teatro","au théâtre"},{"en la estación","à la gare"},
    {"en el coche","dans la voiture"},{"en la playa","à la plage"} }
local PERSONS = { {"el niño","l'enfant"},{"mi amigo","mon ami"},{"el profesor","le professeur"},{"el vecino","le voisin"},
    {"el músico","le musicien"},{"mi hermano","mon frère"},{"el actor","l'acteur"},{"el chico","le garçon"},{"mi padre","mon père"},{"el médico","le médecin"} }
local THINGS = { {"el libro","le livre"},{"el café","le café"},{"el hotel","l'hôtel"},{"el tren","le train"},{"el jardín","le jardin"},
    {"el piano","le piano"},{"el teatro","le théâtre"},{"el museo","le musée"},{"el barco","le bateau"},{"el abrigo","le manteau"},{"el sombrero","le chapeau"} }
local POETIC = { {"el paisaje","le paysage"},{"el cielo","le ciel"},{"el silencio","le silence"},{"el lago","le lac"},{"el jardín","le jardin"},{"el horizonte","l'horizon"} }
local ADJ_NOUNS = { ["Describir objetos"] = THINGS, ["Moda"] = THINGS, ["Lengua poética"] = POETIC }
-- thèmes d'objets ou de personnes qu'on peut « trouver dans la cuisine » ; les autres utilisent des phrases « on en parle »
local CONCRETE = {}
for _, n in ipairs({ "Familia","Comida","Casa","Colores y ropa","Frutas","Verduras","Bebidas y postres","En clase","Juguetes y juegos",
    "Profesiones","Muebles","Baño e higiene","Electrodomésticos","Juegos de mesa","Granja y mascotas","Ropa y accesorios","Comida española",
    "Supermercado","En la cocina","Tecnología","Peces y mariscos","Instrumentos musicales","Profesiones 2","Pequeños objetos","Herramientas",
    "Tienda y dinero","Escuela y estudios","Deporte y ocio","Mar y playa","Montaña y parapente","Aficiones","Fotografía","Cartas y colección" }) do CONCRETE[n] = true end
local HABLAR = { es={"hablo","hablas","habla","habla","hablamos","hablan"}, fr={"parle","parles","parle","parle","parlons","parlent"} }
local REFL_ES = {"me","te","se","se","nos","se"}
local REFL_FR = {"me","te","se","se","nous","se"}

local function nounOf(w)
    if w.es:find("[%(%?¿]") then return nil end
    local es = w.es
    local art = es:match("^(%a+) ")
    if art ~= "el" and art ~= "la" and art ~= "los" and art ~= "las" then return nil end
    local _, n = es:gsub("%S+", "")
    if n > 4 then return nil end
    local fr = frClean(w.fr)
    if not (startsWith(fr, "le ") or startsWith(fr, "la ") or startsWith(fr, "les ") or startsWith(fr, "l'")) then return nil end
    return { es = es, fr = fr, pl = (art == "los" or art == "las") }
end
local function verbOf(w, kind)
    if kind ~= "v" then return nil end
    local es = w.es
    if es:find(" ") or es:find("[%(%?¿]") then return nil end
    local base, refl = es, false
    if endsWith(es, "se") and (endsWith(es, "arse") or endsWith(es, "erse") or endsWith(es, "irse") or endsWith(es, "írse")) then
        base = es:sub(1, -3); refl = true
    end
    if not (endsWith(base, "ar") or endsWith(base, "er") or endsWith(base, "ir") or endsWith(base, "ír")) then return nil end
    local fr = frClean(w.fr)
    local frrefl = startsWith(fr, "se ") or startsWith(fr, "s'")
    if frrefl then fr = startsWith(fr, "se ") and fr:sub(4) or fr:sub(3) end
    return { base = base, refl = refl, fr = fr, frrefl = frrefl, es = es }
end
local function adjOf(w, kind)
    if kind ~= "a" then return nil end
    local es = w.es
    if es:find("[%(%?¿]") then return nil end
    local art = es:match("^(%a+) ")
    if art == "el" or art == "la" or art == "los" or art == "las" then return nil end
    local _, n = es:gsub("%S+", "")
    if n > 3 then return nil end
    if n == 1 and (endsWith(es, "ar") or endsWith(es, "er") or endsWith(es, "ir")) then return nil end
    local fr = frClean(w.fr)
    if startsWith(fr, "le ") or startsWith(fr, "la ") or startsWith(fr, "les ") or startsWith(fr, "l'") then return nil end
    return { es = es, fr = fr }
end

-- forme française « sujet + verbe (+ ne…pas) »
local function frSV(p, vfr, neg)
    local s = SUBJ[p][2]
    local first, rest = vfr:match("^(%S+)%s*(.*)$")
    if neg then
        local v = elide("ne", first) .. " pas" .. (rest ~= "" and (" " .. rest) or "")
        return s .. " " .. v
    end
    if s == "je" then return elide("je", vfr) end
    return s .. " " .. vfr
end
-- infinitif espagnol accordé (levantarse -> levantarme)
local function esInf(v, p) if v.refl then return v.base .. REFL_ES[p] end return v.base end
local function frInf(v, p)
    if v.frrefl then return elide(REFL_FR[p], v.fr) end
    return v.fr
end

local function finish(es, fr)
    es = (" " .. es):gsub(" de el ", " del "):gsub(" a el ", " al "):sub(2)
    es = capFirst(es); fr = capFirst(fr)
    if not (endsWith(es, "?") or endsWith(es, "!")) then es = es .. "." end
    if not (endsWith(fr, "?") or endsWith(fr, "!")) then fr = fr .. "." end
    return es, fr
end
local function estar(n) return n.pl and "están" or "está" end
local function etre(n) return n.pl and "sont" or "est" end
local function netre(n) return n.pl and "ne sont pas" or "n'est pas" end

-- phrase avec un nom du thème (formes valables pour objets ET personnes)
local function genNoun(tier, n, n2)
    local tm, pc = pick(TIME), pick(PLACE)
    local es, fr, extra
    if tier == 1 then
        local k = math.random(3)
        if k == 1 then es = "¿dónde " .. estar(n) .. " " .. n.es .. "?"; fr = "où " .. etre(n) .. " " .. n.fr .. " ?"
        elseif k == 2 then es = "me " .. (n.pl and "gustan" or "gusta") .. " " .. n.es; fr = "j'aime " .. n.fr
        else es = n.es .. " " .. estar(n) .. " aquí"; fr = n.fr .. " " .. etre(n) .. " ici" end
        extra = { n.pl and "está" or "están" }
    elseif tier == 2 then
        local k = math.random(3)
        if k == 1 then es = n.es .. " no " .. estar(n) .. " aquí"; fr = n.fr .. " " .. netre(n) .. " ici"
        elseif k == 2 then es = "me " .. (n.pl and "gustan" or "gusta") .. " mucho " .. n.es; fr = "j'aime beaucoup " .. n.fr
        else es = n.es .. " " .. estar(n) .. " " .. pc[1]; fr = n.fr .. " " .. etre(n) .. " " .. pc[2] end
        extra = { "allí", n.pl and "está" or "están" }
    elseif tier == 3 then
        if math.random() < 0.5 then
            es = tm[1] .. " " .. n.es .. " " .. estar(n) .. " " .. pc[1]; fr = tm[2] .. ", " .. n.fr .. " " .. etre(n) .. " " .. pc[2]
        else
            es = n.es .. " y " .. n2.es .. " están " .. pc[1]; fr = n.fr .. " et " .. n2.fr .. " sont " .. pc[2]
        end
        extra = { "pero", "es" }
    elseif tier == 4 then
        es = n.es .. " " .. estar(n) .. " " .. pc[1] .. " pero " .. n2.es .. " no " .. estar(n2) .. " aquí"
        fr = n.fr .. " " .. etre(n) .. " " .. pc[2] .. " mais " .. n2.fr .. " " .. netre(n2) .. " ici"
        extra = { "y", "son" }
    else
        local p, v, o = math.random(6), pick(VERBS), pick(OBJ)
        es = "cuando " .. n.es .. " " .. estar(n) .. " aquí, " .. SUBJ[p][1] .. " " .. v.es[p] .. " " .. o[1] .. " " .. pc[1]
        fr = "quand " .. n.fr .. " " .. etre(n) .. " ici, " .. joinDe(frSV(p, v.fr[p]), o[2]) .. " " .. pc[2]
        extra = { v.es[(p % 6) + 1], "porque" }
    end
    es, fr = finish(es, fr)
    return { es = es, fr = fr, extra = extra }
end

-- phrases pour les noms abstraits (on en parle, on y pense, ça intéresse)
local function genTopic(tier, n, n2)
    local p = math.random(6)
    local es, fr, extra
    local interesa = n.pl and "interesan" or "interesa"
    if tier == 1 then
        if math.random() < 0.5 then es = "me " .. interesa .. " " .. n.es; fr = n.fr .. " m'intéresse" .. (n.pl and "nt" or "")
        else es = "hablamos de " .. n.es; fr = "nous parlons " .. deNP(n.fr) end
        extra = { "habla" }
    elseif tier == 2 then
        local neg = math.random() < 0.4
        es = SUBJ[p][1] .. (neg and " no " or " ") .. HABLAR.es[p] .. " de " .. n.es
        fr = frSV(p, HABLAR.fr[p], neg) .. " " .. deNP(n.fr)
        extra = { HABLAR.es[p % 6 + 1], "en" }
    elseif tier == 3 then
        local tm = pick(TIME)
        es = tm[1] .. " " .. SUBJ[p][1] .. " " .. HABLAR.es[p] .. " de " .. n.es .. " y de " .. n2.es
        fr = tm[2] .. ", " .. frSV(p, HABLAR.fr[p]) .. " " .. deNP(n.fr) .. " et " .. deNP(n2.fr)
        extra = { "pero", "en" }
    elseif tier == 4 then
        es = "pienso en " .. n.es .. " pero no hablo de " .. n2.es
        fr = "je pense " .. joinA(n.fr) .. " mais je ne parle pas " .. deNP(n2.fr)
        extra = { "piensas", "y" }
    else
        es = "cuando " .. SUBJ[p][1] .. " " .. HABLAR.es[p] .. " de " .. n.es .. ", yo pienso en " .. n2.es
        fr = "quand " .. frSV(p, HABLAR.fr[p]) .. " " .. deNP(n.fr) .. ", je pense " .. joinA(n2.fr)
        extra = { "porque", "habla" }
    end
    es, fr = finish(es, fr)
    return { es = es, fr = fr, extra = extra }
end

local function genVerb(tier, v)
    local p = math.random(6)
    local m = pick(MODALS)
    local es, fr, extra
    if tier == 1 then
        local k = math.random(2)
        if k == 1 then es = "quiero " .. esInf(v, 1); fr = elide("je", "veux") .. " " .. frInf(v, 1)
        else es = "me gusta " .. esInf(v, 1); fr = "j'aime " .. frInf(v, 1) end
        extra = { "quieres" }
    elseif tier == 2 then
        local neg = math.random() < 0.35
        es = SUBJ[p][1] .. (neg and " no " or " ") .. m.es[p] .. " " .. esInf(v, p)
        fr = joinDe(frSV(p, m.fr[p], neg), frInf(v, p))
        extra = { m.es[(p % 6) + 1] }
    elseif tier == 3 then
        local tm = pick(TIME)
        es = tm[1] .. " " .. SUBJ[p][1] .. " " .. m.es[p] .. " " .. esInf(v, p)
        fr = tm[2] .. ", " .. joinDe(frSV(p, m.fr[p]), frInf(v, p))
        extra = { m.es[(p + 1) % 6 + 1], "no" }
    elseif tier == 4 then
        local p2 = (p % 6) + 1
        local m2 = pick(MODALS)
        es = SUBJ[p][1] .. " " .. m.es[p] .. " " .. esInf(v, p) .. " pero " .. SUBJ[p2][1] .. " no " .. m2.es[p2] .. " " .. esInf(v, p2)
        fr = joinDe(frSV(p, m.fr[p]), frInf(v, p)) .. " mais " .. joinDe(frSV(p2, m2.fr[p2], true), frInf(v, p2))
        extra = { "y", m.es[(p + 2) % 6 + 1] }
    else
        local pc = pick(PLACE)
        es = "cuando estoy " .. pc[1] .. ", " .. SUBJ[p][1] .. " " .. m.es[p] .. " " .. esInf(v, p)
        fr = "quand je suis " .. pc[2] .. ", " .. joinDe(frSV(p, m.fr[p]), frInf(v, p))
        extra = { "estás", "porque" }
    end
    es, fr = finish(es, fr)
    return { es = es, fr = fr, extra = extra }
end

local function genAdj(tier, a, a2, nouns)
    nouns = nouns or PERSONS
    local n = pick(nouns)
    local es, fr, extra
    if tier == 1 then es = n[1] .. " es " .. a.es; fr = n[2] .. " est " .. a.fr; extra = { "está" }
    elseif tier == 2 then
        if math.random() < 0.5 then es = n[1] .. " no es " .. a.es; fr = n[2] .. " n'est pas " .. a.fr
        else es = n[1] .. " es muy " .. a.es; fr = n[2] .. " est très " .. a.fr end
        extra = { "son", "poco" }
    elseif tier == 3 then es = n[1] .. " es " .. a.es .. " y " .. a2.es; fr = n[2] .. " est " .. a.fr .. " et " .. a2.fr; extra = { "pero", "muy" }
    elseif tier == 4 then
        local n2 = pick(nouns)
        es = n[1] .. " es " .. a.es .. " pero " .. n2[1] .. " es " .. a2.es
        fr = n[2] .. " est " .. a.fr .. " mais " .. n2[2] .. " est " .. a2.fr
        extra = { "y", "no" }
    else
        es = "creo que " .. n[1] .. " es " .. a.es .. " porque es muy " .. a2.es
        fr = "je crois que " .. n[2] .. " est " .. a.fr .. " parce qu'il est très " .. a2.fr
        extra = { "pero", "son" }
    end
    es, fr = finish(es, fr)
    return { es = es, fr = fr, extra = extra }
end

local function genGeneric(tier)
    local o, o2 = pick(OBJ), pick(OBJ)
    while o2 == o do o2 = pick(OBJ) end
    local v, v2 = pick(VERBS), pick(VERBS)
    local p = math.random(6)
    local p2 = (p + math.random(4)) % 6 + 1
    local tm, pc = pick(TIME), pick(PLACE)
    local es, fr, extra
    if tier <= 1 then
        es = SUBJ[1][1] .. " " .. v.es[1] .. " " .. o[1]; fr = joinDe(frSV(1, v.fr[1]), o[2]); extra = { v.es[5] }
    elseif tier == 2 then
        local neg = math.random() < 0.35
        es = SUBJ[p][1] .. (neg and " no " or " ") .. v.es[p] .. " " .. o[1]; fr = joinDe(frSV(p, v.fr[p], neg), o[2])
        extra = { v.es[(p + 1) % 6 + 1] }
    elseif tier == 3 then
        es = tm[1] .. " " .. SUBJ[p][1] .. " " .. v.es[p] .. " " .. o[1] .. " " .. pc[1]
        fr = tm[2] .. ", " .. joinDe(frSV(p, v.fr[p]), o[2]) .. " " .. pc[2]
        extra = { v.es[(p + 2) % 6 + 1], "con" }
    elseif tier == 4 then
        es = SUBJ[p][1] .. " " .. v.es[p] .. " " .. o[1] .. " pero " .. SUBJ[p2][1] .. " no " .. v2.es[p2] .. " " .. o2[1]
        fr = joinDe(frSV(p, v.fr[p]), o[2]) .. " mais " .. joinDe(frSV(p2, v2.fr[p2], true), o2[2])
        extra = { v.es[(p + 1) % 6 + 1], "y" }
    else
        es = "cuando " .. SUBJ[p][1] .. " " .. v.es[p] .. " " .. o[1] .. ", " .. SUBJ[p2][1] .. " " .. v2.es[p2] .. " " .. o2[1] .. " " .. pc[1]
        fr = "quand " .. joinDe(frSV(p, v.fr[p]), o[2]) .. ", " .. joinDe(frSV(p2, v2.fr[p2]), o2[2]) .. " " .. pc[2]
        extra = { v.es[(p + 1) % 6 + 1], "porque" }
    end
    es, fr = finish(es, fr)
    return { es = es, fr = fr, extra = extra }
end

function Core:generate(t, tier)
    local nouns, verbs, adjs = {}, {}, {}
    for _, w in ipairs(t.words) do
        local n = nounOf(w); if n then nouns[#nouns + 1] = n end
        local v = verbOf(w, t.kind); if v then verbs[#verbs + 1] = v end
        local a = adjOf(w, t.kind); if a then adjs[#adjs + 1] = a end
    end
    local q
    if #verbs >= 4 and math.random() < 0.8 then
        q = genVerb(tier, pick(verbs))
    elseif #adjs >= 4 and math.random() < 0.8 then
        local a, a2 = pick(adjs), pick(adjs)
        while a2 == a do a2 = pick(adjs) end
        q = genAdj(tier, a, a2, ADJ_NOUNS[t.name])
    elseif #nouns >= 4 and math.random() < 0.75 then
        local n, n2 = pick(nouns), pick(nouns)
        while n2 == n do n2 = pick(nouns) end
        if not CONCRETE[t.name] or math.random() < 0.35 then q = genTopic(tier, n, n2) else q = genNoun(tier, n, n2) end
    else
        q = genGeneric(tier)
    end
    return q
end

---------------------------------------------------------------- phrases
local function tierOf(n) if n <= 4 then return 1 elseif n <= 6 then return 2 elseif n <= 8 then return 3 elseif n <= 10 then return 4 end return 5 end

function Core:nextSentence(t, practice)
    local tp = self:tp(t.id)
    local pending = {}
    for _, c in ipairs(CURATED[t.li .. "-" .. t.ti] or {}) do
        if not tp.c[c.key] then pending[#pending + 1] = c end
    end
    local need = PGOAL - tp.p
    if not practice and #pending > 0 and (#pending >= need or (tierOf(pending[1].len) <= self.S.tier + 1 and math.random() < 0.5)) then
        local c = pending[1]
        -- mots pièges pris dans le vocabulaire débloqué
        local extra, toks = {}, {}
        for _, x in ipairs(tokens(c.es)) do toks[x:lower()] = true end
        for _ = 1, 30 do
            local w = pick(THEMES[math.random(self.S.nunlocked)].words)
            if not w.es:find("[ %?¿%(]") and not toks[w.es:lower()] then extra[#extra + 1] = w.es end
            if #extra >= (c.len >= 7 and 2 or 1) then break end
        end
        return { es = c.es, fr = c.fr, extra = extra, curated = true, key = c.key }
    end
    local q = self:generate(t, math.min(5, self.S.tier))
    -- les mots du thème qui apparaissent dans la phrase (pour la pile « à revoir »)
    return q
end

function Core:newPhrase(t, practice)
    local q = self:nextSentence(t, practice)
    local target = tokens(q.es)
    local tiles, ids = {}, {}
    for i, x in ipairs(target) do tiles[#tiles + 1] = { id = i, text = x } end
    for _, x in ipairs(q.extra or {}) do
        for _, y in ipairs(tokens(x)) do tiles[#tiles + 1] = { id = #tiles + 1, text = y } end
    end
    for _, tl in ipairs(tiles) do ids[#ids + 1] = tl.id end
    -- mots du thème présents dans la phrase
    local words, lowes = {}, " " .. table.concat(target, " "):lower() .. " "
    for _, w in ipairs(t.words) do
        local key = " " .. w.es:lower() .. " "
        if not w.es:find("[%(%?¿]") and lowes:find(key, 1, true) then words[#words + 1] = w.es end
    end
    return { t = t, practice = practice, q = q, target = target, tiles = tiles, bank = shuffle(ids), ans = {}, state = "play", words = words }
end

function Core:tileText(P, id) return P.tiles[id].text end
function Core:moveTile(P, id)
    if P.state ~= "play" then return end
    for i, x in ipairs(P.ans) do
        if x == id then table.remove(P.ans, i); table.insert(P.bank, id); return end
    end
    for i, x in ipairs(P.bank) do
        if x == id then table.remove(P.bank, i); table.insert(P.ans, id); return end
    end
end
function Core:clearAnswer(P)
    for _, x in ipairs(P.ans) do table.insert(P.bank, x) end
    P.ans = {}
end

function Core:checkPhrase(P)
    local got = {}
    for _, id in ipairs(P.ans) do got[#got + 1] = P.tiles[id].text end
    self.S.sTotal = self.S.sTotal + 1
    self:markToday()
    if table.concat(got, " ") == table.concat(P.target, " ") then
        return self:phraseSuccess(P)
    end
    P.state = "ko"
    self.S.sstreak = 0
    P.added = {}
    for _, k in ipairs(P.words) do
        if not self.S.review[k] then self.S.review[k] = true; P.added[#P.added + 1] = k end
    end
    return false
end

function Core:phraseSuccess(P)
    P.state = "ok"
    if P.added then for _, k in ipairs(P.added) do self.S.review[k] = nil end end
    self.S.sOk = self.S.sOk + 1
    self.S.sstreak = self.S.sstreak + 1
    self.S.carrots = self.S.carrots + 2
    local tp = self:tp(P.t.id)
    if not P.practice then
        tp.p = tp.p + 1
        if P.q.curated then tp.c[P.q.key] = true end
    end
    P.tierUp = false
    if self.S.sstreak >= STREAK_UP then
        self.S.sstreak = 0
        if self.S.tier < 5 then self.S.tier = self.S.tier + 1; P.tierUp = true end
    end
    P.stageDone = (not P.practice) and tp.p == PGOAL
    return true
end

---------------------------------------------------------------- cartes
function Core:buildDeck(t)
    local deck = {}
    if self.S.cardMode == "review" then
        for k in pairs(self.S.review) do if WORDS[k] then deck[#deck + 1] = WORDS[k] end end
        return shuffle(deck)
    end
    local rev, un = {}, {}
    for _, w in ipairs(t.words) do
        if self.S.review[w.es] then rev[#rev + 1] = w
        elseif not self.S.known[w.es] then un[#un + 1] = w end
    end
    rev = shuffle(rev)
    for _, w in ipairs(shuffle(un)) do rev[#rev + 1] = w end
    return rev
end
function Core:cardKnown(w)
    self.S.known[w.es] = true
    self.S.review[w.es] = nil
    self.S.carrots = self.S.carrots + 1
    self:markToday()
end
function Core:cardAgain(w)
    self.S.review[w.es] = true
    self:markToday()
end

return Core
