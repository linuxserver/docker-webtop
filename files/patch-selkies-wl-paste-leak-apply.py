#!/usr/bin/env python3
"""
Patch selkies input_handler.py for Wayland/pixelflux (KDE on wayland-0) mode.

Issues fixed:

1. wl-paste blocking on empty clipboard (original + v2 fix):
   wl-paste --list-types blocks indefinitely on wayland-0 when the clipboard is
   empty.  Previous fix (v2) added kill+wait on asyncio.TimeoutError which
   cleaned up the zombie processes but the 1-second timeout cycle still caused
   wl-paste to repeatedly appear as a Wayland client in KDE, making it flash in
   the taskbar every ~1.5 seconds and making clipboard appear broken.

2. wl-paste appearing in KDE taskbar (v3 fix):
   When wl-paste connects to wayland-0 (KWin), KDE briefly registers it as a
   compositor client and shows it in the task manager.  Since selkies polls
   every 0.5 s this causes constant flickering.

3. Clipboard not working for text (v3 fix):
   Because wl-paste always timed out (clipboard empty blocks), selkies never
   actually received any clipboard content from KDE apps.

v3 solution:
   Replace the wl-paste text-clipboard path entirely with KDE Klipper D-Bus.
   gdbus call to Klipper returns immediately (even when clipboard is empty),
   never creates a Wayland client, and therefore never appears in the taskbar.
   Image clipboard still uses wl-paste (with kill-on-timeout), since images
   are rare and Klipper only stores text.

Also adds _get_wl_clipboard_env() to force WAYLAND_DISPLAY=wayland-0 for the
remaining image-clipboard wl-paste calls (KDE apps write to wayland-0, not
wayland-1 which selkies streams on).
"""
import glob
import pathlib
import shutil
import sys
import os

HANDLER = "/opt/selkies-env/lib/python3.14/site-packages/selkies/input_handler.py"

# ── idempotency ────────────────────────────────────────────────────────────────
with open(HANDLER, encoding="utf-8") as f:
    src = f.read()

if "_find_kde_dbus_address" in src and "setClipboardContents" in src and "dbus_addr_bin" in src:
    print("Already patched (v4.1), skipping.")
    sys.exit(0)

if "_find_kde_dbus_address" in src and "setClipboardContents" in src:
    # v4 applied but not v4.1 (binary mode Klipper check missing) — restore and reapply
    bak = HANDLER + ".bak"
    if os.path.exists(bak):
        print("v4 patch detected without binary-mode Klipper fix – restoring from backup for clean v4.1 apply.")
        shutil.copy(bak, HANDLER)
        with open(HANDLER, encoding="utf-8") as f:
            src = f.read()
    else:
        print("WARNING: v4 detected but no backup; patching binary mode Klipper check on top.")

if "_find_kde_dbus_address" in src and "setClipboardContents" not in src:
    # v3 applied but not v4 (write_clipboard patch missing) — restore and reapply
    bak = HANDLER + ".bak"
    if os.path.exists(bak):
        print("v3 patch detected without write_clipboard fix – restoring from backup for clean v4.1 apply.")
        shutil.copy(bak, HANDLER)
        with open(HANDLER, encoding="utf-8") as f:
            src = f.read()
    else:
        print("WARNING: v3 detected but no backup; patching write_clipboard on top.")

# If v2 patch is present, restore from backup first so we start clean
if "_get_wl_clipboard_env" in src:
    bak = HANDLER + ".bak"
    if os.path.exists(bak):
        print("v2 patch detected – restoring original from backup.")
        shutil.copy(bak, HANDLER)
        with open(HANDLER, encoding="utf-8") as f:
            src = f.read()
    else:
        print("WARNING: v2 patch detected but no backup found; patching on top of v2 anyway.")

# ── make a backup if none exists ───────────────────────────────────────────────
bak = HANDLER + ".bak"
if not os.path.exists(bak):
    shutil.copy(HANDLER, bak)
    print(f"Backup saved to {bak}")

