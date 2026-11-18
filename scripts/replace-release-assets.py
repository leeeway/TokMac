#!/usr/bin/env python3
"""Stage, verify, and swap the three assets of an existing GitHub release."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
from uuid import uuid4

NOTICE = '> macOS 提示：本次安装包使用 ad-hoc 开发签名，尚未经过 Apple 公证；首次启动可能被 Gatekeeper 阻止。\n\n'


class Release:
    def __init__(self, repo, tag, expected_commit):
        self.repo = repo
        self.tag = tag
        self.base = f'repos/{repo}/releases'
        self.expected_commit = expected_commit
        release = self.api(f'{self.base}/tags/{tag}')
        self.id = release['id']
        self.body = release.get('body') or ''
        if release.get('immutable') or release['tag_name'] != tag:
            raise ValueError('The requested release cannot be replaced')

    def verify_tag(self):
        git = f'repos/{self.repo}/git'
        target = self.api(f'{git}/ref/tags/{self.tag}')['object']
        for _ in range(8):
            if target['type'] != 'tag':
                break
            target = self.api(f'{git}/tags/{target["sha"]}')['object']
        if target['type'] != 'commit' or target['sha'] != self.expected_commit:
            raise RuntimeError(f'{self.tag} no longer points to build commit {self.expected_commit}')

    @staticmethod
    def gh(*args, timeout=60):
        result = subprocess.run(['gh', *args], text=True, capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or f'gh exited with {result.returncode}')
        return result.stdout

    def api(self, endpoint, *args):
        output = self.gh('api', endpoint, *args)
        return json.loads(output) if output else None

    def assets(self):
        pages = self.api(f'{self.base}/{self.id}/assets?per_page=100', '--paginate', '--slurp')
        return {asset['name']: asset for page in pages for asset in page}

    def upload(self, path):
        self.gh('release', 'upload', self.tag, str(path), '--repo', self.repo, timeout=600)

    def rename(self, asset_id, name):
        self.api(f'{self.base}/assets/{asset_id}', '--method', 'PATCH', '-f', f'name={name}')

    def delete(self, asset_id):
        self.api(f'{self.base}/assets/{asset_id}', '--method', 'DELETE')

    def update_body(self, body):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'notes.md'
            path.write_text(body, encoding='utf-8')
            self.api(f'{self.base}/{self.id}', '--method', 'PATCH', '-F', f'body=@{path}')


def digest(path):
    with path.open('rb') as stream:
        return 'sha256:' + hashlib.file_digest(stream, 'sha256').hexdigest()


def verify(assets, names, expected):
    for final_name, remote_name in names.items():
        asset = assets.get(remote_name)
        checksum, size = expected[final_name]
        if not asset or asset['state'] != 'uploaded' or asset.get('digest') != checksum or asset['size'] != size:
            raise RuntimeError(f'Asset verification failed: {remote_name}')


def cleanup(release, names):
    try:
        assets = release.assets()
    except Exception as error:
        print(f'Could not list temporary assets for cleanup: {error}', file=sys.stderr)
        return
    for name in names:
        if name not in assets:
            continue
        try:
            release.delete(assets[name]['id'])
        except Exception as error:
            print(f'Could not clean up {name}: {error}', file=sys.stderr)


def replace(release, files, notarized):
    release.verify_tag()
    suffix = uuid4().hex
    staged = {name: f'tokmac-stage-{suffix}-{name}' for name in files}
    backups = {name: f'tokmac-backup-{suffix}-{name}' for name in files}
    expected = {name: (digest(path), path.stat().st_size) for name, path in files.items()}
    original = release.assets()
    touched = []
    notes_attempted = False
    try:
        # Upload and verify every new file before making any canonical URL unavailable.
        with tempfile.TemporaryDirectory() as directory:
            for name, path in files.items():
                staging_path = Path(directory) / staged[name]
                shutil.copyfile(path, staging_path)
                release.upload(staging_path)
        assets = release.assets()
        verify(assets, staged, expected)
        release.verify_tag()

        for name in files:
            # Track the attempt before the PATCH, in case it takes effect but the response is lost.
            touched.append(name)
            if name in original:
                release.rename(original[name]['id'], backups[name])
            release.rename(assets[staged[name]]['id'], name)
        verify(release.assets(), {name: name for name in files}, expected)

        notes = release.body.replace(NOTICE, '')
        if not notarized:
            notes = NOTICE + notes
        if notes != release.body:
            notes_attempted = True
            release.update_body(notes)
        release.verify_tag()  # Retain backups until the remote tag still matches after the swap.
    except (Exception, KeyboardInterrupt):
        restored = True
        for name in reversed(touched):
            try:
                current = release.assets().get(name)
                if current and current['id'] == assets[staged[name]]['id']:
                    release.rename(current['id'], staged[name])
                if name in original:
                    release.rename(original[name]['id'], name)
            except Exception as error:
                restored = False
                print(f'Rollback failed for {name}. Recover using {backups[name]}: {error}', file=sys.stderr)
        if notes_attempted:
            try:
                release.update_body(release.body)
            except Exception as error:
                print(f'Could not restore original release notes: {error}', file=sys.stderr)
        if restored:
            cleanup(release, staged.values())
        raise
    cleanup(release, backups.values())


def interrupted(_signum, _frame):
    raise KeyboardInterrupt()


def main():
    directory, tag, commit = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    version = tag.removeprefix('v')
    names = (f'TokMac-{version}.dmg', f'TokMac-Setup-{version}.exe', 'TokMac-Windows-Portable.zip')
    status = json.loads((directory / 'macos-release-status.json').read_text())
    signal.signal(signal.SIGTERM, interrupted)
    release = Release(os.environ['GITHUB_REPOSITORY'], tag, commit)
    replace(release, {name: directory / name for name in names}, status['notarized'])
    print('Release assets swapped and verified.')


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        raise SystemExit(f'Release assets could not be replaced: {error or "interrupted"}')
