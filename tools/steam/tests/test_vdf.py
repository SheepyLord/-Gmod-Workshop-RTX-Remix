import unittest

import vdf


class VdfTests(unittest.TestCase):
    def test_nested_blocks_comments_and_escapes(self):
        text = r'''
        // app manifest excerpt
        "AppState"
        {
            "appid"       "4000"
            "name"        "Garry's \"Mod\""
            "path"        "C:\\Program Files (x86)\\Steam"
            "InstalledDepots"
            {
                "4001" { "manifest" "7488132547021413298" "size" "6776360902" }
            }
            unquoted value
        }
        '''
        state = vdf.loads(text)['AppState']
        self.assertEqual(state['appid'], '4000')
        self.assertEqual(state['name'], 'Garry\'s "Mod"')
        self.assertEqual(state['path'], r'C:\Program Files (x86)\Steam')
        self.assertEqual(state['InstalledDepots']['4001']['manifest'], '7488132547021413298')
        self.assertEqual(state['unquoted'], 'value')

    def test_later_duplicate_key_wins(self):
        self.assertEqual(vdf.loads('"a" "1" "a" "2"'), {'a': '2'})

    def test_platform_conditionals_are_skipped(self):
        self.assertEqual(vdf.loads('"a" "1" [$WIN32]\n"b" "2" [!$X360]'), {'a': '1', 'b': '2'})

    def test_unbalanced_braces_raise(self):
        for bad in ('"a" {', '}', '{ "a" "b" }'):
            with self.subTest(text=bad), self.assertRaises(ValueError):
                vdf.loads(bad)


if __name__ == '__main__':
    unittest.main()
