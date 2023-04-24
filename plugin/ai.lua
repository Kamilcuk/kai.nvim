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
add("AI", {range = true, nargs = "*"})
add("AI4", {range = true, nargs = "*"})
add("AIA", {range = true, nargs = "*"})
add("AIE", {range = true, nargs = "*"})
add("AIEText", {range = true, nargs = "*"})
add("AIChatUse", {nargs = "?"})
add("AIChatHistory")
add("AIChatZDelete", {nargs = 1})
