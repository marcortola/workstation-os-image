#!/usr/bin/env bash
# Send one JSON-RPC request to herdr's socket and print the first response line.
#
# herdr's CLI covers workspaces, tabs, panes and worktrees, but not the raw
# socket methods `layout.export`, `layout.set_split_ratio` and
# `client.window_title.set` (`herdr api` offers only `snapshot` and `schema`).
# Upstream reaches them with `nc -U`; this image ships no netcat, so the base
# image's python3 does the same job with no added package.
set -euo pipefail

socket=${HERDR_SOCKET_PATH:-$HOME/.config/herdr/herdr.sock}

exec /usr/bin/python3 -c '
import socket as s, sys

sock = s.socket(s.AF_UNIX, s.SOCK_STREAM)
sock.connect(sys.argv[1])
sock.sendall(sys.stdin.buffer.read())
sock.shutdown(s.SHUT_WR)

buf = b""
while b"\n" not in buf:
    chunk = sock.recv(65536)
    if not chunk:
        break
    buf += chunk
sys.stdout.buffer.write(buf.split(b"\n", 1)[0] + b"\n")
' "$socket"
