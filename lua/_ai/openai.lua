local M = {}

local config = require("_ai/config")

local function safe_close(handle)
    if not vim.loop.is_closing(handle) then vim.loop.close(handle) end
end

local function mypopen(cmd, cb)
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
            cb.on_complete()
        else
            cb.on_error(cmd .. stderr_chunks)
        end
    end)
    if not handle then
        cb.on_error(vim.inspect(cmd) .. " could not be started: " ..
                        vim.inspect(error))
        return
    end
    stdout:read_start(function(_, chunk)
        if not chunk then return end
        stdout_line = stdout_line .. chunk
        local line_start, line_end = stdout_line:find("\n")
        while line_start do
            local oneline = stdout_line:sub(1, line_end - 1)
            stdout_line = stdout_line:sub(line_end + 1)
            if oneline ~= "" then cb.on_line(oneline) end
            line_start, line_end = stdout_line:find("\n")
        end
    end)
    stderr:read_start(function(_, chunk)
        if not chunk then return end
        stderr_chunks = stderr_chunks .. chunk
    end)
    local ended, _ = vim.wait(config.timeout * 1000,
                              function() return not handle:is_active() end)
    if not ended then handle:kill() end
end

-- Handle json decoding error or a good json response.
local function handle_json_response(txt, cb)
    local success, json = pcall(vim.json.decode, txt)
    if not success then
        cb.on_error("Could not decode json: " .. vim.inspect(txt))
    elseif type(json) ~= "table" then
        cb.on_error("Not a JSON dictionary: " .. vim.inspect(txt))
    elseif json.error and type(json.error) == "table" and json.error.message then
        cb.on_error(json.error.message)
    elseif not json.choices then
        cb.on_error("No choices in response: " .. vim.inspect(txt))
    else
        -- print(vim.inspect(json.choices[1].text))
        cb.on_data(json.choices[1].text)
    end
end

local function request(endpoint, body, cb)
    local api_key = os.getenv("OPENAI_API_KEY")
    if not api_key then
        cb.on_error("$OPENAI_API_KEY environment variable must be set")
        return
    end
    local jsonbody = vim.json.encode(body)
    local curl = {
        "curl", "--silent", "--show-error", "--no-buffer", "--max-time",
        config.timeout, "-L", "https://api.openai.com/v1/" .. endpoint, "-H",
        "Authorization: Bearer " .. api_key, "-X", "POST", "-H",
        "Content-Type: application/json", "-d", jsonbody
    }
    if config.mock_response ~= "" then
        curl = {
            "sh", "-c", [[printf 'data: {"choices":[{"text":"%s"}]}\n' "$1"]],
            "_", config.mock_respone
        }
    end
    -- In case of streaming response, json is prefixed with data:
    local stdout_acc = ""
    local cb_onstream = {
        on_line = function(line)
            if vim.startswith(line, "{") or stdout_acc ~= "" then
                -- This is an error response.
                stdout_acc = stdout_acc .. line
            elseif not vim.startswith(line, "data: ") then
                cb.on_error("Response from API does not start with data: " ..
                                vim.inspect(line))
            else
                line = vim.trim(line:gsub("^data:", ""))
                -- [DONE] means end of parsing.
                if not line or line == "[DONE]" then return end
                handle_json_response(line, cb)
            end
        end,
        on_error = cb.on_error,
        on_complete = function()
            if stdout_acc ~= "" then
                handle_json_response(stdout_acc, cb)
            end
            cb.on_complete()
        end
    }
    --
    local cb_nostream = {
        on_line = function(line) stdout_acc = stdout_acc .. "\n" .. line end,
        on_error = cb.on_error,
        on_complete = function()
            handle_json_response(stdout_acc, cb)
            cb.on_complete()
        end
    }
    --
    local isstream = body["stream"] == true
    mypopen(curl, isstream and cb_onstream or cb_nostream)
end

function M.completions(body, cb)
    body = vim.tbl_extend("keep", body, {
        model = config.completions_model,
        max_tokens = config.max_tokens,
        temperature = config.temperature,
        stream = true
    })
    request("completions", body, cb)
end

function M.edits(body, cb)
    body = vim.tbl_extend("keep", body, {
        model = config.edits_model,
        temperature = config.temperature
    })
    request("edits", body, cb)
end

return M
