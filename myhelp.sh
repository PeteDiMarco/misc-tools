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
# man, file, type, which, alias, info, ps

# Defaults:
DEBUG=false
FOUND=false				# Found something about current argument.
my_name=$(basename "$0")		# This script's name.
my_shell=$(basename "$BASH")		# This script's shell.
preferred_shell=$(basename "$SHELL")	# User's shell from passwd.
declare -A ALIASES=()			# Hash of aliases to values.
declare -A PACKAGES=()			# Hash of package types to package lists.

NO_SUCH_FILE_REGEX='.*No such file or directory.*'
SHELL_VAR_REGEX='^\$.+$'

# We need a temporary file to store the output of `alias`.
temp_file=$(mktemp /tmp/${my_name}.XXXXXX)
trap "rm -f $temp_file" 0 2 3 15

# Are we being sourced?
(return 0 2>/dev/null) && SOURCED=1 || SOURCED=0


#***************************************************************************
# Functions
#***************************************************************************

#***************************************************************************
# Name:         print_declare
# Description:  Uses the `declare` built-in to determine if $1 is a declared
#               variable or function.  Prints the results.
# Parameters:   $1: Name to look for.
# Globals:      FOUND
# Returns:      None
#***************************************************************************
print_declare () {
    local retval value attrs attr name full_desc='' desc
    local -A attr_desc

    # Map `declare` attributes to descriptions.
    attr_desc['-']='shell variable'
    attr_desc['a']='indexed array'
    attr_desc['A']='associative array'
    attr_desc['i']='integer'
    attr_desc['r']='read-only'
    attr_desc['x']='exported'

    # Extract attributes followed by NAME or NAME=VALUE:
    retval=$( declare -p "$1" 2>/dev/null | grep '^declare ' | \
              sed -e 's/^declare \(-[^ ]*\) \(.*\)$/\1 \2/')
    if [[ $? -eq 0 ]] && [[ -n "${retval}" ]]; then
        debug_msg "print_declare: retval=${retval}"
        attrs=$( sed -e 's/^-\([^ ]*\) .*$/\1/' <<< $retval | sed -e 's/\(.\)/\1 /g' )
        name=$( sed -e 's/^[^ ]* //' <<< $retval )
        value=''
        if [[ "${name}" == *=* ]]; then
          value=$( sed -e 's/^[^=]*=//' <<< $name )
          name=$( sed -e 's/=.*$//' <<< $name )
        fi

        # For each attribute, add its description to full_desc:
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

        # Print results:
        echo "$1 is declared with the following attributes: ${full_desc}"
        if [[ -n "${value}" ]]; then
            echo "$1 has the value: ${value}"
            FOUND=true
        fi
    fi

    # Look for shell functions:
    retval=$(declare -f "$1")
    if [[ $? -eq 0 ]]; then
        echo "$1 is declared as a function."
        FOUND=true
    fi
}

#***************************************************************************
# Name:         parse_type
# Description:  Parses the output of the `type` built-in.  Prints the results.
# Parameters:   $1: Text to parse.
#               $2: Name being examined.
# Globals:      FOUND
# Returns:      3 if the type is unrecognized.
#***************************************************************************
parse_type () {
    local length index=0
    local -a array

    debug_msg "parse_type $1 $2"
    IFS=$'\r\n' read -ra array <<< "$1"
    length=${#array[@]}
    while [[ $index < $length ]]; do
        debug_msg "${index} -> ${array[$index]}"
        case "${array[$index]}" in
            *\ is\ a\ function)
                echo ${array[$index]}
                FOUND=true
                ;;

            *\ is\ a\ shell\ keyword)
                echo ${array[$index]}
                FOUND=true
                help -d "$2"
                ;;

            *\ is\ a\ shell\ builtin)
                echo ${array[$index]}
                FOUND=true
                help -d "$2"
                ;;

            *\ is\ aliased\ to\ *)
                echo ${array[$index]}
                FOUND=true
                ;;

            *\ is\ hashed\ \(*)
                echo 'WARNING: ' ${array[$index]} '.  USE "hash -r" TO CLEAR.'
                FOUND=true
                ;;

            *\ \(\))
                index=$((index + 1))
                while [[ ! ${array[$index]} =~ ^\}\s*$ ]]; do
                    index=$((index + 1))
                done
                ;;

            *\ is\ *)
                filename=$( sed -e 's/^.* is //' <<< ${array[$index]} )
                echo "$2 is the executable file $filename"
                FOUND=true
                ;;

            *)
                echo "ERROR: Unrecognized type: $1"
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
# Globals:      DEBUG
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
# Globals:      my_name
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
  -D, --DEBUG	        Set debugging mode.
