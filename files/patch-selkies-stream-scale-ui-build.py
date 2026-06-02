#!/usr/bin/env python3
"""
Build-time patch: Selkies STREAM_SCALE UI support for primary clients.

Patches the *source* JS files (selkies-ws-core.js and lib/input.js) BEFORE
the Vite build so the minified output already contains the changes.  This
avoids the fragile approach of pattern-matching against minified variable
names that change on every build.

Run this script from the Docker build stage BEFORE `npm run build`:
    python3 /tmp/patch-selkies-stream-scale-ui-build.py /src/addons/selkies-web-core

Three changes are made:
  1. resetCanvasStyle  – when __selkiesPrimaryStreamResolution is set, size
     the canvas buffer to the scaled stream and stretch the CSS canvas to the
     available browser viewport.
  2. stream_resolution handler – add a primary-client branch that stores the
     scaled resolution and triggers resetCanvasStyle.
  3. Mouse/touch coords in Input class – include the
     __selkiesPrimaryStreamResolution condition so coordinate mapping uses
     canvas-relative scaling (same as manual/shared mode).
"""

from __future__ import annotations

import sys
from pathlib import Path

MARKER = "__selkiesPrimaryStreamResolution"


# ──────────────────────────────────────────────────────────────────────
# Patch 1 – resetCanvasStyle: insert primary-stream branch
# ──────────────────────────────────────────────────────────────────────

RESET_OLD = """\
  const dpr = useCssScaling ? 1 : (window.devicePixelRatio || 1); 
  const internalBufferWidth = roundDownToEven(streamWidth * dpr);
  const internalBufferHeight = roundDownToEven(streamHeight * dpr);"""

RESET_NEW = """\
  // --- STREAM_SCALE: primary client scaled rendering ---
  const __primaryStream = !isSharedMode && !window.is_manual_resolution_mode
    && window.__selkiesPrimaryStreamResolution
    && window.__selkiesPrimaryStreamResolution.width > 0
    && window.__selkiesPrimaryStreamResolution.height > 0
    ? window.__selkiesPrimaryStreamResolution : null;

  if (__primaryStream) {
    const __pDpr = useCssScaling ? 1 : (window.devicePixelRatio || 1);
    const __pBufW = roundDownToEven(__primaryStream.width * __pDpr);
    const __pBufH = roundDownToEven(__primaryStream.height * __pDpr);
    if (canvas.width !== __pBufW || canvas.height !== __pBufH) {
      canvas.width = __pBufW;
      canvas.height = __pBufH;
      console.log(`Canvas internal buffer reset to scaled stream resolution: ${__pBufW}x${__pBufH}`);
    }
    const __pContainer = canvas.parentElement;
    const __pAvailW = __pContainer && __pContainer.clientWidth > 0 ? __pContainer.clientWidth : streamWidth;
    const __pAvailH = __pContainer && __pContainer.clientHeight > 0 ? __pContainer.clientHeight : streamHeight;
    if (__pAvailW > 0 && __pAvailH > 0) {
      canvas.style.position = 'absolute';
      canvas.style.width = `${__pAvailW}px`;
      canvas.style.height = `${__pAvailH}px`;
      canvas.style.top = '0px';
      canvas.style.left = '0px';
      const __pOverlay = document.getElementById('overlayInput');
      if (__pOverlay) {
        __pOverlay.style.width = `${__pAvailW}px`;
        __pOverlay.style.height = `${__pAvailH}px`;
        __pOverlay.style.position = 'absolute';
        __pOverlay.style.top = '0px';
        __pOverlay.style.left = '0px';
      }
      console.log(`Reset canvas CSS to fill viewport ${__pAvailW}x${__pAvailH} for scaled stream ${__primaryStream.width}x${__primaryStream.height}. Buffer: ${__pBufW}x${__pBufH}`);
    } else {
      canvas.style.position = 'absolute';
      canvas.style.width = `${__primaryStream.width}px`;
      canvas.style.height = `${__primaryStream.height}px`;
      canvas.style.top = '0px';
      canvas.style.left = '0px';
      console.log(`Reset canvas CSS scaled stream fallback: ${__primaryStream.width}x${__primaryStream.height}. Buffer: ${__pBufW}x${__pBufH}`);
    }
    canvas.style.objectFit = 'fill';
    canvas.style.display = 'block';
    updateCanvasImageRendering();
    if (window.webrtcInput && typeof window.webrtcInput.resize === 'function') {
      window.webrtcInput.resize();
    }
    return;
  }
  // --- End STREAM_SCALE primary client rendering ---

  const dpr = useCssScaling ? 1 : (window.devicePixelRatio || 1); 
  const internalBufferWidth = roundDownToEven(streamWidth * dpr);
  const internalBufferHeight = roundDownToEven(streamHeight * dpr);"""


# ──────────────────────────────────────────────────────────────────────
# Patch 2 – stream_resolution: add primary-client handler
# ──────────────────────────────────────────────────────────────────────

STREAM_OLD = """\
               console.warn(`Shared mode: Received invalid stream_resolution dimensions: ${obj.width}x${obj.height}`);
               }
             }
           }
         } else {
            console.warn(`Unexpected JSON message type:`, obj.type, obj);"""

