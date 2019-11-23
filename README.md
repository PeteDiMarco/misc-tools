# Miscellaneous Linux Commandline Tools

This is a collection of miscellaneous commandline tools for Posix-like environments.

### Prerequisites

* Python 3.x
* Bash

### Installing

Just copy the files into your local bin directory.  `pagedls.sh` should be aliased to
something more convenient.  To use `myhelp.sh`, create an alias like this:

    alias myhelp="source myhelp.sh"

## Tool Descriptions

### pagedls.sh

Pipes the output of `ls` through a pager without losing any of the formatting or colors that would appear
when `ls` outputs directly to a terminal.  The default pager is `more`.  Passes all
arguments except `--help`
and `--DEBUG` to `ls`.  `pagedls.sh` reads the following shell variables:

*  `LS_OPTIONS` - Standard options to `ls`.
*  `QUOTING_STYLE` - Used by `ls` to format file names.
*  `PAGEDLS_OPTIONS` - Additional options to `ls`.  May override `LS_OPTIONS`.
*  `PAGEDLS_PAGER` - User's preferred pager.
*  `PAGER` - If `PAGEDLS_PAGER` is not defined, use this as the pager.
*  `MORE` -  Parameters to `more`.
*  `LESS` -  Parameters to `less`.


### myhelp.sh

Tries to identify every name provided.  Looks at man pages, info pages, command PATH, aliases, files,
shell variables, and built-in shell commands.

In order for `myhelp.sh`
to read the current shell's variables, this script must either:
1. be run with the `source` command, or
2. have the output of `alias` piped to it.

### otc.py

Implements a cipher similar to a one-time pad.  A binary file can be encrypted
into a text file containing integers with 1 integer per line.  This is done
using a very large binary file as a map.  The map file is accessed either
locally or via a URL.  Decryption is accomplished
by reading the numbers in the encrypted file and using them as indexes into the
map.  Each number in the encrypted file is the index of 1 byte in the map file.

### uncolumn.py

This program will parse a text file that contains multiple columns of text
and return a file of text with those columns in proper sequential order.
It is the opposite of the `column` command.

### untypescript.sh

Strips newlines and ANSI color codes from typescript files.

## Versioning

N/A (yet).

## Authors

* **Pete DiMarco** - *Initial work* - [PeteDiMarco](https://github.com/PeteDiMarco)

## License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file
for details.

