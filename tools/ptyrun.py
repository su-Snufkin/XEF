#!/usr/bin/env python3
"""Runs a command in a pseudo-terminal (80x24, TERM=xterm-256color), types scripted input and prints what the program
wrote (escape sequences stripped unless --raw). For interactive programs under xef-osx (vim, tmux, htop, fzf):
  tools/ptyrun.py [--raw] [--wait S] [--send TEXT]... -- build/xef-osx darwin-rootfs/opt/homebrew/bin/vim
--send takes Python escapes ('\\x1b' = Esc, '\\r' = Enter); a pause of --wait seconds precedes each send and the end."""
import os, pty, re, select, struct, sys, time, fcntl, termios, signal

def main():
    a = sys.argv[1:]
    raw, wait, sends = False, 1.0, []
    while a and a[0] != '--':
        o = a.pop(0)
        if o == '--raw': raw = True
        elif o == '--wait': wait = float(a.pop(0))
        elif o == '--send': sends.append(a.pop(0).encode().decode('unicode_escape').encode('latin-1'))
    cmd = a[1:]
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = 'xterm-256color'
        os.execvp(cmd[0], cmd)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    out = bytearray()
    def pump(t):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try: d = os.read(fd, 65536)
                except OSError: return False
                if not d: return False
                out.extend(d)
        return True
    alive = pump(wait)
    for s in sends:
        if not alive: break
        os.write(fd, s)
        alive = pump(wait)
    st = None
    for _ in range(40):
        p, s = os.waitpid(pid, os.WNOHANG)
        if p: st = s; break
        pump(0.1)
    if st is None:
        os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0); print('[still running: killed]')
    else:
        print('[exit %s]' % (os.waitstatus_to_exitcode(st)))
    text = out.decode('utf-8', 'replace')
    if not raw:
        text = re.sub(r'\x1b\[[0-9;?>=]*[ -/]*[@-~]|\x1b[()][0-9A-Za-z]|\x1b[=>78DEHMNOc]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\r', '', text)
    sys.stdout.write(text)

main()