# ══════════════════════════════════════════════════════════════════════════════
# Change 1: Insert _find_kde_dbus_address() and _get_wl_clipboard_env() after
#            the existing _get_wl_env() method.
# ══════════════════════════════════════════════════════════════════════════════

OLD_WL_ENV = (
    '    def _get_wl_env(self):\n'
    '        env = os.environ.copy()\n'
    '        env["WAYLAND_DISPLAY"] = f"wayland-{self.wayland_socket_index}"\n'
    '        return env\n'
)

NEW_WL_ENV = (
    '    def _get_wl_env(self):\n'
    '        env = os.environ.copy()\n'
    '        env["WAYLAND_DISPLAY"] = f"wayland-{self.wayland_socket_index}"\n'
    '        return env\n'
    '\n'
    '    def _find_kde_dbus_address(self):\n'
    '        """Find D-Bus session bus address from the running KDE plasmashell process.\n'
    '\n'
    '        Scans /proc to locate plasmashell (or kded6/kwin_wayland) and reads\n'
    '        its DBUS_SESSION_BUS_ADDRESS environment variable.  Returns the address\n'
    '        string if found and the socket exists, otherwise None.\n'
    '        """\n'
    '        import glob as _glob\n'
    "        kde_procs = {'plasmashell', 'kded5', 'kded6', 'kwin_wayland'}\n"
    "        for proc_dir in _glob.glob('/proc/[0-9]*/'):\n"
    '            try:\n'
    "                with open(proc_dir + 'comm', 'r') as _f:\n"
    '                    if _f.read().strip() not in kde_procs:\n'
    '                        continue\n'
    "                with open(proc_dir + 'environ', 'rb') as _f:\n"
    "                    for item in _f.read().split(b'\\x00'):\n"
    "                        if item.startswith(b'DBUS_SESSION_BUS_ADDRESS='):\n"
    "                            addr = item.split(b'=', 1)[1].decode('utf-8', errors='ignore')\n"
    "                            if 'unix:path=' in addr:\n"
    "                                sock = addr.split('unix:path=')[1].split(',')[0]\n"
    '                                if os.path.exists(sock):\n'
    '                                    return addr\n'
    '            except (PermissionError, FileNotFoundError, ValueError, UnicodeDecodeError):\n'
    '                continue\n'
    '        return None\n'
    '\n'
    '    def _get_wl_clipboard_env(self):\n'
    '        """Return env for clipboard reads pointing to wayland-0 (KWin/KDE session).\n'
    '\n'
    '        In pixelflux Wayland mode, KDE apps write their clipboard to wayland-0\n'
    '        (the KWin compositor), not to wayland-1 (the selkies streaming compositor).\n'
    '        Using wayland-0 here makes image-clipboard reads work correctly.\n'
    '        """\n'
    '        env = os.environ.copy()\n'
    '        env["WAYLAND_DISPLAY"] = "wayland-0"\n'
    '        return env\n'
)

if OLD_WL_ENV not in src:
    print("ERROR: Could not find _get_wl_env() method to patch.", file=sys.stderr)
    sys.exit(1)
src = src.replace(OLD_WL_ENV, NEW_WL_ENV, 1)
print("v Inserted _find_kde_dbus_address() and _get_wl_clipboard_env()")

# ══════════════════════════════════════════════════════════════════════════════
# Change 2: Replace the entire Wayland text-clipboard path inside read_clipboard()
#            with a Klipper D-Bus call (gdbus).
#
# OLD: always spawns wl-paste --list-types (blocks on empty clipboard),
#      then wl-paste --no-newline for text.
# NEW: calls gdbus to Klipper (immediate, no Wayland client connection),
#      falls back to wl-paste only for binary/image clipboard.
# ══════════════════════════════════════════════════════════════════════════════

