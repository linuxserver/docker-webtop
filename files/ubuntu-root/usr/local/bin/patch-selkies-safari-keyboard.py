#!/usr/bin/env python3
"""
Patch Selkies web UIs to ensure Safari captures keyboard input without IME.
"""

from __future__ import annotations

from pathlib import Path


MARKER = "selkies-safari-keyboard-fix"
SCRIPT = f"""
<script>
// {MARKER}
(function () {{
  var ua = navigator.userAgent || "";
  var isSafari = /^((?!chrome|android).)*safari/i.test(ua);
  if (!isSafari) return;

  var input = document.createElement("textarea");
  input.id = "selkies-safari-keyboard";
  input.setAttribute("aria-hidden", "true");
  input.setAttribute("autocapitalize", "off");
  input.setAttribute("autocomplete", "off");
  input.setAttribute("autocorrect", "off");
  input.setAttribute("spellcheck", "false");
  input.style.position = "fixed";
  input.style.opacity = "0";
  input.style.pointerEvents = "none";
  input.style.height = "1px";
  input.style.width = "1px";
  input.style.left = "-1000px";
  input.style.top = "-1000px";
  document.body.appendChild(input);

  function shouldIgnore(el) {{
    if (!el) return false;
    var tag = (el.tagName || "").toLowerCase();
    return tag === "input" || tag === "textarea" || tag === "select" || el.isContentEditable;
  }}

  function focusTarget(el) {{
    if (!el || typeof el.focus !== "function") return false;
    if (el.tabIndex < 0) el.tabIndex = 0;
    try {{
      el.focus({{ preventScroll: true }});
    }} catch (e) {{
      el.focus();
    }}
    return true;
  }}

  function findInteractiveTarget() {{
    return (
      document.querySelector("[data-selkies-canvas]") ||
      document.querySelector("canvas") ||
      document.querySelector("video") ||
      document.body
    );
  }}

  function focusKeyboard() {{
    var active = document.activeElement;
    if (shouldIgnore(active)) return;
    var target = findInteractiveTarget();
    if (!focusTarget(target)) {{
      focusTarget(document.body);
    }}
    // Safari sometimes drops key events unless a text input is focused.
    if (input.focus) {{
      try {{
        input.focus({{ preventScroll: true }});
      }} catch (e) {{
        input.focus();
      }}
    }}
  }}

  document.addEventListener("pointerdown", focusKeyboard, true);
  document.addEventListener("mousedown", focusKeyboard, true);
  document.addEventListener("touchstart", focusKeyboard, true);
  window.addEventListener("focus", focusKeyboard);
  window.addEventListener("blur", function () {{
    setTimeout(focusKeyboard, 0);
  }});
}})();
</script>
""".strip()

MARKER_V2 = "selkies-safari-keyboard-fix-v2"
SCRIPT_V2 = f"""
<script>
// {MARKER_V2}
(function () {{
  var ua = navigator.userAgent || "";
  var isSafari = /^((?!chrome|android).)*safari/i.test(ua);
  if (!isSafari) return;

  // Safari blocks clipboard read on focus without a user gesture.
  if (typeof window.clipboard_enabled !== "undefined") {{
    window.clipboard_enabled = false;
  }}

  function focusAssist() {{
    var input = document.getElementById("keyboard-input-assist");
    if (!input || typeof input.focus !== "function") return;
    try {{
      input.focus({{ preventScroll: true }});
    }} catch (e) {{
      input.focus();
    }}
  }}

  function attachKeyboardForwarding() {{
    var input = document.getElementById("keyboard-input-assist");
    if (!input || input.dataset.selkiesSafariKeyboard === "1") return false;
    var webrtc = window.webrtcInput;
    if (!webrtc || typeof webrtc._handleKeyDown !== "function") return false;

    input.dataset.selkiesSafariKeyboard = "1";
    input.addEventListener("keydown", function (e) {{
      if (window.webrtcInput && typeof window.webrtcInput._handleKeyDown === "function") {{
        window.webrtcInput._handleKeyDown(e);
      }}
    }}, true);
    input.addEventListener("keyup", function (e) {{
      if (window.webrtcInput && typeof window.webrtcInput._handleKeyUp === "function") {{
        window.webrtcInput._handleKeyUp(e);
      }}
    }}, true);
    return true;
  }}

  function bind() {{
    document.addEventListener("pointerdown", focusAssist, true);
    document.addEventListener("mousedown", focusAssist, true);
    document.addEventListener("touchstart", focusAssist, true);
    window.addEventListener("focus", focusAssist);
    attachKeyboardForwarding();
    var tries = 0;
    var timer = setInterval(function () {{
      tries += 1;
      if (attachKeyboardForwarding() || tries > 120) {{
        clearInterval(timer);
      }}
    }}, 250);
  }}

  if (document.readyState === "loading") {{
    document.addEventListener("DOMContentLoaded", bind);
  }} else {{
    bind();
  }}
}})();
</script>
""".strip()

