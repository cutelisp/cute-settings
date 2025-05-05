VERSION = "0.0.1"

-- This version relies on [PR #3733](https://github.com/zyedidia/micro/pull/3733)
-- 
local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")

local Settings = {
    Definitions = {},
    Definitions_idx = {}, 
    messages = nil,
    wrap_around = nil,
    plugin_name = nil,
    menu_bp = nil,
    lend_bp = nil, -- Was menu_bp created by Settings or passed to open_menu ?
}

local function _full_key(key)
    return Settings.plugin_name .. "." .. key
end

-- Micro stores all settings in string type, 
-- this function is used to cast the values to the meant types
local function _cast_value(def, raw_value)
    if def.type == "number" then
        return tonumber(raw_value)
    elseif def.type == "boolean" then
        if raw_value == true or raw_value == "true" then return true end
        if raw_value == false or raw_value == "false" then return false end
        return nil
    elseif def.type == "string" then
        return tostring(raw_value)
    end
    return raw_value
end

-- Return if raw_value is a valid value for def
local function _is_valid(def, raw_value)
    local value = _cast_value(def, raw_value)
    
    if value == nil then
        return false, "Type mismatch" .. ", expected " .. def.type .. ", got " .. type(raw_value) .." (" .. tostring(raw_value) .. ")"
    end

    if def.type == "number" then
        if (def.min and value < def.min) or (def.max and value > def.max) then
            return false, "Value is out of bounds. min = " .. tostring(def.min) .. ", max = " .. tostring(def.max) .. ", got " .. tostring(value)
        end

    elseif def.type == "string" and def.values then
        local found = false
        for _, v in ipairs(def.values) do
            if v == value then
                found = true
                break
            end
        end
        if not found then
            return false, "'" .. tostring(value) .. "'" .. " is not in the allowed set { " .. table.concat(def.values, ", ") .. " }"
        end
    end

    if def.check and type(def.check) == "function" then
        local valid, err = def.check(value)
        if not valid then
            return false, err
        end
    end

    return true, nil
end

local function _set_step(key, direction)
    local def = Settings.Definitions[key]
    if not def then return false, "Setting '" .. key .. "' does not exist" end

    local current = Settings.get(key, false)

    if def.type == "boolean" then
        if not Settings.wrap_around then
            if direction < 0 and not current or direction > 0 and current then 
                return false 
            end
        end
        return Settings.set(key, not current)

    elseif def.type == "string" and def.values then
        for i, v in ipairs(def.values) do
            if v == current then
                local new_index = i + direction
                local max_index = #def.values
                if new_index < 1 or new_index > max_index then
                    if Settings.wrap_around then
                        new_index = (direction > 0) and 1 or max_index
                    else
                        return false, "Reached limit of values"
                    end
                end
                return Settings.set(key, def.values[new_index])
            end
        end
        return false, "Current value not found in allowed values"

    elseif def.type == "number" and def.min and def.max then
        local step = def.step or 1
        local next_val = current + (step * direction)
        if next_val > def.max or next_val < def.min then
            return false, "Reached numeric bounds"
        end
        return Settings.set(key, next_val)
    end

    return false, "Cannot step through setting of type " .. tostring(def.type)
end


--- Initializes the Settings system
-- @param plugin_name string
-- @param definitions table
-- @param override boolean If true, overrides invalid settings with default values. Helps avoid errors when users edit settings.json manually.
-- @param messages boolean Show messages globally unless overridden
-- @return boolean -- If true, overrides invalid settings with default values. Helps avoid errors when users edit settings.json manually.
function Settings.init(plugin_name, definitions, override, messages, wrap_around)
    Settings.plugin_name = plugin_name
    Settings.Definitions = definitions
    Settings.messages = messages ~= false -- default true
    Settings.wrap_around = wrap_around ~= false -- default true
    local flawless = true
    
    -- Create indexed tbl
    for key, _ in pairs(Settings.Definitions) do
        table.insert(Settings.Definitions_idx, key)
    end

    local VALID_TYPES = {
        number = true,
        string = true,
        boolean = true,
    }
    
    for key, def in pairs(definitions) do
        -- Check type
        if not VALID_TYPES[def.type] then
            local err = "Error loading config: invalid type '" .. tostring(def.type) .. "' for setting '" .. key .. "'"
            if Settings.messages then micro.InfoBar():Error(err) end
            flawless = false
            goto continue
        end
        
        config.RegisterGlobalOption(plugin_name, key, def.default)
        local val = Settings.get(key)
        
        -- Check value
        local valid, err = _is_valid(def, val)
        
        if not valid then
            local m = "Error loading config: invalid value for '" .. key .. "', " .. err
            if override then
                Settings.set(key, def.default, false)
                m = m .. ". Default value restored"
            end
            if Settings.messages then
                micro.InfoBar():Error(m)
            end
            flawless = false
        end
    end
    
    ::continue::
    return flawless
end

-- or_show_message overrides the global show_message flag
function Settings.get(key, or_show_message)
    local show_message = (or_show_message == nil) and Settings.messages or or_show_message

    local def = Settings.Definitions[key]
    if not def then 
        local err = "Error: '" .. key .. "' is not a valid setting"
        if show_message then
            micro.InfoBar():Error(err)
        end
        return nil, err
    end
    
    local raw = config.GetGlobalOption(_full_key(key))
    return _cast_value(def, raw), nil
end

-- or_show_message overrides the global show_message flag
function Settings.set(key, value, or_show_message)
    local show_message = (or_show_message == nil) and Settings.messages or or_show_message

    local def = Settings.Definitions[key]

    if not def then 
        local err = "Error: '" .. key .. "' is not a valid setting"
        if show_message then
            micro.InfoBar():Error(err)
        end
        return false, err
    end

    local valid, error_message = _is_valid(def, value)

    if not valid then
        local err = "Invalid value for '" .. key .. "': " .. error_message
        if show_message then
            micro.InfoBar():Error(err)
        end
        return false, err
    end
    config.SetGlobalOption(_full_key(key), tostring(value))
    return true, nil
end

function Settings.set_default(key)
    return Settings.set(key, Settings.Definitions[key].default)
end

function Settings.set_next(key)
    return _set_step(key, 1)
end

function Settings.set_previous(key)
    return _set_step(key, -1)
end


-- Menu
local overlay = import("micro/overlay")

local overlay_handle = nil
local event_count = 0
local events = {}
local tracked_events = {}
local cur_line = 0

-- Converts a key with underscores into a more readable format with spaces and capitalization
-- Adds <, > to the value for the given key
local function _get_formated(key)
    -- Replace underscores with spaces and capitalize the first letter of each word
    local f_key = key:gsub("_", " "):gsub("(%a)([%a_']*)", function(first, rest) 
        return first:upper() .. rest:lower()
    end)
    local val = Settings.get(key)
    if Settings.Definitions[key].type == "boolean" then 
        val = val and "on" or "off"
    end
    
    local f_val = "<" .. tostring(val) .. ">"
    return f_key, f_val
end

local function _get_cur_def()
    return Settings.Definitions_idx[cur_line + 1]
end
local function _get_cur_key()
    return Settings.Definitions[_get_cur_def()]
end

local function _track_event(name, block)
    -- Registers a global handler for an event
    -- If "block" is passed as the second argument,
    -- the event will be prevented.
    local prefix = block and "pre" or "on" 
    local full_name = prefix .. name

    if not tracked_events[full_name] then
        tracked_events[full_name] = true
            _G[full_name] = function(...)
                if overlay_handle and micro.CurPane() == Settings.menu_bp then 
                    events[name] = {...}
                    event_count = event_count + 1
                    if block then 
                        return false
                    end
                end
            end
    end
end

local function _untrack_events()
    -- Removes all global event handlers
    for e, _ in pairs(tracked_events) do
        _G[e] = nil
    end
    tracked_events = {}
end

local function _reset_events()
    -- Resets tracked events between redraws
    events = {}
    event_count = 0
end

local function _event(event_name, block)
    -- Returns event arguments if the event has occurred, or nil otherwise.
    _track_event(event_name, block)
    return events[event_name]
end

local mn_max_key_length = 0
local mn_max_value_length = 0

local function _mn_draw(bp)
	if _event("Escape") then
		Settings.menu_close()
		return
	end
	
	if _event("Backspace", true ) then
	    Settings.set_default(_get_cur_def())
	end
	
	if _event("DeleteWordLeft", true ) then
        micro.InfoBar():YNPrompt("Restore all settings to default? (y, n, esc)", function (yes)
		if yes then 
			for key, _ in pairs(Settings.Definitions) do
			    Settings.set_default(key)
			end 
		end
	end)
	end

	local up_bound = 0
	local down_bound = #Settings.Definitions_idx - 1
    
    if _event("CursorUp", true ) then 
        if cur_line > up_bound then 
            cur_line = cur_line - 1
            Settings.menu_bp.Cursor.Loc.Y = cur_line 
        end
    end

    if _event("CursorDown", true ) then 
        if cur_line < down_bound then 
            cur_line = cur_line + 1
            Settings.menu_bp.Cursor.Loc.Y = cur_line 
        end
    end
    
    if _event("CursorRight", true) then 
        local x = Settings.Definitions_idx[cur_line + 1]
		Settings.set_next(x)
    end
    
    if _event("CursorLeft", true ) then 
        local x = Settings.Definitions_idx[cur_line + 1]
		Settings.set_previous(x)
    end
    
    
    for key, _ in pairs(Settings.Definitions) do
        local f_key, f_val = _get_formated(key)

        if #f_key > mn_max_key_length then
            mn_max_key_length = #f_key
        end
        if #f_val > mn_max_value_length then
            mn_max_value_length = #f_val
        end
    end
    
    local highlight = overlay.GetColor("constant"):Bold(true) 
    local normal = overlay.GetColor("normal"):Bold(true)

    local w = Settings.menu_bp:GetView().Width
    local f_w = w - (mn_max_value_length + mn_max_key_length + 2) 
    
    local i = 0
    for key, def in pairs(Settings.Definitions) do
        local style = (i == cur_line) and highlight or normal
        local f_key, f_val = _get_formated(key)

        local key_spaces = string.rep(" ", mn_max_key_length - #f_key)
        local value_spaces = string.rep(" ", mn_max_value_length - #f_val)
        local w_spaces = string.rep(" ", f_w - 2)
    
        local output_text = "  " ..  f_key .. key_spaces .. w_spaces .. value_spaces .. f_val .. "\n"
        overlay.DrawText(output_text, 0, i, w, 10, style)
        
        i = i + 1
    end
    Settings.menu_bp.Buf:SetOptionNative('statusformatr', cur_line+1 .. "/" .. #Settings.Definitions_idx)
    Settings.menu_bp.Buf:SetOptionNative('statusformatl', _get_cur_key().description)

    _reset_events()
end

-- This function has 2 modes
-- Either a bp is passed through parameter or a bp is created
function Settings.menu_open(bp, width)
    if overlay_handle then return end
    _reset_events()
    
    Settings.lend_bp = bp ~= nil
    if bp == nil then 
        local cur = micro.CurPane()
        local str = string.rep("\n", #Settings.Definitions_idx)
        local buf = buffer.NewBuffer(str, "")
        bp = cur:VSplitIndex(buf, false)
       	bp.Buf:SetOptionNative("ruler", false)
        bp.Buf:SetOptionNative('statusformatr', '')
        bp.Buf:SetOptionNative('statusformatl', ' ')
        bp:ResizePane(width or 30 )
        Settings.menu_bp = bp        
    end
    Settings.menu_bp = bp
    Settings.menu_is_open = true

    overlay_handle = overlay.CreateOverlay(_mn_draw)
    
end

function Settings.menu_close()
    -- Closes the overlay and untracks all events.
    _untrack_events()
	overlay.DestroyOverlay(overlay_handle)
	overlay_handle = nil
	
	if not Settings.lend_bp then 
        Settings.menu_bp:Quit()
	end
    Settings.menu_is_open = false

end

function deinit()
    Settings.menu_close()
end

return Settings