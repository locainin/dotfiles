# ==============================================================================
# PLUGIN SOURCING (POST-COMPINIT)
# ==============================================================================
# Explicitly source autosuggestions and syntax highlighting after completion.
# ------------------------------------------------------------------------------

# Autosuggestions should load after compinit; prefer system path but fall back
# to the OMZ custom directory when available
if [[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
elif [[ -r ${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source ${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# Syntax highlighting must be sourced last to preserve color overrides
if [[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [[ -r ${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source ${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
