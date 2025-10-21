# ==============================================================================
# FINAL KEYBIND OVERRIDES (RUNS LAST)
# ==============================================================================
# Ensure our custom widgets win over any plugin defaults regardless of keymap
# ------------------------------------------------------------------------------

# only proceed in interactive ZLE
# re-register widgets to ensure plugin overrides do not win
if [[ -o interactive ]]; then
  # register widgets if defined
  whence -w shift_a_accept >/dev/null 2>&1 && zle -N shift_a_accept
  whence -w accept_suggest_or_select >/dev/null 2>&1 && zle -N accept_suggest_or_select

  # Bind Shift+A in all relevant keymaps so it doesn't fall through to self-insert
  bindkey 'A' shift_a_accept 2>/dev/null || true
  bindkey -M emacs  'A' shift_a_accept 2>/dev/null || true
  bindkey -M viins  'A' shift_a_accept 2>/dev/null || true
  bindkey -M main   'A' shift_a_accept 2>/dev/null || true
  bindkey -M menuselect 'A' accept-line 2>/dev/null || true
fi