OLD_READ_CLIPBOARD_WAYLAND = (
    '    async def read_clipboard(self, use_binary=False):\n'
    '        """Reads clipboard. Supports Wayland (wl-paste) and X11 (xclip)."""\n'
    '        if self.is_wayland:\n'
    '            try:\n'
    '                proc_types = await subprocess.create_subprocess_exec(\n'
    '                    "wl-paste", "--list-types",\n'
    '                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,\n'
    '                    env=self._get_wl_env()\n'
    '                )\n'
    '                stdout_types, _ = await asyncio.wait_for(proc_types.communicate(), timeout=1.0)\n'
    '                \n'
    '                if proc_types.returncode != 0:\n'
    '                    return None, None\n'
    '\n'
    "                available_types = stdout_types.decode().strip().split('\\n')\n"
    '\n'
    '                if use_binary:\n'
    "                    image_mimes = ['image/png', 'image/jpeg', 'image/bmp', 'image/webp']\n"
    '                    target_mime = next((m for m in image_mimes if m in available_types), None)\n'
    '                    if target_mime:\n'
    '                        proc_data = await subprocess.create_subprocess_exec(\n'
    '                            "wl-paste", "--type", target_mime,\n'
    '                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,\n'
    '                            env=self._get_wl_env()\n'
    '                        )\n'
    '                        stdout_data, _ = await asyncio.wait_for(proc_data.communicate(), timeout=2.0)\n'
    '                        if proc_data.returncode == 0 and stdout_data:\n'
    '                            return stdout_data, target_mime\n'
    "                text_mimes = ['text/plain', 'text/plain;charset=utf-8', 'UTF8_STRING', 'STRING']\n"
    '                if any(t in available_types for t in text_mimes):\n'
    '                    proc_text = await subprocess.create_subprocess_exec(\n'
    '                        "wl-paste", "--no-newline", # Ensure exact content\n'
    '                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,\n'
    '                        env=self._get_wl_env()\n'
    '                    )\n'
    '                    stdout_text, _ = await asyncio.wait_for(proc_text.communicate(), timeout=1.0)\n'
    '                    if proc_text.returncode == 0:\n'
    "                        return stdout_text.decode('utf-8', errors='replace'), 'text/plain'\n"
    '\n'
    '                return None, None\n'
    '\n'
    '            except Exception as e:\n'
    '                logger_webrtc_input.warning(f"Error reading Wayland clipboard: {e}")\n'
    '                return None, None\n'
)

