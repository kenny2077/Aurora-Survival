#!/usr/bin/env python3
"""Serve the local signed catalog with strict single-range HTTP support."""

from __future__ import annotations

import argparse
import http.server
import pathlib
import re
import socket


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DIRECTORY = ROOT / ".trailguard" / "development" / "product-host"


class RangeRequestHandler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def end_headers(self) -> None:
        self.send_header("Accept-Ranges", "bytes")
        super().end_headers()

    def send_head(self):
        path = pathlib.Path(self.translate_path(self.path))
        if path.is_dir() or not path.is_file():
            return super().send_head()
        range_header = self.headers.get("Range")
        if not range_header:
            return super().send_head()
        match = re.fullmatch(r"bytes=(\d+)-(\d*)", range_header.strip())
        if not match:
            self.send_error(416, "Only one explicit byte range is supported")
            return None
        size = path.stat().st_size
        start = int(match.group(1))
        end = int(match.group(2)) if match.group(2) else size - 1
        if start >= size or end < start:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{size}")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        end = min(end, size - 1)
        stream = path.open("rb")
        stream.seek(start)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(str(path)))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Last-Modified", self.date_time_string(path.stat().st_mtime))
        self.end_headers()
        self._range_bytes_remaining = end - start + 1
        return stream

    def copyfile(self, source, outputfile) -> None:
        remaining = getattr(self, "_range_bytes_remaining", None)
        if remaining is None:
            return super().copyfile(source, outputfile)
        while remaining > 0:
            block = source.read(min(1024 * 1024, remaining))
            if not block:
                break
            outputfile.write(block)
            remaining -= len(block)
        del self._range_bytes_remaining


class IPv6ThreadingHTTPServer(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--directory", type=pathlib.Path, default=DEFAULT_DIRECTORY)
    args = parser.parse_args()
    if not (args.directory / "catalog.json").is_file():
        raise SystemExit(
            "Signed catalog host is missing. Run tools/prepare_product_catalog.py first."
        )
    handler = lambda *items, **kwargs: RangeRequestHandler(  # noqa: E731
        *items, directory=str(args.directory), **kwargs
    )
    server_type = IPv6ThreadingHTTPServer if ":" in args.bind else http.server.ThreadingHTTPServer
    server = server_type((args.bind, args.port), handler)
    print(f"Serving {args.directory} on http://{args.bind}:{args.port}/catalog.json")
    server.serve_forever()


if __name__ == "__main__":
    main()
