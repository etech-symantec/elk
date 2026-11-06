#!/usr/bin/env python3
"""Synchronize the latest stable Elastic Stack 9.x version into Wizard defaults.

Sources:
  - https://www.elastic.co/downloads/elasticsearch
  - https://www.elastic.co/docs/release-notes

This updates only wizard-defaults.js. Existing saved installer configs and manual
version overrides are never modified. On source failure, preserve the old value.
"""
from __future__ import annotations

import argparse
import html
import re
import sys
import time
from html.parser import HTMLParser
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
DEFAULTS = ROOT / "wizard-defaults.js"
SOURCES = (
    ("download", "https://www.elastic.co/downloads/elasticsearch"),
    ("notes", "https://www.elastic.co/docs/release-notes"),
)
DEFAULT_LINE = re.compile(
    r'(?m)^(\s*ELASTIC_VERSION\s*:\s*")(\d+(?:\.\d+){2}|)(",[^\n]*)$'
)


class TextOnly(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.ignored = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "noscript"):
            self.ignored += 1

    def handle_endtag(self, tag):
        if tag in ("script", "style", "noscript") and self.ignored:
            self.ignored -= 1

    def handle_data(self, data):
        if not self.ignored:
            self.parts.append(data)


def visible_text(raw: str) -> str:
    parser = TextOnly()
    parser.feed(raw)
    return re.sub(r"\s+", " ", html.unescape(" ".join(parser.parts)))


def find_versions(raw: str, kind: str) -> list[tuple[int, int, int]]:
    cleaned = visible_text(raw)
    if kind == "download":
        patterns = (r"\bVersion\s*:\s*(\d+\.\d+\.\d+)\b",)
    else:
        patterns = (
            r"\bmost recent\s+(\d+\.\d+\.\d+)\s+release\b",
            r"\bElastic Stack\s+(\d+\.\d+\.\d+)\s+includes\b",
        )
    found = []
    for pattern in patterns:
        for v in re.findall(pattern, cleaned, re.IGNORECASE):
            parsed = tuple(map(int, v.split(".")))
            if parsed[0] == 9:
                found.append(parsed)
    return found


def fetch(url: str) -> str:
    last = None
    for attempt in range(3):
        try:
            req = Request(url, headers={
                "User-Agent": "ELK-OneClick-Release-Checker/1.0",
                "Accept": "text/html",
                "Cache-Control": "no-cache",
            })
            with urlopen(req, timeout=25) as response:
                return response.read(6_000_000).decode("utf-8", "replace")
        except Exception as exc:
            last = exc
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"{url}: {last}")


def main() -> int:
    argp = argparse.ArgumentParser()
    argp.add_argument("--dry-run", action="store_true")
    args = argp.parse_args()

    versions = []
    for kind, url in SOURCES:
        try:
            candidates = find_versions(fetch(url), kind)
        except Exception as exc:
            print(f"[WARN] {kind}: {exc}", file=sys.stderr)
            continue
        if candidates:
            best = max(candidates)
            print(f"[INFO] Elastic {kind}: {'.'.join(map(str, best))}")
            versions.append(best)
        else:
            print(f"[WARN] {kind}: no stable 9.x version found", file=sys.stderr)
    if not versions:
        print("[ERROR] Official Elastic sources unavailable; keeping existing default", file=sys.stderr)
        return 1

    newest = max(versions)
    source = DEFAULTS.read_text(encoding="utf-8")
    match = DEFAULT_LINE.search(source)
    if not match:
        print("[ERROR] ELASTIC_VERSION field not found in wizard-defaults.js", file=sys.stderr)
        return 2
    old = match.group(2)
    if old:
        before = tuple(map(int, old.split(".")))
        if newest < before:
            print(f"[WARN] Refusing to downgrade wizard default from {old} to {newest}")
            return 0
    latest = ".".join(map(str, newest))
    if old == latest:
        print(f"[OK] Wizard default already latest: {latest}")
        return 0
    revised = source[:match.start(2)] + latest + source[match.end(2):]
    if not args.dry_run:
        DEFAULTS.write_text(revised, encoding="utf-8")
    print(f"[OK] Wizard ELASTIC_VERSION: {old or '(auto)'} -> {latest}" +
          (" (dry-run)" if args.dry_run else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
