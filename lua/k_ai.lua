-- Who had fun learning lua? This guy.
--
-- {{{1 config
---@class Config
---@field mock string?
---@field debug boolean
---
---@field cache_dir string
---@field chat_max_tokens integer
---@field chat_model string
---@field chat_temperature number
---@field completions_max_tokens integer
---@field context_after integer
---@field context_before integer
---@field edits_model string
---@field indicator_text string
---@field temperature number
---@field timeout integer Timeout in seconds
local config_defaults = {
    mock = nil,
    debug = false,
    --
    cache_dir = vim.fn.stdpath('cache') .. "/k_ai/",
    chat_max_tokens = 4000,
    chat_model = "gpt-3.5-turbo",
    chat_temperature = 0,
    completions_max_tokens = 2048,
    completions_model = "text-davinci-003",
    context_after = 20,
    context_before = 20,
    edits_model = "code-davinci-edit-001",
    indicator_text = "🤖",
    temperature = 0,
    timeout = 60
}

---@type Config
local config = setmetatable({}, {
    -- Dynamically get values from global options when evaluated.
    __index = function(_, key)
        return vim.g["ai_" .. key] or config_defaults[key]
    end
})

-- {{{1 utils

---@class Pos
---@field row integer 0 based
---@field col integer 0 based
local Pos = {}
Pos.__index = Pos

function Pos:new0(row, col)
    return setmetatable({row = row, col = col}, Pos):assert()
end

function Pos:assert()
    assert(self.row >= -1)
    assert(self.col >= 0)
    return self
end

---@param tbl_or_row integer[] | integer
---@param col nil | integer
function Pos:new10(tbl_or_row, col)
    local row
    if type(tbl_or_row) == "table" then
        row = tbl_or_row[1]
        col = tbl_or_row[2]
    else
        row = tbl_or_row
    end
    return self:new0(row - 1, col)
end
function Pos:get0() return {self.row, self.col} end
function Pos:get10() return {self.row + 1, self.col} end
---@param o Pos
function Pos:copy(o) return Pos:new0(o.row, o.col) end
function Pos:__tostring() return ("Pos{%d,%d}"):format(self.row, self.col) end
---@param o Pos
function Pos:__le(o)
    return (self.row < o.row) or (self.row == o.row and self.col <= o.col)
end

---@class Region
---@field start Pos
---@field stop Pos
local Region = {}
Region.__index = Region

---@param start Pos
---@param stop Pos
function Region.new(start, stop)
    return setmetatable({start = start, stop = stop}, Region):assert()
end

function Region:assert()
    self.start:assert()
    self.stop:assert()
    assert(self.start <= self.stop,
           ("start has to be before stop: start=%s stop=%s"):format(self.start,
                                                                    self.stop))
    return self
end

function Region:__tostring()
    return ("Region{%s,%s}"):format(self.start, self.stop)
end

function Region:height() return self.stop.row - self.start.row end

-- {{{1 my

---@class my My utils
local my = {}

my.prefix = "ai.vim: "

function my.get_row_length(buffer, row)
    return vim.api.nvim_buf_get_lines(buffer, row, row + 1, true)[1]:len()
end

---@returns string
function my.tostrings(...)
    local arg = {...}
    local txt = ""
    for i = 1, #arg do
        txt = txt .. (txt == "" and "" or " ") .. tostring(arg[i])
    end
    return txt
end

---@param fn function
function my.maybe_schedule(fn, ...)
    local arg = {...}
    if vim.in_fast_event() then
        vim.schedule(function() fn(unpack(arg)) end)
    else
        fn(unpack(arg))
    end
end

function my.is_vader_running() return vim.g['vader_bang'] ~= nil end

function my.error(...)
    if my.is_vader_running() then
        my.maybe_schedule(vim.fn['vader#log'], my.prefix .. my.tostrings(...))
    else
        my.maybe_schedule(vim.api.nvim_err_writeln,
                          my.prefix .. my.tostrings(...))
    end
end

function my.log(...)
    if my.is_vader_running() then
        my.maybe_schedule(vim.fn['vader#log'], my.prefix .. my.tostrings(...))
    else
        print(my.prefix .. my.tostrings(...))
    end
end

function my.debug(...) if config.debug then my.log(...) end end

function my.safe_close(handle)
    if handle and not vim.loop.is_closing(handle) then vim.loop.close(handle) end
end

---@class Buffer

-- {{{1 Indicator

local indicatorSign = "k_ai_indicator_sign"

---@class Indicator
---@field buffer Buffer
---@field reg Region Region to replace with text.
---@field signlist {}
---@field first boolean
local Indicator = {}
Indicator.__index = Indicator

---@param buffer Buffer
---@param reg Region
function Indicator.new(buffer, reg)
    return setmetatable({
        buffer = buffer,
        reg = reg,
        first = true,
        signlist = {}
    }, Indicator)
end

---@private
function Indicator:__tostring()
    return ("Indicator{%s,%s}"):format(self.buffer, self.reg)
end

function Indicator:on_start()
    vim.fn.sign_define(indicatorSign, {text = config.indicator_text})
    -- For the whole selection, place the signs.
    self:_place_signs(self.reg.start.row, self.reg.stop.row)
    vim.cmd.redraw()
end

---@param data string
function Indicator:on_data(data)
    -- On the first time they are not equal.
    if self.first then
        self.first = false
        -- Remove the signs placed on the whole selection above.
        self:_unplace_signs()
    end
    --
    local lines = vim.split(data, "\n")
    vim.api.nvim_buf_set_text(self.buffer, self.reg.start.row,
                              self.reg.start.col, self.reg.stop.row,
                              self.reg.stop.col, lines)
    -- Calculate new region stop with the filled text.
    local stop_row = self.reg.start.row + #lines - 1
    self.reg.stop = Pos:new0(stop_row, my.get_row_length(self.buffer, stop_row))
    self.reg:assert()
    -- Place new signs between start.row and stop.row if there were any newlines.
    self:_place_signs(self.reg.start.row, self.reg.stop.row)
    -- On the next loop, we will just append new characters. On the first one, we replace the region.
    self.reg.start = self.reg.stop
    -- Move cursor position to the end of the region to make it visible.
    vim.api.nvim_win_set_cursor(0, self.reg.stop:get10())
    vim.cmd.redraw()
end

---@private
function Indicator:_place_signs(start, stop)
    local toplace = {}
    for row = start, stop do
        table.insert(toplace, {
            buffer = self.buffer,
            group = indicatorSign,
            lnum = row + 1,
            name = indicatorSign
        })
    end
    local ret = vim.fn.sign_placelist(toplace)
    if ret ~= -1 then
        for _, v in pairs(ret) do
            table.insert(self.signlist,
                         {buffer = self.buffer, group = indicatorSign, id = v})
        end
    end
end

---@private
---@return boolean true if any signs were unplaced
function Indicator:_unplace_signs()
    local ret = self.signlist ~= {}
    vim.fn.sign_unplacelist(self.signlist)
    self.signlist = {}
    return ret
end

function Indicator:on_complete()
    if self:_unplace_signs() then vim.cmd.redraw() end
end

---@private
function Indicator:__gc() self:on_complete() end

-- {{{1 Tokenizer

local tok = {}

-- https://stackoverflow.com/questions/72294775/how-do-i-know-how-much-tokens-a-gpt-3-request-used

---@param nchars integer
---@return integer
function tok.nchars_to_ntokens_approx(nchars)
    local init_offset = 0
    -- returns an estimate of #tokens corresponding to #characters nchars
    return math.max(0, math.floor((nchars - init_offset) * math.exp(-1)))
end

-- {{{1 Chat

---@enum ChatRole Chat roles from OpenAI
local ChatRole = {assistant = "assistant", system = "system", user = "user"}

---@type integer
local chatFileVersion = 0

-- Global array of all chat messages in the "chat" format.
---@class Chat
---@field private ms {role: string, content: string}[]? Chat messages with ChatGPT
local chat = {}

---@type Chat
local chatDefault = {
    ms = {{role = ChatRole.system, content = "You are a helpful assistant."}}
}

---@param role ChatRole
---@param content string
function chat:append(role, content)
    -- Accumulate multiple assistant responses into single content.
    if self.ms[#self.ms].role == role then
        self.ms[#self.ms].content = self.ms[#self.ms].content .. content
    else
        assert(vim.tbl_contains(vim.tbl_values(ChatRole), role),
               vim.inspect(role) .. " is not in " .. vim.inspect(ChatRole))
        -- Otherwise, append new element.
        table.insert(self.ms, {role = role, content = content})
    end
end

---@param content string
function chat:append_user(content) self:append(ChatRole.user, content) end

---@return string?
function chat:last_assistant_character()
    if #self.ms ~= 0 and self.ms[#self.ms].role == ChatRole.assistant then
        return self.ms[#self.ms].content:sub(-1)
    end
end

function chat:tokens_cnt()
    local str = ""
    vim.tbl_map(function(v) str = str .. " " .. v.content end, self.ms)
    return tok.nchars_to_ntokens_approx(str:len())
end

---@param x integer
function chat:remove_cnt(x) for _ = 1, x do table.remove(self.ms, 1) end end

---@private
function chat:_trim_messages_to_tokens()
    assert(config.chat_max_tokens >= 0)
    if config.chat_max_tokens == 0 then return end
    while self:tokens_cnt() >= config.chat_max_tokens do self:remove_cnt(1) end
end

function chat:get_messages()
    self:_trim_messages_to_tokens()
    return self.ms
end

function chat:file() return config.cache_dir .. '/chat.json' end

--- Save chat history to file.
function chat:save()
    if config.mock then return end
    if vim.fn.isdirectory(config.cache_dir) == 0 then
        if vim.fn.mkdir(config.cache_dir, "p") == 0 then
            my.log("Cound not create directory to save chat messages " ..
                       config.cache_dir)
            return
        end
    end
    local file = io.open(self:file(), "w")
    if not file then
        my.log("could not save chat messages to " .. self:file())
        return
    end
    local serialized = {version = chatFileVersion, messages = self.ms}
    file:write(vim.json.encode(serialized))
    file:close()
    -- my.print("saved chat mesages to " .. self:file())
end

function chat:_load_in()
    if config.mock then return end
    local file = io.open(self:file(), "r")
    if not file then return end
    local success, serialized = pcall(vim.json.decode, file:read("*all"))
    if not success then
        my.error("Could not json decode file " .. self:file())
        return
    end
    file:close()
    if serialized.version ~= chatFileVersion then return end
    self.ms = serialized.messages
end

--- Loads chat messages history from file. Does it only once.
function chat:load()
    if not self.ms then
        chat:_load_in()
        if not self.ms then self.ms = chatDefault.ms end
    end
end

function chat:delete()
    if not vim.fn.filereadable(self:file()) then
        my.log("File " .. self:file() .. " does not exist.")
        return
    end
    if vim.fn.confirm("Do you really want to delete " .. self:file() .. "?") ==
        0 then return end
    if vim.fn.delete(self:file()) ~= 0 then
        my.log("Could not delete " .. self:file())
    else
        chat = {}
        my.log("Removed file " .. self:file())
    end
end

-- {{{1 Subprocess

---@class Subprocess
---@field private cmd string[] The command to run.
---@field private on_start fun(): nil
---@field private on_line fun(line: string): nil
---@field private on_end fun(code: integer, signal: integer, stderr: string): nil
Subprocess = {}
Subprocess.__index = Subprocess

---@param o {cmd: string[], on_start: (fun(): nil), on_line: (fun(line: string): nil), on_end: (fun(code: integer, signal: integer, stderr: string): nil)}
function Subprocess.run(o)
    assert(o.cmd)
    assert(o.on_start)
    assert(o.on_line)
    assert(o.on_end)
    setmetatable(o, Subprocess):do_run()
end

---@private
---@return Subprocess?
function Subprocess:do_run()
    local stdout = vim.loop.new_pipe()
    local stderr_acc = ""
    local stderr = vim.loop.new_pipe()
    self.handle, _ = vim.loop.spawn(self.cmd[1], {
        args = vim.list_slice(self.cmd, 2),
        stdio = {nil, stdout, stderr}
    }, function(code, signal)
        stdout:read_stop()
        stderr:read_stop()
        my.safe_close(stdout)
        my.safe_close(stderr)
        my.safe_close(self.handle)
        self.on_end(code, signal, stderr_acc)
        self.returncode = code
    end)
    if not self.handle then
        my.error(vim.inspect(self.cmd) .. " could not be started: " ..
                     vim.inspect(error))
        return
    end
    self.on_start()
    --
    local stdout_line = ""
    stdout:read_start(function(_, chunk)
        -- Read output line by line.
        if not chunk then return end
        stdout_line = stdout_line .. chunk
        local line_start, line_end = stdout_line:find("\n")
        while line_start do
            local oneline = stdout_line:sub(1, line_end - 1)
            stdout_line = stdout_line:sub(line_end + 1)
            if oneline ~= "" then self.on_line(oneline) end
            line_start, line_end = stdout_line:find("\n")
        end
    end)
    --
    stderr:read_start(function(_, chunk)
        -- Accumulate stderr into stderr_chunks.
        if not chunk then return end
        stderr_acc = stderr_acc .. chunk
    end)
    --
    local ended, _ = self:wait(config.timeout * 1000)
    if not ended then
        self:terminate()
        ended, _ = self:wait(500)
        if not ended then self:kill() end
    end
end

---@private
function Subprocess:poll() return self.returncode end

---@private
---@param timeout_ms integer
---@return boolean, integer See vim.wait doc.
function Subprocess:wait(timeout_ms)
    return vim.wait(timeout_ms, function() return self.returncode ~= nil end)
end

---@private
---@param sig integer
function Subprocess:send_signal(sig)
    if self.handle and not self.handle:is_closing() then
        self.handle:kill(sig)
    end
end

---@private
function Subprocess:terminate()
    local SIGTERM = 15
    self:send_signal(SIGTERM)
end

---@private
function Subprocess:kill()
    local SIGKILL = 9
    self:send_signal(SIGKILL)
end

---@private
function Subprocess:__gc() self:kill() end

-- {{{1 OpenAI

---@class Openai
---@field private cb Indicator
---@field private acc string
---@field private is_chat boolean
---@field private tokens integer
local Openai = {}
Openai.__index = Openai

---@param cb Indicator
---@return Openai
function Openai.new(cb)
    return
        setmetatable({cb = cb, acc = "", is_chat = false, tokens = 0}, Openai)
end

---@param cmd string[] The command to run.
function Openai:exe(cmd)
    Subprocess.run {
        cmd = cmd,
        on_start = function() self.cb:on_start() end,
        on_line = function(line) self:on_line(line) end,
        on_end = function(code, _, stderr)
            if code == 0 then
                self:on_end()
            else
                my.error(vim.inspect(cmd) .. " " .. stderr)
            end
            vim.schedule(function() self.cb:on_complete() end)
        end
    }
end

---Handle json decoding error or a good json response.
---@private
---@param txt string
function Openai:handle_response(txt)
    local success, json = pcall(vim.json.decode, txt)
    if not success then
        my.error("Could not decode json: " .. vim.inspect(txt))
    elseif type(json) ~= "table" then
        my.error("Not a JSON dictionary: " .. vim.inspect(txt))
    elseif json.error and type(json.error) == "table" and json.error.message then
        my.error(json.error.message)
    elseif not json.choices then
        my.error("No choices in response: " .. vim.inspect(txt))
    elseif json.choices[1].text then
        -- Response from completions and edits no-stream endpoint.
        self:on_data(json.choices[1].text)
    elseif json.choices[1].delta then
        -- Response from chat endpoint stream.
        if json.choices[1].delta.role then
            self.delta_role = json.choices[1].delta.role
        end
        if json.choices[1].delta.content then
            self.tokens = self.tokens + 1
            local content = json.choices[1].delta.content
            chat:append(self.delta_role, content)
            self:on_data(content)
        end
    elseif json.choices[1].message then
        -- Response from chat endpoint no-stream.
        local msg = json.choices[1].message
        chat:append(msg.role, msg.content)
        self:on_data(msg.content)
    else
        my.error("Could not parse response: " .. vim.inspect(txt))
    end
end

---@private
---@param line string
function Openai:on_line(line)
    my.debug("<", vim.inspect(line))
    if self.acc ~= "" or vim.startswith(vim.trim(line), "{") then
        -- This is an error response or not streaming response.
        self.acc = self.acc .. line
    elseif not vim.startswith(line, "data: ") then
        my.error("Response from API does not start with data: " ..
                     vim.inspect(line))
    else
        line = vim.trim(line:gsub("^data:", ""))
        -- [DONE] means end of parsing.
        if not line or line == "[DONE]" then return end
        self:handle_response(line)
    end
end

---@private
---@param txt string
function Openai:on_data(txt)
    my.maybe_schedule(function() self.cb:on_data(txt) end)
end

---@private
function Openai:on_end()
    if self.acc ~= "" then
        self:handle_response(self.acc)
    elseif self.is_chat then
        -- When using chat completion add an additional trailing newline to have the cursor ending on the next line.
        if chat:last_assistant_character() ~= "\n" then
            self:on_data("\n")
        end
    end
end

---@private
function Openai:mock_script()
    return {
        "sh", "-c", [[
        set -- $*
        if [ $# -eq 1 ]; then
            printf '{"choices":[{"text":"%s\\n"}]}\n' "$1"
        else
            for i; do
                sleep 1
                printf 'data: {"choices":[{"text":"%s\\n"}]}\n' "$i"
            done
            printf 'data: [DONE]\n'
        fi
        ]], "--", config.mock
    }
end

---@private
---@param endpoint string
---@param body {}
---@return string[]
function Openai._get_curl(endpoint, body)
    local api_key = os.getenv("OPENAI_API_KEY")
    assert(api_key, "$OPENAI_API_KEY environment variable must be set")
    my.debug(">", vim.inspect(endpoint), vim.inspect(body))
    local jsonbody = vim.json.encode(body)
    local curl = {
        "curl", "--silent", "--show-error", "--no-buffer", "--max-time",
        config.timeout, "-L", "-H", "Authorization: Bearer " .. api_key, "-X",
        "POST", "-H", "Content-Type: application/json", "-d", jsonbody,
        "https://api.openai.com/v1/" .. endpoint
    }
    return curl
end

---@private
---@param endpoint string
---@param body {}
function Openai:_request(endpoint, body)
    local curl = self._get_curl(endpoint, body)
    if config.mock then curl = self:mock_script() end
    self:exe(curl)
end

---Request OpenAI API for completions.
---@param body {prompt: string, suffix: nil | string}
function Openai:completions(body)
    body = vim.tbl_extend("keep", body, {
        model = config.completions_model,
        max_tokens = config.completions_max_tokens,
        temperature = config.temperature,
        stream = true
    })
    self:_request("completions", body)
end

---Request OpenAI API for edit.
---@param body {input: string, instruction: string}
function Openai:edits(body)
    body = vim.tbl_extend("keep", body, {temperature = config.temperature})
    self:_request("edits", body)
end

-- Use embeddings API to count the tokens in a string.
---@param txt string
---@return integer?
function Openai.embeddings_prompt_tokens(txt)
    local body = {model = "text-embedding-ada-002", input = txt}
    local curl = Openai._get_curl("embeddings", body)
    local acc = ""
    Subprocess.run {
        cmd = curl,
        on_start = function() end,
        on_line = function(line) acc = acc .. " " .. line end,
        on_end = function() end
    }
    local json = vim.json.decode(acc)
    return tonumber(json.usage.prompt_tokens)
end

---@param message string
---@param body {model: string}
function Openai:chat(message, body)
    self.is_chat = true
    chat:load()
    chat:append_user(message)
    body = vim.tbl_extend("keep", body, {
        messages = chat:get_messages(),
        temperature = config.chat_temperature,
        stream = true
    })
    self:_request("chat/completions", body)
    chat:save()
end

-- {{{1 Cmd object

---@class Args
---@field args string
---@field range integer
---@field line1 integer
---@field line2 integer
---@field bang boolean
---@field count integer
---@field fargs string[]

---@class Cmd
---@field args Args
---@field buffer Buffer
---@field selection Region? Selected region, if any
---@field prompt string?
Cmd = {}
Cmd.__index = Cmd

---@param args Args
---@return Cmd
function Cmd.new(args)
    local self = setmetatable({
        args = args,
        prompt = (args.args and args.args ~= "") and args.args or nil,
        buffer = vim.api.nvim_get_current_buf()
    }, Cmd)
    local buffer_is_modifiable = vim.api.nvim_buf_get_option(self.buffer,
                                                             'modifiable')
    assert(buffer_is_modifiable, "Buffer is not modifiable")
    self.selection = self:_get_selection()
    return self
end

---@param row integer
function Cmd:get_row_length(row) return my.get_row_length(self.buffer, row) end

-- Get the text from the buffer between the start and end points.
---@param reg Region
---@return string
function Cmd:buffer_get_text(reg)
    return table.concat(vim.api.nvim_buf_get_text(self.buffer, reg.start.row,
                                                  reg.start.col, reg.stop.row,
                                                  reg.stop.col, {}), "\n")
end

-- Parse command arguments and return the selected region, either visual selection or range passed to command.
---@private
---@return nil | Region
function Cmd:_get_selection()
    local args = self.args
    local buffer = self.buffer
    if args.range == 2 then
        local start = Pos:new10(vim.api.nvim_buf_get_mark(buffer, "<"))
        local stop = Pos:new10(vim.api.nvim_buf_get_mark(buffer, ">"))
        -- If last selection was line or character based and the range
        -- passed to args match the selection, then use selection,
        -- otherwise use range.
        local use_visual = vim.fn.visualmode():lower() == 'v' and start.row ==
                               args.line1 and stop.row == self.args.line2
        if use_visual then
            -- Visual selection mode.
            -- Limit col positions, nvim_buf_get_mark outputs end of universe.
            local end_line_length = self:get_row_length(stop.row)
            stop.col = math.min(stop.col, end_line_length)
        else
            -- Range mode, take whole lines.
            start = Pos:new10(args.line1, 0)
            stop = Pos:new10(args.line2, self:get_row_length(args.line2 - 1))
        end
        return Region.new(start, stop)
    end
end

-- Extract context before and after cursor.
---@return string, string
function Cmd:get_context(cursor)
    local selection = self.selection
    local args = self.args
    local before, after
    if selection then
        before = Region.new(selection.start, cursor)
        after = Region.new(cursor, selection.stop)
    else
        local one_arg = args.range == 1 and args.count or nil
        local context_before = one_arg or config.context_before
        local context_after = one_arg or config.context_after
        --
        local start_row = math.max(0, cursor.row - context_before)
        before = Region.new(Pos:new0(start_row, 0), cursor)
        --
        local buffer_line_count = vim.api.nvim_buf_line_count(self.buffer)
        local stop_row = math.min(cursor.row + context_after,
                                  buffer_line_count - 1)
        local stop_row_length = self:get_row_length(stop_row)
        local stop_pos = Pos:new0(stop_row, stop_row_length)
        after = Region.new(cursor, stop_pos)
    end
    my.log(
        ("Genering completion from %d lines above and %d lines below"):format(
            before:height(), after:height()))
    local prefix = self:buffer_get_text(before)
    local suffix = self:buffer_get_text(after)
    return prefix, suffix
end

---@return Pos Position of the cursor.
function Cmd:get_cursor()
    local o = Pos:new10(vim.api.nvim_win_get_cursor(0))
    -- Get the position after cursor.
    -- If the current line is empty, then the cursor starts at zero position.
    -- If the current line is not empty, start with the place _after_ the cursor.
    if self:get_row_length(o.row) ~= 0 then o.col = o.col + 1 end
    return o
end

---@param replace Region to replace when starting writing to buffer.
---@returns Openai
function Cmd:openai(replace)
    return Openai.new(Indicator.new(self.buffer, replace))
end

-- {{{1 M.AI

---@class M
local M = {}

local function AIModel(args, model)
    local cmd = Cmd.new(args)
    assert(not cmd.selection, "Chat does not take selection")
    assert(cmd.prompt, "Prompt is missing")
    local cursor = cmd:get_cursor()
    local replace = Region.new(cursor, cursor)
    cmd:openai(replace):chat(cmd.prompt, {model = model})
end

function M.AI(args) AIModel(args, "gpt-3.5-turbo") end

function M.AI4(args) AIModel(args, "gpt-4") end

function M.AIAdd(args)
    local cmd = Cmd.new(args)
    local cursor = cmd:get_cursor()
    local replace = Region.new(cursor, cursor)
    local prefix, suffix = cmd:get_context(cursor)
    if cmd.prompt then
        -- Prefix the selection with "prompt ```<filetype>".
        local filetype = vim.api.nvim_buf_get_option(cmd.buffer, "filetype")
        local promptnl = cmd.prompt .. "\n\n```" .. filetype .. "\n"
        prefix = promptnl .. prefix
    end
    -- print(vim.inspect(prefix), vim.inspect(suffix))
    cmd:openai(replace):completions({prompt = prefix, suffix = suffix})
end

local function AIEditModel(args, model)
    local cmd = Cmd.new(args)
    local prompt = cmd.prompt
    local selection = cmd.selection
    assert(selection, "Command requires a selection")
    assert(prompt, "Command requires instruction how to edit")
    local selected_text = cmd:buffer_get_text(selection)
    assert(selected_text ~= "", "Selected text is empty")
    cmd:openai(selection):edits({
        model = model,
        input = selected_text,
        instruction = prompt
    })
end

function M.AIEdit(args) AIEditModel(args, config.edits_model) end
function M.AIEditCode(args) AIEditModel(args, "code-davinci-edit-001") end
function M.AIEditText(args) AIEditModel(args, "text-davinci-edit-001") end

function M.AIChatHistory(_)
    chat:load()
    local ms = chat:get_messages()
    local str = ""
    for _, v in pairs(ms) do str = str .. " " .. v.content end
    print(
        ("Number of messages: %d   Approx number of tokens: %s   Number of tokens from embeddings api: %s \n "):format(
            #ms, chat:tokens_cnt(), Openai.embeddings_prompt_tokens(str)))
    for _, v in pairs(ms) do
        print(("%s(%s): %s%s"):format(v.role, tok.nchars_to_ntokens_approx(
                                          v.content:len()), v.content, v.role ==
                                          ChatRole.assistant and "\n " or ""))
    end
end

---@param args Args
function M.AIChatZDelete(args)
    local arg = args.fargs[1]
    if arg == "file" then
        chat:delete()
    else
        local n = tonumber(arg)
        if n and n > 0 then
            chat:remove_cnt(n)
        else
            my.error("Invalid argument: " .. vim.inspect(arg) ..
                         ". It has to be a positive number or string 'file'.")
        end
    end
end

return M

-- }}}

-- vim: foldmethod=marker
