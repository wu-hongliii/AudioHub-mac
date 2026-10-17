"""Exercise the actual macOS host with fragmented browser/socket frames."""
import json
import os
import pathlib
import socket
import struct
import subprocess
import sys
import threading

root = pathlib.Path(f"/tmp/audiohub-{os.getuid()}")
root.mkdir(mode=0o700, exist_ok=True)
path = root / "bridge.sock"
assert not path.exists(), "Another AudioHub server is running; stop it before testing."

def exact(stream, length):
    result = b""
    while len(result) < length:
        chunk = stream.read(length - len(result))
        if not chunk:
            raise EOFError()
        result += chunk
    return result

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
    server.bind(str(path))
    server.listen(1)
    process = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        server.settimeout(5)
        peer, _ = server.accept()
        with peer, peer.makefile("rb") as incoming:
            payload = json.dumps({"version": 1, "type": "snapshot", "tabs": [{"id": 7, "title": "中文网页"}]}).encode()
            frame = struct.pack("<I", len(payload)) + payload
            for byte in frame:
                process.stdin.write(bytes([byte]))
                process.stdin.flush()
            size = struct.unpack("<I", exact(incoming, 4))[0]
            assert exact(incoming, size) == payload
            reply = b'{"version":1,"type":"command","tabId":7,"action":"mute","value":true}'
            for part in (struct.pack("<I", len(reply))[:2], struct.pack("<I", len(reply))[2:], reply):
                peer.sendall(part)
            size = struct.unpack("<I", exact(process.stdout, 4))[0]
            assert exact(process.stdout, size) == reply
            process.stdin.close()
            assert process.wait(timeout=5) == 0
        print("PASS native host: split UTF-8 frames, bidirectional transport, disconnect")
    finally:
        if process.poll() is None:
            process.kill()
        path.unlink(missing_ok=True)