MARKER_V3 = "selkies-safari-keyboard-fix-v3"
SCRIPT_V3 = f"""
<script>
// {MARKER_V3}
(function () {{
  var ua = navigator.userAgent || "";
  var isSafari = /^((?!chrome|android).)*safari/i.test(ua);
  if (!isSafari) return;

  function focusOverlay() {{
    var overlay = document.getElementById("overlayInput");
    if (!overlay || typeof overlay.focus !== "function") return;
    try {{
      overlay.focus({{ preventScroll: true }});
    }} catch (e) {{
      overlay.focus();
    }}
  }}

  function attachOverlayHandlers() {{
    var overlay = document.getElementById("overlayInput");
    if (!overlay || overlay.dataset.selkiesSafariOverlay === "1") return false;
    var webrtc = window.webrtcInput;
    if (!webrtc) return false;

    overlay.dataset.selkiesSafariOverlay = "1";
    overlay.setAttribute("autocomplete", "off");
    overlay.setAttribute("autocorrect", "off");
    overlay.setAttribute("autocapitalize", "off");
    overlay.setAttribute("spellcheck", "false");
    overlay.setAttribute("inputmode", "text");

    function forwardKeyDown(e) {{
      var webrtcNow = window.webrtcInput;
      if (!webrtcNow || typeof webrtcNow._handleKeyDown !== "function") return;
      if (e && e._selkiesSafariHandled) return;
      e._selkiesSafariHandled = true;
      webrtcNow._handleKeyDown(e);
    }}
    function forwardKeyUp(e) {{
      var webrtcNow = window.webrtcInput;
      if (!webrtcNow || typeof webrtcNow._handleKeyUp !== "function") return;
      if (e && e._selkiesSafariHandled) return;
      e._selkiesSafariHandled = true;
      webrtcNow._handleKeyUp(e);
    }}

    overlay.addEventListener("keydown", forwardKeyDown, true);
    overlay.addEventListener("keyup", forwardKeyUp, true);
    var lastValue = "";
    overlay.addEventListener("input", function (e) {{
      var current = overlay.value || "";
      var inputType = e && e.inputType ? e.inputType : "";
      var webrtcNow = window.webrtcInput;
      if (!webrtcNow) return;

      // Handle deletion explicitly (Safari often sends only input events).
      if (inputType.indexOf("delete") === 0 || current.length < lastValue.length) {{
        var deleteCount = Math.max(1, lastValue.length - current.length);
        for (var i = 0; i < deleteCount; i += 1) {{
          if (typeof webrtcNow._guac_press === "function" && typeof webrtcNow._guac_release === "function") {{
            webrtcNow._guac_press(0xFF08);
            webrtcNow._guac_release(0xFF08);
          }}
        }}
        overlay.value = "";
        lastValue = "";
        return;
      }}

      // Handle text insertion via _typeString when available.
      if (current && typeof webrtcNow._typeString === "function") {{
        webrtcNow._typeString(current);
        overlay.value = "";
        lastValue = "";
        return;
      }}

      if (current && typeof webrtcNow._handleMobileInput === "function") {{
        webrtcNow._handleMobileInput(e);
        lastValue = "";
        return;
      }}

      lastValue = current;
    }}, true);

    overlay.addEventListener("pointerdown", focusOverlay, true);
    overlay.addEventListener("mousedown", focusOverlay, true);
    overlay.addEventListener("touchstart", focusOverlay, true);
    return true;
  }}

  function bind() {{
    document.addEventListener("pointerdown", focusOverlay, true);
    document.addEventListener("mousedown", focusOverlay, true);
    document.addEventListener("touchstart", focusOverlay, true);
    window.addEventListener("focus", focusOverlay);
    attachOverlayHandlers();
    var tries = 0;
    var timer = setInterval(function () {{
      tries += 1;
      if (attachOverlayHandlers() || tries > 120) {{
        clearInterval(timer);
      }}
    }}, 250);
  }}

  function shouldIgnoreKeyTarget(target) {{
    if (!target) return false;
    var tag = (target.tagName || "").toLowerCase();
    if (tag === "input" || tag === "textarea" || tag === "select") return true;
    if (target.isContentEditable) return true;
    if (target.classList && target.classList.contains("allow-native-input")) return true;
    return false;
  }}

  document.addEventListener("keydown", function (e) {{
    if (shouldIgnoreKeyTarget(e.target)) return;
    var webrtcNow = window.webrtcInput;
    if (!webrtcNow || typeof webrtcNow._handleKeyDown !== "function") return;
    if (e && e._selkiesSafariHandled) return;
    e._selkiesSafariHandled = true;
    webrtcNow._handleKeyDown(e);
  }}, true);

  document.addEventListener("keyup", function (e) {{
    if (shouldIgnoreKeyTarget(e.target)) return;
    var webrtcNow = window.webrtcInput;
    if (!webrtcNow || typeof webrtcNow._handleKeyUp !== "function") return;
    if (e && e._selkiesSafariHandled) return;
    e._selkiesSafariHandled = true;
    webrtcNow._handleKeyUp(e);
  }}, true);

  if (document.readyState === "loading") {{
    document.addEventListener("DOMContentLoaded", bind);
  }} else {{
    bind();
  }}
}})();
</script>
""".strip()

