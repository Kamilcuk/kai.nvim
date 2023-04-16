local function add(name, opts)
    vim.api.nvim_create_user_command(name, function(args)
        -- For testing only, unload packages to refresh them, for testing.
        -- package.loaded["k_ai"] = nil
        require("k_ai")[name](args)
    end, opts or {})
end
add("AI", {range = true, nargs = "*", bang = true})
add("AIChatHistory")
add("AIChatDelete")
