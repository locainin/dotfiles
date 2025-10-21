# ==============================================================================
# SECTION 7: PROMPT THEME ENGINE
# ==============================================================================
# Switches between external engines and custom prompt themes.
# ------------------------------------------------------------------------------

typeset -gA _PROMPT
# decide runtime prompt engine with graceful fallbacks
case $PROMPT_ENGINE in
  starship)
    if command -v starship >/dev/null; then
      _PROMPT[engine]=starship
    else
      _PROMPT[engine]=custom
      PROMPT_ENGINE=custom
      [[ -t 2 ]] && print -P '%F{yellow}[zsh-config]%f starship not found, using custom prompt.' >&2
    fi
    ;;
  p10k)
    if [[ -f ~/.p10k.zsh ]]; then
      _PROMPT[engine]=p10k
    else
      _PROMPT[engine]=custom
      PROMPT_ENGINE=custom
      [[ -t 2 ]] && print -P '%F{yellow}[zsh-config]%f powerlevel10k config not found, using custom prompt.' >&2
    fi
    ;;
  auto)
    if command -v starship >/dev/null; then
      _PROMPT[engine]=starship
    elif [[ -f ~/.p10k.zsh ]]; then
      _PROMPT[engine]=p10k
    else
      _PROMPT[engine]=custom
    fi
    ;;
  custom|*)
    _PROMPT[engine]=custom
    ;;
esac
_PROMPT[profile]=$PROMPT_PROFILE

case ${_PROMPT[engine]} in
  starship)
    eval "$(starship init zsh)"
    ;;
  p10k)
    source ~/.p10k.zsh
    ;;
esac

if [[ ${_PROMPT[engine]} = custom ]]; then
  typeset -ga SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  typeset -g SPIN_IDX=0
# zsh_spinner_precmd advances spinner frame each prompt refresh
  zsh_spinner_precmd() { SPIN_IDX=$(( (SPIN_IDX+1) % ${#SPINNER[@]} )); }
  add-zsh-hook precmd zsh_spinner_precmd

  autoload -Uz vcs_info
  zstyle ':vcs_info:git*' formats '%F{magenta} %b%f%F{red}%u%f'
  zstyle ':vcs_info:git*' check-for-changes true
  zstyle ':vcs_info:*' enable git
# precmd_vcs_info refreshes git metadata ahead of prompt rendering
  precmd_vcs_info() { vcs_info }
  add-zsh-hook precmd precmd_vcs_info

# git_prompt_segment prints the formatted vcs info in color
  git_prompt_segment() {
    local color=${1:-214}
    [[ -n ${vcs_info_msg_0_} ]] || return
    printf ' %s%s%s' "%F{${color}}" "${vcs_info_msg_0_}" "%f"
  }

# venv_prompt_segment advertises active python environment
  venv_prompt_segment() {
    local env_path=""
    if [[ -n "$VIRTUAL_ENV" ]]; then
      env_path="$VIRTUAL_ENV"
    elif [[ -n "$AUTO_VENV_ACTIVE_DIR" ]]; then
      env_path="$AUTO_VENV_ACTIVE_DIR"
    fi

    if [[ -n "$env_path" ]]; then
      printf '%%F{green}(%s)%%f ' "${env_path:t}"
    fi
  }

# configure_custom_prompt assembles prompt variants by profile id
  configure_custom_prompt() {
    local spinner_segment='${SPINNER[$SPIN_IDX]}'
    local venv_segment='$(venv_prompt_segment)'
    local git_segment_214='$(git_prompt_segment 214)'
    local git_segment_213='$(git_prompt_segment 213)'
    local git_segment_45='$(git_prompt_segment 45)'
    local newline=$'\n'

    case ${_PROMPT[profile]} in
      1)
        PROMPT="${spinner_segment} ${venv_segment}%F{81}╭─╼%f %F{cyan}%n%f@%F{magenta}%m%f %F{81}╾─╮%f${newline}%F{81}╰─╼%f %F{cyan}%~%f${git_segment_214}${newline}%F{214}❯%f "
        ;;
      2)
        PROMPT="${spinner_segment} ${venv_segment}%F{214}➤%f %F{cyan}%~%f${git_segment_45} %F{214}➤%f "
        ;;
      3)
        PROMPT="${spinner_segment} ${venv_segment}%F{39}╓%f %F{cyan}%~%f %F{39}╖%f${newline}%F{39}╙%f %F{221}λ%f${git_segment_213} "
        ;;
      4)
        PROMPT="${spinner_segment} ${venv_segment}%F{45}%~%f${git_segment_213} %B%F{214}%#%f%b "
        ;;
      5)
        PROMPT="${spinner_segment} ${venv_segment}%F{244}%*%f %F{81}%n%f@%F{219}%m%f %F{45}%1~%f${git_segment_45} %F{214}›%f "
        ;;
      6)
        PROMPT="${spinner_segment} %F{244}┌─[%f %F{cyan}%~%f %F{244}]%f${git_segment_214}${newline}${venv_segment}%F{244}└╼%f %F{81}%n%f@%F{219}%m%f %F{214}❱%f "
        ;;
      7)
        PROMPT="${spinner_segment} ${venv_segment}%F{51}╭════╮%f %F{cyan}%~%f${git_segment_213}${newline}%F{51}╰════╯%f %F{220}➜%f "
        ;;
      8)
        PROMPT="${spinner_segment} ${venv_segment}%F{244}[ %F{213}%n%f :: %F{cyan}%~%f %F{244}]%f${git_segment_213} %F{221}⚡%f "
        ;;
      9)
        PROMPT="${spinner_segment} ${venv_segment}%F{44}◆%f %F{cyan}%1~%f %F{44}◆%f${git_segment_45}${newline}%F{44}◇%f "
        ;;
      10)
        PROMPT="${spinner_segment} ${venv_segment}%F{219}▹%f %F{81}%*%f${git_segment_213}${newline}%F{219}▹%f %F{cyan}%~%f %F{214}→%f "
        ;;
      *)
        _PROMPT[profile]=1
        configure_custom_prompt
        ;;
    esac
  }

# promptstyle switches between available custom prompt profiles
  promptstyle() {
    local current=${_PROMPT[profile]:-${PROMPT_PROFILE:-1}}
    if [[ -z $1 || $1 == list ]]; then
      cat <<'MENU'
Prompt styles (set with `promptstyle <number>`):
  1) Skyline arc stack (spinner + multi-line arcs)
  2) Vector arrow minimal (single-line sweep)
  3) Lambda lab two-line (λ highlight)
  4) Retro glyph classic (spinner + git + prompt char)
  5) Chrono ribbon (timestamp + identity)
  6) Blueprint frame (boxed cwd with footer)
  7) Flux wave (dual-line wave & arrow)
  8) Neon capsule (bracketed block + lightning)
  9) Crystal facets (diamond stack)
 10) Twilight drift (time & path cascade)
MENU
      print -P "Current style: %F{cyan}${current}%f"
      return 0
    fi

    if [[ $1 =~ '^(10|[1-9])$' ]]; then
      PROMPT_PROFILE=$1
      _PROMPT[profile]=$PROMPT_PROFILE
      configure_custom_prompt
      print -P "%F{green}[zsh-config]%f prompt style set to %F{cyan}$PROMPT_PROFILE%f"
    else
      print -P "%F{red}[zsh-config]%f choose a number from 1 to 10" >&2
      return 1
    fi
  }

  configure_custom_prompt
fi
