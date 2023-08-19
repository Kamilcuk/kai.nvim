-- k_ai.lua
if vim.g.kai_loaded then return end
vim.g.kai_loaded = true

---@param name string
---@param opts {}?
---@param alias string?
local function kai_addcmd(name, opts, alias)
    local func = alias or name
    vim.api.nvim_create_user_command(name, function(args)
        -- For testing only, unload packages to refresh them, for testing.
        -- package.loaded["k_ai"] = nil
        require("k_ai")[func](args)
    end, opts or {})
end

kai_addcmd("AIA", {range = true, nargs = "*"})
--
kai_addcmd("AIE", {range = true, nargs = "*"})
kai_addcmd("AIEText", {range = true, nargs = "*"})
--
kai_addcmd("AI", {range = true, nargs = "*"})
kai_addcmd("AI4", {range = true, nargs = "*"})
kai_addcmd("AIChatUse", {nargs = "*"})
kai_addcmd("AIChatHistory")
kai_addcmd("AIChatZDelete", {nargs = 1})
