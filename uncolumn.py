#!/usr/bin/env python3
# ***************************************************************************
# * Copyright 2019 Pete DiMarco
# *
# * Licensed under the Apache License, Version 2.0 (the "License");
# * you may not use this file except in compliance with the License.
# * You may obtain a copy of the License at
# *
# *     http://www.apache.org/licenses/LICENSE-2.0
# *
# * Unless required by applicable law or agreed to in writing, software
# * distributed under the License is distributed on an "AS IS" BASIS,
# * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# * See the License for the specific language governing permissions and
# * limitations under the License.
# ***************************************************************************
#
# Name: uncolumn.py
# Version: 0.1
# Date: 2019-09-22
# Written by: Pete DiMarco <pete.dimarco.software@gmail.com>
#
# Description:
# This program will parse a text file that contains multiple columns of text
# and return a file of text with those columns in order.  E.g.:
#     uncolumn.py -c 30,60 -i testfile
# "-c 30,60" means there are 3 columns in the text file:  The first starts at
# position 1, the second starts at position 30, and the third starts at
# position 60.  uncolumn.py will return the first column followed by the second
# followed by the third.
#
# Dependencies:
# Python 3.x

import os
import sys
import re
import argparse

# Defaults:
program_name = os.path.basename(sys.argv[0])
epilog = f"""
This program will parse a text file that contains multiple columns of text
and return a file of text with those columns in proper sequential order.

Example (in Vim):
     :8,19 ! {program_name} -c 30,60
will take lines 8 through 19 and pass them to {program_name}.  "-c 30,60" means
there are 3 columns in the text file:  The first starts at position 1, the
second starts at position 30, and the third starts at position 60.
uncolumn.py will return the first column followed by the second followed by
the third.
"""


if __name__ == "__main__":
    # Parse command line arguments:
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Takes a stream containing columns of text and returns a single column.",
        epilog=epilog,
    )
    parser.add_argument(
        "-c",
        "--columns",
        type=str,
        help="Start position of text columns separated by commas.  Counts from 1.",
    )
    parser.add_argument(
        "-i",
        "--input",
        default="",
        type=str,
        nargs="?",
        help="Input file.  Defaults to stdin.",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="",
        type=str,
        nargs="?",
        help="Output file.  Defaults to stdout.",
    )
    parser.add_argument(
        "-t",
        "--tabsize",
        default=8,
        type=int,
        help="Tab character width.  Defaults to 8.",
    )
    parser.add_argument(
        "-f",
        "--force",
        action="store_true",
        default=False,
        help="Force overwrite of output file.",
    )
    parser.add_argument(
        "-D",
        "--DEBUG",
        action="store_true",
        default=False,
        help="Enable debugging mode.",
    )
    args = parser.parse_args()
    DEBUG = args.DEBUG

    # Parse and normalize column numbers.
    column_inds = []
    for c in args.columns.split(","):
        col = int(c.strip()) - 1
        if col < 0:
            print("Column number must be greater than 0.")
            parser.print_help()
            exit(1)
        column_inds.append(col)

    if len(column_inds) < 1:
        print("Enter a list of 1 or more column numbers separated by commas.")
        parser.print_help()
        exit(1)

    # The first column always starts with 0.
    if column_inds[0] != 0:
        column_inds.insert(0, 0)
    # The last column index is always the end of the string.
    if column_inds[-1] != -1:
        column_inds.append(-1)

    # If no input file, use stdin:
    if not args.input:
        infile = sys.stdin
    elif os.path.exists(args.input):
        infile = open(args.input, "r")
    else:
        print("Unable to open input file.")
        parser.print_help()
        exit(1)

    # If no output file, use stdout:
    if not args.output:
        outfile = sys.stdout
    elif not os.path.exists(args.output) or args.force:
        outfile = open(args.output, "w")
    else:
        print("Unable to open output file.")
        parser.print_help()
        exit(1)

    # Create a list of slice objects to apply to lines of the file.
    slices = []
    for ind in range(len(column_inds) - 1):
        slices.append(slice(column_inds[ind], column_inds[ind + 1]))
    num_cols = len(slices)  # Number of slices == number of columns in the text.
    output_buffers = [""] * num_cols  # 1 buffer per column.

    for line in infile:
        line = line.expandtabs(args.tabsize)
        for col in range(num_cols):
            # Copy slice of line to appropriate buffer:
            output_buffers[col] += line[slices[col]] + "\n"

    for buff in output_buffers:
        outfile.write(buff)

    infile.close()
    outfile.close()

    exit(0)