NEW_READ_CLIPBOARD_WAYLAND = (
    '    async def read_clipboard(self, use_binary=False):\n'
    '        """Reads clipboard. Supports Wayland (Klipper D-Bus + wl-paste for images) and X11 (xclip)."""\n'
    '        if self.is_wayland:\n'
    '            try:\n'
    '                if not use_binary:\n'
    '                    # ── Text clipboard via KDE Klipper D-Bus ──────────────────\n'
    '                    # gdbus exits immediately even when clipboard is empty, and\n'
    '                    # does NOT connect to the Wayland compositor, so it never\n'
    '                    # appears in the KDE task manager or taskbar.\n'
    '                    dbus_addr = self._find_kde_dbus_address()\n'
    '                    if dbus_addr:\n'
    '                        try:\n'
    '                            klipper_env = os.environ.copy()\n'
    "                            klipper_env['DBUS_SESSION_BUS_ADDRESS'] = dbus_addr\n"
    '                            proc_klipper = await subprocess.create_subprocess_exec(\n'
    "                                'gdbus', 'call', '--session',\n"
    "                                '--dest', 'org.kde.klipper',\n"
    "                                '--object-path', '/klipper',\n"
    "                                '--method', 'org.kde.klipper.klipper.getClipboardContents',\n"
    '                                stdout=subprocess.PIPE,\n'
    '                                stderr=subprocess.DEVNULL,\n'
    '                                env=klipper_env\n'
    '                            )\n'
    '                            stdout_klipper, _ = await asyncio.wait_for(\n'
    '                                proc_klipper.communicate(), timeout=2.0\n'
    '                            )\n'
    '                            if proc_klipper.returncode == 0 and stdout_klipper:\n'
    "                                text = stdout_klipper.decode('utf-8', errors='replace').strip()\n"
    "                                # gdbus output format: ('content',)  or  ('')\n"
    '                                if text.startswith("(\'") and text.endswith("\',"+ ")"):\n'
    '                                    text = text[2:-3]\n'
    "                                elif text in (\"('',)\", \"('')\"):\n"
    '                                    return None, None\n'
    '                                if text:\n'
    "                                    return text, 'text/plain'\n"
    '                        except (asyncio.TimeoutError, FileNotFoundError, Exception) as _e:\n'
    '                            logger_webrtc_input.debug(f"Klipper D-Bus clipboard read failed: {_e}")\n'
    '                    return None, None\n'
    '\n'
    '                # ── Binary/image clipboard: first check Klipper for text, ──\n'
    '                # then fall back to wl-paste only if Klipper is empty       \n'
    '                # (meaning clipboard may contain an image).                  \n'
    '                # This prevents wl-paste from blocking on wayland-0 when     \n'
    '                # clipboard has text, which would cause taskbar flickering.  \n'
    '                dbus_addr_bin = self._find_kde_dbus_address()\n'
    '                if dbus_addr_bin:\n'
    '                    try:\n'
    '                        klipper_env_bin = os.environ.copy()\n'
    "                        klipper_env_bin['DBUS_SESSION_BUS_ADDRESS'] = dbus_addr_bin\n"
    '                        proc_klipper_bin = await subprocess.create_subprocess_exec(\n'
    "                            'gdbus', 'call', '--session',\n"
    "                            '--dest', 'org.kde.klipper',\n"
    "                            '--object-path', '/klipper',\n"
    "                            '--method', 'org.kde.klipper.klipper.getClipboardContents',\n"
    '                            stdout=subprocess.PIPE,\n'
    '                            stderr=subprocess.DEVNULL,\n'
    '                            env=klipper_env_bin\n'
    '                        )\n'
    '                        stdout_klipper_bin, _ = await asyncio.wait_for(\n'
    '                            proc_klipper_bin.communicate(), timeout=2.0\n'
    '                        )\n'
    '                        if proc_klipper_bin.returncode == 0 and stdout_klipper_bin:\n'
    "                            text_bin = stdout_klipper_bin.decode('utf-8', errors='replace').strip()\n"
    '                            if text_bin.startswith("(\'") and text_bin.endswith("\',"+ ")"):\n'
    '                                text_bin = text_bin[2:-3]\n'
    '                            elif text_bin in ("(\'\')", "(\'\')"):\n'
    '                                text_bin = ""\n'
    '                            if text_bin:\n'
    "                                return text_bin, 'text/plain'\n"
    '                            # Klipper empty → maybe image, fall through to wl-paste\n'
    '                    except (asyncio.TimeoutError, FileNotFoundError, Exception) as _e:\n'
    '                        logger_webrtc_input.debug(f"Klipper D-Bus binary-mode check failed: {_e}")\n'
    '                # ── Image clipboard via wl-paste (binary mode, Klipper was empty) ──\n'
    '                # wl-paste is only used when the caller requests binary/image\n'
    '                # data; we kill it on timeout to avoid zombie accumulation.\n'
    '                proc_types = await subprocess.create_subprocess_exec(\n'
    '                    "wl-paste", "--list-types",\n'
    '                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,\n'
    '                    env=self._get_wl_clipboard_env()\n'
    '                )\n'
    '                try:\n'
    '                    stdout_types, _ = await asyncio.wait_for(proc_types.communicate(), timeout=1.0)\n'
    '                except asyncio.TimeoutError:\n'
    '                    try:\n'
    '                        proc_types.kill()\n'
    '                    except ProcessLookupError:\n'
    '                        pass\n'
    '                    await proc_types.wait()\n'
    '                    return None, None\n'
    '\n'
    '                if proc_types.returncode != 0:\n'
    '                    return None, None\n'
    '\n'
    "                available_types = stdout_types.decode().strip().split('\\n')\n"
    "                image_mimes = ['image/png', 'image/jpeg', 'image/bmp', 'image/webp']\n"
    '                target_mime = next((m for m in image_mimes if m in available_types), None)\n'
    '                if target_mime:\n'
    '                    proc_data = await subprocess.create_subprocess_exec(\n'
    '                        "wl-paste", "--type", target_mime,\n'
    '                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,\n'
    '                        env=self._get_wl_clipboard_env()\n'
    '                    )\n'
    '                    try:\n'
    '                        stdout_data, _ = await asyncio.wait_for(proc_data.communicate(), timeout=2.0)\n'
    '                    except asyncio.TimeoutError:\n'
    '                        try:\n'
    '                            proc_data.kill()\n'
    '                        except ProcessLookupError:\n'
    '                            pass\n'
    '                        await proc_data.wait()\n'
    '                        return None, None\n'
    '                    if proc_data.returncode == 0 and stdout_data:\n'
    '                        return stdout_data, target_mime\n'
    '                return None, None\n'
    '\n'
    '            except Exception as e:\n'
    '                logger_webrtc_input.warning(f"Error reading Wayland clipboard: {e}")\n'
    '                return None, None\n'
)

