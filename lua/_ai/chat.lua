local config = require("_ai/config")

--- @type {assistant: string, system: string, user: string} Chat roles from OpenAI
local roles = {assistant = "assistant", system = "system", user = "user"}

-- Global array of all chat messages in the "chat" format.
---@class Chat
---@field m nil | {role: string, message: string}[]
local M = {msg = nil}
M.__index = M

function M:init()
    if not self.msg then
        self.msg = {{role = roles.system, content = config.chat_system_init}}
    end
end

function M:append(role, content)
    self:init()
    -- Accumulate multiple assistant responses into single content.
    if role == "assistant" and self.msg[#self.msg].role == role then
        self.msg[#self.msg].content = self.msg[#self.msg].content .. content
    else
        -- Otherwise, append new element.
        self.msg[#self.msg + 1] = {role = role, content = content}
    end
    return self:get_messages()
end

function M:append_user(content) self:append(roles.user, content) end

function M:append_assistant(content) self:append(roles.assistant, content) end

function M:last_assistant_character()
    if #self.msg ~= 0 and self.msg[#self.msg].role == roles.assistant then
        local c = self.msg[#self.msg].content
        return c[#c]
    end
    return nil
end

function M:get_messages() return self.msg end

function M:save()
    local file = io.open(config.chat_file, "w")
    if not file then
        config.print("could not save chat messages to " .. config.chat_file)
        return
    end
    local serialized = {version = 0, messages = self.msg}
    file:write(vim.json.encode(serialized))
    file:close()
end

function M:load()
    local file = io.open(config.chat_file, "r")
    if not file then
        config.print("could not load chat messages from " .. config.chat_file)
        return
    end
    local serialized = vim.json.decode(file:read("*a"))
    file:close()
    if serialized.version ~= 0 then
        config.print("chat file version is not supported: " .. serialized.version)
        return
    end
    self.msg = serialized.messages
    return self:get_messages()
end

return M
