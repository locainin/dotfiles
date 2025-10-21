# ==============================================================================
# LOCAL ENVIRONMENT OVERRIDES
# ==============================================================================
# Miscellaneous exports and command-specific aliases.
# ------------------------------------------------------------------------------

# GOPATH defaults to user-scoped go workspace
export GOPATH="$HOME/.go"
if command -v thefuck >/dev/null 2>&1; then
  # hook thefuck alias only when binary is present
  eval "$(thefuck --alias)"
else
  z_warn "thefuck not found; alias not enabled"
fi
