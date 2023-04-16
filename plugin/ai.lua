local function add(name, opts)
    vim.api.nvim_create_user_command(name, function(args)
        -- For debugging only
        if true then
            -- Unload packages to refresh them, for testing.
            package.loaded["k_ai"] = nil
        end
        require("k_ai")[name](args)
    end, opts or {})
end
add("AI", {range = true, nargs = "*", bang = true})
add("AIChatHistory")
add("AIChatDel")
