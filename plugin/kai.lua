-- kai.lua
if vim.g.kai_loaded then
	return
end
vim.g.kai_loaded = true

---@param name string
---@param opts {}?
---@param alias string?
local function kai_addcmd(name, opts, alias)
	local func = alias or name
	vim.api.nvim_create_user_command(name, function(args)
		-- For testing only, unload packages to refresh them, for testing.
		if vim.g.kai_reload then
			package.loaded["kai"] = nil
		end
		require("kai")[func](args)
	end, opts or {})
end

local function kai_complete_chat_names(ArgLead, CmdLine, CursorPos)
	local func = "complete_chat_names"
	-- For testing only, unload packages to refresh them, for testing.
	if vim.g.kai_reload then
		package.loaded["kai"] = nil
	end
	return require("kai")[func](ArgLead, CmdLine, CursorPos)
end

kai_addcmd("AIA", { range = true, nargs = "*" })
--
kai_addcmd("AIE", { range = true, nargs = "*" })
kai_addcmd("AIEText", { range = true, nargs = "*" })
--
kai_addcmd("AI", { range = true, nargs = "*" })
kai_addcmd("AI4", { range = true, nargs = "*" })
kai_addcmd("AIChatNew", { nargs = "*" })
kai_addcmd("AIChatUse", { nargs = 1, complete = kai_complete_chat_names })
kai_addcmd("AIChatOpen", { nargs = "?", complete = kai_complete_chat_names })
kai_addcmd("AIChatView", { nargs = "?", complete = kai_complete_chat_names })
kai_addcmd("AIChatList")
kai_addcmd("AIChatRemove", { nargs = 1, complete = kai_complete_chat_names })
