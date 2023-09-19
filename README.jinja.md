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

{% for c in configs %}
kai_{{c.name}}

: {{c.view}} {{c.desc}}

{% endfor %}

## How do I use this?

Read [https://platform.openai.com/docs/guides/code](https://platform.openai.com/docs/guides/code)
on how to write good AI prompts.

### Completion

{% for c in commands %}

:{{c.name}}

: {{c.desc}}

{% endfor %}

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
