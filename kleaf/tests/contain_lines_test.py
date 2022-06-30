# Copyright (C) 2022 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Compare pairs of files. The files specified in --actual must
contain all lines from the corresponding file specified in --expected.

Order of lines does not matter. For example, if actual contains lines
["foo", "bar", "baz"] and expected contains ["bar", "foo"], test passes.

Duplicated lines are counted. For example, if actual contains lines
["foo"] and expected contains ["foo", "foo"], test fails because two "foo"s
are expected.

The actual and expected file are correlated by the file name.
Example:
  contain_lines_test \
    --actual foo.txt bar.txt \
    --expected expected/bar.txt expected/foo.txt
This command checks that foo.txt contains all lines in expected/foo.txt
and bar.txt contains all lines in expected/bar.txt.
"""

import argparse
import collections
import unittest
import sys
import os

from absl.testing import absltest


def load_arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("--actual", nargs="*", help="actual files")
    parser.add_argument("--expected", nargs="*", help="expected files")
    return parser.parse_known_args()


arguments = None


def _read_non_empty_lines(path):
    with open(path) as f:
        lines = f.readlines()
        lines = [line.strip() for line in lines]
        lines = [line for line in lines if line]
    return lines


class CompareTest(unittest.TestCase):
    def test_all(self):
        # Turn lists into a dictionary from basename to the value. Duplications
        # in basename are not allowed.
        actual = collections.defaultdict()
        actual.update({os.path.basename(path): path for path in arguments.actual})
        self.assertEquals(len(actual), len(arguments.actual))

        expected = collections.defaultdict()
        expected.update({os.path.basename(path): path for path in arguments.expected})
        self.assertEquals(len(expected), len(arguments.expected))

        test_cases = set() | actual.keys() | expected.keys()

        for test_case in test_cases:
            with self.subTest(test_case):
                self._expect_contain_lines(test_case=test_case, actual=actual[test_case],
                                           expected=expected[test_case])

    def _expect_contain_lines(self, test_case, actual, expected):
        self.assertIsNotNone(actual, f"missing actual file for {test_case}")
        self.assertIsNotNone(expected, f"missing expected file for {test_case}")

        actual_lines = collections.Counter(_read_non_empty_lines(actual))
        expected_lines = collections.Counter(_read_non_empty_lines(expected))
        diff = expected_lines - actual_lines
        self.assertFalse(diff,
                         f"{actual} does not contain all lines from {expected}, missing\n" +
                         ("\n".join(diff.elements())))


if __name__ == '__main__':
    arguments, unknown = load_arguments()
    sys.argv[1:] = unknown
    absltest.main()
