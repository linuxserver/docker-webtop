#!/usr/bin/env python3
"""
Patch selkies-gstreamer for websockets 15.x compatibility.
websockets 15.x has breaking API changes that require these fixes.
"""

import re
import sys
import glob

def get_python_site_packages():
    """Dynamically find the Python site-packages directory"""
    patterns = [
        "/lsiopy/lib/python3.*/site-packages/selkies_gstreamer",
    ]
    for pattern in patterns:
        matches = glob.glob(pattern)
        if matches:
            return matches[0]
    return None

def patch_signalling_web():
    """Patch signalling_web.py for websockets 15.x"""
    base_dir = get_python_site_packages()
    if not base_dir:
        print("selkies_gstreamer package directory not found")
        return False
    
    f = f"{base_dir}/signalling_web.py"
    
    try:
        with open(f, "r") as file:
            content = file.read()
    except FileNotFoundError:
        print(f"File not found: {f}")
        return False
    
    modified = False
    
    # 1. Add WS_15_PLUS check and imports
    if "WS_15_PLUS" not in content:
        content = content.replace(
            "import websockets",
            """import websockets
try:
    from websockets.http11 import Response as WsResponse
    from websockets.datastructures import Headers as WsHeaders
    WS_15_PLUS = True
except ImportError:
    WS_15_PLUS = False"""
        )
        modified = True
        print("  Added WS_15_PLUS imports")
    
    # 2. Add _make_response function before class definition
    if "def _make_response(" not in content:
        class_def = "class WebRTCSimpleServer"
        if class_def in content:
            helper_func = '''
def _make_response(status, headers, body):
    """Create HTTP response compatible with websockets version"""
    if WS_15_PLUS:
        ws_headers = WsHeaders(headers)
        return WsResponse(status.value, status.phrase, ws_headers, body)
    else:
        return status, headers, body


'''
            content = content.replace(class_def, helper_func + class_def)
            modified = True
            print("  Added _make_response function")
    
    # 3. Fix handler(ws, path) -> handler(ws)
    if "async def handler(ws, path):" in content:
        content = content.replace(
            "async def handler(ws, path):",
            "async def handler(ws):"
        )
        modified = True
        print("  Fixed handler signature")
    
    # 4. Remove loop=self.loop parameters
    if "loop=self.loop" in content:
        content = content.replace(", loop=self.loop,", ",")
        content = content.replace("loop=self.loop,", "")
        content = content.replace(", loop=self.loop)", ")")
        content = re.sub(
            r"asyncio\.ensure_future\(([^)]+),\s*loop=self\.loop\)",
            r"asyncio.ensure_future(\1)",
            content
        )
        modified = True
        print("  Removed loop parameter")
    
    # 5. Fix process_request for websockets 15.x
    old_process = """    async def process_request(self, server_root, path, request_headers):
        response_headers = [
            ('Server', 'asyncio websocket server'),
            ('Connection', 'close'),
        ]

        username = ''
        if self.enable_basic_auth:
            if "basic" in request_headers.get("authorization", "").lower():
                username, passwd = basicauth.decode(request_headers.get("authorization"))"""
    
    new_process = """    async def process_request(self, server_root, connection, request=None):
        # websockets 15.x compatibility
        if hasattr(connection, 'request'):
            # websockets 15.x - connection is ServerConnection
            if request is not None and hasattr(request, 'path'):
                path = request.path
                request_headers = dict(request.headers) if hasattr(request, 'headers') else {}
            else:
                req = getattr(connection, 'request', None)
                if req and hasattr(req, 'path'):
                    path = req.path
                    request_headers = dict(req.headers) if hasattr(req, 'headers') else {}
                else:
                    return None
        elif isinstance(connection, str):
            # Old websockets API
            path = connection
            request_headers = dict(request) if request else {}
        else:
            return None

        response_headers = [
            ('Server', 'asyncio websocket server'),
            ('Connection', 'close'),
        ]

        username = ''
        if self.enable_basic_auth:
            auth_header = request_headers.get("authorization", request_headers.get("Authorization", ""))
            if "basic" in auth_header.lower():
                username, passwd = basicauth.decode(auth_header)"""
    
    if old_process in content:
        content = content.replace(old_process, new_process)
        modified = True
        print("  Fixed process_request signature")
    
    # 6. Replace return tuples with _make_response calls
    # Pattern: return HTTPStatus.XXX, response_headers, body
    # or: return http.HTTPStatus.XXX, response_headers, body
    patterns = [
        (r"return HTTPStatus\.(\w+), response_headers, (b'[^']*'|b\"[^\"]*\"|str\.encode\([^)]+\)|data|body)",
         r"return _make_response(HTTPStatus.\1, response_headers, \2)"),
        (r"return http\.HTTPStatus\.(\w+), response_headers, (b'[^']*'|b\"[^\"]*\"|str\.encode\([^)]+\)|data|body)",
         r"return _make_response(http.HTTPStatus.\1, response_headers, \2)"),
    ]
    
    for pattern, replacement in patterns:
        new_content = re.sub(pattern, replacement, content)
        if new_content != content:
            content = new_content
            modified = True
            print("  Fixed return statements")
    
    if modified:
        with open(f, "w") as file:
            file.write(content)
        print(f"Patched: {f}")
    else:
        print(f"No changes needed: {f}")
    
    return True


def patch_webrtc_signalling():
    """Patch webrtc_signalling.py for websockets 15.x"""
    base_dir = get_python_site_packages()
    if not base_dir:
        print("selkies_gstreamer package directory not found")
        return False
    
    f = f"{base_dir}/webrtc_signalling.py"
    
    try:
        with open(f, "r") as file:
            content = file.read()
    except FileNotFoundError:
        print(f"File not found: {f}")
        return False
    
    modified = False
    
    # Change extra_headers to additional_headers for websockets 15.x
    if "extra_headers=headers" in content:
        content = content.replace("extra_headers=headers", "additional_headers=headers")
        modified = True
        print("  Fixed extra_headers -> additional_headers")
    
    if modified:
        with open(f, "w") as file:
            file.write(content)
        print(f"Patched: {f}")
    else:
        print(f"No changes needed: {f}")
    
    return True


def main():
    print("Patching selkies-gstreamer for websockets 15.x compatibility...")
    
    success = True
    success = patch_signalling_web() and success
    success = patch_webrtc_signalling() and success
    
    if success:
        print("Patching completed successfully!")
        return 0
    else:
        print("Patching failed!")
        return 1


if __name__ == "__main__":
    sys.exit(main())
