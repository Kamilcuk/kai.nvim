
hi KaiChatSy     gui=bold term=bold cterm=bold ctermbg=DarkCyan
hi KaiChatSyText                               ctermbg=DarkCyan
hi KaiChatMe     gui=bold term=bold cterm=bold ctermbg=DarkBlue
hi clear KaiChatMeText
hi KaiChatAi     gui=bold term=bold cterm=bold ctermbg=DarkGreen
hi KaiChatAiText ctermfg=LightGrey
syntax match KaiChatSy /^SY: /
syntax region KaiChatSyText start=/^SY: /rs=e,hs=e end=/^\(SY\|ME\|AI\): /me=s-1 contains=KaiChatSy
syntax match KaiChatMe /^ME: /he=e-1
syntax region KaiChatMeText start=/^ME: /rs=e,hs=e end=/^\(SY\|ME\|AI\): /me=s-1 contains=KaiChatMe
syntax match KaiChatAi /^AI: /he=e-1
syntax region KaiChatAiText start=/^AI: /rs=e,hs=e end=/^\(SY\|ME\|AI\): /me=s-1 contains=KaiChatAi


