"""Behavior regressions for native brush glass, loose broken glass and the networked shard data."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
ADDON = REPO / 'packages/fixes/garrysmod/garrysmod/addons/Glass-Rewrite-Remix'

# GLua, the game's Lua, adds // and /* */ comments, !, !=, && and || and continue to Lua 5.1.
TOKEN = re.compile(r'''
    (?P<long>--\[(?P<ceq>=*)\[.*?\](?P=ceq)\]|\[(?P<seq>=*)\[.*?\](?P=seq)\])
  | (?P<comment>--[^\n]*)
  | (?P<cline>//[^\n]*)
  | (?P<cblock>/\*.*?\*/)
  | (?P<string>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>!=|&&|\|\||!)
  | (?P<other>.)
''', re.S | re.X)
OPERATORS = {'!=': '~=', '&&': ' and ', '||': ' or ', '!': ' not '}


def glua_to_lua(source):
    """The same program in plain Lua for LuaJIT: comments rewritten, the operators spelled out, and a
    continue turned into a goto to a label at the end of its loop."""
    out, blocks, labels = [], [], 0
    for match in TOKEN.finditer(source):
        kind, text = match.lastgroup, match.group()
        if kind == 'cline':
            text = '--' + text[2:]
        elif kind == 'cblock':
            text = '--[==[' + text[2:-2] + ']==]'
        elif kind == 'op':
            text = OPERATORS[text]
        elif kind == 'name':
            if text in ('function', 'if', 'repeat'):
                blocks.append({'kind': text})
            elif text in ('for', 'while'):
                blocks.append({'kind': 'loop', 'header': True})
            elif text == 'do':
                if blocks and blocks[-1].get('header'):
                    blocks[-1]['header'] = False  # the loop's own do
                else:
                    blocks.append({'kind': 'do'})
            elif text in ('end', 'until'):
                block = blocks.pop()
                if block.get('label'):
                    text = '::%s:: %s' % (block['label'], text)
            elif text == 'continue':
                loop = next((b for b in reversed(blocks) if b['kind'] in ('loop', 'repeat', 'function')), None)
                if not loop or loop['kind'] != 'loop':
                    raise ValueError('continue outside a for or while loop')
                if 'label' not in loop:
                    labels += 1
                    loop['label'] = 'continue_%d' % labels
                text = 'goto ' + loop['label']
        out.append(text)
    if blocks:
        raise ValueError('unbalanced blocks: %s' % blocks)
    return ''.join(out)


def luajit():
    found = shutil.which('luajit')
    local = Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
    return found or (str(local) if local.is_file() else None)


def run_harness(addon, folder):
    """Runs glass_map_harness.lua against an add-on folder; the GLua sources it executes are converted
    into `folder` first."""
    paths = []
    for relative in ('lua/autorun/networking.lua', 'lua/entities/procedural_shard.lua', 'lua/world_functions.lua'):
        target = Path(folder) / Path(relative).name
        target.write_text(glua_to_lua((Path(addon) / relative).read_text(encoding='utf-8')), encoding='utf-8')
        paths.append(str(target))
    return subprocess.run([luajit(), str(REPO / 'tools/tests/glass_map_harness.lua'), str(addon), *paths],
                          cwd=REPO, capture_output=True, encoding='utf-8', errors='replace', timeout=120)


class GlassMapTests(unittest.TestCase):
    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_actual_geometry_native_break_loose_glass_lifecycle_and_packet_writer(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='glass-map-', dir=scratch) as folder:
            result = run_harness(ADDON, folder)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('all glass map assertions passed', result.stdout)

    @unittest.skipUnless(luajit(), 'LuaJIT is not installed')
    def test_glua_conversion_keeps_the_program(self):
        source = ('local out = {} // GLua comment\n'
                  '/* block\ncomment */\n'
                  'for i = 1, 6 do\n'
                  '    local skip = i % 2 == 0\n'
                  '    if skip && i != 6 then continue end\n'
                  '    for j = 1, 2 do if j == 2 then continue end out[#out + 1] = i * 10 + j end\n'
                  '    while true do break end\n'
                  '    if !skip || i == 6 then out[#out + 1] = "s!=" .. i end\n'
                  'end\n'
                  'print(table.concat(out, ","))\n')
        converted = glua_to_lua(source)
        self.assertIn('goto continue_', converted)
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='glua-', dir=scratch) as folder:
            path = Path(folder) / 'program.lua'
            path.write_text(converted, encoding='utf-8')
            result = subprocess.run([luajit(), str(path)], capture_output=True, encoding='utf-8', timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), '11,s!=1,31,s!=3,51,s!=5,61,s!=6')
        with self.assertRaises(ValueError):
            glua_to_lua('function f() continue end')


if __name__ == '__main__':
    unittest.main()