if OLD_READ_CLIPBOARD_WAYLAND not in src:
    print("ERROR: Could not find read_clipboard() Wayland block to replace.", file=sys.stderr)
    print("       The selkies source may have changed; inspect input_handler.py manually.", file=sys.stderr)
    sys.exit(1)
src = src.replace(OLD_READ_CLIPBOARD_WAYLAND, NEW_READ_CLIPBOARD_WAYLAND, 1)
print("v Replaced read_clipboard() Wayland path with Klipper D-Bus implementation")

# ══════════════════════════════════════════════════════════════════════════════
# Change 3: Replace the Wayland path in write_clipboard() to use Klipper D-Bus
#            for text/plain (so wl-copy never runs for text) and
#            _get_wl_clipboard_env() (wayland-0) for binary data.
#
# OLD: always spawns wl-copy with _get_wl_env() (wayland-1 = selkies compositor),
#      causing wl-copy to appear as a Wayland app in KDE task manager.
# NEW: for text/plain → gdbus call to Klipper setClipboardContents (no Wayland
#      connection at all).  For binary/image → wl-copy on wayland-0 (KDE) so it
#      doesn't appear through the selkies streaming compositor.
# ══════════════════════════════════════════════════════════════════════════════

OLD_WRITE_CLIPBOARD_WAYLAND = (
    '        env = self._get_wl_env() if self.is_wayland else os.environ.copy()\n'
    "        if 'LANG' not in env or env['LANG'] == 'C':\n"
    "            env['LANG'] = 'C.UTF-8'\n"
    '\n'
    '        if self.is_wayland:\n'
    '            try:\n'
    '                cmd = ["wl-copy", "--type", mime_type]\n'
    '                process = await subprocess.create_subprocess_exec(\n'
    '                    *cmd,\n'
    '                    stdin=subprocess.PIPE,\n'
    '                    stdout=subprocess.DEVNULL,\n'
    '                    stderr=subprocess.DEVNULL,\n'
    '                    env=env\n'
    '                )\n'
    '                if process.stdin:\n'
    '                    process.stdin.write(input_bytes)\n'
    '                    await process.stdin.drain()\n'
    '                    process.stdin.close()\n'
    '                await asyncio.wait_for(process.communicate(), timeout=2.0)\n'
    '                if process.returncode == 0:\n'
    '                    return True\n'
    '                else:\n'
    '                    logger_webrtc_input.warning(f"wl-copy failed code: {process.returncode}")\n'
    '                    return False\n'
    '            except Exception as e:\n'
    '                logger_webrtc_input.warning(f"wl-copy exception: {e}")\n'
    '                return False\n'
)

