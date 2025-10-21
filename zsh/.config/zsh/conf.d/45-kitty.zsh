# kitty specific overrides so behavior matches expectations inside kitty
# redefine clear so kitty scrollback is wiped using escape 3J
if [[ -n "$KITTY_WINDOW_ID" ]]; then
  clear() {
    command clear "$@"
    printf '\033[3J'
  }
fi
