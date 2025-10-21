# ==============================================================================
# ZSH ENVIRONMENT DIAGNOSTICS
# ==============================================================================
# Provides a quick snapshot of tooling and plugin availability.
# ------------------------------------------------------------------------------

# zsh_diag reports plugin state and binary availability at a glance
zsh_diag() {
  emulate -L zsh
  setopt localoptions
  print -P "%F{cyan}zsh diagnostics%f"
  print "shell:  $ZSH_VERSION"
  print "oh-my-zsh: ${ZSH:-unset} $( [[ -s $ZSH/oh-my-zsh.sh ]] && print present || print missing )"
  print "plugins dir: $ZSH/custom/plugins"
  print "autosuggestions: $( [[ -d $ZSH/custom/plugins/zsh-autosuggestions ]] && print present || print missing )"
  print "syntax-highlighting: $( [[ -d $ZSH/custom/plugins/zsh-syntax-highlighting ]] && print present || print missing )"
  print "starship: $(command -v starship >/dev/null && print present || print missing)"
  print "p10k config: $( [[ -f ~/.p10k.zsh ]] && print present || print missing )"
  print "fzf: $(command -v fzf >/dev/null && print present || print missing)"
  print "rg: $(command -v rg >/dev/null && print present || print missing)"
  print "fd: $(command -v fd >/dev/null && print present || print missing)"
  print "thefuck: $(command -v thefuck >/dev/null && print present || print missing)"
  print "extras: figlet $(command -v figlet >/dev/null && print ok || print -n '✗'), lolcat $(command -v lolcat >/dev/null && print ok || print -n '✗'), cowsay $(command -v cowsay >/dev/null && print ok || print -n '✗'), fortune $(command -v fortune >/dev/null && print ok || print -n '✗')"
}
