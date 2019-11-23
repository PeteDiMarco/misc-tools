#!/bin/bash
#***************************************************************************
#* Copyright 2019 Pete DiMarco
#* 
#* Licensed under the Apache License, Version 2.0 (the "License");
#* you may not use this file except in compliance with the License.
#* You may obtain a copy of the License at
#* 
#*     http://www.apache.org/licenses/LICENSE-2.0
#* 
#* Unless required by applicable law or agreed to in writing, software
#* distributed under the License is distributed on an "AS IS" BASIS,
#* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#* See the License for the specific language governing permissions and
#* limitations under the License.
#***************************************************************************
#
# Name: myhelp.sh
# Version: 0.1
# Date: 2019-10-14
# Written by: Pete DiMarco <pete.dimarco.software@gmail.com>
#
# Description:
# A "super help" command that tries to identify the name(s) provided on the
# commandline.
#
# See also:
# http://mywiki.wooledge.org/BashFAQ/081
#
# Dependencies:
# whatis, apropos, file, type, which, alias, info, ps

# Defaults:
DEBUG=false
my_name=$(basename "$0")              # This script's name.
my_shell=$(basename "$BASH")		      # This script's shell.
preferred_shell=$(basename "$SHELL")	# User's shell from passwd.
declare -A aliases=()


#***************************************************************************
# Functions
#***************************************************************************

#***************************************************************************
# Name:         print_declare
# Description:  Uses the `declare` built-in to determine if $1 is a declared
#               variable or function.  Prints the results.
# Parameters:   $1: Name to look for.
# Returns:      None
#***************************************************************************
print_declare () {
    local retval
    local value
    local attrs
    local attr
    local name
    local full_desc
    local desc
    declare -A attr_desc
    attr_desc['-']='shell variable'
    attr_desc['a']='indexed array'
    attr_desc['A']='associative array'
    attr_desc['i']='integer'
    attr_desc['r']='read-only'
    attr_desc['x']='exported'

    full_desc=''
    retval=$(declare -p "$1" | grep '^declare ' | sed -e 's/^declare \(-[^ ]*\) \(.*\)$/\1 \2/')
    if [[ $? -eq 0 ]]; then
        debug_msg "print_declare: retval=${retval}"
        attrs=$(echo $retval | sed -e 's/^-\([^ ]*\) .*$/\1/' | sed -e 's/\(.\)/\1 /g' )
        name=$(echo $retval | sed -e 's/^[^ ]* //')
        value=''
        if [[ "${name}" == *=* ]]; then
          value=$(echo $name | sed -e 's/^[^=]*=//')
          name=$(echo $name | sed -e 's/=.*$//')
        fi

        for attr in ${attrs}; do
            desc="${attr_desc[$attr]}"
            if [[ -n "${desc}" ]]; then
                if [[ -z "${full_desc}" ]]; then
                    full_desc="${desc}"
                else
                    full_desc="${full_desc}, ${desc}"
                fi
            else
                echo "Unknown attribute: ${attr}"
            fi
        done

        echo "$1 is declared with the following attributes: ${full_desc}"
        if [[ -n "${value}" ]]; then
            echo "$1 has the value: ${value}"
        fi
    fi

    retval=$(declare -f "$1")
    if [[ $? -eq 0 ]]; then
        echo "$1 is declared as a function."
    fi
}

#***************************************************************************
# Name:         parse_type
# Description:  Parses the output of the `type` built-in.  Prints the results.
# Parameters:   $1: Text to parse.
#               $2: Name being examined.
# Returns:      3 if the type is unrecognized.
#***************************************************************************
parse_type () {
    debug_msg "parse_type $1 $2"
    declare -a array
    IFS=$'\r\n' read -ra array <<< "$1"
    length=${#array[@]}
    index=0
    while [[ $index < $length ]]; do
        debug_msg "${index} -> ${array[$index]}"
        case "${array[$index]}" in
            *\ is\ a\ function)
                echo ${array[$index]}
                ;;

            *\ is\ a\ shell\ keyword)
                echo ${array[$index]}
                help -d "$2"
                ;;

            *\ is\ a\ shell\ builtin)
                echo ${array[$index]}
                help -d "$2"
                ;;

            *\ is\ aliased\ to\ *)
                echo ${array[$index]}
                ;;

            *\ \(\))
                index=$((index + 1))
                while [[ ! ${array[$index]} =~ ^\}\s*$ ]]; do
                    index=$((index + 1))
                done
                ;;

            *\ is\ *)
                filename=$(echo ${array[$index]} | sed -e 's/^.* is //')
                echo "$2 is the executable file $filename"
                file -b "$filename"
                ;;

            *)
                echo "Unrecognized type: $1"
                #exit 3
                return 3
                ;;
        esac
        index=$((index + 1))
    done
}

#***************************************************************************
# Name:         debug_msg
# Description:  Prints the message if $DEBUG is true.
# Parameters:   $1: Message.
# Returns:      None.
#***************************************************************************
debug_msg () {
    if [[ "$DEBUG" = true ]]; then
        echo 'DEBUG: '"$1"
    fi
}

