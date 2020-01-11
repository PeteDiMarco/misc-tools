#!/usr/bin/env python3
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
# Name:         otc.py
# Version:      0.1
# Written by:   Pete DiMarco <pete.dimarco.software@gmail.com>
# Date:         2019-11-06

#import getpass
import os
import sys
import argparse
import psutil
import random
import requests
import tempfile
from urllib.parse import urlparse

Epilog = """
Description:

Implements a cipher similar to a one-time pad.  A binary file can be encrypted
into a text file containing integers with 1 integer per line.  This is done
using a very large binary file as a map.  The map file is accessed either
locally or via a URL.  The file name or URL may be passed on the commandline or
(preferably) entered interactively like a password.  Decryption is accomplished
by reading the numbers in the encrypted file and using them as indexes into the
map.  Each number in the encrypted file is the index of 1 byte in the map file.
"""
DEBUG = False


class MapError(Exception):
    """
    Exception class for problems with map files.
    """
    def __init__(self, message):
        self.message = message


def read_file(file_name: str):
    """
    Reads the contents of a file into 1 large string.
    :param file_name: Name of file to read.
    :type file_name: str
    :return: Contents of file.
    :rtype: str
    """
    result = ""
    if os.path.exists(file_name) and os.path.isfile(file_name):
        try:
            fp = open(file_name, "rb")
            result = fp.read()
            fp.close()
        except:
            raise PermissionError(file_name)
    else:
        raise FileNotFoundError(file_name)
    return result


def ask(question: str, default=None):
    """
    If "default" is None, prompts the user with "question" for a "yes" or "no"
    answer and returns a boolean.  Otherwise prompts the user to enter a string
    which will be converted to the type of "default".  If the user enters an
    empty string then return "default".
    :param question: Question to ask user.
    :type question: str
    :param default: Default object to return if this is not a true/false question.
    :type default: Object
    :return: Either true or false, or an object of type "default".
    :rtype: bool or Object
    """
    if default is None:
        while True:
            answer = input(question + " ").lower().lstrip()
            if len(answer) == 0 or answer[0] == "y":
                return True
            elif answer[0] == "n":
                return False
            else:
                print('Please enter "yes" or "no".')
                print('Just pressing <Enter> is assumed to mean "yes".')
    else:
        new_question = f"{question} (default={str(default)}) "
        answer = input(new_question)
        if len(answer) == 0:  # If the user pressed <Enter> then
            return default  # return default, else convert answer
        else:  # (which is a str) to default's type.
            return type(default)(answer)


def open_output_file(file_name: str, binary: bool, force: bool = False):
    """
    Opens a file for output or returns stdout.
    :param file_name: Name of output file or "".
    :param binary: Write output as binary file.
    :param force: Force overwrite of output file if it already exists.
    :return: File object.
    """
    if file_name == "":
        return sys.stdout.buffer if binary else sys.stdout
    else:
        mode = "wb" if binary else "w"
        if (
            not os.path.exists(file_name)
            or force
            or ask(f"Overwrite existing {file_name}?")
        ):
            return open(file_name, mode)
        else:
            print("Will not overwrite output file %s." % file_name)
            raise FileExistsError(file_name)


class EncryptMap:
    """
    A dictionary that maps byte values (0-255) to lists of indexes into a file.
    """

    class TrackedList:
        """
        A list with an built-in index to the next available element.
        """

        def __init__(self, first):
            self.index = 0
            self.list = [first]

        def append(self, elt):
            self.list.append(elt)

