# ==============================================================================
# SECTION 2.2: SUDO PASSWORD PROMPT
# ==============================================================================
# Defines a custom sudo password prompt and a quick test helper
# ------------------------------------------------------------------------------

# set colorful sudo password prompt when sudo exists
if command -v sudo >/dev/null 2>&1; then
  export SUDO_PROMPT=$'\033[48;2;75;60;110m  \033[1;38;2;236;240;241mPassword for %p:\033[0m \033[48;2;150;85;180m ▶ \033[0m '
else
  [[ $(typeset -f z_warn) ]] && z_warn "sudo not found; skipping SUDO_PROMPT"
fi

# sudo_prompt_test forces a fresh sudo prompt using our style
sudo_prompt_test() {
  sudo -k
  sudo -p "$SUDO_PROMPT" -v || true
}

# sudoprompt previews the prompt by running a no-op under sudo
alias sudoprompt="sudo -p \"$SUDO_PROMPT\" true"
