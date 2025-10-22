# ==============================================================================
# SMART CD (FD-POWERED NAVIGATION)
# ==============================================================================
# Enhances `cd` with fuzzy directory search and optional fzf selection.
# ------------------------------------------------------------------------------

# smartcd augments cd with case-insensitive path resolve, then fd search

# _smartcd_resolve_ci resolves a path case-insensitively per segment
# returns resolved path on stdout if it exists; non-zero if not found
_smartcd_resolve_ci() {
  emulate -L zsh
  setopt localoptions null_glob

  local original="$1"
  [[ -z "$original" ]] && return 1

  local path_in="$original"
  # expand ~ early
  if [[ "$path_in" == \~* && "$path_in" != '~-' && "$path_in" != '~+' ]]; then
    path_in="${path_in/#\~/$HOME}"
  fi

  local current_dir
  local -a parts
  # absolute vs relative
  if [[ "$path_in" == /* ]]; then
    current_dir="/"
  else
    current_dir="$PWD"
  fi

  # split into parts safely
  parts=(${(s:/:)path_in})

  local index=1
  local total=${#parts[@]}
  local seg
  for seg in "${parts[@]}"; do
    # skip empties (from leading / or repeated //)
    [[ -z "$seg" ]] && { (( index++ )); continue }
    # handle dot segments
    if [[ "$seg" == "." ]]; then
      (( index++ ))
      continue
    fi
    if [[ "$seg" == ".." ]]; then
      current_dir="${current_dir:h}"
      (( index++ ))
      continue
    fi

    local target="$current_dir/$seg"
    # exact match first
    if [[ -d "$target" ]]; then
      current_dir="$target"
      (( index++ ))
      continue
    fi

    # case-insensitive match among entries; include hidden only if seg starts with '.'
    local -a candidates
    if [[ "$seg" == .* ]]; then
      candidates=("$current_dir"/.*(/N))
    else
      candidates=("$current_dir"/*(/N))
    fi
    local lower_seg="${seg:l}"
    local matched=""
    local cand
    for cand in "${candidates[@]}"; do
      local name="${cand:t}"
      if [[ "${name:l}" == "$lower_seg" ]]; then
        matched="$name"
        break
      fi
    done
    if [[ -n "$matched" ]]; then
      current_dir="$current_dir/$matched"
      (( index++ ))
      continue
    fi

    # not found at this segment
    return 1
  done

  # final directory must exist
  [[ -d "$current_dir" ]] || return 1
  print -r -- "$current_dir"
}

smartcd() {
  emulate -L zsh
  setopt localoptions pipefail

  if (( $# == 0 )); then
    builtin cd ~
    return
  fi

  local input="$*"
  local arg="$input"

  if [[ "$arg" == "-" ]]; then
    builtin cd -
    return
  fi

  local expanded="$arg"
  if [[ "$expanded" == \~* && "$expanded" != '~-' && "$expanded" != '~+' ]]; then
    expanded="${expanded/#\~/$HOME}"
  fi

  if [[ -d "$expanded" ]]; then
    builtin cd -- "$expanded"
    return
  fi

  # try case-insensitive, segment-wise resolution
  local resolved_ci
  if resolved_ci=$(_smartcd_resolve_ci "$expanded" 2>/dev/null); then
    if [[ -n "$resolved_ci" && -d "$resolved_ci" ]]; then
      builtin cd -- "$resolved_ci"
      return
    fi
  fi

  if ! command -v fd >/dev/null 2>&1; then
    z_warn "fd not found; cannot search for '$arg'"
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
  local pattern="*${arg}*"
  local -a results=()
  local root
  z_debug "smartcd search pattern='$pattern' roots='${(j: :)roots}' depth=$depth"
  local -a fd_opts=(--hidden
                    --exclude .git --exclude node_modules --exclude .venv --exclude venv
                    --exclude dist --exclude build --exclude target --exclude .cache
                    --exclude dosdevices --exclude .wine --exclude .steam
                    --max-depth $depth --glob --color=never -a -t d --max-results 2000)
  if [[ ${SMARTCD_INCLUDE_HIDDEN:-} == 0 ]]; then
    fd_opts=(${fd_opts:#--hidden})
    if [[ $arg == .* ]]; then
      fd_opts+=(--hidden)
    fi
  fi
  local -a found
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    found=(${(f)"$(fd "${fd_opts[@]}" "$pattern" "$root" 2>/dev/null)"})
    (( ${#found[@]} )) && results+=("${found[@]}")
  done
  if (( ${#results[@]} )); then
    # dedupe and filter noisy paths to keep selections clean
    local -a deduped=()
    local -A seen_path
    for candidate in "${results[@]}"; do
      [[ -z $candidate ]] && continue
      case $candidate in
        */dosdevices/*|*/.wine/*|*/.cache/*|*/.steam/*|*/proc/*)
          continue
          ;;
      esac
      if [[ -z ${seen_path[$candidate]:-} ]]; then
        seen_path[$candidate]=1
        deduped+=("$candidate")
      fi
    done
    results=("${deduped[@]}")
  fi
  z_debug "smartcd matches=${#results[@]}"

  if (( ${#results[@]} == 0 )); then
    z_warn "no matches for '$arg'"
    return 1
  fi

  local trimmed="${arg%/}"
  local -a exact_matches=()
  local candidate=""
  for candidate in "${results[@]}"; do
    local base="${candidate%/}"
    base="${base:t}"
    if [[ "$base" == "$trimmed" ]]; then
      exact_matches+=("$candidate")
    fi
  done

  local -a selection_pool=("${results[@]}")
  if (( ${#exact_matches[@]} )); then
    selection_pool=("${exact_matches[@]}")
  fi

  local dest=""
  local interactive=0
  [[ -t 0 && -t 1 ]] && interactive=1
  if (( ${#selection_pool[@]} == 1 )); then
    dest="${selection_pool[1]}"
  elif (( interactive )); then
    local selection=""
    local use_fzf=1
    [[ -n ${SMARTCD_DISABLE_FZF:-} ]] && use_fzf=0
    (( interactive )) || use_fzf=0
    if (( use_fzf )) && command -v fzf >/dev/null 2>&1; then
      local fzf_opts=(--height 40% --layout=reverse --prompt='cd> ' --ansi --header='select destination (ESC to cancel)')
      if [[ -n ${SMARTCD_FZF_OPTS:-} ]]; then
        fzf_opts=(${=SMARTCD_FZF_OPTS})
      fi
      z_debug "smartcd using fzf selector"
      selection=$(printf '%s\n' "${selection_pool[@]}" | fzf "${fzf_opts[@]}")
    else
      z_debug "smartcd using numbered selector"
      local i=1
      for r in "${selection_pool[@]}"; do
        print -r -- "$i) $r"
        i=$(( i + 1 ))
      done
      printf "choose [1-%d]: " ${#selection_pool[@]} >&2
      local idx
      read -r idx
      if [[ "$idx" =~ '^[0-9]+$' && $idx -ge 1 && $idx -le ${#selection_pool[@]} ]]; then
        selection="${selection_pool[$idx]}"
      else
        z_warn "invalid selection"
        return 1
      fi
    fi
    [[ -z "$selection" ]] && return 1
    dest="$selection"
  else
    dest="${selection_pool[1]}"
  fi
  [[ -z "$dest" ]] && return 1

  [[ -f "$dest" ]] && dest="${dest:h}"
  if [[ -d "$dest" ]]; then
    builtin cd -- "$dest"
  else
    z_warn "selected path is not a directory: $dest"
    return 1
  fi
}

alias cd=smartcd