#***************************************************************************
# Name:         print_help
# Description:  Prints the help text and exits the script.
# Parameters:   None.
# Returns:      None.
#***************************************************************************
print_help () {
    cat <<HelpInfoHERE
Usage: ${my_name} [-h] [-D] [-a] name1 [name2 ...]

Identifies the names provided.  Tries every test imaginable.  Looks for:
man pages, info pages, executables in PATH, aliases, shell variables, running
processes, shell functions, built-in shell commands, and files relative to
the current working directory.  If called in its own subshell, this script will
not be able to identify variables from the parent shell unless they are
exported.  To get around this, use either:
    source ${my_name} name1 ...
or pipe the current aliases into the script:
    alias | ${my_name} -a name1 ...

Optional Arguments:
  -h, --help            Show this help message and exit.
  -a, --aliases         Read a list of aliases from standard input.
  -D, --DEBUG	          Set debugging mode.
HelpInfoHERE
    exit 0
}


#***************************************************************************
# Main Code
#***************************************************************************

# Get the names of all the running processes.
# Process names in brackets []:
progs=$(ps --no-headers -Ao args -ww | grep '^\[' | sed -Ee 's/^\[([^]/:]+).*$/\1/')
# Process names without brackets:
progs=${progs}$(ps --no-headers -Ao args -ww | grep -v '^\[' | sed -e 's/ .*$//')
progs=$(echo "${progs}" | sort | uniq | xargs basename -a)
debug_msg "Programs running: ${progs}"

# Make sure we have the correct version of get_opt:
getopt --test > /dev/null
if [[ $? -ne 4 ]]; then
    echo "ERROR: This script requires the enhanced version of 'getopt'."
    #exit 4
    return 4
fi

# Parse commandline options:
OPTIONS='hDa'
LONGOPTIONS='help,DEBUG,aliases'

PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    # If getopt has complained about wrong arguments to stdout:
    echo 'Bad arguments.'
    #exit 2
    return 2
fi

# Read getopt's output this way to handle the quoting right:
eval set -- "$PARSED"

# Process options in order:
while true; do
    case "$1" in
        -h|--help)
            print_help
            #exit 0
            return 0
            ;;

        -D|--DEBUG)
            DEBUG=true
            shift
            ;;

        -a|--aliases)
            while IFS= read -r line; do
                key=$(echo "$line" | sed -e 's/^alias \([^=]*\).*$/\1/')
                val=$(echo "$line" | sed -e 's/^[^=]*=\(.*\)$/\1/')
                aliases["$key"]="$val"
            done
            shift
            ;;

        --)             # WHY IS THIS NECESSARY?
            shift
            break
            ;;

        *)
            echo "Unrecognized option: $1"
            print_help
            #exit 3
            return 3
            ;;
    esac
done

# Determine command for searching man pages.
which whatis >/dev/null
if [[ $? -eq 0 ]]; then
    whatis_cmd='whatis'
else
    which apropos >/dev/null
    if [[ $? -eq 0 ]]; then
        whatis_cmd='apropos'
    else
        whatis_cmd='asdassd #'   # This should always fail.
    fi
fi

# We need a temporary file to store the output of `alias`.
temp_file=$(mktemp /tmp/${my_name}.XXXXXX)
trap "rm -f $temp_file" 0 2 3 15

NO_SUCH_FILE_REGEX='.*No such file or directory.*'

# Iterate through all remaining arguments.
while [[ $# -ne 0 ]]; do
    debug_msg "Examining ${1}."

    if [[ -z "$1" ]]; then    # Skip over blanks.
        shift
        continue
    fi

    reference=${!1}       # If $1 is a shell variable, what is its value?
    if [[ -n "${reference}" ]]; then
      echo "There is a shell variable named ${1} with value: ${reference}"
    fi

    # Use `type` built-in.
    retval=$( type -a "$1" 2>/dev/null )
    if [[ $? -eq 0 ]]; then
        parse_type "$retval" "$1"
    else
        print_declare "$1"
    fi

    # Test with `file`.
    retval=$( file -b "$1" )
    if [[ $? -eq 0 ]] && ! [[ "${retval}" =~ $NO_SUCH_FILE_REGEX ]]; then
        echo "File $1 is $retval"
    fi

    # Check if `info` has a page.
    INFO_NO_MENU_REGEX='^info: No menu item .*'
    INFO_NO_NODE_REGEX='^info: Cannot find node .*'
    retval=$( info -o - "$1" 2>&1 )
    if [[ -n "$retval" ]] && ! [[ "$retval" =~ $INFO_NO_MENU_REGEX ]] \
          && ! [[ "$retval" =~ $INFO_NO_NODE_REGEX ]]; then
        echo "There is an \"info\" page for $1."
    fi

    # Use `which`.
    retval=$( which -a "$1" 2>/dev/null )
    if [[ $? -eq 0 ]]; then
        echo "There is an executable called $1 here: $retval"
        retval=$( file -b "$retval" )
        if [[ $? -eq 0 ]] && ! [[ "${retval}" =~ $NO_SUCH_FILE_REGEX ]]; then
            echo "File $1 is $retval"
        fi
    fi

    # Check for a `man` page.
    retval=$( ${whatis_cmd} "$1" 2>/dev/null )
    if [[ $? -eq 0 ]]; then
        echo "There is an \"man\" page for $1: $retval"
    fi

    # Check aliases in the current shell.
    alias "$1" 2>/dev/null > $temp_file     # Can't create sub-shell w/o losing aliases.
    if [[ $? -eq 0 ]]; then
        echo "There is an alias for $1: $(cat $temp_file)"
    fi

    # If aliases are piped in:
    if [[ -n "${aliases[$1]}" ]]; then
        echo "There is an alias for $1: ${aliases[$1]} in stdin."
    fi

    # Is this program running?
    echo "${progs}" | grep "^$1\$" >/dev/null
    if [[ $? -eq 0 ]]; then
        echo "There is at least one process running called $1."
    fi

    shift
done