JS_MARKER = f"// {MARKER} (selkies-core)"
JS_SNIPPET = f"""
{JS_MARKER}
(function () {{
  var ua = navigator.userAgent || "";
  var isSafari = /^((?!chrome|android).)*safari/i.test(ua);
  if (!isSafari) return;

  function focusAssist() {{
    var kbd = document.getElementById("keyboard-input-assist");
    if (!kbd) return;
    try {{
      kbd.focus({{ preventScroll: true }});
    }} catch (e) {{
      kbd.focus();
    }}
  }}

  function bind() {{
    var overlay = document.getElementById("overlayInput");
    if (overlay) {{
      overlay.addEventListener("pointerdown", focusAssist, true);
      overlay.addEventListener("mousedown", focusAssist, true);
      overlay.addEventListener("touchstart", focusAssist, true);
    }}
    window.addEventListener("focus", focusAssist);
  }}

  if (document.readyState === "loading") {{
    document.addEventListener("DOMContentLoaded", bind);
  }} else {{
    bind();
  }}
}})();
""".strip()


def patch_html(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return False

    scripts = []
    if MARKER not in text:
        scripts.append(SCRIPT)
    if MARKER_V2 not in text:
        scripts.append(SCRIPT_V2)
    if MARKER_V3 not in text:
        scripts.append(SCRIPT_V3)
    if not scripts:
        return False

    if "</body>" in text:
        updated = text.replace("</body>", f"{'\n'.join(scripts)}\n</body>", 1)
    elif "</html>" in text:
        updated = text.replace("</html>", f"{'\n'.join(scripts)}\n</html>", 1)
    else:
        return False

    path.write_text(updated, encoding="utf-8")
    return True


def patch_js(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return False

    if JS_MARKER in text:
        return False

    updated = f"{text}\n{JS_SNIPPET}\n"
    path.write_text(updated, encoding="utf-8")
    return True


def main() -> int:
    roots = [
        Path("/usr/share/selkies"),
        Path("/usr/share/selkies/web"),
        Path("/opt/gst-web"),
    ]
    targets: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        targets.extend(root.rglob("index.html"))

    patched = 0
    for path in targets:
        if patch_html(path):
            patched += 1
            print(f"Patched Safari keyboard fix into {path}")

    js_targets: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        js_targets.extend(root.rglob("selkies-core.js"))

    js_patched = 0
    for path in js_targets:
        if patch_js(path):
            js_patched += 1
            print(f"Patched Safari keyboard fix into {path}")

    if patched == 0 and js_patched == 0:
        print("No Selkies HTML/JS files patched for Safari keyboard fix.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
