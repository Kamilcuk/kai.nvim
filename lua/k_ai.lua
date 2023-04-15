-- vim: foldmethod=marker
-- {{{1 config
-- s/[^"]*"\([^"]*\).*/---@field \1 unknown/
---@class Config
---@field _default_values unknown[]
---@field debug unknown
---@field cache_dir unknown
---@field chat_model unknown
---@field chat_temperature unknown
---@field completions_model unknown
---@field context_after unknown
---@field context_before unknown
---@field edits_model unknown
---@field indicator_style unknown
---@field indicator_text unknown
---@field max_tokens unknown
---@field temperature unknown
---@field timeout unknown
local config = setmetatable({_default_values = {}}, {
    -- Dynamically get values from global options when evaluated.
    __index = function(self, key)
        return vim.g["ai"] and vim.g["ai"][key] or self._default_values[key]
    end
})

---@param name string
---@param default_value unknown
function config:var(name, default_value)
    self._default_values[name] = default_value
end

config:var("debug", false)
config:var("cache_dir", vim.fn['stdpath']('cache') .. "/k_ai/")
config:var("chat_model", "gpt-3.5-turbo")
config:var("chat_temperature", 0.2)
config:var("completions_model", "text-davinci-003")
config:var("context_after", config.debug and 20 or 9999)
config:var("context_before", config.debug and 20 or 9999)
config:var("edits_model", "text-davinci-edit-001")
config:var("indicator_style", "sign")
config:var("indicator_text", "🤖")
config:var("max_tokens", 2048)
config:var("temperature", 0)
config:var("timeout", 60)

---@param err string
function config.error(err) vim.api.nvim_err_writeln("ai.vim: " .. err) end
---@param txt string
function config.print(txt) print("ai.vim: " .. txt) end

-- {{{1 Utils

---@class Args
---@field args string
---@field range integer
---@field line1 integer
---@field line2 integer
---@field bang boolean

---@class Pos
---@field row integer 0 based
---@field col integer 0 based
Pos = {
    new0 = function(self, row, col)
        return setmetatable({row = row, col = col}, Pos)
    end,
    ---@param tbl_or_row integer[] | integer
    ---@param col nil | integer
    new10 = function(self, tbl_or_row, col)
        local row
        if type(tbl_or_row) == "table" then
            row = tbl_or_row[1]
            col = tbl_or_row[2]
        else
            row = tbl_or_row
        end
        return self:new0(row - 1, col)
    end,
    get0 = function(self) return {self.row, self.col} end,
    get10 = function(self) return {self.row + 1, self.col} end
}

---@class Region
---@field start Pos
---@field stop Pos
Region = {
    new = function(self, start, stop)
        return setmetatable({start = start, stop = stop}, Region)
    end
}

local function get_row_length(buffer, row)
    return vim.api.nvim_buf_get_lines(buffer, row, row + 1, true)[1]:len()
end

-- Get the text from the buffer between the start and end points.
---@param reg Region
local function buffer_get_text(buffer, reg)
    return table.concat(vim.api.nvim_buf_get_text(buffer, reg.start.row,
                                                  reg.start.col, reg.stop.row,
                                                  reg.stop.col, {}), "\n")
end

---@param args Args
---@return nil | Region
local function get_selection(buffer, args)
    if args.range > 0 then
        -- Use the visual selection
        local start = Pos:new10(vim.api.nvim_buf_get_mark(buffer, "<"))
        local stop
        if start.row == 0 then
            -- No visual selection, called in range mode.
            start = Pos:new10(args.line1, 0)
            stop = Pos:new10(args.line2, get_row_length(buffer, args.line2 - 1))
        else
            stop = Pos:new10(vim.api.nvim_buf_get_mark(buffer, ">"))
            -- Limit col positions, nvim_buf_get_mark outputs end of universe.
            local end_line_length = get_row_length(buffer, stop.row)
            stop.col = math.min(stop.col, end_line_length)
        end
        return Region:new(start, stop)
    end
end

-- {{{1 Indicator

---@class Indicator
---@field buffer unknown
---@field accumulated_text string
---@field reg Region Region to replace with text.
local Indicator = {}
Indicator.__index = Indicator

function Indicator:new(buffer, reg)
    local o = setmetatable({buffer = buffer, accumulated_text = "", reg = reg},
                           Indicator)
    return o
end

function Indicator:set_text()
    local lines = vim.split(self.accumulated_text, "\n")
    vim.api.nvim_buf_set_text(self.buffer, self.reg.start.row,
                              self.reg.start.col, self.reg.stop.row,
                              self.reg.stop.col, lines)
    -- Calculate new region stop with the filled text.
    self.reg.stop = Pos:new0(self.start_row + #lines - 1, lines[#lines]:len())
    -- Move cursor positin to the end of the region to make it visible.
    vim.api.nvim_win_set_cursor(0, self.reg.stop:get10())
end

---@param data string
function Indicator:add_preview_text(data)
    self.accumulated_text = self.accumulated_text .. data
    self:set_text()
    vim.cmd.redraw()
end

-- {{{1 Chat

--- @type {assistant: string, system: string, user: string} Chat roles from OpenAI
local chatRoles = {assistant = "assistant", system = "system", user = "user"}

-- Global array of all chat messages in the "chat" format.
---@class Chat
---@field msg nil | {role: string, message: string}[]
local chat = {msg = nil}
chat.__index = chat

function chat:init()
    if not self.msg then
        self.msg = {
            {role = chatRoles.system, content = "You are a helpful assistant."}
        }
    end
end

function chat:append(role, content)
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

function chat:append_user(content) self:append(chatRoles.user, content) end

function chat:append_assistant(content) self:append(chatRoles.assistant, content) end

function chat:last_assistant_character()
    if #self.msg ~= 0 and self.msg[#self.msg].role == chatRoles.assistant then
        local c = self.msg[#self.msg].content
        return c[#c]
    end
    return nil
end

function chat:get_messages() return self.msg end

function chat:file() return config.cache_dir .. '/chat.json' end

function chat:save()
    if not vim.fn.isdirectory(config.cache_dir) then
        vim.fn.mkdir(config.cache_dir, "p")
    end
    local file = io.open(self:file(), "w")
    if not file then
        config.print("could not save chat messages to " .. self:file())
        return
    end
    local serialized = {version = 0, messages = self.msg}
    file:write(vim.json.encode(serialized))
    file:close()
end

function chat:load()
    local file = io.open(self:file(), "r")
    if not file then return end
    local serialized = vim.json.decode(file:read("*a"))
    file:close()
    if serialized.version ~= 0 then
        config.print("chat file version is not supported: " ..
                         serialized.version)
        return
    end
    self.msg = serialized.messages
    return self:get_messages()
end

-- {{{1 OpenAI

---@class Openai
---@field on_data function(data: {}) The callback to call with the response.
---@field on_error function(err: string) The callback to call with an error.
---@field on_complete function() The callback to call when the request is complete.
---@field isstream boolean
---@field acc string
local Openai = {}
Openai.__index = Openai

local function safe_close(handle)
    if not vim.loop.is_closing(handle) then vim.loop.close(handle) end
end

---@param o {on_data: function, on_complete: function, on_error: function}
function Openai:new(o)
    return setmetatable({
        on_data = o.on_data,
        on_complete = o.on_complete,
        on_error = o.on_error,
        acc = "",
        stream = false
    }, Openai)
end

---@param cmd string[] The command to run.
function Openai:mypopen(cmd)
    local stdout_line = ""
    local stdout = vim.loop.new_pipe()
    local stderr_chunks = ""
    local stderr = vim.loop.new_pipe()
    local handle, pid
    handle, _ = vim.loop.spawn(cmd[1], {
        args = {unpack(cmd, 2, #cmd)},
        stdio = {nil, stdout, stderr}
    }, function(code)
        stdout:read_stop()
        stderr:read_stop()
        safe_close(stdout)
        safe_close(stderr)
        safe_close(handle)
        if code == 0 then
            self:on_end()
        else
            self.on_error(cmd .. stderr_chunks)
        end
    end)
    if not handle then
        self.on_error(vim.inspect(cmd) .. " could not be started: " ..
                          vim.inspect(error))
        return
    end
    stdout:read_start(function(_, chunk)
        -- Read output line by line.
        if not chunk then return end
        stdout_line = stdout_line .. chunk
        local line_start, line_end = stdout_line:find("\n")
        while line_start do
            local oneline = stdout_line:sub(1, line_end - 1)
            stdout_line = stdout_line:sub(line_end + 1)
            if oneline ~= "" then self:on_line(oneline) end
            line_start, line_end = stdout_line:find("\n")
        end
    end)
    stderr:read_start(function(_, chunk)
        -- Accumulate stderr into stderr_chunks.
        if not chunk then return end
        stderr_chunks = stderr_chunks .. chunk
    end)
    local ended, _ = vim.wait(config.timeout * 1000,
                              function() return not handle:is_active() end)
    if not ended then handle:kill() end
end

---Handle json decoding error or a good json response.
---@param txt string
function Openai:handle_json_response(txt)
    local success, json = pcall(vim.json.decode, txt)
    if not success then
        self.on_error("Could not decode json: " .. vim.inspect(txt))
    elseif type(json) ~= "table" then
        self.on_error("Not a JSON dictionary: " .. vim.inspect(txt))
    elseif json.error and type(json.error) == "table" and json.error.message then
        self.on_error(json.error.message)
    elseif not json.choices then
        self.on_error("No choices in response: " .. vim.inspect(txt))
    elseif json.choices[1].text then
        -- Response from completions and edits endpoints.
        self.on_data(json.choices[1].text)
    elseif json.choices[1].delta then
        -- Response from chat endpoint stream.
        if json.choices[1].delta.role then
            -- I think this has to be assistant
        end
        if json.choices[1].delta.content then
            local content = json.choices[1].delta.content
            chat:append_assistant(content)
            self.on_data(content)
        end
    elseif json.choices[1].message then
        -- Response from chat endpoint no stream.
        local msg = json.choices[1].message
        chat:append(msg.role, msg.content)
        self.on_data(msg.content)
    else
        self.on_error("Could not parse response: " .. vim.inspect(txt))
    end
end

function Openai:on_line(line)
    if config.debug then print("<", vim.inspect(line)) end
    if self.acc ~= "" or vim.startswith(vim.trim(line), "{") then
        -- This is an error response or not streaming.
        self.acc = self.acc .. line
    elseif not vim.startswith(line, "data: ") then
        self.on_error("Response from API does not start with data: " ..
                          vim.inspect(line))
    else
        line = vim.trim(line:gsub("^data:", ""))
        -- [DONE] means end of parsing.
        if not line or line == "[DONE]" then return end
        self:handle_json_response(line)
    end
end

function Openai:on_end()
    if self.acc ~= "" then
        self:handle_json_response(self.acc)
    elseif string.find(self.endpoint, "chat") then
        -- When using chat completion add an additional trailing newline to have the cursor ending on the next line.
        if chat:last_assistant_character() ~= "\n" then
            self.on_data("\n")
        end
    end
    self.on_complete()
end

function Openai:request(endpoint, body)
    self.endpoint = endpoint
    local api_key = os.getenv("OPENAI_API_KEY")
    if not api_key then
        self.on_error("$OPENAI_API_KEY environment variable must be set")
        return
    end
    if config.debug then print(">", vim.inspect(endpoint), vim.inspect(body)) end
    local jsonbody = vim.json.encode(body)
    local curl = {
        "curl", "--silent", "--show-error", "--no-buffer", "--max-time",
        config.timeout, "-L", "https://api.openai.com/v1/" .. endpoint, "-H",
        "Authorization: Bearer " .. api_key, "-X", "POST", "-H",
        "Content-Type: application/json", "-d", jsonbody
    }
    if false then
        curl = {
            "sh", "-c", [[
            for i in $(seq 10); do
                printf 'data: {"choices":[{"text":"%s\\n"}]}\n' "$i"
                sleep 0.1
            done
            printf 'data: [DONE]\n'
            ]], "_"
        }
    end
    self:mypopen(curl)
end

---Request OpenAI API for completions.
---@param body {} The body of the request.
function Openai:completions(body)
    body = vim.tbl_extend("keep", body, {
        model = config.completions_model,
        max_tokens = config.max_tokens,
        temperature = config.temperature,
        stream = true
    })
    self:request("completions", body)
end

---Request OpenAI API for edit.
---@param body {} The body of the request.
function Openai:edits(body)
    body = vim.tbl_extend("keep", body, {
        model = config.edits_model,
        temperature = config.temperature
    })
    self:request("edits", body)
end

---@param message string
function Openai:chat(message)
    chat:append_user(message)
    local body = {
        model = config.chat_model,
        stream = true,
        temperature = config.chat_temperature,
        messages = chat:get_messages()
    }
    self:request("chat/completions", body)
end

-- {{{1 Command AI

---@class M
local M = {}

---@param args Args
function M.AI(args)
    -- print(vim.inspect(args))
    local visual_mode = args.range > 0
    local buffer = vim.api.nvim_get_current_buf()
    local start_row, start_col
    local end_row, end_col
    local selection = get_selection(buffer, args)
    local cursor = Pos:new10(vim.api.nvim_win_get_cursor(0))
    local aftercursor = Pos:new0(cursor.row, cursor.col + 1)
    local replace = selection or aftercursor
    local indicator = Indicator:new(buffer, replace)
    local openai = Openai:new{
        ---@param data string
        on_data = function(data)
            vim.schedule(function() indicator:add_preview_text(data) end)
        end,
        on_complete = function() end,
        ---@param err string
        on_error = function(err)
            vim.schedule(function() config.error(err) end)
        end
    }

    local prompt = args.args
    if selection then
        local selected_text = buffer_get_text(buffer, selection)
        if prompt == "" then
            -- Replace the selected text, also using it as a prompt.
            openai:completions({prompt = selected_text})
        else
            -- Edit selected text
            openai:edits({input = selected_text, instruction = prompt})
        end
    else
        if not args.bang then
            -- Insert some text generated using surrounding context.
            local start_row_before = math.max(0,
                                              start_row - config.context_before)
            local prefix = buffer_get_text(buffer, Region:new(
                                               Pos:new0(start_row_before, 0),
                                               aftercursor))
            local line_count = vim.api.nvim_buf_line_count(buffer)
            local stop_row_after = math.min(end_row + config.context_after,
                                            line_count - 1)
            local suffix = buffer_get_text(buffer, Region:new(aftercursor,
                                                              Pos:new0(
                                                                  stop_row_after,
                                                                  get_row_length(
                                                                      buffer,
                                                                      stop_row_after))))
            if prompt then
                -- Pass prompt with the prefix.
                prompt = prompt .. "\n\n" .. prefix
            else
                prompt = prefix
            end
            openai:completions({prompt = prompt, suffix = suffix})
        else
            -- Insert text generated from executing the prompt.
            if not prompt then
                config.error("empty prompt for :AI!")
            else
                openai:chat(prompt)
            end
        end
    end
end

return M
