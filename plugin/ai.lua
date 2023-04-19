---@param name string
---@param opts {}?
---@param alias string?
local function add(name, opts, alias)
    local func = alias or name
    vim.api.nvim_create_user_command(name, function(args)
        -- For testing only, unload packages to refresh them, for testing.
        -- package.loaded["k_ai"] = nil
        require("k_ai")[func](args)
    end, opts or {})
end
--
add("AI", {nargs = "*"})
add("AI4", {nargs = "*"})
add("AIA", {range = true, nargs = "*"}, "AIAdd")
add("AIAdd", {range = true, nargs = "*"})
add("AIEdit", {range = true, nargs = "*"})
add("AIEditCode", {range = true, nargs = "*"})
add("AIEditText", {range = true, nargs = "*"})
add("AIChatHistory")
add("AIChatZDelete", {nargs = 1})