NEW_WRITE_CLIPBOARD_WAYLAND = (
    '        env = self._get_wl_env() if self.is_wayland else os.environ.copy()\n'
    "        if 'LANG' not in env or env['LANG'] == 'C':\n"
    "            env['LANG'] = 'C.UTF-8'\n"
    '\n'
    '        if self.is_wayland:\n'
    '            try:\n'
    "                if mime_type == 'text/plain':\n"
    '                    # ── Text: use Klipper D-Bus (no Wayland connection, no taskbar) ──\n'
    '                    dbus_addr = self._find_kde_dbus_address()\n'
    '                    if dbus_addr:\n'
    '                        try:\n'
    '                            klipper_env = os.environ.copy()\n'
    "                            klipper_env['DBUS_SESSION_BUS_ADDRESS'] = dbus_addr\n"
    "                            text_str = input_bytes.decode('utf-8', errors='replace')\n"
    '                            proc_klipper = await subprocess.create_subprocess_exec(\n'
    "                                'gdbus', 'call', '--session',\n"
    "                                '--dest', 'org.kde.klipper',\n"
    "                                '--object-path', '/klipper',\n"
    "                                '--method', 'org.kde.klipper.klipper.setClipboardContents',\n"
    '                                text_str,\n'
    '                                stdout=subprocess.DEVNULL,\n'
    '                                stderr=subprocess.DEVNULL,\n'
    '                                env=klipper_env\n'
    '                            )\n'
    '                            await asyncio.wait_for(proc_klipper.communicate(), timeout=2.0)\n'
    '                            if proc_klipper.returncode == 0:\n'
    '                                return True\n'
    '                        except Exception as _e:\n'
    '                            logger_webrtc_input.debug(f"Klipper D-Bus write failed: {_e}")\n'
    '                    # Fallback: wl-copy on wayland-0 (not wayland-1, to avoid taskbar)\n'
    '                    clip_env = self._get_wl_clipboard_env()\n'
    "                    if 'LANG' not in clip_env or clip_env['LANG'] == 'C':\n"
    "                        clip_env['LANG'] = 'C.UTF-8'\n"
    '                    process = await subprocess.create_subprocess_exec(\n'
    '                        "wl-copy", "--type", mime_type,\n'
    '                        stdin=subprocess.PIPE,\n'
    '                        stdout=subprocess.DEVNULL,\n'
    '                        stderr=subprocess.DEVNULL,\n'
    '                        env=clip_env\n'
    '                    )\n'
    '                else:\n'
    '                    # ── Binary/image: wl-copy on wayland-0 (KDE session) ─────\n'
    '                    clip_env = self._get_wl_clipboard_env()\n'
    "                    if 'LANG' not in clip_env or clip_env['LANG'] == 'C':\n"
    "                        clip_env['LANG'] = 'C.UTF-8'\n"
    '                    process = await subprocess.create_subprocess_exec(\n'
    '                        "wl-copy", "--type", mime_type,\n'
    '                        stdin=subprocess.PIPE,\n'
    '                        stdout=subprocess.DEVNULL,\n'
    '                        stderr=subprocess.DEVNULL,\n'
    '                        env=clip_env\n'
    '                    )\n'
    '                if process.stdin:\n'
    '                    process.stdin.write(input_bytes)\n'
    '                    await process.stdin.drain()\n'
    '                    process.stdin.close()\n'
    '                await asyncio.wait_for(process.communicate(), timeout=2.0)\n'
    '                if process.returncode == 0:\n'
    '                    return True\n'
    '                else:\n'
    '                    logger_webrtc_input.warning(f"wl-copy failed code: {process.returncode}")\n'
    '                    return False\n'
    '            except Exception as e:\n'
    '                logger_webrtc_input.warning(f"wl-copy exception: {e}")\n'
    '                return False\n'
)

