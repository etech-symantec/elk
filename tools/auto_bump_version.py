#!/usr/bin/env python3
"""Increment the canonical OneClick patch version once per qualifying push.

The only version authority is _internal/docs/VERSION. Generated copies are
reconciled by tools/sync_release.py after this command.
"""
import argparse
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
file = root / '_internal/docs/VERSION'
p = argparse.ArgumentParser()
p.add_argument('--min-version', default=None, help='Optional lower bound e.g. 2.9.56')
a = p.parse_args()
current = file.read_text(encoding='utf-8').strip()
if not re.fullmatch(r'\d+\.\d+\.\d+', current):
    raise SystemExit('ERROR: invalid _internal/docs/VERSION')
parts = tuple(map(int, current.split('.')))
next_version = (parts[0], parts[1], parts[2]+1)
if a.min_version:
    if not re.fullmatch(r'\d+\.\d+\.\d+', a.min_version):
        raise SystemExit('ERROR: invalid --min-version')
    minimum = tuple(map(int, a.min_version.split('.')))
    next_version = max(next_version, minimum)
next_text = '.'.join(map(str, next_version))
file.write_text(next_text+'\n', encoding='utf-8')
print(f'OneClick release: {current} -> {next_text}')
