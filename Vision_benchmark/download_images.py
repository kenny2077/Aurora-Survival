#!/usr/bin/env python3
"""
Materialize the Aurora Expert Vision benchmark images from Wikimedia Commons.

Usage:
    python3 download_images.py
    python3 download_images.py --width 960
    python3 download_images.py --dry-run

Only Python's standard library is required.
"""
from pathlib import Path
from urllib.parse import urlencode
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import argparse, json, mimetypes, time, hashlib

HERE = Path(__file__).resolve().parent
SOURCES = json.loads((HERE / "sources.json").read_text(encoding="utf-8"))
OUT = HERE / "images"
API = "https://commons.wikimedia.org/w/api.php"
UA = "Aurora-ExpertVision-Benchmark/1.0 (offline model evaluation; source attribution in archive)"

def open_with_retry(req, timeout):
    delays = (0, 10, 30)
    last_error = None
    for delay in delays:
        if delay:
            time.sleep(delay)
        try:
            return urlopen(req, timeout=timeout)
        except (HTTPError, URLError) as error:
            last_error = error
            if isinstance(error, HTTPError) and error.code not in (429, 500, 502, 503, 504):
                raise
    raise last_error

def get_info(filename, width):
    params = {
        "action": "query",
        "format": "json",
        "formatversion": "2",
        "prop": "imageinfo",
        "iiprop": "url|mime|size",
        "iiurlwidth": str(width),
        "titles": "File:" + filename,
    }
    req = Request(API + "?" + urlencode(params), headers={"User-Agent": UA})
    with open_with_retry(req, timeout=30) as r:
        data = json.load(r)
    page = data["query"]["pages"][0]
    if page.get("missing"):
        raise RuntimeError(f"Commons file missing: {filename}")
    info = page["imageinfo"][0]
    return info

def download(url, path):
    req = Request(url, headers={"User-Agent": UA})
    with open_with_retry(req, timeout=60) as r:
        data = r.read()
        ctype = r.headers.get("Content-Type", "")
    if not data:
        raise RuntimeError(f"Empty response for {url}")
    path.write_bytes(data)
    return len(data), hashlib.sha256(data).hexdigest(), ctype

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=1280, help="Requested Commons thumbnail width (default: 1280)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    OUT.mkdir(exist_ok=True)

    resolved = []
    for n, s in enumerate(SOURCES, 1):
        dest = OUT / f"{s['id']}.{s.get('local_ext','jpg')}"
        print(f"[{n:02d}/{len(SOURCES)}] {s['id']}  {s['filename']}")
        if args.dry_run:
            continue
        if dest.exists() and not args.force:
            raw = dest.read_bytes()
            resolved.append({**s, "local_path": str(dest.relative_to(HERE)),
                             "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
                             "status":"cached"})
            print(f"    cached: {dest.name}")
            continue
        info = get_info(s["filename"], args.width)
        url = info.get("thumburl") or info["url"]
        size, sha, ctype = download(url, dest)
        resolved.append({**s, "local_path": str(dest.relative_to(HERE)),
                         "download_url_resolved": url, "bytes": size, "sha256": sha,
                         "content_type": ctype, "status":"downloaded"})
        print(f"    saved {size/1024:.1f} KiB  sha256={sha[:12]}…")
        time.sleep(0.15)

    if not args.dry_run:
        (HERE / "resolved_sources.json").write_text(
            json.dumps(resolved, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        print(f"\nDone. {len(resolved)} images are in {OUT}")
        print("Use prompts.jsonl for the 60 benchmark trials.")

if __name__ == "__main__":
    main()
