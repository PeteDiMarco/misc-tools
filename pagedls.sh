#!/bin/bash
# *****************************************************************************
#  Copyright (c) 2019 Pete DiMarco
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
# *****************************************************************************
#
# Name:         pagedls.sh
# Version:      0.1
# Written by:   Pete DiMarco <pete.dimarco.software@gmail.com>
# Date:         2019-11-12
#
# Description:
# Pipes the output of ls to a pager without losing the formatting used by ls
# when it sends its output directly to the terminal.  Passes all parameters
# except --help and --DEBUG to ls.

default_cols=80
default_pager="$(which more)"
ls_cmd="$(which ls)"
my_name=$(basename "${0}")
DEBUG=false

# Prints a debug message.
debug_msg () {
  if [[ "$DEBUG" = true ]]; then
    echo -e "$*"
  fi
}

# Prints help message.
print_help () {
  cat <<HelpInfoHERE
Usage: ${my_name} [--help]
       ${my_name} [--DEBUG] <LS-ARGUMENTS>

Pipes the output of "${ls_cmd}" through a pager without losing any of the
formatting or colors that would appear when "${ls_cmd}" outputs directly to
a terminal.  The default pager is "${default_pager}".  Passes all arguments
except "--help" and "--DEBUG" to "${ls_cmd}".

Optional Arguments:
  --help                Show this help message and exit.
  --DEBUG               Print debugging messages.

Shell Variables:
  LS_OPTIONS            Standard options to "ls".
  PAGEDLS_OPTIONS       Additional options to "ls".  May override LS_OPTIONS.
  QUOTING_STYLE         Used by "ls" to format file names.
  PAGEDLS_PAGER         User's preferred pager.
  PAGER                 If PAGEDLS_PAGER is not defined, use this as the pager.
  MORE                  Parameters to "more".
  LESS                  Parameters to "less".
HelpInfoHERE
  exit 0
}


# Process parameters.
if [[ $# -le 0 ]]; then
  # Look at current directory by default:
  params="."
else
  # Capture all other parameters for ls:
  params="$*"
  # Check if the user supplied "--help" as an option:
  if (echo -e "${params}" | grep -Eqe '(^|[[:space:]])--help($|[[:space:]])'); then
    print_help
  fi
  # Check if the user supplied "--DEBUG" as an option:
  if (echo -e "${params}" | grep -Eqe '(^|[[:space:]])--DEBUG($|[[:space:]])'); then
    DEBUG=true
    # Remove "--DEBUG" from params before passing it to ls:
    params="$(echo -e ${params} | sed -E 's/(^|[[:space:]])--DEBUG($|[[:space:]])/ /')"
  fi
fi

# pagedls_opts is built from LS_OPTIONS.  If LS_OPTIONS contains "--color=auto"
# replace it with --color=always so that ls will pipe colors to more.
pagedls_opts=""
if [[ -n "${LS_OPTIONS}" ]]; then
  pagedls_opts="$(echo -e ${LS_OPTIONS} | sed -E 's/(^|[[:space:]])--color=auto($|[[:space:]])/ --color=always /')"
fi

# Add PAGEDLS_OPTIONS to pagedls_opts:
pagedls_opts="${pagedls_opts} ${PAGEDLS_OPTIONS}"

# If pagedls_opts doesn't contain a "-1" option, then force ls to pipe columns
# of file names to more.
if ! (echo -e "${pagedls_opts}" | grep -Eqe '(^|[[:space:]])-[[:alpha:]]*1'); then
  # Get the number of columns from the terminal:
  columns=$(tput cols)

  # Check if the user supplied "--width=" or "-w" as an option:
  if (echo -e "${pagedls_opts}" | grep -Eqe '(^|[[:space:]])(--width=[0-9]*|-[[:alpha:]]*w)'); then
    pagedls_opts="${pagedls_opts} -C"
  # Else if "tput cols" didn't work, use default_cols:
  elif [[ -z "${columns}" ]]; then
    debug_msg "WARNING: Cannot determine column width of terminal. Assuming ${default_cols}."
    pagedls_opts="${pagedls_opts} -C --width=${default_cols}"
  # Else use columns from the terminal:
  else
    pagedls_opts="${pagedls_opts} -C --width=${columns}"
  fi
fi

# Regex for detecting the following ls options:
#     -N, -Q, --literal, --quoting-style=.*, --quote-name
match_quote='(^|[[:space:]])(-([[:alpha:]]*[NQ]+[[:alpha:]]*)+|--literal|--quoting-style=|--quote-name)($|[[:space:]])'

# If the user did not specify a QUOTING_STYLE:
if [[ -z "${QUOTING_STYLE}" ]]; then
  # If the user did not pass a parameter affecting quoting style:
  if ! (echo -e "${pagedls_opts}" | grep -Eqe "${match_quote}"); then
    # Use the standard quoting style for when ls sends its output to the terminal:
    pagedls_opts="${pagedls_opts} --quoting-style=shell-escape"
  fi
fi

# Figure out which pager to use:
if [[ -n "${PAGEDLS_PAGER}" ]]; then
  debug_msg 'Using PAGEDLS_PAGER.'
  pager="${PAGEDLS_PAGER}"
elif [[ -n "${PAGER}" ]]; then
  debug_msg 'Using PAGER.'
  pager="${PAGER}"
else
  pager="${default_pager}"
fi

# Determine pager options:
pager_opts=''
case "$(basename ${pager})" in
  'more')
    pager_opts="${MORE} -f"     # -f doesn't fold long lines.
    ;;

  'less')
    pager_opts="${LESS}"
    if (echo -e "${pagedls_opts}" | grep -Eqe '(^|[[:space:]])--color=(always|auto)'); then
      pager_opts="${pager_opts} -R"   # Output ANSI "color" escape sequences in "raw" form.
    fi
    ;;

  *)
    debug_msg "WARNING: Unrecognized pager (${pager}). No options supplied."
    ;;
esac

debug_msg "Command to run: ${ls_cmd}" ${pagedls_opts} ${params} '|' "${pager}" ${pager_opts}
"${ls_cmd}" ${pagedls_opts} ${params} | "${pager}" ${pager_opts}