STREAM_NEW = """\
               console.warn(`Shared mode: Received invalid stream_resolution dimensions: ${obj.width}x${obj.height}`);
               }
             }
           } else {
             // --- STREAM_SCALE: primary client stream_resolution ---
             const __pDpr = useCssScaling ? 1 : (window.devicePixelRatio || 1);
             const __pW = parseInt(obj.width, 10);
             const __pH = parseInt(obj.height, 10);
             if (__pW > 0 && __pH > 0) {
               const __pRW = roundDownToEven(__pW);
               const __pRH = roundDownToEven(__pH);
               const __pLW = __pRW / __pDpr;
               const __pLH = __pRH / __pDpr;
               window.__selkiesPrimaryStreamResolution = { width: __pLW, height: __pLH };
               const __pViewNode = canvas && canvas.parentElement ? canvas.parentElement : document.querySelector('.video-container');
               let __pVW, __pVH;
               if (__pViewNode) {
                 const __pVRect = __pViewNode.getBoundingClientRect();
                 __pVW = roundDownToEven(__pVRect.width);
                 __pVH = roundDownToEven(__pVRect.height);
               } else {
                 __pVW = roundDownToEven(window.innerWidth);
                 __pVH = roundDownToEven(window.innerHeight);
               }
               if (__pVW > 0 && __pVH > 0) resetCanvasStyle(__pVW, __pVH);
               console.log(`Primary mode: Received stream_resolution ${__pLW.toFixed(2)}x${__pLH.toFixed(2)} (logical). Canvas updated.`);
             } else {
               console.warn(`Primary mode: Received invalid stream_resolution dimensions: ${obj.width}x${obj.height}`);
             }
             // --- End STREAM_SCALE ---
           }
         } else {
            console.warn(`Unexpected JSON message type:`, obj.type, obj);"""


# ──────────────────────────────────────────────────────────────────────
# Patch 3 / 4 – Mouse and touch coordinate mapping in Input class
# ──────────────────────────────────────────────────────────────────────

INPUT_MOUSE_OLD = "if ((window.is_manual_resolution_mode || this.isSharedMode) && canvas) {\n                const canvasRect = canvas.getBoundingClientRect(); // CSS logical size\n                if (canvasRect.width > 0 && canvasRect.height > 0 && canvas.width > 0 && canvas.height > 0) {\n                    const mouseX_on_canvas_logical_css"
INPUT_MOUSE_NEW = "if ((window.is_manual_resolution_mode || this.isSharedMode || window.__selkiesPrimaryStreamResolution) && canvas) {\n                const canvasRect = canvas.getBoundingClientRect(); // CSS logical size\n                if (canvasRect.width > 0 && canvasRect.height > 0 && canvas.width > 0 && canvas.height > 0) {\n                    const mouseX_on_canvas_logical_css"

INPUT_TOUCH_OLD = "if ((window.is_manual_resolution_mode || this.isSharedMode) && canvas) {\n            const canvasRect = canvas.getBoundingClientRect(); // CSS logical size\n            if (canvasRect.width > 0 && canvasRect.height > 0 && canvas.width > 0 && canvas.height > 0) {\n                const touchX_on_canvas_logical_css"
INPUT_TOUCH_NEW = "if ((window.is_manual_resolution_mode || this.isSharedMode || window.__selkiesPrimaryStreamResolution) && canvas) {\n            const canvasRect = canvas.getBoundingClientRect(); // CSS logical size\n            if (canvasRect.width > 0 && canvasRect.height > 0 && canvas.width > 0 && canvas.height > 0) {\n                const touchX_on_canvas_logical_css"


# ──────────────────────────────────────────────────────────────────────
# Apply patches
# ──────────────────────────────────────────────────────────────────────

def apply_patch(content: str, old: str, new: str, label: str, path: str) -> str:
    if new in content:
        print(f"  [SKIP] {label}: already applied in {path}")
        return content
    count = content.count(old)
    if count != 1:
        raise RuntimeError(
            f"{label}: expected exactly 1 match, found {count} in {path}"
        )
    print(f"  [OK]   {label}: {path}")
    return content.replace(old, new, 1)


def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <selkies-web-core-dir>", file=sys.stderr)
        return 1

    root = Path(sys.argv[1])
    ws_core = root / "selkies-ws-core.js"
    input_js = root / "lib" / "input.js"

    for f in (ws_core, input_js):
        if not f.is_file():
            raise RuntimeError(f"Source file not found: {f}")

    print("Patching Selkies source for STREAM_SCALE primary-client rendering")

    # --- selkies-ws-core.js ---
    content = ws_core.read_text()
    content = apply_patch(content, RESET_OLD, RESET_NEW,
                          "resetCanvasStyle primary branch", str(ws_core))
    content = apply_patch(content, STREAM_OLD, STREAM_NEW,
                          "stream_resolution primary handler", str(ws_core))
    ws_core.write_text(content)

    # --- lib/input.js ---
    content = input_js.read_text()
    content = apply_patch(content, INPUT_MOUSE_OLD, INPUT_MOUSE_NEW,
                          "Mouse coord mapping", str(input_js))
    content = apply_patch(content, INPUT_TOUCH_OLD, INPUT_TOUCH_NEW,
                          "Touch coord mapping", str(input_js))
    input_js.write_text(content)

    print("Source patching complete. Vite build will produce patched output.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
