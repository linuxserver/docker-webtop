#!/usr/bin/env python3
import base64
import hashlib
import hmac
import http.server
import json
import os
import secrets
import time

PORT = 6060
SESSION_TTL = 24 * 3600
COOKIE_NAME = "selkies_session"
AUTH_PATH = "/auth"


def load_auth():
    with open("/etc/web-auth.json", "r") as f:
        data = json.load(f)
    return {
        "user": data["user"],
        "salt": data["salt"],
        "pw_hash": data["pw_hash"],
        "secret": data["secret"],
    }


AUTH = load_auth()


def hash_pw(pw: str) -> str:
    return hashlib.sha256((pw + AUTH["salt"]).encode()).hexdigest()


def sign_session(user: str) -> str:
    exp = int(time.time()) + SESSION_TTL
    nonce = secrets.token_hex(8)
    payload = f"{user}:{exp}:{nonce}"
    sig = hmac.new(AUTH["secret"].encode(), payload.encode(), hashlib.sha256).hexdigest()
    token = f"{payload}:{sig}"
    return base64.urlsafe_b64encode(token.encode()).decode()


def verify_session(token: str) -> bool:
    try:
        raw = base64.urlsafe_b64decode(token.encode()).decode()
        user, exp, nonce, sig = raw.split(":")
        if user != AUTH["user"]:
            return False
        if int(exp) < int(time.time()):
            return False
        expected = hmac.new(
            AUTH["secret"].encode(), f"{user}:{exp}:{nonce}".encode(), hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(sig, expected)
    except Exception:
        return False


def render_login(message: str = "") -> bytes:
    msg_html = f"<div class='msg error'>{message}</div>" if message else ""
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>Login</title>
<style>
body {{
  font-family: "Inter","Segoe UI",system-ui,-apple-system,sans-serif;
  display: flex; justify-content: center; align-items: center;
  min-height: 100vh; background: radial-gradient(circle at 20% 20%, #1f3b73 0, #0f172a 35%, #0b1020 70%);
  color: #e5e7eb; margin: 0;
}}
.card {{
  width: 360px; padding: 28px; border-radius: 16px;
  background: rgba(17,24,39,0.85); box-shadow: 0 15px 40px rgba(0,0,0,0.35);
  border: 1px solid rgba(255,255,255,0.06);
}}
.title {{ font-size: 22px; font-weight: 700; margin: 0 0 6px; }}
.subtitle {{ font-size: 13px; color: #9ca3af; margin: 0 0 18px; }}
label {{ display:block; font-size:13px; color:#cbd5e1; margin-bottom:6px; }}
input {{
  width: 100%; padding: 10px 12px; border-radius: 10px; border: 1px solid #334155;
  background: #0f172a; color: #e5e7eb; font-size: 14px; box-sizing: border-box;
}}
input:focus {{ outline: 2px solid #38bdf8; border-color: #38bdf8; }}
button {{
  width:100%; margin-top: 14px; padding: 12px; border: none; border-radius: 10px;
  background: linear-gradient(135deg,#38bdf8,#6366f1); color:#0b1020; font-weight:700;
  font-size: 15px; cursor: pointer; transition: transform 0.05s ease;
}}
button:hover {{ transform: translateY(-1px); }}
.msg.error {{ background:#7f1d1d; color:#fecdd3; padding:10px 12px; border-radius:10px; margin-bottom:12px; font-size:13px; }}
</style></head>
<body>
  <div class="card">
    <div class="title">Sign in</div>
    <p class="subtitle">Authenticate to open the remote desktop.</p>
    {msg_html}
    <form method="POST" action="{AUTH_PATH}/login">
      <label>Username</label>
      <input type="text" name="username" autofocus required>
      <div style="height:12px;"></div>
      <label>Password</label>
      <input type="password" name="password" required>
      <button type="submit">Continue</button>
    </form>
  </div>
</body></html>""".encode()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith(f"{AUTH_PATH}/login"):
            self._send_response(200, render_login())
        elif self.path.startswith(f"{AUTH_PATH}/logout"):
            self._clear_cookie()
            self._redirect(f"{AUTH_PATH}/login")
        elif self.path.startswith(f"{AUTH_PATH}/verify"):
            self._handle_verify()
        else:
            # Fallback: show login page instead of 404
            self._send_response(200, render_login())

    def do_POST(self):
        if self.path.startswith(f"{AUTH_PATH}/login"):
            self._handle_login()
        else:
            self.send_error(404)

    def _handle_verify(self):
        token = self._get_cookie()
        if token and verify_session(token):
            self.send_response(200)
            self.end_headers()
            return
        self.send_response(401)
        self.end_headers()

    def _handle_login(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode()
        fields = dict(part.split("=", 1) for part in body.split("&") if "=" in part)
        username = fields.get("username", "")
        password = fields.get("password", "")
        if username == AUTH["user"] and hash_pw(password) == AUTH["pw_hash"]:
            token = sign_session(username)
            self.send_response(302)
            self.send_header("Set-Cookie", f"{COOKIE_NAME}={token}; HttpOnly; Path=/; SameSite=Lax")
            self.send_header("Location", "/")
            self.end_headers()
        else:
            self._send_response(401, render_login("Invalid credentials"))

    def _redirect(self, location: str):
        self.send_response(302)
        self.send_header("Location", location)
        self.end_headers()

    def _get_cookie(self):
        cookie = self.headers.get("Cookie", "")
        for part in cookie.split(";"):
            if part.strip().startswith(f"{COOKIE_NAME}="):
                return part.strip().split("=", 1)[1]
        return ""

    def _clear_cookie(self):
        self.send_response(302)
        self.send_header(
            "Set-Cookie",
            f"{COOKIE_NAME}=deleted; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
        )
        self.send_header("Location", f"{AUTH_PATH}/login")
        self.end_headers()

    def _send_response(self, code: int, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        return


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    server.serve_forever()
