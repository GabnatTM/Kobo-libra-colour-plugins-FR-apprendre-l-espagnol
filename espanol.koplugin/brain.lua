--[[
Le petit cerveau local de Kobi.
Il assemble ses répliques à partir de modèles et d'un lexique, selon la situation
(série de bonnes réponses, erreurs récentes, heure, mot réussi…),
et évite de répéter ses 25 dernières phrases.
]]
local Brain = {}

local function pick(t) return t[math.random(#t)] end
local function cap(s)
    local b = s:byte(1)
    if b and b < 128 then return s:sub(1, 1):upper() .. s:sub(2) end
    return s
end

local LEX = {
    bravo = { "Bravo", "Génial", "Super", "Trop fort", "Magnifique", "Impeccable", "Chapeau", "Bien joué", "Excellent", "Nickel", "Parfait", "Formidable", "Joli coup" },
    esb = { "¡Muy bien!", "¡Olé!", "¡Genial!", "¡Perfecto!", "¡Qué bien!", "¡Fenomenal!", "¡Bravo!", "¡Increíble!", "¡Eso es!", "¡Estupendo!", "¡Buenísimo!" },
    joy = { "mon écran e-ink rougit de fierté", "je tourne les pages de joie", "mon encre électronique fait des étincelles", "ma batterie remonte à 100 %",
        "je fais un petit saut de page", "mon marque-page frétille", "je rafraîchis tout mon écran de bonheur", "je suis fier de toi",
        "je n'en reviens pas", "j'en perds mes pixels", "je m'illumine comme un éclairage frontal" },
    soft = { "Pas grave", "Aucun souci", "Ce n'est rien", "Tranquille", "Ça arrive", "On respire", "Pas de panique" },
    soft2 = { "les erreurs font partie du chemin", "même les liseuses font des fautes de frappe", "la prochaine sera la bonne",
        "ton cerveau est en train d'apprendre", "on le reverra ensemble", "c'est en se trompant qu'on retient", "je crois en toi",
        "on tourne la page et on continue" },
    tip = { "« Ser » sert pour ce qui dure, « estar » pour les états et les lieux.", "Le « ¿ » à l'envers ouvre chaque question en espagnol.",
        "« Embarazada » veut dire enceinte, pas embarrassée !", "Le « ñ » se prononce comme « gn » dans « montagne ».",
        "En espagnol, on peut omettre le sujet : « hablo » suffit pour « je parle ».", "La « j » espagnole se prononce du fond de la gorge.",
        "Les mots en -ción sont presque toujours féminins.", "« Me gusta » veut dire littéralement « ça me plaît ».",
        "« Constipado » veut dire enrhumé. Attention aux faux amis !", "Le « h » ne se prononce jamais en espagnol.",
        "« Vale » est le « d'accord » de tous les jours en Espagne.", "Les Espagnols soupent tard : souvent vers 21 h ou 22 h !",
        "« Libro » veut dire livre et « librería » librairie. Moi, je suis une « biblioteca » portable.",
        "Au Mexique, « ahorita » peut vouloir dire tout de suite… ou bien plus tard !", "« La mano » est féminin, même si le mot finit par -o.",
        "Devant un mot qui commence par « i », « y » devient « e » : « padre e hijo ».", "« Éxito » veut dire succès, pas sortie (la sortie, c'est « salida »)." },
    cheer = { "Allez, on continue", "On garde le rythme", "Encore un petit effort", "Tu chauffes", "Continue comme ça", "Page suivante" },
}

local T = {
    hello = { "{greet} Moi c'est Kobi, ta liseuse prof d'espagnol. Aujourd'hui : {theme}.", "{greet} On attaque {theme} ? Mon écran est prêt.",
        "{greet} {tip}", "{greet} Tu as déjà {known} mots en poche.", "{greet} Thème du jour : {theme}. ¡Vamos!" },
    night = { "Il est tard… je suis en mode veille, mais je t'accompagne. On fait quelques mots ?", "{greet} Une petite séance avant de dormir ? Bonne idée pour la mémoire." },
    quiz_ok = { "{esb} « {word} », c'est « {fr} ».", "{bravo} ! Plus que {left} mot{s} dans ce quiz.", "{bravo} ! {Joy}.", "{esb} {Joy}.",
        "Exactement : {word} = {fr}.", "{esb} {cheer} !" },
    quiz_ko = { "{soft}. « {word} » veut dire « {fr} ». {Soft2}.", "{soft} ! Je range « {word} » dans tes cartes à revoir.",
        "Presque. « {word} » = « {fr} ». {Soft2}." },
    phr_ok = { "{esb} Une vraie phrase en espagnol !", "{bravo} ! {Joy}.", "{esb} Encore {pleft} phrase{ps} pour finir l'étape.",
        "{bravo} ! Ça construit des phrases comme un pro.", "{esb} {cheer} !" },
    phr_ko = { "{soft}. L'ordre des mots est piégeux. {Soft2}.", "{soft} ! J'ai mis ces mots dans tes cartes à revoir.", "Pas loin ! {Soft2}." },
    card_ok = { "{esb}", "{bravo}, « {word} » rejoint ta bibliothèque.", "Et de {known} mots sus !", "« {word} »… {bravo} !", "{cheer} !" },
    card_again = { "On le reverra, pas d'inquiétude.", "Bonne idée de le revoir.", "Je le garde dans mon marque-page.", "Il reviendra un peu plus tard." },
    run = { "{run} bonnes réponses d'affilée ! {Joy} !", "Série de {run} ! ¡Qué crack!", "{run} d'affilée, rien ne t'arrête !" },
    tired = { "{soft}, prends ton temps. {Soft2}.", "Petite pause ? Je me mets en veille deux minutes, puis on repart. {Soft2}." },
    tier = { "Les phrases deviennent plus longues. Je sais que tu es prêt !", "Complexité {tier} ! On passe aux choses sérieuses." },
    stage_quiz = { "Quiz terminé ! Place aux phrases.", "{esb} Tous les mots du quiz sont validés. Maintenant, les phrases !" },
    stage_phr = { "Phrases terminées ! Dernière étape : les cartes.", "{esb} Étape phrases réussie. On finit avec les cartes." },
    theme = { "Thème terminé ! {n} nouveaux mots arrivent : {theme}.", "{esb} « {theme} » est débloqué, {n} mots tout neufs !" },
    level = { "¡Increíble! Niveau {lvl} débloqué ! {Joy} !", "Tu passes au niveau {lvl} ! Je fais la fête !" },
    tap = { "Hé, ça chatouille l'écran !", "Astuce : {tip}", "{greet} Tu as {carrots} étoiles. Je les compte, hein.",
        "Je m'appelle Kobi. Enfin… Kobi el lector.", "{tip}", "Tu as appris {known} mots. ¡Qué bien!", "Mon mot préféré ? « el marcapáginas ». Le marque-page !", "{cheer} !" },
    ["end"] = { "Tu as terminé les 10 niveaux ! ¡Eres un campeón! Tu peux continuer à t'entraîner autant que tu veux." },
}

local function greet()
    local h = tonumber(os.date("%H"))
    if h < 12 then return "¡Buenos días!" elseif h < 20 then return "¡Buenas tardes!" end
    return "¡Buenas noches!"
end

local function fill(tpl, ctx)
    return (tpl:gsub("{(%w+)}", function(k)
        if k == "greet" then return greet() end
        local low = k:sub(1, 1):lower() .. k:sub(2)
        if LEX[low] then
            local v = pick(LEX[low])
            if k ~= low then return cap(v) end
            return v
        end
        local v = ctx[k]
        if v == nil then return "" end
        return tostring(v)
    end))
end

-- mem = { recent = {…} } (sauvegardé avec la progression)
function Brain.line(ev, ctx, mem)
    local pool = T[ev] or T.tap
    local recent = mem.recent
    local seen = {}
    for _, r in ipairs(recent) do seen[r] = true end
    local out
    for _ = 1, 12 do
        out = fill(pick(pool), ctx or {})
        if not seen[out] then break end
    end
    recent[#recent + 1] = out
    while #recent > 25 do table.remove(recent, 1) end
    return out
end

return Brain
