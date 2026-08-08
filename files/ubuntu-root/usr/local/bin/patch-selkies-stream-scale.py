#!/usr/bin/env python3
"""
Patch selkies to support STREAM_SCALE environment variable.

When STREAM_SCALE is set (e.g., 0.5), the browser-reported resolution is
scaled down before being applied to the virtual desktop.  This reduces the
amount of pixel data that must be encoded and streamed, saving bandwidth
while keeping DPI and application scaling untouched.

The patch also keeps the container DPI authoritative when a browser reconnects
with a stale scaling_dpi value from local storage.

1. _apply_client_settings – scales target_w / target_h right after the
   even-pixel alignment, before the dimensions are stored in display_state,
   but only when the target came from initial browser-reported dimensions.
2. The standalone resize handler (~line 3321) that processes resize messages
   from the websocket – same logic applied to its target_w / target_h, and
   Wayland resize broadcasts the new stream resolution to connected clients.
"""

import sys
import os
import glob


def find_selkies_py():
    """Find selkies.py in the installed selkies package."""
    candidates = glob.glob("/opt/selkies-env/lib/python*/site-packages/selkies/selkies.py")
    for path in candidates:
        if os.path.isfile(path):
            return path
    return None


def apply_patch(content, patch_name, old_text, new_text):
    """Apply a single patch, replacing old_text with new_text."""
    if old_text not in content:
        print(f"  [SKIP] {patch_name}: pattern not found (may already be patched)")
        return content
    count = content.count(old_text)
    if count > 1:
        print(f"  [WARN] {patch_name}: pattern found {count} times, replacing all")
        content = content.replace(old_text, new_text)
    else:
        content = content.replace(old_text, new_text)
    print(f"  [OK]   {patch_name}")
    return content


