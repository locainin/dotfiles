# ==============================================================================
# SECTION 3: OH MY ZSH - FRAMEWORK & PLUGINS
# ==============================================================================
# Loads Oh My Zsh and configures plugins, deferring theme handling to prompt engine.
# ------------------------------------------------------------------------------

# export root to align with installer
export ZSH="$HOME/.oh-my-zsh"
# theme left blank so custom prompt wins
ZSH_THEME=""

# base plugin stack plus conditional extras
plugins=(git fzf sudo zsh-autosuggestions zsh-syntax-highlighting)
command -v docker  >/dev/null && plugins+=(docker)
command -v kubectl >/dev/null && plugins+=(kubectl)

# source framework only when its script exists
[[ -s "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"
