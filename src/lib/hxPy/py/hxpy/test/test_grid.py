# -*- coding: utf-8 -*-
#
# Copyright (c) 2021, SkyFoundry LLC
# Licensed under the Academic Free License version 3.0
#
# History:
#   13 Dec 2021  Matthew Giannini  Creation
#

import unittest

from hxpy.haystack import Grid, GridBuilder


class TestGrid(unittest.TestCase):

    def test_to_dataframe(self):
        g = GridBuilder().add_col_names(["a", "b", "c"]).add_row([1, 2, 3]).to_grid()
        self.assertEqual(g.col_names(), ["a", "b", "c"])
        f = g.to_dataframe()
        self.assertEqual(f.columns.values.tolist(), ["a", "b", "c"])
        self.assertEqual(f.values.tolist()[0], [1, 2, 3])

        g2 = Grid.from_dataframe(f)
        self.assertEqual(g2.col_names(), ["a","b","c"])
        self.assertEqual(g2.rows()[0].cells(), [1, 2, 3])


# TestGrid