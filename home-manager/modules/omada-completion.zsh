#compdef omada

_omada() {
  local help_text line option metavar
  local in_commands=0
  local -a command_path commands operation_commands specs

  if (( CURRENT == 2 )); then
    help_text="$(command omada --help 2>/dev/null)" || return 1
  elif [[ "${words[2]}" == "schema" ]] && (( CURRENT == 3 )); then
    help_text="$(command omada --help 2>/dev/null)" || return 1
  else
    command_path=("${words[2]}")
    if [[ "${words[2]}" == (spec|sites|help) && "${words[3]}" != -* ]] && (( CURRENT > 3 )); then
      command_path+=("${words[3]}")
    fi
    help_text="$(command omada "${command_path[@]}" --help 2>/dev/null)" || return 1
  fi

  while IFS= read -r line; do
    if [[ "$line" == "Commands:" ]]; then
      in_commands=1
      continue
    fi
    if (( in_commands )) && [[ "$line" == "Options:"* ]]; then
      in_commands=0
    fi
    if (( in_commands )) && [[ "$line" =~ '^  ([^[:space:]]+)([[:space:]].*)?$' ]]; then
      commands+=("${match[1]}")
    fi
  done <<< "$help_text"

  if (( CURRENT == 2 )); then
    _describe "command" commands
    return
  fi

  if [[ "${words[2]}" == "schema" ]] && (( CURRENT == 3 )); then
    for option in "${commands[@]}"; do
      case "$option" in
        auth|config|help|list|schema|sites|spec) ;;
        *) operation_commands+=("$option") ;;
      esac
    done
    _describe "operation" operation_commands
    return
  fi

  if (( ${#commands} )); then
    _describe "command" commands
    return
  fi

  while IFS= read -r line; do
    if [[ "$line" =~ '^[[:space:]]+(-[^,]+,[[:space:]]+)?--([^[:space:]]+)([[:space:]]+<([^>]+)>)?' ]]; then
      option="--${match[2]}"
      metavar="${match[4]}"
      if [[ -n "$metavar" ]]; then
        specs+=("$option:$metavar:")
      else
        specs+=("$option")
      fi
    fi
  done <<< "$help_text"

  words=("${(@)words[2,-1]}")
  (( CURRENT-- ))
  _arguments -s -S "${specs[@]}" '*:argument:'
}

_omada "$@"
