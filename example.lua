-- This is an example how a plugin uses cutesettings

local PLUGIN_NAME = "cute_plugin"
local config = import("micro/config")

package.path = package.path .. ';' .. config.ConfigDir .. '/plug/' .. PLUGIN_NAME .. '/?.lua'

local Settings = require("cute_settings")

function init()
    local definitions = {
        master_volume = {
            description = "loud",
            type = "number",
            min = 1,
            max = 10,
            default = 5,
            check = function(value)
                if value % 3 == 0 then
                    return false, "Volume cannot be a multiple of 3."
                end
                return true
            end
        },
        notifications = {
            description = "Triiiiiim!",
            type = "boolean",
            default = true,
        },
        theme = {
            description = "black n white",
            type = "string",
            values = { "light", "dark", "blue" },
            default = "dark",
        },
        temperature = {
            description = "it's never too hot",
            type = "number",
            min = -10,
            max = 50,
            step = 4,
            default = 22,
        },
    }
    
    Settings.init(
        "cutesettings", 
        definitions, 
        true, 
        true , 
        true
    )  
    
    local function toggle()  
        if Settings.menu_is_open then 
            Settings.menu_close()
        else
            Settings.menu_open()
        end
    end
   
    config.MakeCommand("cutesettings", toggle, config.NoComplete)
   	config.TryBindKey("CtrlSpace", "command:cutesettings", false)
end




