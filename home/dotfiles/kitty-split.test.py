"""Tests for kitty-split.py, run with `kitty +launch` for kitty's own Pair."""

import importlib.util
import sys
import unittest

from kitty.layout.splits import Pair

spec = importlib.util.spec_from_file_location("kitty_split", sys.argv.pop(1))
kitty_split = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kitty_split)

SIDEBAR, EDITOR, NEW, OTHER = 1, 2, 3, 4


def sidebar_pair(bias=0.2):
    """Return the tree after a split of the editor beside its sidebar."""
    pair = Pair(horizontal=True)
    pair.bias = bias
    pair.one, pair.two = SIDEBAR, EDITOR
    pair.split_and_add(EDITOR, NEW, True, True)
    return pair


class RegroupTest(unittest.TestCase):
    def test_vsplit_groups_sidebar_with_editor(self):
        pair = sidebar_pair()
        kitty_split.regroup(pair, SIDEBAR, EDITOR, NEW, True)
        self.assertTrue(pair.horizontal)
        self.assertEqual(pair.bias, 0.5)
        self.assertEqual(pair.two, NEW)
        self.assertEqual((pair.one.one, pair.one.two), (SIDEBAR, EDITOR))

    def test_vsplit_keeps_sidebar_width(self):
        pair = sidebar_pair()
        kitty_split.regroup(pair, SIDEBAR, EDITOR, NEW, True)
        self.assertAlmostEqual(pair.one.bias, 0.4)

    def test_hsplit_keeps_sidebar_share(self):
        pair = sidebar_pair()
        kitty_split.regroup(pair, SIDEBAR, EDITOR, NEW, False)
        self.assertFalse(pair.horizontal)
        self.assertAlmostEqual(pair.one.bias, 0.2)

    def test_sidebar_on_the_right(self):
        pair = Pair(horizontal=True)
        pair.bias = 0.8
        pair.one, pair.two = EDITOR, SIDEBAR
        pair.split_and_add(EDITOR, NEW, True, True)
        kitty_split.regroup(pair, SIDEBAR, EDITOR, NEW, True)
        self.assertEqual((pair.one.one, pair.one.two), (EDITOR, SIDEBAR))
        self.assertAlmostEqual(pair.one.bias, 0.6)

    def test_separated_sidebar_is_left_alone(self):
        pair = Pair(horizontal=True)
        pair.one, pair.two = SIDEBAR, OTHER
        kitty_split.regroup(pair, SIDEBAR, EDITOR, NEW, True)
        self.assertEqual((pair.one, pair.two), (SIDEBAR, OTHER))


unittest.main(argv=sys.argv[:1])
