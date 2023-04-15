--
---@param name string
---@param opts nil | {}
local function add(name, opts)
    vim.api.nvim_create_user_command(name, function(args)
        -- For debugging only
        if true then
            -- Unload packages to refresh them, for testing.
            for k, v in pairs(package.loaded) do
                if k:find("_ai/") then package.loaded[k] = nil end
            end
        end
        require("_ai/commands")[name](args)
    end, opts or {})
end
--
add("AI", {range = true, nargs = "*", bang = true})