def patch_selkies(filepath):
    """Apply STREAM_SCALE patches to selkies.py."""
    print(f"Patching {filepath} for STREAM_SCALE support")

    with open(filepath, 'r') as f:
        content = f.read()

    original = content

    # =========================================================================
    # PATCH 1: Add STREAM_SCALE import near the top of the file
    # Insert after the existing os import.
    # =========================================================================
    PATCH1_OLD = '\n'.join([
        'import os',
    ])

    PATCH1_NEW = '\n'.join([
        'import os',
        '',
        '# --- STREAM_SCALE support ---',
        'def _get_stream_scale():',
        '    """Read STREAM_SCALE from environment (0.25 - 1.0, default 1.0)."""',
        '    try:',
        '        v = float(os.environ.get("STREAM_SCALE", "1.0"))',
        '        if 0.25 <= v <= 1.0:',
        '            return v',
        '    except (ValueError, TypeError):',
        '        pass',
        '    return 1.0',
        '',
        '',
        'def _apply_stream_scale(w, h):',
        '    """Scale dimensions by STREAM_SCALE, keeping values even."""',
        '    scale = _get_stream_scale()',
        '    if scale >= 1.0:',
        '        return w, h',
        '    w = int(round(w * scale / 2.0)) * 2',
        '    h = int(round(h * scale / 2.0)) * 2',
        '    if w <= 0: w = 2',
        '    if h <= 0: h = 2',
        '    return w, h',
        '# --- END STREAM_SCALE support ---',
    ])

    content = apply_patch(content, "Patch 1: Add _apply_stream_scale helper", PATCH1_OLD, PATCH1_NEW)

    # =========================================================================
    # PATCH 2: Apply scale in _apply_client_settings after even-pixel alignment
    # =========================================================================
    PATCH2_OLD = '\n'.join([
        '            if target_w % 2 != 0: target_w -= 1',
        '            if target_h % 2 != 0: target_h -= 1',
        '            resolution_actually_changed = (target_w != old_display_width or target_h != old_display_height)',
    ])

    PATCH2_NEW = '\n'.join([
        '            apply_stream_scale_to_target = False',
        '            if is_initial_settings and isinstance(settings.get("initialClientWidth"), int) and isinstance(settings.get("initialClientHeight"), int):',
        '                apply_stream_scale_to_target = True',
        '            if target_w % 2 != 0: target_w -= 1',
        '            if target_h % 2 != 0: target_h -= 1',
        '            if apply_stream_scale_to_target:',
        '                # STREAM_SCALE: scale down browser-reported dimensions once',
        '                target_w, target_h = _apply_stream_scale(target_w, target_h)',
        '            resolution_actually_changed = (target_w != old_display_width or target_h != old_display_height)',
    ])

    content = apply_patch(content, "Patch 2: Apply STREAM_SCALE in _apply_client_settings", PATCH2_OLD, PATCH2_NEW)

    # Upgrade older images/scripts where STREAM_SCALE was applied every time
    # _apply_client_settings ran. On Wayland this can double-scale after the
    # resize handler has already updated display_state.
    PATCH2B_OLD = '\n'.join([
        '            if target_w % 2 != 0: target_w -= 1',
        '            if target_h % 2 != 0: target_h -= 1',
        '            # STREAM_SCALE: scale down for lower-bandwidth streaming',
        '            target_w, target_h = _apply_stream_scale(target_w, target_h)',
        '            resolution_actually_changed = (target_w != old_display_width or target_h != old_display_height)',
    ])

    content = apply_patch(content, "Patch 2b: Avoid double STREAM_SCALE in _apply_client_settings", PATCH2B_OLD, PATCH2_NEW)

    # =========================================================================
    # PATCH 3: Apply scale in the standalone resize handler
    # =========================================================================
    PATCH3_OLD = '\n'.join([
        '        if target_w % 2 != 0: target_w -= 1',
        '        if target_h % 2 != 0: target_h -= 1',
        '        if target_w <= 0 or target_h <= 0:',
    ])

    PATCH3_NEW = '\n'.join([
        '        if target_w % 2 != 0: target_w -= 1',
        '        if target_h % 2 != 0: target_h -= 1',
        '        # STREAM_SCALE: scale down for lower-bandwidth streaming',
        '        target_w, target_h = _apply_stream_scale(target_w, target_h)',
        '        if target_w <= 0 or target_h <= 0:',
    ])

    content = apply_patch(content, "Patch 3: Apply STREAM_SCALE in resize handler", PATCH3_OLD, PATCH3_NEW)

    # =========================================================================
    # PATCH 4: Wayland dynamic resize must notify clients of the new stream size
    # =========================================================================
    PATCH4_OLD = '\n'.join([
        '                await data_server_instance._stop_capture_for_display(display_id)',
        '                await data_server_instance._start_capture_for_display(display_id, target_w, target_h, 0, 0)',
        '            else:',
    ])

    PATCH4_NEW = '\n'.join([
        '                await data_server_instance._stop_capture_for_display(display_id)',
        '                await data_server_instance._start_capture_for_display(display_id, target_w, target_h, 0, 0)',
        '                if display_id == "primary" and hasattr(data_server_instance, "broadcast_stream_resolution"):',
        '                    await data_server_instance.broadcast_stream_resolution()',
        '            else:',
    ])

    content = apply_patch(content, "Patch 4: Broadcast stream_resolution after Wayland resize", PATCH4_OLD, PATCH4_NEW)

    # =========================================================================
    # PATCH 5: Do not let stale browser-local DPI override container settings
    # =========================================================================
    PATCH5_OLD = '            new_dpi = sanitize_value("scaling_dpi", settings.get("scaling_dpi"))'

    PATCH5_NEW = '\n'.join([
        '            # DPI is configured by the container launcher. Browser-local settings',
        '            # may be stale after --reconfigure, so keep the container value authoritative.',
        '            try:',
        '                new_dpi = int(os.environ.get("DPI", ""))',
        '                if new_dpi <= 0:',
        '                    raise ValueError("DPI must be positive")',
        '            except (TypeError, ValueError):',
        '                new_dpi = sanitize_value("scaling_dpi", settings.get("scaling_dpi"))',
    ])

    content = apply_patch(content, "Patch 5: Keep container DPI authoritative", PATCH5_OLD, PATCH5_NEW)

    # =========================================================================
    # Write patched file
    # =========================================================================
    if content == original:
        print("No patches were applied. File may already be patched or has unexpected format.")
        return False

    with open(filepath, 'w') as f:
        f.write(content)

    print(f"\nSuccessfully patched {filepath}")
    return True


def main():
    filepath = find_selkies_py()
    if not filepath:
        print("ERROR: Could not find selkies.py. Searched in /opt/selkies-env/")
        sys.exit(1)

    success = patch_selkies(filepath)
    if not success:
        sys.exit(1)

    print("\n=== STREAM_SCALE Patch Summary ===")
    print("Patched locations:")
    print("  1. Added _apply_stream_scale() helper function")
    print("  2. _apply_client_settings: scale browser-reported dimensions")
    print("  3. Standalone resize handler: scale resize-request dimensions")
    print("  4. Wayland resize handler: broadcast stream_resolution after restart")
    print("  5. Browser settings cannot override the container DPI")
    print("")
    print("Set STREAM_SCALE=0.5 to stream at half the browser window resolution.")
    print("Default is 1.0 (no scaling). Valid range: 0.25 - 1.0.")


if __name__ == "__main__":
    main()
