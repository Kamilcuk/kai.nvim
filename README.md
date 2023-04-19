# 🤖 ai.vim

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
Plug 'kamilcuk/ai.vim'
```

## How do I use this?

Read [https://platform.openai.com/docs/guides/code](https://platform.openai.com/docs/guides/code).

- `:AI prompt`
    - Chat with AI using `chats/completions` API.
    - The response will be printed on cursor position.
    - The chat conversation history is saved into `g:cache_dir/k_ai/chat.json` file.
    - The chat history is trimmed to approximate number of tokens
      to keep below maximum number of tokens allowed and also to reduce number of tokens you pay for.
          - The calculation of tokens is approximate, because really counting tokens would be too hard.
    - I use this for prompting simple stuff, like `:AI how to write lua function that does something...?`
      then I can polish the results by asking follow up questions.
    - I can use this freely, because it does not send company proprietary code to OpenAI.
    - You can get chat history with `:AIChatHistory`.
    - You can delete one most earliest prompt from history with `:AIChatZDelete 1`, in case you get "too many tokens" error.
    - You can delete history file with `:AIChatZDelete file`.
- `:AIA` or `:AIAdd`
    - Take 20 lines before current position.
    - Take 20 lines after the cursor position.
    - Send that to `completions` OpenAI API.
    - "Add" the response from the completion to the buffer at cursor position.
    - `:20AIA` or `:40AIA`
        - The single number does _not_ represent the line number, I decided that is useless.
        - Uses the single number for the count of lines below and after the cursor position.
    - `:-20,+10AI` or `:%AI` or `:'<,'>AI`
        - Take the selection and split it on cursor position for before and after sections..
- `:\<,\>AIEdit fix spelling` or `:%AIEdit fix spelling`
   - Take the selected range and sends it to `edits` API with the presented prompt.
   - Uses `code-davinci-edit-001` model.
   - There is also `AIEditText` that uses `text-davinci-edit-001` for editing text.

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

ai.vim isn't just for programming! You can also complete regular human text:

```
Hey Joe, here are some ideas for slogans for the new petshop. Which do you like best?
1. <:AI>
```

Results in:

```
Hey Joe, here are some ideas for slogans for the new petshop. Which do you like best?
1. "Where Pets Come First!"
2. "Your Pet's Home Away From Home!"
3. "The Best Place for Your Pet!"
4. "The Pet Store That Cares!"
5. "The Pet Store That Loves Your Pet!"
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

Visually selecting the above CSS and running `:AIEdit convert colors to hex` results in:

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