HelpInfoHERE
}

#***************************************************************************
# Name:         check_variable
# Description:  Checks if parameter is a shell variable.  If it is, prints
#               its value.
# Parameters:   $1: Possible shell variable.
# Globals:      FOUND
# Returns:      None.
#***************************************************************************
check_variable () {
    local reference
    export bad_sub_test=$1
    # Must check in sub-shell first to catch "bad substitution" errors.
    bash -c 'echo "${!bad_sub_test}" 2>&1 >/dev/null' >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        reference=${!1}       # If $1 is a shell variable, what is its value?
        if [[ -n "${reference}" ]]; then
            echo "There is a shell variable named ${1} with value: ${reference}"
            FOUND=true
        fi
    fi
}

#***************************************************************************
# Name:         print_file_type
# Description:  Checks if parameter is a file.  Prints its file type.
# Parameters:   $1: One or more possible file names.
# Globals:      FOUND
# Returns:      None.
#***************************************************************************
print_file_type () {
    local retval line
    for line in "$1"; do
        retval=$( file -b "${line}" )
        if [[ $? -eq 0 ]] && ! [[ "${retval}" =~ $NO_SUCH_FILE_REGEX ]]; then
            echo "File ${line} is ${retval}."
            FOUND=true
        fi
    done
}

#***************************************************************************
# Name:         read_packages
# Description:  Reads a list of packages into the PACKAGES hash.
# Parameters:   $1: Package type
#               $2: Package command
#               $3: Package command filter
# Globals:      PACKAGES
# Returns:      None.
#***************************************************************************
read_packages() {
    debug_msg "read_packages: $1, $2, $3"

    if [[ -n "${PACKAGES[$1]}" ]]; then
        echo "ERROR: PACKAGES already contains a list of type ${1}.  It's value is:"
        echo "${PACKAGES[$1]}"
        return 1
    fi

#    PACKAGES["$1"]=
    if which "$2" >/dev/null 2>&1; then
        PACKAGES["$1"]=$(eval $3)
    fi
}

#***************************************************************************
# Name:         search_packages
# Description:  Searches lists of packages in the PACKAGES hash.
# Parameters:   $1: Package name
# Globals:      PACKAGES
# Returns:      None.
#***************************************************************************
search_packages() {
    local k

    debug_msg "search_packages: $1"

    for k in "${!PACKAGES[@]}"
    do
        if [[ -n "${PACKAGES[$k]}" ]]; then
            if grep "^$1\$" >/dev/null 2>&1 <<< ${PACKAGES[$k]}; then
                echo "There is a $k called $1."
                FOUND=true
            fi
        fi
    done
}


#***************************************************************************
# Main Code
#***************************************************************************

# Make sure we have the correct version of get_opt:
getopt --test > /dev/null
if [[ $? -ne 4 ]]; then
    echo "ERROR: This script requires the enhanced version of 'getopt'."
    if [[ "${SOURCED}" -eq 1 ]]; then
        return 4
    else
        exit 4
    fi
fi

# Parse commandline options:
OPTIONS='hDa'
LONGOPTIONS='help,DEBUG,aliases'

PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    # If getopt has complained about wrong arguments to stdout:
    echo 'ERROR: Bad arguments.'
    if [[ "${SOURCED}" -eq 1 ]]; then
        return 2
    else
        exit 2
    fi
fi

# Read getopt's output this way to handle the quoting right:
eval set -- "$PARSED"

# Process options in order:
while true; do
    case "$1" in
        -h|--help)
            print_help
            if [[ "${SOURCED}" -eq 1 ]]; then
                return 0
            else
                exit 0
            fi
            ;;

        -D|--DEBUG)
            DEBUG=true
            shift
            ;;

        -a|--aliases)
            while IFS= read -r line; do
                key=$(sed -e 's/^alias \([^=]*\).*$/\1/' <<< "$line")
                val=$(sed -e 's/^[^=]*=\(.*\)$/\1/' <<< "$line")
                ALIASES["$key"]="$val"
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
            if [[ "${SOURCED}" -eq 1 ]]; then
                return 3
            else
                exit 3
            fi
            ;;
    esac
done


