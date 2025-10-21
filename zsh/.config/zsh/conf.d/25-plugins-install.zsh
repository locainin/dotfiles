# ==============================================================================
# PLUGIN INSTALLER (OH-MY-ZSH + COMMUNITY PLUGINS)
# ==============================================================================
# Ensures Oh My Zsh + selected plugins exist locally. Idempotent and silent.
# ------------------------------------------------------------------------------

# establish ZSH root for subsequent lookups
if [[ -z ${ZSH:-} ]]; then
  export ZSH="$HOME/.oh-my-zsh"
fi

# install Oh My Zsh if missing (git clone to avoid remote scripts)
if [[ ! -s "$ZSH/oh-my-zsh.sh" ]]; then
  command -v git >/dev/null 2>&1 && {
    mkdir -p "${ZSH:h}"
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$ZSH" >/dev/null 2>&1 || true
  }
fi

# plugin roots so we can drop community extras predictably
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$ZSH/custom}"
PLUG_DIR="$ZSH_CUSTOM_DIR/plugins"
mkdir -p "$PLUG_DIR"

# zsh-autosuggestions managed via shallow clone for speed
if [[ ! -d "$PLUG_DIR/zsh-autosuggestions" ]]; then
  command -v git >/dev/null 2>&1 && {
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$PLUG_DIR/zsh-autosuggestions" >/dev/null 2>&1 || true
  }
fi

# zsh-syntax-highlighting synced in identical fashion
if [[ ! -d "$PLUG_DIR/zsh-syntax-highlighting" ]]; then
  command -v git >/dev/null 2>&1 && {
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$PLUG_DIR/zsh-syntax-highlighting" >/dev/null 2>&1 || true
  }
fi
