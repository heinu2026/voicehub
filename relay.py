#!/usr/bin/env python3
"""IPv4 -> IPv6 Whisper 转发器"""
import socket
import threading
import http.client
import sys

LISTEN_HOST = "192.168.100.156"
LISTEN_PORT = 12018
UPSTREAM_HOST = "::1"
UPSTREAM_PORT = 12017

def handle(client, addr):
    try:
        upstream = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        upstream.connect((UPSTREAM_HOST, UPSTREAM_PORT, 0, 0))
    except Exception as e:
        print(f"连接上游失败: {e}")
        client.close()
        return

    def forward(src, dst):
        try:
            while True:
                data = src.recv(4096)
                if not data:
                    break
                dst.sendall(data)
        except Exception:
            pass
        finally:
            try:
                src.close()
                dst.close()
            except Exception:
                pass

    t1 = threading.Thread(target=forward, args=(client, upstream))
    t2 = threading.Thread(target=forward, args=(upstream, client))
    t1.start()
    t2.start()

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind((LISTEN_HOST, LISTEN_PORT))
sock.listen(50)
print(f"监听 {LISTEN_HOST}:{LISTEN_PORT} -> [{UPSTREAM_HOST}]:{UPSTREAM_PORT}")
sys.stdout.flush()
while True:
    client, addr = sock.accept()
    threading.Thread(target=handle, args=(client, addr), daemon=True).start()