#        def next(self):
#            retval = self.list[self.index]  # Throws an exception if out of range.
#            self.index += 1
#            return retval

        def reset(self):
            self.index = 0

        def __iter__(self):
            return self

        def __next__(self):
            """
            This method is handling state and informing
            the container of the iterator where we are
            currently pointing to within our data collection.
            """
            if self.index > len(self.list)-1:
                raise StopIteration

            value = self.list[self.index]
            self.index += 1
            return value

    def __init__(self, map_fp, strict: bool = True):
        """
        :param map_fp: Input file or stream.
        :type map_fp: File
        :param strict: Never reuse an index in the map file.
        :type strict: bool
        """
        self.map_fp = map_fp
        self.strict = strict
        self.map = dict()
        index = 0
        for byte in map_fp.read():
            if byte in self.map:
                self.map[byte].append(index)
            else:
                self.map[byte] = EncryptMap.TrackedList(index)
            index += 1
        self.verify()
        self.shuffle()

    def shuffle(self):
        """
        Shuffle the order of every index in the map.
        """
        for key in self.map:
            random.shuffle(self.map[key].list)

    def verify(self):
        """
        Ensure that the map contains indexes for every possible byte.
        """
        if len(self.map) != 256:
            raise MapError("Gaps in map file.")

    @staticmethod
    def assess_file(map_fp, silent: bool = False):
        """
        Scans a potential map file to determine if it contains values 0 to 255.
        Prints statistics.
        :param map_fp: Map file
        :type map_fp: file object
        :param silent: Don't print statistics.
        :type silent: bool
        :return: True if contains all byte values, False otherwise.
        :rtype: bool
        """
        byte_counts = [0] * 256
        current_byte = map_fp.read(1)
        while len(current_byte) == 1:
            byte_counts[int.from_bytes(current_byte, byteorder='little')] += 1
            current_byte = map_fp.read(1)
        minimum = min(byte_counts)
        if not silent:
            print(f"The smallest number of instances of a byte is {minimum}.")
        return minimum != 0

    @staticmethod
    def find_next_byte(fp, target_byte, index: int):
        """
        Scans a file or stream looking for "target_byte".  If found, returns its position.
        Otherwise exits with an error.  Will wrap around to the beginning of the file
        if necessary, but only scans the file once.
        :param fp: File or stream to read from.
        :type fp: File
        :param target_byte: Byte we are looking for.
        :type target_byte:
        :param index: Starting position in file.
        :type index: int
        :return: Position in file where "target_byte" was found.
        :rtype: int
        """
        new_index = index
        current_byte = fp.read(1)
        while len(current_byte) == 1 and current_byte != target_byte:
            current_byte = fp.read(1)
            new_index += 1
        if current_byte == target_byte:
            return new_index
        elif len(current_byte) != 1:
            new_index = 0
            fp.seek(new_index)
            current_byte = fp.read(1)
            while (
                len(current_byte) == 1 and new_index < index and current_byte != target_byte
            ):
                current_byte = fp.read(1)
                new_index += 1
            if current_byte == target_byte:
                return new_index
            else:
                raise MapError("Gaps in map file.")

    def encode(self, byte: int):
        """
        Returns a position of "byte" in the map.
        :param byte:
        :type byte: int
        :return: index of "byte" in the map.
        :rtype: int
        """
        try:
            index = next(self.map[byte])
        except IndexError:
            raise MapError(f"Map does not contain the key {byte}.")
        except StopIteration:
            # If self.strict is True, then fail with error.
            # Otherwise, do self.map[byte].reset(), then next(self.map[byte]).
            if self.strict:
                raise MapError("Map file not complex enough.")
            else:
                self.map[byte].reset()
                index = next(self.map[byte])
        return index


