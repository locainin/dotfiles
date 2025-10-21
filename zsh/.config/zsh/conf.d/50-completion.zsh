# ==============================================================================
# SECTION 5: COMPLETION & KEYBINDINGS
# ==============================================================================

autoload -Uz colors compinit add-zsh-hook
zmodload zsh/complist
zmodload zsh/terminfo
colors

setopt AUTO_LIST LIST_AMBIGUOUS COMPLETE_IN_WORD AUTO_PARAM_SLASH ALWAYS_TO_END
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 'r:|[._-]=** r:|=**'
zstyle ':completion:*' menu select=2
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

ZSH_COMPDUMP="$HOME/.config/zsh/cache/.zcompdump-${HOST}-${ZSH_VERSION}"
if [[ -r $ZSH_COMPDUMP ]]; then
  compinit -C -d "$ZSH_COMPDUMP"
else
  compinit    -d "$ZSH_COMPDUMP"
fi

# --- widgets -------------------------------------------------------------------

# Tab: if on a cd line, try to accept autosuggestion first; else do normal completion
# smart_cd_tab stitches cd heuristics into the default tab experience
smart_cd_tab() {
  if [[ $BUFFER == (cd|builtin\ cd)\ * ]]; then
    if try_accept_autosuggestion; then
      apply_cd_after_accept
      return
    fi
  fi
  zle complete-word
}
zle -N smart_cd_tab

# Shift-A:
#  - strictly accept the *grey* autosuggestion (if any)
#  - if accepted on a cd line, optionally auto-cd
#  - otherwise insert 'A' (no recursion)
# shift_a_accept treats Shift+A as an accept key while falling back gracefully
shift_a_accept() {
  if [[ ${KEYMAP:-} == menuselect ]]; then
    zle accept-line
    return
  fi

  if try_accept_autosuggestion; then
    return
  fi

  zle .self-insert
}
zle -N shift_a_accept

# --- bindings ------------------------------------------------------------------

if [[ -o zle ]]; then
  # history search on arrows
  [[ -n ${terminfo[kcuu1]} ]] && bindkey "${terminfo[kcuu1]}" history-beginning-search-backward
  [[ -n ${terminfo[kcud1]} ]] && bindkey "${terminfo[kcud1]}" history-beginning-search-forward

  [[ -n ${terminfo[kcuf1]} ]] && bindkey "${terminfo[kcuf1]}" forward-char
  [[ -n ${terminfo[kend]}  ]] && bindkey "${terminfo[kend]}"  end-of-line

  # If zsh-autosuggestions is loaded, also accept on Ctrl-F
  if zle -la autosuggest-accept; then
    bindkey -M emacs '^F' autosuggest-accept
    bindkey -M viins  '^F' autosuggest-accept
  fi

  # Tab uses smart cd-accept
  bindkey -M emacs '^I' smart_cd_tab
  bindkey -M viins  '^I' smart_cd_tab

  # sequences that should accept suggestion (or selection in menu)
  local -a accept_keys=()
  [[ -n ${terminfo[kcbt]} ]] && accept_keys+=("${terminfo[kcbt]}")    # Shift-Tab
  accept_keys+=($'\e[Z' $'\e\t' $'\e[1;5I' $'\e[27;5;9~' $'\e[9;5~' $'\e[9;6~')
  if [[ -n ${SMARTCD_ACCEPT_KEYS:-} ]]; then
    accept_keys+=(${=SMARTCD_ACCEPT_KEYS})
  fi
  local -A _seen
  local _k
  for _k in "${accept_keys[@]}"; do
    [[ -z $_k || -n ${_seen[$_k]:-} ]] && continue
    _seen[$_k]=1
    bindkey "$_k" accept_suggest_or_select
    bindkey -M menuselect "$_k" accept-line
  done

  # Shift+A -> accept grey autosuggestion; otherwise insert 'A'
  bindkey -M emacs 'A' shift_a_accept
  bindkey -M viins  'A' shift_a_accept
  bindkey -M menuselect 'A' accept-line
fi
