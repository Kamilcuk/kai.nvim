local M = {}

---@param name string
---@param default_value unknown
---@return unknown
local function get_var(name, default_value)
    return vim.g["ai"] and vim.g["ai"][name] or default_value
end

M.debug = nil
M.indicator_style = get_var("indicator_style", "sign")
M.indicator_text = get_var("indicator_text", "🤖")
M.completions_model = get_var("completions_model", "text-davinci-003")
M.edits_model = get_var("edits_model", "text-davinci-edit-001")
M.temperature = get_var("temperature", 0)
M.context_before = get_var("context_before", M.debug and 20 or 9999)
M.context_after = get_var("context_after", M.debug and 20 or 9999)
M.timeout = get_var("timeout", 60)
M.max_tokens = get_var("max_tokens", 2048)
M.chat_model = get_var("chat_model", "gpt-3.5-turbo")
M.chat_system_init = get_var("chat_system_init", "You are a helpful assistant.")
M.chat_temperature = get_var("chat_temperature", 0.2)
M.chat_file = get_var("chat_file", vim.fn['stdpath']('cache') .. "/ai_chatmessages.json")

function M.print(txt)
    print("ai.vim: " .. txt)
end

return M
