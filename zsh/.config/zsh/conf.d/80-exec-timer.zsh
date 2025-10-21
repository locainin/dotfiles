# ==============================================================================
# COMMAND EXECUTION TIMER
# ==============================================================================
# Adds an RPROMPT segment showing runtime of the previous command.
# ------------------------------------------------------------------------------

# format_elapsed_time turns seconds into human friendly string
format_elapsed_time() {
  local total_seconds=$1
  (( total_seconds < 0 )) && total_seconds=0

  local hours=$(( total_seconds / 3600 ))
  local minutes=$(( (total_seconds % 3600) / 60 ))
  local seconds=$(( total_seconds % 60 ))
  local -a time_parts=()

  (( hours > 0 )) && time_parts+=("${hours}h")
  (( minutes > 0 )) && time_parts+=("${minutes}m")
  if (( seconds > 0 || ${#time_parts[@]} == 0 )); then
    time_parts+=("${seconds}s")
  fi

  printf '%s' "${(j: :)time_parts}"
}

# command_time_preexec captures start timestamp before command runs
command_time_preexec() {
  unset _command_start_time
  _command_start_time=$SECONDS
}

# command_time_precmd computes elapsed time and sets RPROMPT accordingly
command_time_precmd() {
  if [[ -n $_command_start_time ]]; then
    local elapsed=$((SECONDS - _command_start_time))
    if [[ $elapsed -ge 3 ]]; then
      local formatted_duration
      formatted_duration=$(format_elapsed_time "$elapsed")
      RPROMPT="%F{226}[took: %F{33}${formatted_duration}%F{226}]%f"
    else
      RPROMPT=""
    fi
    unset _command_start_time
  fi
}

add-zsh-hook preexec command_time_preexec
add-zsh-hook precmd command_time_precmd
