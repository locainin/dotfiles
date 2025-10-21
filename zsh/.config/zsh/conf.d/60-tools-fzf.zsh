# ==============================================================================
# FZF INTEGRATION
# ==============================================================================
# Sources fzf extras and sets default search helpers used elsewhere.
# ------------------------------------------------------------------------------

[[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh
if command -v rg >/dev/null; then
  # default command ensures fzf search respects hidden files but skips git
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/**"'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi
# consistent picker aesthetics for fzf integrations
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'
