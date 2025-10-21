# ==============================================================================
# PLUGIN CONFIGURATION (AUTOSUGGESTIONS / HIGHLIGHTING)
# ==============================================================================

# zsh-autosuggestions tuning for responsiveness and visibility
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_USE_ASYNC=1
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=50000
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

# zsh-syntax-highlighting should be loaded late; OMZ plugin ordering already
# places it after autosuggestions in our plugins array.
