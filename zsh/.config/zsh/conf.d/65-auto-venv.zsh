# ==============================================================================
# PYTHON AUTO-VIRTUALENV
# ==============================================================================
# Automatically activates and deactivates project-local Python virtualenvs.
# ------------------------------------------------------------------------------

export VIRTUAL_ENV_DISABLE_PROMPT=1
typeset -g AUTO_VENV_ACTIVE_DIR=""
typeset -g AUTO_VENV_PROJECT_ROOT=""

# auto_venv activates nearest python env and backs out when leaving tree
auto_venv() {
  if [[ -n "$AUTO_VENV_ACTIVE_DIR" && -z "$VIRTUAL_ENV" ]]; then
    AUTO_VENV_ACTIVE_DIR=""
    AUTO_VENV_PROJECT_ROOT=""
  fi

  if [[ -n "$AUTO_VENV_ACTIVE_DIR" ]]; then
    # ensure we drop stale state when env disappeared or we left the project
    if [[ ! -d "$AUTO_VENV_ACTIVE_DIR" ]]; then
      deactivate 2>/dev/null || true
      AUTO_VENV_ACTIVE_DIR=""
      AUTO_VENV_PROJECT_ROOT=""
    else
      case "$PWD" in
        "$AUTO_VENV_PROJECT_ROOT"|"$AUTO_VENV_PROJECT_ROOT"/*)
          ;;
        *)
          if [[ "$VIRTUAL_ENV" == "$AUTO_VENV_ACTIVE_DIR" ]]; then
            deactivate 2>/dev/null || true
          fi
          AUTO_VENV_ACTIVE_DIR=""
          AUTO_VENV_PROJECT_ROOT=""
          ;;
      esac
    fi
  fi

  local search_dir="$PWD"
  local found_env=""
  local project_root=""
  local -a env_candidates=(.venv venv)
  while true; do
    local candidate_name=""
    for candidate_name in "${env_candidates[@]}"; do
      local candidate_dir="$search_dir/$candidate_name"
      if [[ -f "$candidate_dir/bin/activate" ]]; then
        found_env="$candidate_dir"
        project_root="$search_dir"
        break 2
      fi
    done
    if [[ "$search_dir" == "/" || "$search_dir" == "$HOME" ]]; then
      break
    fi
    local parent_dir="${search_dir:h}"
    if [[ "$parent_dir" == "$search_dir" ]]; then
      break
    fi
    search_dir="$parent_dir"
  done

  if [[ -n "$found_env" ]]; then
    # activate new environment and remember project root for exit checks
    if [[ "$VIRTUAL_ENV" != "$found_env" ]]; then
      source "$found_env/bin/activate"
    fi
    AUTO_VENV_ACTIVE_DIR="$found_env"
    AUTO_VENV_PROJECT_ROOT="$project_root"
    return
  fi

  if [[ -n "$AUTO_VENV_ACTIVE_DIR" && "$VIRTUAL_ENV" == "$AUTO_VENV_ACTIVE_DIR" ]]; then
    # leaving project tree so tear down active virtualenv
    deactivate 2>/dev/null || true
    AUTO_VENV_ACTIVE_DIR=""
    AUTO_VENV_PROJECT_ROOT=""
  fi
}

add-zsh-hook precmd auto_venv
auto_venv
