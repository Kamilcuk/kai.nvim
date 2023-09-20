# 🤖 kai.nvim

Neovim plugin for generating and editing text using OpenAI.

## Features

- Use OpenAI completions, edit and chat API, see
  [https://platform.openai.com/docs/guides/completion](https://platform.openai.com/docs/guides/completion).
- Generate new text using a prompt.
- Select and edit existing text in-place.
- Depends on `curl` installed, no additional installation required.

## Installing

Generate OpenAI API key from [https://beta.openai.com/account/api-keys](https://beta.openai.com/account/api-keys).

Export the key in `$OPENAI_API_KEY` environment variable.

Put this with vim-plug:

```vim
Plug 'kamilcuk/kai.nvim'
```

## Global options

kai_cache_dir

: string The cache dir used to store conversations history. default: stdpath(cache)/kai/

kai_chat_max_tokens

: integer The maximum number of tokens to send to chat/completions API. There is a limit in the API.

kai_chat_model

: string The default chat model to use

kai_chat_temperature

: number The temperature option when talking to chat/completions API.

kai_chat_use

: string The current conversation chat to use.

kai_completions_max_tokens

: integer The maximum number of tokens to send to completions API.

kai_completions_model

: string The completions model to use

kai_context_after

: integer The default number of lines to send to completions API after cursor.

kai_context_before

: integer The default number of lines to send to completione API before cursor.

kai_debug

: boolean Increase verbosity.

kai_edit_model

: string The edits API model to use

kai_indicator_text

: string The indication to show on the indication panel when working.

kai_loaded

: boolean Set to true skip loading this plugin with AI user commands.

kai_mock

: string? Used for debugging.

kai_temperature

: number The temperature to send to other apis except chat/completions API.

kai_timeout

: integer Timeout of curl in seconds.


## How do I use this?

Read [https://platform.openai.com/docs/guides/code](https://platform.openai.com/docs/guides/code)
on how to write good AI prompts.

### Completion


:AI

:  Chat with AI using [chats/completions OpenAI API](https://platform.openai.com/docs/api-reference/chat/create).
 The response will be printed at cursor position.
 The chat conversations history is saved into `global.cache_dir/kai/chat*.json` files.
 Chat history is send to chats/completion API reduced to the `chat_max_tokens` number of tokens.
    - To keep below maximum number of tokens allowed and also to reduce number of tokens you pay for.
    - The calculation of tokens is approximate, because really counting tokens would be too hard.
 I use this for prompting simple stuff, like `:AI how to write lua function that does something...?`
 then I can polish the results by asking follow up questions.
 I can use this freely, because it does not send company proprietary code to OpenAI.


:AIA

:  Mnemonic from AI Add.
 This is the main command that I use for filling up unfinished functions.
 By default takes 20 lines before position and 20 lines after the cursor position.
 Sends that to [completions OpenAI API](https://platform.openai.com/docs/api-reference/completions).
 The response from API is added into the buffer at cursor position.
 Command takes a prompt
   - `:AIA write code here that changes the world`
   - The prompt is added to the before part with two newline and three backticks.
 Command takes a single number
   - A single number specifies the number of lines before and after cursor position to send to the API.
       - `:20AIA` is the default. For example: `:40AIA` `:1000AIA`
       - The single number does _not_ represent the line number, I decided that is useless.
 Command takes a line range
   - A range specifies the number of lines to send the API.
       - `:-20,+10AIA` `:%AIA` `:'<,'>AIA`
       - Takes the selection and split it on cursor position for before and after sections.


:AIChatList

:  Lists the chats


:AIChatNew

:  Starts a new chat with specific name and prompt.


:AIChatOpen

:  Opens the current chat, or given an argument open the chat with the name


:AIChatRemove

:  Remove the chat with the name.


:AIChatUse

:  Selects a chat history file to use by name. The "default" chat is the default.


:AIChatView

:  Print chat contents


:AIE

:  Mnemonic from AI Edit.
 Uses [edits OpenAI API](https://platform.openai.com/docs/api-reference/moderations).
 Just `:AIA`, by default sends 20 lines before and after cursor position.
 Takes prompt sends as instruction.
 I typically select text and use `:'<,'>AIE do this`.
 `%AIE do this`


:AIEText

:  Like `:AIE` but uses `text-davinci-edit-001` model instead of `code-davinci-edit-001`.


:AIModel

:  Switch model used by AI


## Tutorial

For example:

```typescript
function capitalize (str: string): string {
    <cursor><type :AIA>
}
```

Will result in:

```typescript
function capitalize (str: string): string {
    return str.charAt(0).toUpperCase() + str.slice(1);
}
```

For example:

```
:AIA write a thank you email to Bigco engineering interviewer
```

Results in something like:

```
Dear [Name],

I wanted to take a moment to thank you for taking the time to interview me for the engineering
position at Bigco. I was very impressed with the company and the team, and I am excited about the
possibility of joining the team.

I appreciate the time you took to explain the role and the company's mission. I am confident that I
have the skills and experience to be a valuable asset to the team.

Once again, thank you for your time and consideration. I look forward to hearing from you soon.

Sincerely,
[Your Name]
```

Besides generating new text, you can also edit existing text using a given instruction.

```css
body {
    color: orange;
    background: green;
}
```

Visually selecting the above CSS and running `:AIE convert colors to hex` results in:

```css
body {
    color: #ffa500;
    background: #008000;
}
```

Another example of text editing:

```
List of capitals:
1. Toronto
2. London
3. Honolulu
4. Miami
5. Boston
```

Visually selecting this text and running `:AIEdit sort by population` results in:

```
List of capitals:
1. London
2. Toronto
3. Boston
4. Miami
5. Honolulu
```

## Important Disclaimers

**Accuracy**: GPT is good at producing text and code that looks correct at first glance, but may be
completely wrong. Make sure you carefully proof read and test everything output by this plugin!

**Privacy**: This plugin sends text to OpenAI when generating completions and edits. Don't use it in
files containing sensitive information.

## License

See LICENSE.txt