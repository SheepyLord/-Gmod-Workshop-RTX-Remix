"""Attach the R10-H probes to a locked PoC session started by poc_session.py."""
import argparse
import ctypes
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import poc_session as poc

REPO = Path(__file__).resolve().parents[2]
POC = Path(r'H:\SteamLibrary\steamapps\common\GarrysMod_PoC')
LOCK = Path(r'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\r10\poc.lock')


def main():
    ctypes.windll.user32.SetProcessDPIAware()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--mode', choices=('npc', 'expressions'), required=True)
    ap.add_argument('--maps', nargs='*', default=['gm_flatgrass', 'gm_construct'])
    ap.add_argument('--prefix', default='1c2ed2fc', help='library asset hash prefix in NPC mode')
    ap.add_argument('--cold-first', action='store_true', help='first create the NPC only after the first map change')
    args = ap.parse_args()
    if len(args.prefix)<8 or any(c not in '0123456789abcdef' for c in args.prefix):
        ap.error('prefix must contain at least eight lowercase hex digits')
    if args.cold_first and not args.maps:
        ap.error('--cold-first needs a destination map')
    out = args.out.resolve()
    if not out.is_relative_to(REPO / 'out'):
        ap.error('evidence must be in this worktree/out')
    lock = json.loads(LOCK.read_text(encoding='utf8'))
    if lock.get('task') != 'R10-H':
        ap.error('R10-H must own the PoC lock')
    out.mkdir(parents=True, exist_ok=True)
    log = POC / 'garrysmod/console.log'
    events = []
    seen_window = False

    def window():
        nonlocal seen_window
        processes = poc.game_processes(POC)
        for pid in processes:
            hwnd = poc.game_window(pid)
            if hwnd:
                seen_window = True
                return hwnd
        if seen_window and not processes:
            raise RuntimeError('PoC game exited')
        return None  # deployment/renderer startup can precede the first window

    def wait(marker, offset=0, timeout=120):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not window():
                time.sleep(.25)
                continue
            text = poc.read_shared(log, offset)
            for line in text.splitlines():
                if line.startswith(marker):
                    value = line[len(marker):].strip()
                    events.append(dict(marker=marker, value=value))
                    print(marker, value, flush=True)
                    return value
                if line.startswith('R10_QA_ERROR'):
                    raise RuntimeError(line)
            time.sleep(.25)
        raise RuntimeError('timeout: ' + marker)

    def send(command):
        hwnd = window()
        if not hwnd or not poc.console(hwnd, command):
            raise RuntimeError('console delivery failed')

    def lua(code, server=True):
        for line in poc.client_lua_lines('r10_qa', code):
            send(line.replace('lua_run_cl ', 'lua_run ', 1) if server else line)

    def quiet():
        last, since = None, time.monotonic()
        while time.monotonic() - since < 5:
            size = log.stat().st_size
            if size != last: last, since = size, time.monotonic()
            window(); time.sleep(.25)

    def install():
        quiet()
        lua(Path(__file__).with_name('mmd_expression_probe.lua').read_text(encoding='utf8'))
        wait('R10_QA_INSTALLED')
        send('sv_cheats 1')
        send('ai_disabled 1')

    def spawn(prefix, role='citizen'):
        send('setang 35 180 0')
        lua('player.GetAll()[1]:SetEyeAngles(Angle(35,180,0))')
        time.sleep(.3)  # publish the same nearby-ground aim a library button uses
        offset = log.stat().st_size
        lua('''local id
for k in pairs(mmdhl.library.Refresh()) do if k:sub(1,%d)=="%s" then id=k break end end
assert(id,"QA library character absent")
local options=mmdhl.GetGlobalSettings() options.role="%s" options.gender="female" options.frozen=true
local ok,err=mmdhl.RequestSpawn(id,options,function(state,message,index)
 if state=="ready" then print("R10_QA_UI "..util.TableToJSON({index=index}))
 elseif state=="error" then print("R10_QA_ERROR "..tostring(message)) end
end)
if not ok then print("R10_QA_ERROR "..tostring(err)) end''' % (len(prefix), prefix, role), False)
        ready = json.loads(wait('R10_QA_UI', offset))
        lua('''local e=Entity(%d) assert(IsValid(e),"QA spawn not on server")
if IsValid(R10MMDQA.ent) and R10MMDQA.ent~=e then MMDVMDNPC.StopPlayback(R10MMDQA.ent,true) R10MMDQA.ent:Remove() end
R10MMDQA.ent=e e:SetPos(Vector(0,0,0)) e:SetAngles(Angle(0,0,0))
print("R10_QA_SPAWN "..util.TableToJSON({index=e:EntIndex(),model=e:GetModel(),map=game.GetMap(),valid=util.IsValidModel(e:GetModel()),attached=mmdhl.IsMMD(e),key=e:GetNW2String("MMDHLRig"),ui=true}))''' % ready['index'])
        return json.loads(wait('R10_QA_SPAWN', offset))

    try:
        # Wait for this session's first map, then the RTX fixes' reloads to finish.
        wait('Clientside Lua startup!')
        install()
        if args.mode == 'npc':
            spawn(args.prefix, 'ragdoll')
            if not args.cold_first: spawn(args.prefix)
            cold = args.cold_first
            for name in [None, *args.maps]:
                if name is None and cold: continue
                if name:
                    offset = log.stat().st_size
                    send('map ' + name)
                    wait('Clientside Lua startup!', offset)
                    install()
                if cold:
                    spawn(args.prefix)
                    cold = False
                offset = log.stat().st_size
                lua('R10MMDQA.Menu("%s")' % args.prefix)
                menu = json.loads(wait('R10_QA_MENU_SPAWN', offset))
                # The spawned menu NPC was just inspected. Keep it from
                # occupying the next library request's nearby-ground ray.
                lua('local e=Entity(%d) if IsValid(e) then e:Remove() end' % menu['index'])
                spawn(args.prefix)
        else:
            for prefix in ('1c2ed2fc', 'f9c3e4b4'):
                ent = spawn(prefix)
                lua('R10MMDTarget=' + str(ent['index']) + '\n' + Path(__file__).with_name('mmd_expression_camera.lua').read_text(encoding='utf8'), False)
                time.sleep(2)
                for kind in ('smile', 'wink', 'blink'):
                    offset = log.stat().st_size
                    lua(f'R10MMDQA.Build("{kind}")')
                    wait('R10_QA_BUILT', offset)
                    offset = log.stat().st_size
                    lua('R10MMDQA.Play()')
                    held = json.loads(wait('R10_QA_HELD', offset))
                    time.sleep(2)
                    send('hideconsole')
                    poc.screenshot(window(), out / f'{prefix}-{kind}.png')
                    path = POC / 'garrysmod/data' / held['probe']
                    poc.copy_if_present(path, out / f'{prefix}-{kind}.json')
                    if kind == 'smile':
                        lua('MMDVMDNPC.OpenDebugForPlayer(player.GetAll()[1],R10MMDQA.ent,R10MMDQA.motion,30)')
                        time.sleep(2)
                        poc.screenshot(window(), out / f'{prefix}-mapping.png')
                        lua('if IsValid(MMDVMDNPC.DebugFrame) then MMDVMDNPC.DebugFrame:Close() end gui.HideGameUI()', False)
                    lua('R10MMDQA.Stop()')
        return 0
    finally:
        (out / 'events.json').write_text(json.dumps(events, indent=2, ensure_ascii=False), encoding='utf8')
        # End the owning poc_session's --lua-shots wait, so it can perform its
        # own normal quit and log collection immediately, also after a probe error.
        try:
            lua('print("NL_SHOT_DONE")', False)
        except RuntimeError:
            pass


if __name__ == '__main__':
    raise SystemExit(main())