if OLD_WRITE_CLIPBOARD_WAYLAND not in src:
    print("ERROR: Could not find write_clipboard() Wayland block to replace.", file=sys.stderr)
    print("       The selkies source may have changed; inspect input_handler.py manually.", file=sys.stderr)
    sys.exit(1)
src = src.replace(OLD_WRITE_CLIPBOARD_WAYLAND, NEW_WRITE_CLIPBOARD_WAYLAND, 1)
print("v Replaced write_clipboard() Wayland path: text via Klipper D-Bus, binary via wl-copy on wayland-0")

# ══════════════════════════════════════════════════════════════════════════════
# Change 4: Fix wl-copy --clear to use _get_wl_clipboard_env() (wayland-0)
#            instead of _get_wl_env() (wayland-1/selkies compositor).
# ══════════════════════════════════════════════════════════════════════════════

OLD_WL_COPY_CLEAR = (
    '                elif self.is_wayland:\n'
    '                    try:\n'
    '                        proc = await subprocess.create_subprocess_exec(\n'
    '                            "wl-copy", "--clear",\n'
    '                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,\n'
    '                            env=self._get_wl_env()\n'
    '                        )\n'
    '                        await asyncio.wait_for(proc.communicate(), timeout=1.0)\n'
    '                    except Exception:\n'
    '                        pass\n'
)

NEW_WL_COPY_CLEAR = (
    '                elif self.is_wayland:\n'
    '                    try:\n'
    '                        # Clear clipboard via Klipper D-Bus (no Wayland connection)\n'
    '                        _dbus_addr = self._find_kde_dbus_address()\n'
    '                        if _dbus_addr:\n'
    '                            _env_clear = os.environ.copy()\n'
    "                            _env_clear['DBUS_SESSION_BUS_ADDRESS'] = _dbus_addr\n"
    '                            _p = await subprocess.create_subprocess_exec(\n'
    "                                'gdbus', 'call', '--session',\n"
    "                                '--dest', 'org.kde.klipper',\n"
    "                                '--object-path', '/klipper',\n"
    "                                '--method', 'org.kde.klipper.klipper.setClipboardContents',\n"
    "                                '',\n"
    '                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,\n'
    '                                env=_env_clear\n'
    '                            )\n'
    '                            await asyncio.wait_for(_p.communicate(), timeout=1.0)\n'
    '                        else:\n'
    '                            proc = await subprocess.create_subprocess_exec(\n'
    '                                "wl-copy", "--clear",\n'
    '                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,\n'
    '                                env=self._get_wl_clipboard_env()\n'
    '                            )\n'
    '                            await asyncio.wait_for(proc.communicate(), timeout=1.0)\n'
    '                    except Exception:\n'
    '                        pass\n'
)

if OLD_WL_COPY_CLEAR not in src:
    print("WARNING: Could not find wl-copy --clear block (may already be patched or changed).")
else:
    src = src.replace(OLD_WL_COPY_CLEAR, NEW_WL_COPY_CLEAR, 1)
    print("v Replaced wl-copy --clear with Klipper D-Bus setClipboardContents('')")

# ── write patched file ─────────────────────────────────────────────────────────
with open(HANDLER, "w", encoding="utf-8") as f:
    f.write(src)

# Remove stale .pyc cache
for pyc in glob.glob(
    "/opt/selkies-env/lib/python3.14/site-packages/selkies/__pycache__/input_handler*.pyc"
):
    pathlib.Path(pyc).unlink(missing_ok=True)

print(f"\nPatch v3 applied successfully to {HANDLER}")
print(f"Backup at {HANDLER}.bak")
