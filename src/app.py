import os
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

PORT = int(os.environ.get("PORT", "8000"))
SERVICE_NAME = os.environ.get("SERVICE_NAME", "python-microservice")

class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload, content_type="application/json"):
        body = payload if isinstance(payload, (bytes, bytearray)) else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/" or self.path == "/":
            self._send(200, {"service": SERVICE_NAME, "ok": True})
        elif self.path == "/health":
            self._send(200, {"status": "healthy"})
        else:
            self._send(404, {"error": "not found"})

def main():
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Serving {SERVICE_NAME} on 0.0.0.0:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
