# ==============================================================================
# SECTION 1: CORE CONFIGURATION & BEHAVIOR
# ==============================================================================
# Fundamental Zsh behaviors, history preferences, locale, and helper utilities.
# ------------------------------------------------------------------------------

# --- Core Options -------------------------------------------------------------
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_SILENT
setopt PUSHD_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt EXTENDED_GLOB
setopt SHARE_HISTORY
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt GLOBDOTS
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY_TIME
setopt EXTENDED_HISTORY
setopt HIST_SAVE_NO_DUPS
setopt HIST_EXPIRE_DUPS_FIRST
setopt PROMPT_SUBST
setopt TYPESET_SILENT

# --- History Configuration ----------------------------------------------------
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=200000
export SAVEHIST=200000

# --- Locale and Editor --------------------------------------------------------
export LANG=en_US.UTF-8
if command -v nvim >/dev/null; then
  export EDITOR=nvim
elif command -v vim >/dev/null; then
  export EDITOR=vim
else
  export EDITOR=nano
fi
export VISUAL="$EDITOR"
export PAGER=less
export LESS='-R'

# --- Logging helpers ----------------------------------------------------------
# z_info prints colored info lines when stderr is a TTY
z_info() { [[ -t 2 ]] && print -P "%F{cyan}[zsh]%f $*" >&2 || print "[zsh] $*" >&2 }
# z_warn highlights warnings in yellow for readability
z_warn() { [[ -t 2 ]] && print -P "%F{yellow}[zsh]%f $*" >&2 || print "[zsh] $*" >&2 }
# z_err shows errors in red and always targets stderr
z_err()  { [[ -t 2 ]] && print -P "%F{red}[zsh]%f $*" >&2 || print "[zsh] $*" >&2 }

# enable debug messages by setting ZSH_DEBUG=1
# z_debug respects ZSH_DEBUG so chatter stays opt-in
z_debug() { [[ -n ${ZSH_DEBUG:-} ]] && z_info "debug: $*" }

# --- Missing tools report -----------------------------------------------------
# zsh_report_missing scans core tools and optional extras for visibility
zsh_report_missing() {
  local -a tools=(fzf rg fd git thefuck unrar 7z unzip)
  local -a missing=()
  local tool
  for tool in "${tools[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  [[ -d "$ZSH/custom/plugins/zsh-autosuggestions" ]] || missing+=("zsh-autosuggestions-plugin")
  [[ -d "$ZSH/custom/plugins/zsh-syntax-highlighting" ]] || missing+=("zsh-syntax-highlighting-plugin")
  if (( ${#missing[@]} > 0 )); then
    z_warn "missing: ${missing[*]}"
  fi

  if [[ -n ${ZSH_CHECK_EXTRAS:-} ]]; then
    local -a extras=(figlet lolcat cowsay fortune)
    local -a xmiss=()
    for tool in "${extras[@]}"; do
      command -v "$tool" >/dev/null 2>&1 || xmiss+=("$tool")
    done
    (( ${#xmiss[@]} > 0 )) && z_warn "optional missing: ${xmiss[*]}"
  fi
}
