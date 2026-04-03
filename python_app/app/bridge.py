"""
TCP Bridge — sends MAXScript code to a running 3ds Max instance.

Protocol (simple, line-based):
  Client → Max :  <length:8 hex digits>\n<code bytes>
  Max → Client :  OK\n  or  ERROR:<message>\n

Default port: 27120
The MAXScript listener script (max_bridge_listener.ms) must be
running inside 3ds Max before connecting.
"""
from __future__ import annotations
import socket
import struct
import threading
from dataclasses import dataclass, field
from typing import Callable, Optional

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 27120
TIMEOUT_SEC  = 5.0


@dataclass
class BridgeConfig:
    host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    timeout: float = TIMEOUT_SEC
    auto_execute: bool = True   # execute code immediately on arrival in Max

    def to_dict(self) -> dict:
        return {"host": self.host, "port": self.port,
                "timeout": self.timeout, "auto_execute": self.auto_execute}

    @staticmethod
    def from_dict(d: dict) -> "BridgeConfig":
        cfg = BridgeConfig()
        cfg.host         = d.get("host",         DEFAULT_HOST)
        cfg.port         = int(d.get("port",     DEFAULT_PORT))
        cfg.timeout      = float(d.get("timeout", TIMEOUT_SEC))
        cfg.auto_execute = bool(d.get("auto_execute", True))
        return cfg


class BridgeError(Exception):
    pass


# ---------------------------------------------------------------------------
# Low-level send (blocking, called from worker thread)
# ---------------------------------------------------------------------------
def _send_blocking(code: str, cfg: BridgeConfig) -> str:
    """
    Sends code to 3ds Max via TCP.
    Returns the response string from Max ("OK" or "ERROR:...").
    Raises BridgeError on connection / protocol failure.
    """
    payload = code.encode("utf-8")
    length_header = f"{len(payload):08X}\n".encode("ascii")

    try:
        with socket.create_connection((cfg.host, cfg.port), timeout=cfg.timeout) as sock:
            sock.sendall(length_header + payload)
            # read response (up to 1 KB)
            response = b""
            while True:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                response += chunk
                if b"\n" in response:
                    break
        return response.decode("utf-8", errors="replace").strip()
    except ConnectionRefusedError:
        raise BridgeError(
            f"Connection refused — is max_bridge_listener.ms running in 3ds Max?\n"
            f"  Host: {cfg.host}   Port: {cfg.port}"
        )
    except socket.timeout:
        raise BridgeError(
            f"Timeout after {cfg.timeout}s — 3ds Max did not respond.\n"
            f"  Host: {cfg.host}   Port: {cfg.port}"
        )
    except OSError as e:
        raise BridgeError(f"Socket error: {e}")


# ---------------------------------------------------------------------------
# Async wrapper — runs in a thread to keep the UI responsive
# ---------------------------------------------------------------------------
class MaxBridge:
    """
    Thread-safe bridge.  Call .send_async() from the UI thread;
    the result/error is delivered via callbacks.
    """

    def __init__(self, config: Optional[BridgeConfig] = None):
        self.config = config or BridgeConfig()

    def send_async(
        self,
        code: str,
        on_success: Callable[[str], None],
        on_error: Callable[[str], None],
    ) -> None:
        """Non-blocking send. Callbacks are called from a worker thread."""
        def _worker():
            try:
                resp = _send_blocking(code, self.config)
                on_success(resp)
            except BridgeError as e:
                on_error(str(e))

        t = threading.Thread(target=_worker, daemon=True)
        t.start()

    def ping(self) -> tuple[bool, str]:
        """Synchronous connectivity test. Returns (ok, message)."""
        try:
            resp = _send_blocking("-- ping", self.config)
            return True, resp
        except BridgeError as e:
            return False, str(e)
