#!/usr/bin/env python3
"""Synchronize version metadata, Wizard bundles and shared build identity."""
import subprocess
from pathlib import Path
import sys
root=Path(__file__).resolve().parent.parent
commands=[
    ['python3','tools/sync_version.py'],
    ['python3','tools/sync_wizard.py'],
    ['python3','tools/sync_version.py'],
    ['python3','tools/sync_wizard.py'],
    ['python3','tools/sync_version.py','--check'],
    ['python3','tools/sync_wizard.py','--check'],
    ['python3','tools/check_version.py'],
]
for cmd in commands:
    print('+',' '.join(cmd),flush=True)
    code=subprocess.call(cmd,cwd=root)
    if code: sys.exit(code)
print('OK: version.json and Config Wizard share the same version/build.')
