# ==============================================================================
# WELCOME BANNER
# ==============================================================================
# Displays a banner on interactive startup depending on BANNER_MODE.
# ------------------------------------------------------------------------------

if [[ -n "$KITTY_SUPPRESS_BANNER" ]]; then
  unset KITTY_SUPPRESS_BANNER
else
  if [[ -t 1 && -z ${_WELCOME_SHOWN:-} ]]; then
    # choose banner style based on BANNER_MODE for quick theming
    case $BANNER_MODE in
      off)
        ;;
      minimal)
        print -P '%F{cyan}Welcome back, %n%f'
        ;;
      classic|*)
        if command -v figlet >/dev/null && command -v lolcat >/dev/null; then
          figlet -f slant "Welcome, $USER!" | lolcat
        else
          print -P '%F{cyan}Welcome, %n%f'
        fi
        if command -v fortune >/dev/null && command -v cowsay >/dev/null && command -v lolcat >/dev/null; then
          fortune | cowsay -f dragon | lolcat
        fi
        ;;
    esac
    typeset -g _WELCOME_SHOWN=1
  fi
fi
