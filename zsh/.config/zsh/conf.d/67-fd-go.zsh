# ==============================================================================
# FD-GO NAVIGATION
# ==============================================================================
# Quick token-based directory jumps backed by fd and optional fzf selection.
# ------------------------------------------------------------------------------

# fd_go searches directories with fd and jumps in a single command
fd_go() {
  emulate -L zsh
  setopt localoptions pipefail

  local query="$*"
  if [[ -z "$query" ]]; then
    z_warn "usage: fd_go <query>"
    return 1
  fi
  if ! command -v fd >/dev/null 2>&1; then
    z_warn "fd not found; cannot search"
    return 1
  fi

  local -a roots
  if [[ -n ${SMARTCD_SEARCH_ROOTS:-} ]]; then
    roots=(${=SMARTCD_SEARCH_ROOTS})
  else
    roots=()
    roots+=("$PWD")
    [[ -d "$HOME/Documents" ]] && roots+=("$HOME/Documents")
    roots+=("$HOME")
  fi
  local -a unique_roots=()
  local -A seen_root
  local candidate_root
  for candidate_root in "${roots[@]}"; do
    [[ -d "$candidate_root" ]] || continue
    if [[ -z ${seen_root[$candidate_root]:-} ]]; then
      seen_root[$candidate_root]=1
      unique_roots+=("$candidate_root")
    fi
  done
  roots=("${unique_roots[@]}")

  local depth=${SMARTCD_MAX_DEPTH:-8}
  local pattern="*${query}*"
  z_debug "fd_go pattern='$pattern' roots='${(j: :)roots}' depth=$depth"
  local -a results=()
  local -a fd_opts=(--follow
                    --exclude .git --exclude node_modules --exclude .venv --exclude venv
                    --exclude dist --exclude build --exclude target --exclude .cache
                    --max-depth $depth --glob --color=never -a -t d --max-results 2000)
  if [[ ${SMARTCD_INCLUDE_HIDDEN:-} == 1 || $query == .* ]]; then
    fd_opts+=(--hidden)
  fi
  for candidate_root in "${roots[@]}"; do
    local found
    found=(${(f)"$(fd "${fd_opts[@]}" "$pattern" "$candidate_root" 2>/dev/null)"})
    (( ${#found[@]} )) && results+=("${found[@]}")
  done
  if (( ${#results[@]} )); then
    # dedupe matches so fzf list stays readable
    local -a deduped=()
    local -A seen_path
    local entry
    for entry in "${results[@]}"; do
      if [[ -z ${seen_path[$entry]:-} ]]; then
        seen_path[$entry]=1
        deduped+=("$entry")
      fi
    done
    results=("${deduped[@]}")
  fi
  z_debug "fd_go matches=${#results[@]}"

  if (( ${#results[@]} == 0 )); then
    z_warn "no matches for '$query'"
    return 1
  fi

  local interactive=0
  [[ -t 0 && -t 1 ]] && interactive=1
  local dest=""
  if (( ${#results[@]} == 1 )) || (( ! interactive )); then
    dest="${results[1]}"
  else
    local selection=""
    local use_fzf=1
    [[ -n ${SMARTCD_DISABLE_FZF:-} ]] && use_fzf=0
    (( interactive )) || use_fzf=0
    if (( use_fzf )) && command -v fzf >/dev/null 2>&1; then
      z_info "fd_go: ${#results[@]} matches for '$query' (fzf select)"
      local fzf_opts=(--height 40% --layout=reverse --prompt='goto> ' --ansi --header='select destination (ESC to cancel)')
      if [[ -n ${SMARTCD_FZF_OPTS:-} ]]; then
        fzf_opts=(${=SMARTCD_FZF_OPTS})
      fi
      selection=$(printf '%s\n' "${results[@]}" | fzf "${fzf_opts[@]}")
    else
      z_info "fd_go: ${#results[@]} matches for '$query' (enter number)"
      local i=1
      for entry in "${results[@]}"; do
        print -r -- "$i) $entry"
        i=$(( i + 1 ))
      done
      printf "choose [1-%d]: " ${#results[@]} >&2
      local idx
      read -r idx
      if [[ "$idx" =~ '^[0-9]+$' && $idx -ge 1 && $idx -le ${#results[@]} ]]; then
        selection="${results[$idx]}"
      else
        z_warn "invalid selection"
        return 1
      fi
    fi
    [[ -z "$selection" ]] && return 1
    dest="$selection"
  fi

  [[ -f "$dest" ]] && dest="${dest:h}"
  if [[ -d "$dest" ]]; then
    builtin cd -- "$dest"
  else
    z_warn "selected path is not a directory: $dest"
    return 1
  fi
}

# fd_go_widget captures token under cursor and feeds fd_go
fd_go_widget() {
  local token
  token="${LBUFFER##* }"
  [[ -z "$token" ]] && token="$BUFFER"
  if [[ -z "$token" ]]; then
    zle -M "no token to search"
    return
  fi
  fd_go "$token" || zle beep
  BUFFER=""
  zle reset-prompt
}

if [[ -o zle ]]; then
  zle -N fd_go_widget
  bindkey -M emacs '^[g' fd_go_widget
  bindkey -M viins  '^[g' fd_go_widget
fi