# If the user supplies more than 1 argument, print a blank line between each
# report.
separate=$(( $# > 1 ))

# Get scannable lists:

# Get the names of all the running processes.
# Process names in brackets []:
progs=$(ps --no-headers -Ao args -ww | grep '^\[' | sed -Ee 's/^\[([^]/:]+).*$/\1/')
# Process names without brackets and append to progs:
progs=${progs}$(ps --no-headers -Ao args -ww | grep -v '^\[' | sed -e 's/ .*$//')
# Filter and sort progs:
progs=$(echo "${progs}" | sort | uniq | xargs basename -a)

read_packages 'KDE applet' 'kpackagetool5' \
              "kpackagetool5 --list --type Plasma/Applet -g | \
               grep -v '^Listing service types:' | sed -e 's/^org\.kde\.plasma\.//'"

read_packages 'Debian package' 'dpkg' \
              "dpkg -l | grep '^ii'| sed -e 's/   */\t/g' | cut -f 2 | sed -e 's/:.*$//'"

read_packages 'Snap package' 'snap' \
              "snap list --all | sed -e 's/ .*$//'"

read_packages 'Red Hat package' 'rpm' \
              "rpm -qa"

read_packages 'Ruby package' 'gem' \
              "gem list | sed -e 's/ (.*$//'"

read_packages 'Python package' 'pip' \
              "pip list 2>/dev/null | sed -e 's/  .*$//'"

read_packages 'Python2 package' 'pip2' \
              "pip2 list 2>/dev/null | sed -e 's/  .*$//'"

read_packages 'Python3 package' 'pip3' \
              "pip3 list 2>/dev/null | sed -e 's/  .*$//'"

read_packages 'Python conda package' 'conda' \
              "conda list | sed -e 's/  .*$//'"

#read_packages 'Node JavaScript package' 'npm' \
#              "npm ls -parseable"

#read_packages 'Yarn JavaScript package' 'yarn' \
#              "yarn list"

# TODO:  Rust: cargo or rustup?
# Perl or PHP?


# Iterate through all remaining arguments.
while [[ $# -ne 0 ]]; do
    debug_msg "Examining ${1}."
    FOUND=false

    if [[ -z "$1" ]]; then    # Skip over blanks.
        shift
        continue
    fi

    if [[ "$1" =~ $SHELL_VAR_REGEX ]]; then
        retval=$( sed -e 's/^\$//' <<< "$1" )
        check_variable "${retval}"
    fi

    check_variable "$1"

    # Use `type` built-in.
    retval=$( type -a "$1" 2>/dev/null )
    if [[ $? -eq 0 ]]; then
        parse_type "$retval" "$1"
    else
        print_declare "$1"
    fi

    print_file_type "$1"

    # Check if `info` has a page.
    retval=$( info -w "$1" )
    if [[ $? -eq 0 ]] && [[ -n "$retval" ]] && [[ "$retval" != 'dir' ]] \
       && [[ $(readlink -f "${retval}") != $(readlink -f "$1") ]]; then
        echo "There is an \"info\" page for $1."
        FOUND=true
    fi

    # Use `which`.
    retval=$( which -a "$1" 2>/dev/null )
    if [[ $? -eq 0 ]]; then
        if [[ "${1}" =~ ^/ ]]; then
            # We have an absolute path.
            echo "There is an executable called $1."
        elif [[ $(wc -l <<< "${retval}") -gt 1 ]]; then
            # We have several paths.
            echo "There is are several executables called $1 here:"
            echo "${retval}"
        else
            echo "There is an executable called $1 here: $retval"
        fi
        print_file_type "${retval}"
    fi

    # Check for a `man` page.
    retval=$( man --whatis "$1" 2>/dev/null )
    if [[ $? -eq 0 ]]; then
        echo "There is a \"man\" page for $1: $retval"
        FOUND=true
    fi

    # Check aliases in the current shell.
    alias "$1" 2>/dev/null > $temp_file     # Can't create sub-shell w/o losing aliases.
    if [[ $? -eq 0 ]]; then
        echo "There is an alias for $1: $(cat $temp_file)"
        FOUND=true
    fi

    # If aliases are piped in:
    if [[ -n "${ALIASES[$1]}" ]]; then
        echo "There is an alias for $1 in stdin: ${ALIASES[$1]}"
        FOUND=true
    fi

    # Is this program running?
    if [[ -n "${progs}" ]]; then
        if grep "^$1\$" >/dev/null 2>&1 <<< ${progs}; then
            echo "There is at least one process running called $1."
            FOUND=true
        fi
    fi

    # Is this a package?
    search_packages "$1"

    if [[ "${FOUND}" == false ]]; then
        echo "Nothing found for \"$1\"."
    fi

    if [[ "${separate}" == 1 ]]; then
        echo
    fi

    shift
done

