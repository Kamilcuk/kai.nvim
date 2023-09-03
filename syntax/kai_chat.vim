
hi KaiChatSy     gui=bold term=bold cterm=bold ctermbg=DarkCyan
hi KaiChatSyText gui=NONE term=NONE cterm=NONE ctermbg=DarkCyan
hi KaiChatMe     gui=bold term=bold cterm=bold ctermbg=DarkBlue
hi clear KaiChatMeText
hi KaiChatAi     gui=bold term=bold cterm=bold ctermbg=DarkGreen
hi KaiChatAiText gui=NONE term=NONE cterm=NONE ctermfg=LightGrey
hi KaiChatInfo      gui=bold term=bold cterm=bold ctermbg=DarkCyan
hi KaiChatInfoText  gui=NONE term=NONE cterm=NONE ctermbg=DarkCyan
syntax match  KaiChatSy             /^SY: /
syntax match  KaiChatMe             /^ME: /he=e-1
syntax match  KaiChatAi             /^AI: /he=e-1
syntax match  KaiChatInfo           /^::: /
syntax region KaiChatSyText   start=/^SY: /rs=e,hs=e end=/^\(SY\|ME\|AI\|::\): /me=s-1 contains=KaiChatSy
syntax region KaiChatMeText   start=/^ME: /rs=e,hs=e end=/^\(SY\|ME\|AI\|::\): /me=s-1 contains=KaiChatMe
syntax region KaiChatAiText   start=/^AI: /rs=e,hs=e end=/^\(SY\|ME\|AI\|::\): /me=s-1 contains=KaiChatAi
syntax region KaiChatInfoText start=/^::: /rs=e,hs=e end=/^\(SY\|ME\|AI\|::\): /me=s-1 contains=KaiChatInfo


