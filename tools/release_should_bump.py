#!/usr/bin/env python3
"""Decide if human-authored commits since the last automatic release need a bump.

Exit 0 for a bump, 3 for no pending human changes. The baseline release
commit is recognized by the release commit subject, not by a changing build id.
"""
import subprocess
import sys

def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()

RELEASE_SUBJECT = 'chore(release): auto-bump OneClick version and synchronize assets'

def should_bump():
    history = git('log', '-n', '1', '--format=%H', '--fixed-strings', '--grep', RELEASE_SUBJECT)
    if history:
        revs = git('rev-list', '--reverse', f'{history}..HEAD').splitlines()
    else:
        # Migration from the old sync-only workflow: take the current
        # latest human commit as the first pending release input.
        revs = [git('rev-parse', 'HEAD')]
    for rev in revs:
        author = git('show', '-s', '--format=%ae', rev).lower()
        subject = git('show', '-s', '--format=%s', rev)
        # GitHub App / AI commits may be bot-authored but still modify release sources.
        # Only release synchronization commits are excluded to avoid bump loops.
        if subject.startswith('chore(release):') or subject.startswith('chore: sync OneClick version'):
            continue
        if git('diff-tree', '--no-commit-id', '--name-only', '-r', '--root', rev):
            print(f'Pending release source change: {rev[:12]} {subject}')
            return True
    print('No new source changes after last synchronized release.')
    return False

if __name__ == '__main__':
    try:
        sys.exit(0 if should_bump() else 3)
    except subprocess.CalledProcessError as exc:
        print(f'ERROR: cannot inspect Git history: {exc}', file=sys.stderr)
        sys.exit(2)
