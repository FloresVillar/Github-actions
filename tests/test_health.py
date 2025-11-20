import http.client
import os
import subprocess
import time

def test_health_endpoint():
    # Run server as a subprocess
    env = os.environ.copy()
    env["PORT"] = "8090"
    p = subprocess.Popen(["python", "-m", "src.app"], env=env)
    try:
        time.sleep(1.5)
        conn = http.client.HTTPConnection("127.0.0.1", 8090, timeout=3)
        conn.request("GET", "/health")
        resp = conn.getresponse()
        assert resp.status == 200
    finally:
        p.terminate()
        p.wait(timeout=5)
