#!/usr/bin/env python3
"""
Runtime verification for Selkies STREAM_SCALE UI patch.

The actual patching is now done at Docker build time by
patch-selkies-stream-scale-ui-build.py, which patches the source JS files
before the Vite build.  This runtime script verifies that the build-time
patch was applied successfully and removes any legacy injected scripts.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT = Path("/usr/share/selkies")
LEGACY_MARKER = "selkies-stream-scale-ui-fix"
BUILD_PATCH_MARKER = "__selkiesPrimaryStreamResolution"
PRIMARY_DECODER_REINIT_MARKER = "Primary mode: Reinitializing decoder for stream resolution change."

LEGACY_SCRIPT_RE = re.compile(
    rf"<script>\s*//\s*{re.escape(LEGACY_MARKER)}.*?</script>",
    re.S,
)


def remove_legacy_scripts(frontend_roots: list[Path]) -> bool:
    """Remove any legacy HTML-injected workaround scripts."""
    changed = False
    seen: set[Path] = set()
    for frontend_root in frontend_roots:
        for html_path in frontend_root.rglob("*.html"):
            if html_path in seen:
                continue
            seen.add(html_path)
            content = html_path.read_text()
            updated, count = LEGACY_SCRIPT_RE.subn("", content)
            if count:
                html_path.write_text(updated)
                changed = True
                print(f"  [OK]   Removed legacy injected script from {html_path}")
    return changed


def verify_build_patch(frontend_roots: list[Path]) -> bool:
    """Check whether the build-time patch marker exists in the built JS."""
    for frontend_root in frontend_roots:
        # Check src/selkies-core.js (the Vite-built web-core output)
        src_js = frontend_root / "src" / "selkies-core.js"
        if src_js.is_file() and BUILD_PATCH_MARKER in src_js.read_text():
            return True
        # Check bundle files
        for bundle in frontend_root.glob("assets/index-*.js"):
            if BUILD_PATCH_MARKER in bundle.read_text():
                return True
    return False


def patch_primary_decoder_reinit(frontend_roots: list[Path]) -> bool:
    """Patch built JS so primary clients reinitialize H.264 decoder on resize.

    The source-level STREAM_SCALE patch adds a primary stream_resolution branch,
    but upstream only reinitializes the main decoder in the shared-mode branch.
    Auto-resize can therefore leave the primary decoder/canvas using the old
    coded size until the browser reloads. This post-build patch mirrors the
    shared-mode behavior for the current built bundle.
    """
    changed = False
    candidates: list[Path] = []
    seen: set[Path] = set()
    for frontend_root in frontend_roots:
        candidates.extend(frontend_root.glob("assets/selkies-core-*.js"))
        src_js = frontend_root / "src" / "selkies-core.js"
        if src_js.is_file():
            candidates.append(src_js)

    patches = [
        (
            # /usr/share/selkies/web/assets/selkies-core-*.js
            'window.__selkiesPrimaryStreamResolution={width:W,height:q};const ee=t&&t.parentElement?t.parentElement:document.querySelector(".video-container");let ve,ye;if(ee){const oe=ee.getBoundingClientRect();ve=Y(oe.width),ye=Y(oe.height)}else ve=Y(window.innerWidth),ye=Y(window.innerHeight);ve>0&&ye>0&&At(ve,ye),console.log(`Primary mode: Received stream_resolution ${W.toFixed(2)}x${q.toFixed(2)} (logical). Canvas updated.`)',
            'const oe=window.__selkiesPrimaryStreamResolution,st=!oe||oe.width!==W||oe.height!==q;window.__selkiesPrimaryStreamResolution={width:W,height:q};const ee=t&&t.parentElement?t.parentElement:document.querySelector(".video-container");let ve,ye;if(ee){const Nt=ee.getBoundingClientRect();ve=Y(Nt.width),ye=Y(Nt.height)}else ve=Y(window.innerWidth),ye=Y(window.innerHeight);ve>0&&ye>0&&At(ve,ye),st&&(console.log("Primary mode: Reinitializing decoder for stream resolution change."),fe(),f&&t.width>0&&t.height>0&&(f.setTransform(1,0,0,1,0,0),f.clearRect(0,0,t.width,t.height))),console.log(`Primary mode: Received stream_resolution ${W.toFixed(2)}x${q.toFixed(2)} (logical). Canvas updated.`)',
        ),
        (
            # /usr/share/selkies/web/src/selkies-core.js
            'window.__selkiesPrimaryStreamResolution={width:G,height:J};const ne=o&&o.parentElement?o.parentElement:document.querySelector(".video-container");let ee,he;if(ne){const be=ne.getBoundingClientRect();ee=W(be.width),he=W(be.height)}else ee=W(window.innerWidth),he=W(window.innerHeight);ee>0&&he>0&&Tt(ee,he),console.log(`Primary mode: Received stream_resolution ${G.toFixed(2)}x${J.toFixed(2)} (logical). Canvas updated.`)',
            'const be=window.__selkiesPrimaryStreamResolution,Rt=!be||be.width!==G||be.height!==J;window.__selkiesPrimaryStreamResolution={width:G,height:J};const ne=o&&o.parentElement?o.parentElement:document.querySelector(".video-container");let ee,he;if(ne){const rt=ne.getBoundingClientRect();ee=W(rt.width),he=W(rt.height)}else ee=W(window.innerWidth),he=W(window.innerHeight);ee>0&&he>0&&Tt(ee,he),Rt&&(console.log("Primary mode: Reinitializing decoder for stream resolution change."),pe(),c&&o.width>0&&o.height>0&&(c.setTransform(1,0,0,1,0,0),c.clearRect(0,0,o.width,o.height))),console.log(`Primary mode: Received stream_resolution ${G.toFixed(2)}x${J.toFixed(2)} (logical). Canvas updated.`)',
        ),
    ]

    for js_path in candidates:
        if js_path in seen:
            continue
        seen.add(js_path)
        content = js_path.read_text()
        if PRIMARY_DECODER_REINIT_MARKER in content:
            continue
        updated = content
        for old, new in patches:
            if old in updated:
                updated = updated.replace(old, new, 1)
                break
        if updated != content:
            js_path.write_text(updated)
            changed = True
            print(f"  [OK]   Patched primary decoder reinit in {js_path}")
    return changed


def discover_frontend_roots() -> list[Path]:
    web_root = ROOT / "web"
    if web_root.is_dir():
        return [web_root]

    dashboard = os.environ.get("DASHBOARD", "selkies-dashboard")
    selected_root = ROOT / dashboard
    if selected_root.is_dir():
        return [selected_root]

    print(f"WARNING: Frontend root not found (checked {web_root}, {selected_root}). Skipping.")
    return []


def main() -> int:
    print("Verifying Selkies STREAM_SCALE UI patch")

    frontend_roots = discover_frontend_roots()
    if not frontend_roots:
        return 0

    remove_legacy_scripts(frontend_roots)
    patch_primary_decoder_reinit(frontend_roots)

    if verify_build_patch(frontend_roots):
        print("  [OK]   Build-time STREAM_SCALE UI patch is present.")
    else:
        print("  [WARN] Build-time STREAM_SCALE UI patch marker not found in frontend assets.")
        print("         STREAM_SCALE UI auto-fit will not be active for primary clients.")
        print("         Rebuild the base image to apply the patch.")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"WARNING: {exc}")
        sys.exit(0)