if __name__ == "__main__":
    # Parse command line arguments:
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="Performs one-time cypher on file.",
        epilog=Epilog,
    )
    parser.add_argument(
        "-i",
        "--input",
        type=str,
        default="",
        help="Name of the file to read.  Assumes STDIN if not supplied.",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="",
        help="Name of the file to write.  Assumes STDOUT if not supplied.",
    )
    parser.add_argument(
        "-m",
        "--map",
        type=str,
        default="",
        help="Name of map file or URL.  If not provided on the commandline, the user will be prompted interactively.",
    )
    parser.add_argument(
        "-e",
        "--encrypt",
        action="store_true",
        default=False,
        help="Encrypt file or input stream.",
    )
    parser.add_argument(
        "-d",
        "--decrypt",
        action="store_true",
        default=False,
        help="Decrypt file or input stream.",
    )
    parser.add_argument(
        "-t",
        "--testmap",
        action="store_true",
        default=False,
        help="Tests suitability of map file (coverage, size).",
    )
    parser.add_argument(
        "-f",
        "--force",
        action="store_true",
        default=False,
        help="Force overwrite of the output file.",
    )
    parser.add_argument(
        "-s",
        "--strict",
        action="store_true",
        default=False,
        help="Encrypt mode only: Require all indexes are unique.",
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

    if sum([int(args.encrypt), int(args.decrypt), int(args.testmap)]) != 1:
        print("One, and only one, of the following must be specified:")
        print("\t--encrypt, --decrypt, or --testmap")
        parser.print_help()
        exit(1)

    if args.map == "":
        #args.map = getpass.getpass("Enter a URL or path to a file to serve as a map: ")
        args.map = input("Enter a URL or path to a file to serve as a map: ")

    if urlparse(args.map).scheme in ["", "file"]:
        # If no URL scheme, assume local file.
        map_size = os.path.getsize(args.map)
        map_fp = open(args.map, "rb")
    else:
        # Else open the URL to get the map file.
        map_data = requests.get(args.map)
        map_size = len(map_data.content)
        map_fp = tempfile.TemporaryFile()
        map_fp.write(map_data.content)
        map_fp.seek(0)

    # If we just want to test a potential map file:
    if args.testmap:
        EncryptMap.assess_file(map_fp)
        map_fp.close()
        exit(0)

    free_memory = psutil.virtual_memory().available
    if DEBUG:
        print(f"map_size = {map_size:d}, free_memory = {free_memory:d}")

    # If decrypting then we want map file as single linear string, input file
    # as a text file, and output file as a binary file.
    if args.decrypt:
        if args.input == "":
            input_fp = sys.stdin
        else:
            input_fp = open(args.input, "r")

        output_fp = open_output_file(args.output, True, args.force)

        if map_size > free_memory:
            # If map won't fit in RAM, then read it incrementally.
            if DEBUG:
                print("WARNING: Map data will not fit in memory. Using filesystem.")
            for line in input_fp:
                map_fp.seek(int(line))
                output_fp.write(map_fp.read(1))
        else:  # Else read the entire map file.
            map_bytes = map_fp.read()
            for line in input_fp:
                index = int(line)
                output_fp.write(map_bytes[index : index + 1])

    # Else if encrypting then we want map file loaded into an EncryptMap object, input file
    # as a binary file, and output file as a text file.
    elif args.encrypt:
        if args.input == "":
            input_fp = sys.stdin.buffer
        else:
            input_fp = open(args.input, "rb")

        output_fp = open_output_file(args.output, False, args.force)

        if map_size > free_memory:
            # If map won't fit in RAM, then read it incrementally.
            if DEBUG:
                print("WARNING: Map data will not fit in memory. Using filesystem.")
            if args.strict:
                print("WARNING: Map is too large to enforce --strict.")
            map_index = 0
            byte = input_fp.read(1)
            while len(byte) == 1:
                map_index = EncryptMap.find_next_byte(map_fp, byte, map_index)
                output_fp.write(f"{map_index:d}\n")
                byte = input_fp.read(1)
        else:
            map_obj = EncryptMap(map_fp, args.strict)
            byte = input_fp.read(1)
            while len(byte) == 1:
                try:
                    index = map_obj.encode(byte[0])
                except MapError:
                    print(f'ERROR: Map file "{args.map}" is too small to use with --strict.')
                    exit(1)
                output_fp.write(f"{index:d}\n")
                byte = input_fp.read(1)

    map_fp.close()
    input_fp.close()
    output_fp.close()
