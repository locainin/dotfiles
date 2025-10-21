# ==============================================================================
# SECTION 4: HELPER FUNCTIONS
# ==============================================================================
# Lightweight utilities shared across the configuration.
# extract unwraps common archive formats with minimal typing
extract() {
  if [[ -f "$1" ]]; then
    case "$1" in
      *.tar.bz2) tar xjf "$1" ;;
      *.tar.gz)  tar xzf "$1" ;;
      *.bz2)     bunzip2 "$1" ;;
      *.rar)     unrar x "$1" ;;
      *.gz)      gunzip "$1" ;;
      *.tar)     tar xf "$1" ;;
      *.tbz2)    tar xjf "$1" ;;
      *.tgz)     tar xzf "$1" ;;
      *.zip)     unzip "$1" ;;
      *.Z)       uncompress "$1" ;;
      *.7z)      7z x "$1" ;;
      *)         echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# ------------------------------------------------------------------------------

# accept *only* zsh-autosuggestions' ghost text if present
# success (0) iff buffer changed
# try_accept_autosuggestion normalizes the autosuggestion acceptance path
try_accept_autosuggestion() {
  local before="$BUFFER"
  if zle -la autosuggest-accept; then
    zle autosuggest-accept
  elif [[ -n ${POSTDISPLAY:-} ]]; then
    # fallback: manually insert ghost text when widget is unavailable
    LBUFFER+="$POSTDISPLAY"
  else
    return 1
  fi
  [[ "$BUFFER" == "$before" ]] && return 1
  return 0
}

# after accepting, if the line is a cd command, optionally jump into the dir
# apply_cd_after_accept handles tilde, quoting, and path fixes
apply_cd_after_accept() {
  if [[ $BUFFER == (cd|builtin\ cd)\ * ]]; then
    local candidate="${BUFFER#* }"
    if [[ $candidate == \"*\" && $candidate == *\" ]]; then
      candidate=${candidate:1:${#candidate}-2}
    elif [[ $candidate == \'*\' && $candidate == *\' ]]; then
      candidate=${candidate:1:${#candidate}-2}
    fi
    if [[ $candidate == \~* ]]; then
      candidate="${candidate/#\~/$HOME}"
    fi
    if [[ -d $candidate ]]; then
      builtin cd -- "$candidate"
      BUFFER=""
      zle reset-prompt
      return 0
    elif [[ -f $candidate ]]; then
      builtin cd -- "${candidate:h}"
      BUFFER=""
      zle reset-prompt
      return 0
    fi
  fi
  return 1
}

# accept inline autosuggestion and (optionally) auto-cd; else fall back to completion
# cd_autosuggest_widget offers a smart Tab-like widget for navigation
cd_autosuggest_widget() {
  if try_accept_autosuggestion; then
    apply_cd_after_accept
    return 0
  fi
  if zle -la accept-and-menu-complete; then
    zle accept-and-menu-complete
  else
    zle complete-word
  fi
}
zle -N cd_autosuggest_widget

# accept autosuggestion if visible, or accept current completion selection
# accept_suggest_or_select prioritizes ghost text while respecting menu selection
accept_suggest_or_select() {
  # if we are in the completion menu, accept highlighted entry
  if [[ ${KEYMAP:-} == menuselect ]]; then
    zle accept-line
    return
  fi

  if try_accept_autosuggestion; then
    apply_cd_after_accept
    return
  fi

  if zle -la accept-and-menu-complete; then
    zle accept-and-menu-complete
  else
    zle complete-word
  fi
}
zle -N accept_suggest_or_select
