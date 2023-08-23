-- Who had fun learning lua? This guy.
--
-- {{{1 config
--
---@class Config
---@field mock string?
---@field debug boolean
---
---@field cache_dir string The cache dir used to store conversations history.
---@field chat_use string The current conversation chat to use.
---@field chat_max_tokens integer The maximum number of tokens to send to chat/completions API. There is a limit in the API.
---@field chat_temperature number The temperature option when talking to chat/completions API.
---@field completions_max_tokens integer The maximum number of tokens to send to completions API.
---@field context_after integer The default number of lines to send to completions API after cursor.
---@field context_before integer The default number of lines to send to completione API before cursor.
---@field indicator_text string The indication to show on the indication panel when working.
---@field temperature number The temperature to send to other apis except chat/completions API.
---@field timeout integer Timeout of curl in seconds.
local config_defaults = {
	mock = "",
	debug = false,
	--
	cache_dir = vim.fn.stdpath("cache") .. "/kai/",
	chat_use = "default",
	chat_max_tokens = 4000,
	chat_temperature = 0,
	completions_max_tokens = 2048,
	completions_model = "text-davinci-003",
	context_after = 20,
	context_before = 20,
	indicator_text = "🤖",
	temperature = 0,
	timeout = 1200,
}

---@type Config
local config = setmetatable({}, {
	-- Dynamically get values from global options when evaluated.
	__index = function(_, key)
		local ret = vim.g["kai_" .. key] or config_defaults[key]
		assert(ret ~= nil, sprintf("Internal error: There is no such key in config: %s %s", key, ret))
		return ret
	end,
})

-- }}}
-- {{{1 my

---@class my My utils
local my = {}

my.prefix = "kai.nvim: "

my.modifiable = "modifiable"
my.filetype = "kai_chat"

---@alias Buffer integer

---@param buffer Buffer | integer
---@param row integer
---@returns integer
function my.get_row_length(buffer, row)
	return vim.api.nvim_buf_get_lines(buffer, row, row + 1, true)[1]:len()
end

---@returns string
function my.tostrings(...)
	local arg = { ... }
	local txt = ""
	for i = 1, #arg do
		txt = txt .. (txt == "" and "" or " ") .. tostring(arg[i])
	end
	return txt
end

---@param fn function
function my.maybe_schedule(fn, ...)
	local arg = { ... }
	if vim.in_fast_event() then
		vim.schedule(function()
			fn(unpack(arg))
		end)
	else
		fn(unpack(arg))
	end
end

---@return boolean
function my.is_vader_running()
	return vim.g["vader_bang"] ~= nil
end

---@param fmt string
function my.error(fmt, ...)
	local txt = my.prefix .. fmt:format(...)
	if my.is_vader_running() then
		my.maybe_schedule(vim.fn["vader#log"], txt)
	else
		my.maybe_schedule(vim.api.nvim_err_writeln, txt)
	end
end

---@param fmt string
function my.log(fmt, ...)
	local txt = my.prefix .. fmt:format(...)
	if my.is_vader_running() then
		my.maybe_schedule(vim.fn["vader#log"], txt)
	else
		print(txt)
	end
end

function my.debug(...)
	if config.debug then
		my.log(...)
	end
end

function my.safe_close(handle)
	if handle and not vim.loop.is_closing(handle) then
		vim.loop.close(handle)
	end
end

---@param fn function
function my.pcallprint(fn, ...)
	local status, err = pcall(fn, unpack({ ... }))
	if not status then
		my.error("%s\n%s", err, debug.traceback())
	end
	return status, err
end

---@param str string
function my.isempty(str)
	return str == nil or str == ""
end

---@param fmt string
---@return string
---@diagnostic disable: lowercase-global
sprintf = function(fmt, ...)
	return fmt:format(...)
end

---@param arr any[][]
---@param format string[]?
---@return string
function my.tabularize(arr, format)
	local sizes = {}
	for _, row in ipairs(arr) do
		for i, v in ipairs(row) do
			sizes[i] = math.max(sizes[i] or 0, tostring(v):len())
		end
	end
	local txt = ""
	for _, row in ipairs(arr) do
		for i, v in ipairs(row) do
			txt = txt
				.. (i ~= 1 and " " or "")
				.. sprintf("%" .. (format ~= nil and format[i] or "") .. tostring(sizes[i]) .. "s", tostring(v))
		end
		txt = txt .. "\n"
	end
	return txt
end

---@param str string
---@return string[]
function my.splitlines(str)
	return vim.split(str, "\n", { plain = true })
end

-- }}}
-- {{{1 Pos

---@class Pos
---@field row integer 0 based
---@field col integer 0 based
local Pos = {}
Pos.__index = Pos

---@param row integer
---@param col integer
---@return Pos
function Pos.new0(row, col)
	return setmetatable({ row = row, col = col }, Pos):assert()
end

---@return Pos
function Pos:assert()
	assert(self.row >= -1)
	assert(self.col >= 0)
	return self
end

---@param rowcol integer[]
---@return Pos
function Pos.new10arr(rowcol)
	return Pos.new0(rowcol[1] - 1, rowcol[2])
end

---@param row integer
---@param col integer
---@return Pos
function Pos.new10(row, col)
	return Pos.new0(row - 1, col)
end

---@return {[1]: integer, [2]: integer}
function Pos:get0()
	return { self.row, self.col }
end

---@return {[1]: integer, [2]: integer}
function Pos:get10()
	return { self.row + 1, self.col }
end

---@param o Pos
---@return Pos
function Pos:copy(o)
	return Pos.new0(o.row, o.col)
end

---@return string
function Pos:__tostring()
	return sprintf("Pos{%d,%d}", self.row, self.col)
end

---@return boolean
---@param o Pos
function Pos:__le(o)
	return (self.row < o.row) or (self.row == o.row and self.col <= o.col)
end

---@param buffer Buffer
---@return Pos
function Pos.buffer_end(buffer)
	local row = vim.api.nvim_buf_line_count(buffer)
	return Pos.new10(row, my.get_row_length(buffer, row - 1))
end

function Pos:set_cursor(window)
	vim.api.nvim_win_set_cursor(window, self:get10())
end

-- }}}
-- {{{1 Region

---@class Region
---@field start Pos
---@field stop Pos
local Region = {}
Region.__index = Region

---@param start Pos
---@param stop Pos
function Region.new(start, stop)
	return setmetatable({ start = start, stop = stop }, Region):assert()
end

function Region:assert()
	self.start:assert()
	self.stop:assert()
	assert(self.start <= self.stop, sprintf("start has to be before stop: start=%s stop=%s", self.start, self.stop))
	return self
end

function Region:__tostring()
	return sprintf("Region{%s,%s}", self.start, self.stop)
end

---@param buffer Buffer
function Region.buffer(buffer)
	return Region.new(Pos.new0(0, 0), Pos.buffer_end(buffer))
end

-- }}}
-- {{{1 BufferN

---@class BufferN
---@field v integer
BufferN = {}
BufferN.__index = BufferN
setmetatable(BufferN, {
	__call = function(cls, ...)
		return cls.new(...)
	end,
})

function BufferN.new(v)
	assert(type(v) == "number", "v has type " .. type(v))
	return setmetatable({ v = v }, BufferN)
end

function BufferN:line_count()
	return vim.api.nvim_buf_line_count(self.v)
end

---@param row integer
---@returns integer
function BufferN:get_row_length(row)
	return vim.api.nvim_buf_get_lines(self.v, row, row + 1, true)[1]:len()
end

---@generic T
---@param option string
---@param set T?
---@return T?
function BufferN:option(option, set)
	if set ~= nil then
		vim.api.nvim_buf_set_option(self.v, option, set)
	else
		return vim.api.nvim_buf_get_option(self.v, option)
	end
end

---@param set boolean?
---@return boolean?
function BufferN:modifiable(set)
	return self:option("modifiable", set)
end

---@return Pos
function BufferN:endpos()
	local row = vim.api.nvim_buf_line_count(self.v)
	return Pos.new10(row, self:get_row_length(row - 1))
end

---@return Region
function BufferN:region()
	return Region.new(Pos.new0(0, 0), self:endpos())
end

---@param reg Region
---@param lines string[]
function BufferN:set_text(reg, lines)
	vim.api.nvim_buf_set_text(self.v, reg.start.row, reg.start.col, reg.stop.row, reg.stop.col, lines)
end

---@param name string
---@return Pos
function BufferN:get_mark(name)
	return Pos.new10arr(vim.api.nvim_buf_get_mark(self.v, name))
end

-- Get the text from the buffer between the start and end points.
---@param reg Region
---@return string
function BufferN:get_text(reg)
	return table.concat(
		vim.api.nvim_buf_get_text(self.v, reg.start.row, reg.start.col, reg.stop.row, reg.stop.col, {}),
		"\n"
	)
end

---@return boolean
function BufferN:ischatbuffer()
	local filetype = vim.api.nvim_buf_get_option(self.v, "filetype")
	return filetype == my.filetype
end

function BufferN:chatbuffermodify()
	if self:ischatbuffer() then
		vim.api.nvim_buf_set_option(self.v, "modifiable", true)
	end
end

function BufferN:chatbufferunmodify()
	if self:ischatbuffer() then
		vim.api.nvim_buf_set_option(self.v, "modifiable", false)
	end
end

-- }}}
-- {{{1 Subprocess

---@class Subprocess
---Mimics python subprocess module.
---@field private cmd string[] The command to run.
---@field private on_start fun(): nil
---@field private on_line fun(line: string, handle: Subprocess): nil
---@field private on_exit fun(code: integer, signal: integer, stderr: string): nil
Subprocess = {}
Subprocess.__index = Subprocess

---@class SubprocessParam
---Parameters to construct a subprocess.
---@field cmd string[] The command to run.
---@field on_start nil | fun(): nil
---@field on_line nil | fun(line: string, handle: Subprocess): nil
---@field on_exit nil | fun(code: integer, signal: integer, stderr: string): nil

---@param o SubprocessParam
---@return integer? nil if not run, otherwise the exit status of the process
function Subprocess.spawn(o)
	assert(o.cmd)
	local self = setmetatable({
		cmd = o.cmd,
		on_start = o.on_start or function() end,
		on_line = o.on_line or function() end,
		on_exit = o.on_exit or function() end,
	}, Subprocess)
	return self:_do_run()
end

---@param cmd string[]
---@return string
function Subprocess.call_output(cmd)
	local out = ""
	Subprocess.spawn({
		cmd = cmd,
		on_line = function(line)
			out = out .. (out == "" and "" or "\n") .. line
		end,
	})
	return out
end

---@private
---@return integer?
function Subprocess:_do_run()
	local stdout = vim.loop.new_pipe()
	local stdout_line = ""
	local stderr_acc = ""
	local stderr = vim.loop.new_pipe()
	local pid_or_error
	self.handle, pid_or_error = vim.loop.spawn(self.cmd[1], {
		args = vim.list_slice(self.cmd, 2),
		stdio = { nil, stdout, stderr },
	}, function(code, signal)
		stdout:read_stop()
		stderr:read_stop()
		my.safe_close(stdout)
		my.safe_close(stderr)
		my.safe_close(self.handle)
		if stdout_line and stdout_line ~= "" then
			self.on_line(stdout_line, self)
		end
		self.on_exit(code, signal, stderr_acc)
		self.returncode = code
	end)
	if not self.handle then
		local error = pid_or_error
		my.error("%s could not be started: %s", vim.inspect(self.cmd), error)
		return nil
	end
	self.on_start()
	--
	stdout:read_start(function(_, chunk)
		-- Read output line by line.
		if not chunk then
			return
		end
		stdout_line = stdout_line .. chunk
		local line_start, line_end = stdout_line:find("\n")
		while line_start do
			local oneline = stdout_line:sub(1, line_end - 1)
			stdout_line = stdout_line:sub(line_end + 1)
			if oneline ~= "" then
				-- If there is an error in the callback, terminate.
				if not my.pcallprint(self.on_line, oneline, self) then
					self:terminate()
				end
			end
			line_start, line_end = stdout_line:find("\n")
		end
	end)
	--
	stderr:read_start(function(_, chunk)
		-- Accumulate stderr into stderr_chunks.
		if not chunk then
			return
		end
		stderr_acc = stderr_acc .. chunk
	end)
	--
	local ended, _ = self:_wait(config.timeout * 1000)
	if not ended then
		self:terminate()
		ended, _ = self:_wait(500)
		if not ended then
			self:_kill()
		end
	end
	return self.returncode
end

---@private
function Subprocess:_poll()
	return self.returncode
end

---@private
---@param timeout_ms integer
---@return boolean, integer See vim.wait doc.
function Subprocess:_wait(timeout_ms)
	return vim.wait(timeout_ms, function()
		return self.returncode ~= nil
	end)
end

---@private
---@param sig integer
function Subprocess:_send_signal(sig)
	if self.handle and not self.handle:is_closing() then
		self.handle:kill(sig)
	end
end

function Subprocess:terminate()
	local SIGTERM = 15
	self:_send_signal(SIGTERM)
end

---@private
function Subprocess:_kill()
	local SIGKILL = 9
	self:_send_signal(SIGKILL)
end

---@private
function Subprocess:__gc()
	self:_kill()
end

-- }}}
-- {{{1 Tokenizer

---@class Tokenizer
local tok = {}

-- Return the number of tokens in a string.
-- One token is defined as in OpenAI api, see https://platform.openai.com/tokenizer
-- https://stackoverflow.com/questions/72294775/how-do-i-know-how-much-tokens-a-gpt-3-request-used
---@param str string
---@return integer
function tok.count_approx(str)
	-- Count the number of words in str. One word is anything separated by spaces.
	local nwords = 0
	for _ in str:gmatch("%S+") do
		nwords = nwords + 1
	end
	-- Calculate the offset for the initial token.
	local init_offset = math.max(0, math.floor(nwords * 0.5))
	-- Calculate the number of tokens.
	-- returns an estimate of #tokens corresponding to #characters nchars
	local scale = 1.2
	local ret = (str:len() - init_offset) * math.exp(-1) * scale
	return math.max(0, math.floor(ret))
end

---@private
function tok.has_tiktoken()
	if vim.g.ai_has_tiktoken == nil then
		vim.g.ai_has_tiktoken = os.execute('python3 -c "import tiktoken"') == 0
	end
	return vim.g.ai_has_tiktoken
end

---@param str string
---@return integer
---@private
function tok.ntokens_tiktoken(str)
	local ret = Subprocess.call_output({
		"python3",
		"-c",
		"import sys,tiktoken;print(len(tiktoken.encoding_for_model(sys.argv[1]).encode(sys.argv[2])))",
		"gpt-4",
		str,
	})
	return tonumber(ret) or 0
end

---@return boolean
function tok.has_perl()
	return vim.fn.executabe("perl")
end

---@param str string
---@param regex string
---@return integer
function tok.count_perl(str, regex)
	--https://community.openai.com/t/what-is-the-openai-algorithm-to-calculate-tokens/58237/33
	--print join("|", @count), "\n";
	local perlscript = [=[
	    local @count = $ARGV[1] =~ /$ARGV[0]/g;
        print scalar @count;
    ]=]
	local out = Subprocess.call_output({
		"perl",
		"-e",
		perlscript,
		regex,
		str,
	})
	if false then
		my.log("perl %s", out:gsub("\n", " \\n "))
		out = out:gsub("^[^\n]*\n", "")
	end
	return tonumber(out) or 0
end

---@param str string
---@param pattern string
---@return integer
function tok.count_vim(str, pattern)
	if false then
		local out2 = vim.fn.substitute(str, pattern, "&|", "g")
		my.log("vim %s", out2)
	end
	local out = vim.fn.substitute(str, pattern, "1", "g")
	return out:len()
end

---@param str string
---@return integer
function tok.count_perl_r50k_base(str)
	return tok.count_perl(str, [=['s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+]=])
end

---@param str string
---@return integer
function tok.count_vim_r50k_base(str)
	--Converted from perl regex above.
	return tok.count_vim(
		str,
		[=[\('s\|'t\|'re\|'ve\|'m\|'ll\|'d\| \?[[:alpha:]]\+\| \?[[:digit:]]\+\| \?[^\s[:alnum:]]\+\|\s\+\S\@!\|\s\+\)]=]
	)
end

---@param str string
---@return integer
function tok.count_perl_cl100k_base(str)
	return tok.count_perl(
		str,
		[=[(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+]=]
	)
end

---@param str string
---@return integer
function tok.count_vim_cl100k_base(str)
	--Converted from perl regex above.
	return tok.count_vim(
		str,
		[=[\c\('s\|'t\|'re\|'ve\|'m\|'ll\|'d\|[^\r\n[:alnum:]]\?[[:alpha:]]\+\|[[:digit:]]\{1,3}\| \?[^\s[:alnum:]]\+[\r\n]*\|\s*[\r\n]\+\|\s\+\S\@!\|\s\+\)]=]
	)
end

---@param str string
---@return integer
function tok.ntokens(str)
	return tok.count_vim_cl100k_base(str)
end

---@param messages ChatMsg[]
---@return integer
function tok.num_tokens_from_messages(messages)
	-- based on num_tokens_from_messages from
	-- https://github.com/openai/openai-cookbook/blob/main/examples/How_to_count_tokens_with_tiktoken.ipynb
	local tokens_per_message = 3
	-- every reply is primed with <|start|>assistant<|message|>
	local num_tokens = 3
	for _, m in ipairs(messages) do
		num_tokens = num_tokens + tokens_per_message + tok.ntokens(m.role) + tok.ntokens(m.content)
	end
	return num_tokens
end

-- Returns number of most recent messages with number of tokens lower than max.
---@param messages ChatMsg[]
---@param max integer
---@return ChatMsg[]
function tok.trim_messages_to_num_tokens(messages, max)
	assert(#messages > 1)
	-- based on the above num_tokens_from_messages
	-- assuming not gpt-3.5-turbo-0301
	-- every message follows <|start|>{role/name}\n{content}<|end|>\n
	local tokens_per_message = 3
	-- every reply is primed with <|start|>assistant<|message|>
	local num_tokens = 3
	local ret = {}
	-- Always include the system message
	local loopstartidx = 1
	if messages[1].role == "system" then
		m = messages[1]
		loopstartidx = 2
		table.insert(ret, m)
		num_tokens = num_tokens + tokens_per_message + tok.ntokens(m.role) + tok.ntokens(m.content)
	end
	for i = #messages, loopstartidx, -1 do
		local m = messages[i]
		num_tokens = num_tokens + tokens_per_message + tok.ntokens(m.role) + tok.ntokens(m.content)
		if num_tokens >= max then
			break
		end
		table.insert(ret, loopstartidx, m)
	end
	return ret
end

---@param func fun(string): integer
---@return string
function tok.get_func_name(func)
	local info = debug.getinfo(func)
	if info.name then
		return info.name
	end
	local source = info.source:gsub("^@", "")
	local f = io.open(source, "r")
	assert(f)
	local count = 1
	for line in f:lines() do
		if count == info.linedefined then
			f:close()
			return line:gsub([[function *tok.count_]], ""):gsub("[(].*$", "")
		end
		count = count + 1
	end
	f:close()
	error("not enough lines in file")
end

---@param func fun(string): integer
---@param str string
---@param val integer
---@return integer
function tok._test(func, str, val)
	local res = func(str)
	local name = tok.get_func_name(func)
	local err = res ~= val
	local pre = err and "DIFF:" or ""
	local eq = err and "!=" or "=="
	local desc = sprintf("%5s %18s(%q) = %d %s %d", pre, name, str, res, eq, val)
	my.log("%s", desc)
	return err and 1 or 0
end

function tok.test()
	---@type {[1]: string, [2]: integer}[]
	local tests = {
		{ " a", 1 },
		{ "a ", 2 },
		{ "a b", 2 },
		{ "a b ", 3 },
		{ "a b c", 3 },
		{ "12345647657", 5 },
		{ "abcdef 12345647657 ;',./pl[flewq'l abc'l", 21 },
		{ "You miss 100% of the shots you don't take", 13 },
		{ "You miss 100% of the shots you don’t take", 13 },
	}
	---@type (fun(string): integer)[]
	local backends = {
		tok.count_approx,
		tok.count_perl_cl100k_base,
		tok.count_vim_cl100k_base,
		tok.count_perl_r50k_base,
		tok.count_vim_r50k_base,
	}
	local errors = 0
	for _, test in ipairs(tests) do
		for _, backend in ipairs(backends) do
			errors = errors + tok._test(backend, test[1], test[2])
		end
	end
	assert(errors == 0)
end

-- }}}
-- {{{1 ChatRole

---@enum ChatRole Chat roles from OpenAI
local ChatRole = { assistant = "assistant", system = "system", user = "user" }

---@param str string
---@return boolean
function ChatRole.is(str)
	return vim.tbl_contains(vim.tbl_values(ChatRole), str)
end

---@type integer
ChatRole.maxlen = ChatRole.assistant:len()

local chatRoles = { ChatRole.assistant, ChatRole.system, ChatRole.user }

-- }}}
-- {{{1 Chat

---@class ChatMsg
---@field role ChatRole
---@field content string

---@class ChatFile
---@field version integer
---@field messages ChatMsg[]

---@param role string
---@param content string
---@return ChatMsg
function ChatMsg(role, content)
	return { role = role, content = content }
end

---@class Chat Global array of all chat messages in the "chat" format.
---@field name string
---@field ms ChatMsg[] Chat messages with ChatGPT
local Chat = {}
Chat.__index = Chat

---@type string
local chatDefaultInitMsg = "You are a helpful assistant."

-- Chat constructor
---@param name string
---@param initmsg string?
---@return Chat
function Chat.new(name, initmsg)
	assert(name:find("/") == nil, "Chat name can't contain /: " .. name)
	return setmetatable({
		name = name,
		ms = { ChatMsg(ChatRole.system, initmsg or chatDefaultInitMsg) },
	}, Chat)
end

-- Append a new message to chat.
---@param role ChatRole
---@param content string
function Chat:append(role, content)
	-- Accumulate multiple assistant responses into single content.
	if self.ms[#self.ms].role == role then
		self.ms[#self.ms].content = self.ms[#self.ms].content .. content
	else
		assert(ChatRole.is(role), vim.inspect(role) .. " is not in " .. vim.inspect(ChatRole))
		-- Otherwise, append new element.
		table.insert(self.ms, ChatMsg(role, content))
	end
end

-- Append a message from the user to chat.
---@param content string
function Chat:append_user(content)
	self:append(ChatRole.user, content)
end

-- Get last character sent by assistant.
---@return string?
function Chat:last_assistant_character()
	if #self.ms ~= 0 and self.ms[#self.ms].role == ChatRole.assistant then
		return self.ms[#self.ms].content:sub(-1)
	end
end

-- Get messages trimmed to config.chat_max_tokens tokens.
---@return ChatMsg[]
function Chat:get_trimmed_messages()
	assert(config.chat_max_tokens >= 0)
	local ms = tok.trim_messages_to_num_tokens(self.ms, config.chat_max_tokens)
	assert(#ms > 0, "Your query was longer that the g:kai_chat_max_tokens!")
	return ms
end

-- Get the system message chat was started with.
---@return string?
function Chat:get_system_message()
	for _, v in ipairs(self.ms) do
		if v.role == ChatRole.system then
			return v.content
		end
	end
end

-- Return the global number of tokens in all messages.
---@return integer
function Chat:ntokens()
	return tok.num_tokens_from_messages(self.ms)
end

-- Convert chat to text for the use of chat window.
---@return string
function Chat:to_text()
	local names = {
		[ChatRole.system] = "SY",
		[ChatRole.assistant] = "AI",
		[ChatRole.user] = "ME",
	}
	local data = "Chat name=" .. self.name .. " file=" .. self:file() .. "\n"
	for _, msg in ipairs(self.ms) do
		local ntokens = tok.ntokens(msg.content) + 3
		local new = sprintf("%2s: %s\n", names[msg.role], msg.content)
		data = data .. new
	end
	return data
end

---@param buffer integer
---@param ending string?
function Chat:show_chat(buffer, ending)
	buffer = buffer or 0
	local text = self:to_text():sub(1, -2) .. (ending or "\n")
	local lines = my.splitlines(text)
	vim.api.nvim_buf_set_lines(buffer, 0, -1, true, lines)
	vim.api.nvim_win_set_buf(0, buffer)
	vim.api.nvim_win_set_cursor(0, { #lines, my.get_row_length(buffer, #lines - 1) })
end

-- Shows the string ME: on the end of buffer. Synchronize with to_text.
---@param buffer integer
function Chat.show_m_e(buffer)
	local bufferend = Pos.buffer_end(buffer)
	vim.api.nvim_buf_set_text(buffer, bufferend.row, bufferend.col, bufferend.row, bufferend.col, { "ME: " })
	Pos.buffer_end(buffer):set_cursor(0)
end

-- }}}
-- {{{1 Chat file ops

---@type integer
local chatFileVersion = 1

-- The file where chat is saved, static version.
---@private
---@return string
function Chat._file(name)
	return vim.fn.simplify(sprintf("%s/chat-%s.json", config.cache_dir, name))
end

-- The file where the chat is saved.
---@return string
function Chat:file()
	return Chat._file(self.name)
end

-- Internal function for loading the chat from file
-- Returns tuple of optional error message and optional chat messages.
---@private
---@param filename string
---@return string?, ChatMsg[]?
function Chat._load(filename)
	local file = io.open(filename, "r")
	if not file then
		return nil, nil
	end
	local success, serialized = pcall(vim.json.decode, file:read("*all"))
	if not success then
		return "json decode error"
	end
	file:close()
	if serialized.version ~= chatFileVersion then
		return sprintf("version %s != %d", tostring(serialized.version), chatFileVersion)
	end
	---@type ChatMsg[]
	local ms = serialized.ms
	if ms == nil or type(ms) ~= "table" or #ms == 0 then
		return sprintf("invalid content ms=%s", vim.inspect(serialized.ms))
	end
	for i, v in ipairs(serialized.ms) do
		if
			v.content == nil
			or type(v.content) ~= "string"
			or v.role == nil
			or type(v.role) ~= "string"
			or not ChatRole.is(v.role)
		then
			return sprintf("invalid message number %d in file=%s", i, filename)
		end
	end
	return nil, ms
end

-- Loads chat messages history from file.
-- Constructor
---@param name string
function Chat.load(name)
	Chat.assert_exists(name)
	local ret = Chat.new(name)
	local filename = Chat._file(name)
	local err, ms = Chat._load(filename)
	if ms == nil and err == nil then
		my.log("Started new chat at %s", filename)
	elseif err ~= nil then
		my.error("Error loading file %s: %s", filename, err)
	end
	if ms ~= nil then
		ret.ms = ms
	end
	return ret
end

-- Asserts that a chat with name exists.
function Chat.assert_exists(name)
	assert(
		vim.tbl_contains(Chat.listnames(), name),
		sprintf("There is no chat with name %s at %s", name, config.cache_dir)
	)
end

---@private
---@return ChatFile
function Chat:_serialize()
	return { version = chatFileVersion, ms = self.ms }
end

--- Save chat history to file.
---@return boolean
function Chat:save()
	if config.mock ~= "" then
		return true
	end
	if vim.fn.isdirectory(config.cache_dir) == 0 then
		if vim.fn.mkdir(config.cache_dir, "p") == 0 then
			my.log("Cound not create directory to save chat messages %s", config.cache_dir)
			return false
		end
	end
	-- Save to temporary file
	local tmpfile = self:file() .. ".tmp"
	local file = io.open(tmpfile, "w")
	if not file then
		my.log("could not save chat messages to %s", self:file())
		return false
	end
	file:write(vim.json.encode(self:_serialize()))
	file:close()
	-- Atomically rename.
	os.rename(tmpfile, self:file())
	my.debug("saved chat mesages to %s", self:file())
	return true
end

-- Delete chat file.
function Chat:delete()
	if not vim.fn.filereadable(self:file()) then
		my.log("file does not exists: %s", self:file())
		return
	end
	if vim.fn.confirm("Do you really want to delete " .. self:file() .. "?") == 0 then
		return
	end
	if vim.fn.delete(self:file()) ~= 0 then
		my.log("Could not delete %s", self:file())
	else
		my.log("Removed file %s", self:file())
		self.ms = nil
	end
end

-- List all chat names.
---@return string[]
function Chat.listnames()
	local files = vim.fn.globpath(config.cache_dir, "chat-*.json", false, true, true)
	local ret = {}
	for _, file in pairs(files) do
		local filename = vim.fn.fnamemodify(file, ":t")
		local name = filename:gsub("^chat[-]", ""):gsub(".json$", "")
		table.insert(ret, name)
	end
	return ret
end

-- }}}
-- {{{1 Indicator

local indicatorSign = "kai_indicator_sign"

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
		signlist = {},
	}, Indicator)
end

---@private
function Indicator:__tostring()
	return sprintf("Indicator{%s,%s}", self.buffer, self.reg)
end

function Indicator:on_start()
	vim.fn.sign_define(indicatorSign, { text = config.indicator_text })
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
	vim.api.nvim_buf_set_text(
		self.buffer,
		self.reg.start.row,
		self.reg.start.col,
		self.reg.stop.row,
		self.reg.stop.col,
		lines
	)
	-- Calculate new region stop with the filled text.
	local stop_row = self.reg.start.row + #lines - 1
	local stop_col = #lines == 1 and (self.reg.stop.col + lines[1]:len()) or my.get_row_length(self.buffer, stop_row)
	self.reg.stop = Pos.new0(stop_row, stop_col)
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
			name = indicatorSign,
		})
	end
	local ret = vim.fn.sign_placelist(toplace)
	if ret ~= -1 then
		for _, v in pairs(ret) do
			table.insert(self.signlist, { buffer = self.buffer, group = indicatorSign, id = v })
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
	if BufferN(self.buffer):ischatbuffer() then
		Chat.show_m_e(self.buffer)
	end
	BufferN(self.buffer):chatbufferunmodify()
	if self:_unplace_signs() then
		vim.cmd.redraw()
	end
end

---@private
function Indicator:__gc()
	self:on_complete()
end

-- }}}
-- {{{1 OpenAI

---@class Openai
---@field private cb Indicator
---@field private acc string
---@field private chatobj Chat?
---@field private tokens integer
local Openai = {}
Openai.__index = Openai

---@param cb Indicator
---@return Openai
function Openai.new(cb)
	return setmetatable({ cb = cb, acc = "", tokens = 0 }, Openai)
end

---@param cmd string[] The command to run.
function Openai:exe(cmd)
	Subprocess.spawn({
		cmd = cmd,
		on_start = function()
			self.cb:on_start()
		end,
		on_line = function(line, handle)
			self:on_line(line, handle)
		end,
		on_exit = function(code, _, stderr)
			if code == 0 then
				self:on_exit()
			else
				my.error("%s %s", vim.inspect(cmd), stderr)
			end
			vim.schedule(function()
				self.cb:on_complete()
			end)
		end,
	})
end

---Handle json decoding error or a good json response.
---@private
---@param txt string
---@param handle Subprocess?
function Openai:handle_response(txt, handle)
	local success, json = pcall(vim.json.decode, txt)
	if not success then
		my.error("Could not decode json: %s", vim.inspect(txt))
	elseif type(json) ~= "table" then
		my.error("Not a JSON dictionary: %s", vim.inspect(txt))
	elseif json.error and type(json.error) == "table" and json.error.message then
		my.error(json.error.message)
	elseif not json.choices then
		my.error("No choices in response: %s", vim.inspect(txt))
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
			self.chatobj:append(self.delta_role, content)
			self:on_data(content)
		end
	elseif json.choices[1].message then
		-- Response from chat endpoint no-stream.
		local msg = json.choices[1].message
		self.chatobj:append(msg.role, msg.content)
		self:on_data(msg.content)
	else
		my.error("Could not parse response: %s", vim.inspect(txt))
	end
end

---@private
---@param line string
---@param handle Subprocess
function Openai:on_line(line, handle)
	my.debug("< %s", vim.inspect(line))
	-- print(vim.inspect(line))
	if self.acc ~= "" or vim.startswith(vim.trim(line), "{") then
		-- This is an error response or not streaming response.
		self.acc = self.acc .. line
	elseif not vim.startswith(line, "data: ") then
		my.error("Response from API does not start with data: %s", vim.inspect(line))
	else
		line = vim.trim(line:gsub("^data:", ""))
		-- [DONE] means end of parsing.
		if not line or line == "[DONE]" then
			return
		end
		self:handle_response(line, handle)
	end
end

---@private
---@param txt string
---@param handle Subprocess?
function Openai:on_data(txt, handle)
	my.maybe_schedule(function()
		if not my.pcallprint(self.cb.on_data, self.cb, txt) then
			-- In case the callback fails, terminate curl instead of printing same error over and over again.
			if handle then
				handle:terminate()
			end
		end
	end)
end

---@private
function Openai:on_exit()
	if self.acc ~= "" then
		self:handle_response(self.acc)
	elseif self.chatobj ~= nil then
		-- When using chat completion add an additional trailing newline to have the cursor ending on the next line.
		if self.chatobj:last_assistant_character() ~= "\n" then
			self:on_data("\n")
		end
	end
end

---@private
---@return string[]
function Openai:_mock_script()
	return {
		"sh",
		"-c",
		[[
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
        ]],
		"--",
		config.mock,
	}
end

---@private
---@param endpoint string
---@param body {}
---@return string[]
function Openai._get_curl(endpoint, body)
	local api_key = os.getenv("OPENAI_API_KEY")
	assert(api_key, "$OPENAI_API_KEY environment variable must be set")
	my.debug("> %s %s", vim.inspect(endpoint), vim.inspect(body))
	local jsonbody = vim.json.encode(body)
	local curl = {
		"curl",
		"--silent",
		"--show-error",
		"--no-buffer",
		"--max-time",
		config.timeout,
		"-L",
		"-H",
		"Authorization: Bearer " .. api_key,
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-d",
		jsonbody,
		"https://api.openai.com/v1/" .. endpoint,
	}
	return curl
end

---@private
---@param endpoint string
---@param body {}
function Openai:_request(endpoint, body)
	local curl = self._get_curl(endpoint, body)
	if config.mock ~= "" then
		curl = self:_mock_script()
	end
	self:exe(curl)
end

---Request OpenAI API for completions.
---@param body {prompt: string, suffix: nil | string}
function Openai:completions(body)
	body = vim.tbl_extend("keep", body, {
		model = config.completions_model,
		max_tokens = config.completions_max_tokens,
		temperature = config.temperature,
		stream = true,
	})
	self:_request("completions", body)
end

---Request OpenAI API for edit.
---@param body {input: string, instruction: string}
function Openai:edits(body)
	body = vim.tbl_extend("keep", body, { temperature = config.temperature })
	self:_request("edits", body)
end

-- Use embeddings API to count the tokens in a string.
---@param txt string
---@return integer?
function Openai.embeddings_prompt_tokens(txt)
	local body = { model = "text-embedding-ada-002", input = txt }
	local curl = Openai._get_curl("embeddings", body)
	local acc = Subprocess.call_output(curl)
	local json = vim.json.decode(acc)
	return tonumber(json.usage.prompt_tokens)
end

---@param chat Chat
---@param body {model: string}
function Openai:chat(chat, body)
	self.chatobj = chat
	body = vim.tbl_extend("keep", body, {
		messages = self.chatobj:get_trimmed_messages(),
		temperature = config.chat_temperature,
		stream = true,
	})
	self:_request("chat/completions", body)
	self.chatobj:save()
end

-- }}}
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
---@field cursor Pos
---@field prompt string?
---@field buffern BufferN
Cmd = {}
Cmd.__index = Cmd

---@param args Args
---@return Cmd
function Cmd.new(args)
	local self = setmetatable({
		args = args,
		prompt = (args.args and args.args ~= "") and args.args or nil,
		buffer = vim.api.nvim_get_current_buf(),
	}, Cmd)
	self.buffern = BufferN(self.buffer)
	if not self.buffern:ischatbuffer() then
		assert(self.buffern:modifiable(), "Buffer is not modifiable")
	end
	self.cursor = self:_get_cursor()
	return self
end

---@param row integer
function Cmd:get_row_length(row)
	return self.buffern:get_row_length(row)
end

-- Get the text from the buffer between the start and end points.
---@param reg Region
---@return string
function Cmd:buffer_get_text(reg)
	return self.buffern:get_text(reg)
end

---@private
---@return Pos Position of the cursor.
function Cmd:_get_cursor()
	local o = Pos.new10arr(vim.api.nvim_win_get_cursor(0))
	-- Get the position after cursor.
	-- If the current line is empty, then the cursor starts at zero position.
	-- If the current line is not empty, start with the place _after_ the cursor.
	if self:get_row_length(o.row) ~= 0 then
		o.col = o.col + 1
	end
	return o
end

-- Extract command buffer context.
---@return Region
function Cmd:get_context()
	local args = self.args
	local buffer = self.buffer
	local cursor = self.cursor
	---@type Pos, Pos
	local before, after
	if args.range == 2 then
		local start = Pos.new10arr(vim.api.nvim_buf_get_mark(buffer, "<"))
		local stop = Pos.new10arr(vim.api.nvim_buf_get_mark(buffer, ">"))
		-- If last selection was line or character based and the range
		-- passed to args match the selection, then use selection,
		-- otherwise use range.
		local use_visual = vim.fn.visualmode():lower() == "v"
			and start.row == args.line1
			and stop.row == self.args.line2
		if use_visual then
			-- Visual selection mode.
			-- Limit col positions, nvim_buf_get_mark outputs end of universe.
			local end_line_length = self:get_row_length(stop.row)
			stop.col = math.min(stop.col, end_line_length)
		else
			-- Range mode, take whole lines.
			start = Pos.new10(args.line1, 0)
			stop = Pos.new10(args.line2, self:get_row_length(args.line2 - 1))
		end
		before = start
		after = stop
	else
		local one_arg = args.range == 1 and args.count or nil
		local context_before = one_arg or config.context_before
		local context_after = one_arg or config.context_after
		--
		local start_row = math.max(0, cursor.row - context_before)
		before = Pos.new0(start_row, 0)
		--
		local buffer_line_count = vim.api.nvim_buf_line_count(self.buffer)
		local stop_row = math.min(cursor.row + context_after, buffer_line_count - 1)
		local stop_row_length = self:get_row_length(stop_row)
		after = Pos.new0(stop_row, stop_row_length)
	end
	my.log(
		"Generating completion from %d lines above and %d lines below",
		math.abs(cursor.row - before.row),
		math.abs(cursor.row - after.row)
	)
	return Region.new(before, after)
end

---@param replace Region to replace when starting writing to buffer.
---@return Openai
function Cmd:openai(replace)
	return Openai.new(Indicator.new(self.buffer, replace))
end

-- Prefix the string with "prompt ```<filetype>" if prompt is not nil.
---@param str string
---@return string
function Cmd:prefix_with_prompt(str)
	if self.prompt then
		local filetype = vim.api.nvim_buf_get_option(self.buffer, "filetype")
		local promptnl = self.prompt .. "\n\n```" .. filetype .. "\n"
		str = promptnl .. str
	end
	return str
end

function Cmd:inchatbuffer()
	return self.buffern:ischatbuffer()
end

-- }}}
-- {{{1 M.AI

---@class M
local M = { tok = tok, my = my, Chat = Chat }

---@param opts table
function M.setup(opts)
	vim.tbl_extend(config, opts)
end

---@param args Args
function M.AIA(args)
	local cmd = Cmd.new(args)
	local cursor = cmd.cursor
	local replace = Region.new(cursor, cursor)
	local context = cmd:get_context()
	assert(context.start <= cursor and cursor <= context.stop, "Cursor position has to be inside selected region")
	local prefix = cmd:buffer_get_text(Region.new(context.start, cursor))
	local suffix = cmd:buffer_get_text(Region.new(cursor, context.stop))
	prefix = cmd:prefix_with_prompt(prefix)
	-- print(vim.inspect(prefix), vim.inspect(suffix))
	cmd:openai(replace):completions({ prompt = prefix, suffix = suffix })
end

-------------------------------------------------------------------------------

---@param args Args
---@param model string?
function M.AIE(args, model)
	model = model or "code-davinci-edit-001"
	--
	local cmd = Cmd.new(args)
	local context = cmd:get_context()
	local selected_text = cmd:buffer_get_text(context)
	assert(selected_text ~= "", "Selected text is empty")
	cmd:openai(context):edits({
		model = model,
		input = selected_text,
		instruction = cmd.prompt,
	})
end

function M.AIEText(args)
	M.AIE(args, "text-davinci-edit-001")
end

-------------------------------------------------------------------------------

---@param args Args
---@param model string?
function M.AI(args, model)
	model = model or "gpt-3.5-turbo"
	--
	local cmd = Cmd.new(args)
	cmd.buffern:chatbuffermodify()
	---@type string, Region
	local prompt, replace
	if args.range > 0 then
		assert(not cmd:inchatbuffer(), "Range not supported in chat window")
		local context = cmd:get_context()
		prompt = cmd:buffer_get_text(context)
		prompt = cmd:prefix_with_prompt(prompt)
		-- If the context stops at the end of the line, start the answer with a newline.
		if context.stop.col == cmd:get_row_length(context.stop.row) then
			-- Insert a newline.
			vim.api.nvim_buf_set_text(
				cmd.buffer,
				context.stop.row,
				context.stop.col,
				context.stop.row,
				context.stop.col,
				{ "", "" }
			)
			-- Adjust position to the next line.
			context.stop.col = 0
			context.stop.row = context.stop.row + 1
		end
		replace = Region.new(context.stop, context.stop)
	else
		assert(
			cmd.prompt,
			cmd:inchatbuffer() and "You have to give prompt for :AI command."
				or "You have to give either range or prompt given for :AI command."
		)
		local cursor = cmd.cursor
		prompt = cmd.prompt
		replace = Region.new(cursor, cursor)
	end
	assert(prompt)
	--
	local name = config.chat_use
	if cmd:inchatbuffer() then
		name = vim.api.nvim_buf_get_name(cmd.buffer):gsub(".*[[]", ""):gsub("[]]", "")
	end
	local chat = Chat.load(name)
	chat:append_user(prompt)
	if cmd:inchatbuffer() then
		chat:append(ChatRole.assistant, "")
		chat:show_chat(cmd.buffer, "")
		local bufferend = Pos.buffer_end(cmd.buffer)
		replace = Region.new(bufferend, bufferend)
	end
	--
	cmd:openai(replace):chat(chat, { model = model })
end

---@param args Args
function M.AI4(args)
	M.AI(args, "gpt-4")
end

---@return string[]
function M.complete_chat_names(ArgLead, CmdLine, CursorPos)
	local names = Chat.listnames()
	local ret = {}
	if ArgLead == "" then
		ret = names
	else
		for _, v in ipairs(names) do
			if vim.startswith(v, ArgLead) then
				table.insert(ret, v)
			end
		end
	end
	return ret
end

---@param args Args
function M.AIChatNew(args)
	local name = args.fargs[1]
	local prompt = table.concat(vim.list_slice(args.fargs, 2), " ")
	assert(
		not vim.tbl_contains(Chat.listnames(), name),
		sprintf("There is already a chat with name %s at %s. Remove it with AIChatRemove", name, config.cache_dir)
	)
	Chat.new(name, prompt):save()
	vim.g.kai_chat_use = name
	my.log("Created chat %s and switched to it", name)
end

---@param args Args
function M.AIChatUse(args)
	assert(#args.fargs == 1, sprintf("Wrong number of arguments: %d", #args.fargs))
	local name = args.fargs[1]
	Chat.load(name)
	vim.g.kai_chat_use = name
end

---@param args Args
function M.AIChatOpen(args)
	assert(#args.fargs <= 1, sprintf("Wrong number of arguments: %d", #args.fargs))
	local name = args.fargs[1] or config.chat_use
	local chat = Chat.load(name)
	local bufname = "[" .. name .. "]"
	local buffer = nil
	-- Find buffer if already exists
	for _, v in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		if vim.endswith(v.name, bufname) then
			buffer = v.bufnr
			break
		end
	end
	if buffer == nil then
		-- Create a scratch buffer if not found
		buffer = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_buf_set_option(buffer, "buftype", "nofile")
		vim.api.nvim_buf_set_option(buffer, "bufhidden", "hide")
		vim.api.nvim_buf_set_option(buffer, "swapfile", false)
		vim.api.nvim_buf_set_option(buffer, "filetype", my.filetype)
		vim.api.nvim_buf_set_option(buffer, "readonly", true)
		vim.api.nvim_buf_set_option(buffer, "modifiable", false)
		vim.api.nvim_buf_set_name(buffer, bufname)
	end
	vim.api.nvim_buf_set_option(buffer, "modifiable", true)
	chat:show_chat(buffer, "\n")
	chat.show_m_e(buffer)
	vim.api.nvim_buf_set_option(buffer, "modifiable", false)
end

---@param args Args
function M.AIChatView(args)
	assert(#args.fargs <= 1, sprintf("Wrong number of arguments: %d", #args.fargs))
	local name = args.fargs[1] or config.chat_use
	local txt = Chat.load(name):to_text()
	my.log("%s", txt)
end

---@param args Args
function M.AIChatList(args)
	assert(#args.fargs == 0, sprintf("Wrong number of arguments: %d", #args.fargs))
	local names = Chat.listnames()
	local txt = sprintf("There are %d chats.\n", #names)
	---@type string[][]
	local data = {}
	table.insert(data, { "name", "file", "#tok", "init" })
	for _, name in ipairs(names) do
		local chat = Chat.load(name)
		table.insert(data, { chat.name, chat:file(), chat:ntokens(), sprintf("%q", chat:get_system_message()) })
	end
	txt = txt .. my.tabularize(data, { "", "-", "", "-" })
	my.log("%s", txt)
end

---@param args Args
function M.AIChatRemove(args)
	assert(#args.fargs <= 1, sprintf("Wrong number of arguments: %d", #args.fargs))
	local name = args.fargs[1] or config.chat_use
	Chat.assert_exists(name)
	Chat.new(name):delete()
end

return M

-- }}}

-- vim: foldmethod=marker
