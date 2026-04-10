#!/usr/bin/env python3
import socket
import os

display_env = os.environ.get("DISPLAY", ":1")
display_num = display_env.lstrip(":")
path = f"/tmp/.X11-unix/X{display_num}"

if os.path.exists(path):
    os.remove(path)

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
s.listen(128)

fd = s.fileno()
os.set_inheritable(fd, True)

os.execlp(
    "kwin_wayland",
    "kwin_wayland",
    "--no-lockscreen",
    "--xwayland",
    f"--xwayland-display=:{display_num}",
    f"--xwayland-fd={fd}"
)
