--[[
Mi Español — plugin KOReader
Menu : Outils (icône clé) > Mi Español
Progression enregistrée dans koreader/settings/espanol.lua
]]
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local function plugin_dir()
    local src = debug.getinfo(1, "S").source
    return src:match("^@(.*)/[^/]*$") or "plugins/espanol.koplugin"
end
local DIR = plugin_dir()

local Espanol = WidgetContainer:extend{
    name = "espanol",
    is_doc_only = false,
}

function Espanol:init()
    self.ui.menu:registerToMainMenu(self)
end

function Espanol:addToMainMenu(menu_items)
    menu_items.espanol = {
        text = "Mi Español",
        sorting_hint = "tools",
        callback = function() self:openApp() end,
    }
end

function Espanol:openApp()
    local ok, err = pcall(function()
        local App = loadfile(DIR .. "/app.lua")(DIR)
        UIManager:show(App:new{}, "full")
    end)
    if not ok then
        logger.err("Mi Español:", err)
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = "Mi Español n'a pas pu démarrer :\n" .. tostring(err) })
    end
end

return Espanol
