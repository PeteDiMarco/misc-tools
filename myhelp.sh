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
#
# See also:
# http://mywiki.wooledge.org/BashFAQ/081
#
# Dependencies:
# whatis, apropos, file, type, which, alias
# TODO: add ps -e

# Defaults:
DEBUG=false
my_name=$(basename "$0")     # This script's name.
my_shell=$(basename "$BASH")		# This script's shell.
preferred_shell=$(basename "$SHELL")	# User's shell from passwd.
declare -A aliases=()


print_declare () {
    declare -a lines
    local line
    local retval
    local value

    retval=$(declare "$2" | sed -e "s/^declare $2 //" | grep "^$1")
    if [[ $? -eq 0 ]]; then
        debug_msg "print_declare: retval=${retval}"
        IFS='\n' read -ra lines <<< "$retval"
        for line in ${lines[@]}; do
            if [[ "$line" =~ ^"$1"=.*$ ]]; then
                #value=`echo "$retval" | sed -e 's/^[^=]*=//'`
                value=${"$1"}
                echo "$1 is declared as type $3 with the value $value"
            elif [[ "$line" =~ ^"$1" ().*$ ]]; then
                echo "$1 is declared as type $3"
            elif [[ "$line" =~ ^"$1"$ ]]; then
                echo "$1 is declared as type $3 with no value"
            else
                echo "Cannot recognize $line"
                #exit 1
                return 1
            fi
        done
    fi
}


check_declares () {
    debug_msg "check_declares($1)"
    print_declare "$1" '-r' 'read only'
    print_declare "$1" '-i' 'integer'
    print_declare "$1" '-a' 'array'
    print_declare "$1" '-f' 'function'
    print_declare "$1" '-x' 'exported'
}


parse_type () {
    debug_msg "parse_type $1 $2"
    declare -a array
    IFS='\n' read -ra array <<< "$1"
    length=${#array[@]}
    index=0
    while [[ $index < $length ]]; do
        case ${array[$index]} in
            "* is a function")
                echo ${array[$index]}
                ;;

            "* is a shell keyword")
                echo ${array[$index]}
                help -d "$2"
                ;;

            "* is a shell builtin")
                echo ${array[$index]}
                help -d "$2"
                ;;

            "* is aliased to *")
                echo ${array[$index]}
                ;;

            "* \(\)")
                index=$((index + 1))
                while [[ ! ${array[$index]} =~ ^\}[ 	]*$ ]]; do
                    index=$((index + 1))
                done
                ;;

            "* is *")
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
    done
}


debug_msg () {
    if [[ "$DEBUG" = true ]]; then
        echo 'DEBUG: '"$1"
    fi
}


print_help () {
    cat <<HelpInfoHERE
Usage: ${my_name} [-h] [-D] name1 [name2 ...]

Identifies the names provided.  Tries every test imaginable.

Optional Arguments:
  -h, --help            Show this help message and exit.
  -a, --aliases         Read a list of aliases from standard input.
  -D, --DEBUG	        	Set debugging mode.
HelpInfoHERE
}


# Make sure we have the correct version of get_opt:
getopt --test > /dev/null
if [[ $? -ne 4 ]]; then
    echo "ERROR: This script requires the enhanced version of 'getopt'."
    echo "       (Or better yet, rewrite this script in Python.)"
    #exit 4
    return 4
fi

# Parse commandline options:
OPTIONS='hDa'
LONGOPTIONS='help,DEBUG,aliases'

PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTIONS --name "$0" -- "$@")
if [[ $? -ne 0 ]]; then
    # If getopt has complained about wrong arguments to stdout:
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
                key=`echo "$line" | sed -e 's/^alias \([^=]*\).*$/\1/'`
                val=`echo "$line" | sed -e 's/^[^=]*=\(.*\)$/\1/'`
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


which whatis >/dev/null
if [[ $? -eq 0 ]]; then
    whatis_cmd='whatis'
else
    which apropos >/dev/null
    if [[ $? -eq 0 ]]; then
        whatis_cmd='apropos'
    else
        whatis_cmd='asdassd #'
    fi
fi

temp_file=$(mktemp /tmp/${my_name}.XXXXXX)
trap "rm -f $temp_file" 0 2 3 15

while [[ $# -ne 0 ]]; do
    if [[ -z "$1" ]]; then
        shift
        continue
    fi

    debug_msg "before type"

    retval=$(type -a "$1" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        parse_type "$retval" "$1"
    else
        check_declares "$1"
    fi
    debug_msg "type = $retval"

    retval=$( file -b "$1" )
    if [[ ( $? -eq 0 ) && !( "$retval" =~ .*No such file or directory.* ) ]]; then
        echo "File $1 is $retval"
    fi
    debug_msg "file -b = $retval"

#    retval=`info "$1" 2>&1  >/dev/null`
#    if [[ -n "$retval" ]]; then
#        echo "There is an \"info\" page for $1"
#    fi

    retval=$( which -a "$1" 2>/dev/null )
    if [[ $? -eq 0 ]]; then
        echo "There is an executable called $1 here: $retval"
        retval=$( file -b "$retval" )
        if [[ ( $? -eq 0 ) && "$retval" =~ .*No such file or directory.* ]]; then
            echo "File $1 is $retval"
        fi
    fi

    debug_msg "whatis_cmd = $whatis_cmd"
    retval=$( ${whatis_cmd} "$1" 2>/dev/null )
    if [[ $? -eq 0 ]]; then
        echo "There is an \"man\" page for $1: $retval"
    fi

    alias "$1" 2>/dev/null > $temp_file
    if [[ $? -eq 0 ]]; then
        echo "There is an alias for $1: $(cat $temp_file)"
    fi

    if [[ -n aliases["$1"] ]]; then
        echo "There is an alias for $1: $(aliases[$1]) in stdin."
    fi

    shift
done
