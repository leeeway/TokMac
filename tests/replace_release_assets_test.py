import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('replace_release_assets', ROOT / 'scripts/replace-release-assets.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FakeRelease:
    def __init__(self, files, body='Original release notes\n'):
        self.body = self.current_body = body
        self.current = {
            index: {'id': index, 'name': name, 'digest': 'original', 'size': 1, 'state': 'uploaded'}
            for index, name in enumerate(files, 1)
        }
        self.uploads = 0
        self.fail_upload_at = None
        self.corrupt_upload = False
        self.fail_when_promoting = None
        self.fail_when_updating_body = False
        self.tag_checks = 0
        self.moved_tag_at = None

    def verify_tag(self):
        self.tag_checks += 1
        if self.tag_checks == self.moved_tag_at:
            raise RuntimeError('tag moved away from expected build')

    def assets(self):
        return {record['name']: dict(record) for record in self.current.values()}

    def upload(self, path):
        self.uploads += 1
        index = max(self.current) + 1
        self.current[index] = {
            'name': path.name, 'digest': 'corrupt' if self.corrupt_upload else module.digest(path),
            'size': path.stat().st_size, 'state': 'uploaded', 'id': index,
        }
        if self.uploads == self.fail_upload_at:
            raise RuntimeError('upload response lost')

    def rename(self, asset_id, name):
        if any(record['id'] != asset_id and record['name'] == name for record in self.current.values()):
            raise RuntimeError('name already exists')
        self.current[asset_id]['name'] = name
        if name == self.fail_when_promoting:
            self.fail_when_promoting = None
            raise RuntimeError('rename response lost')

    def delete(self, asset_id):
        del self.current[asset_id]

    def update_body(self, body):
        self.current_body = body
        if self.fail_when_updating_body:
            self.fail_when_updating_body = False
            raise RuntimeError('notes response lost')


class ReplaceTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.files = {}
        for name in ['TokMac-1.0.0.dmg', 'TokMac-Setup-1.0.0.exe', 'TokMac-Windows-Portable.zip']:
            path = Path(directory.name) / name
            path.write_text(name)
            self.files[name] = path
        self.release = FakeRelease(self.files)
        self.original = self.release.assets()

    def test_upload_failure_preserves_all_original_assets(self):
        self.release.fail_upload_at = 2
        with self.assertRaisesRegex(RuntimeError, 'upload response lost'):
            module.replace(self.release, self.files, notarized=False)
        self.assertEqual(self.release.assets(), self.original)
        self.assertEqual(self.release.current_body, self.release.body)

    def test_bad_staged_digest_preserves_all_original_assets(self):
        self.release.corrupt_upload = True
        with self.assertRaisesRegex(RuntimeError, 'Asset verification failed'):
            module.replace(self.release, self.files, notarized=False)
        self.assertEqual(self.release.assets(), self.original)

    def test_rename_failure_after_remote_change_restores_original_assets(self):
        self.release.fail_when_promoting = list(self.files)[1]
        with self.assertRaisesRegex(RuntimeError, 'rename response lost'):
            module.replace(self.release, self.files, notarized=False)
        self.assertEqual(self.release.assets(), self.original)

    def test_notes_failure_restores_original_assets_and_notes(self):
        self.release.fail_when_updating_body = True
        with self.assertRaisesRegex(RuntimeError, 'notes response lost'):
            module.replace(self.release, self.files, notarized=False)
        self.assertEqual(self.release.assets(), self.original)
        self.assertEqual(self.release.current_body, self.release.body)

    def test_success_keeps_canonical_names_and_removes_backups(self):
        module.replace(self.release, self.files, notarized=False)
        assets = self.release.assets()
        self.assertEqual(set(assets), set(self.files))
        self.assertEqual(self.release.current_body, module.NOTICE + self.release.body)
        for name, path in self.files.items():
            self.assertEqual(assets[name]['digest'], module.digest(path))
            self.assertNotEqual(assets[name]['id'], self.original[name]['id'])

    def test_notarized_package_removes_previous_development_notice(self):
        release = FakeRelease(self.files, '# Notes\n\n' + module.NOTICE + 'Original release notes\n')
        module.replace(release, self.files, notarized=True)
        self.assertEqual(release.current_body, '# Notes\n\nOriginal release notes\n')

    def test_tag_move_during_upload_leaves_previous_assets_in_place(self):
        self.release.moved_tag_at = 2
        with self.assertRaisesRegex(RuntimeError, 'tag moved'):
            module.replace(self.release, self.files, notarized=False)
        self.assertEqual(self.release.assets(), self.original)

    def test_tag_move_during_swap_rolls_back_assets_and_notes(self):
        self.release.moved_tag_at = 3
        with self.assertRaisesRegex(RuntimeError, 'tag moved'):
            module.replace(self.release, self.files, notarized=False)
        self.assertEqual(self.release.assets(), self.original)
        self.assertEqual(self.release.current_body, self.release.body)

    def test_remote_annotated_tag_resolves_to_build_commit(self):
        release = object.__new__(module.Release)
        release.repo = 'test/repo'
        release.tag = 'v1.0.0'
        release.expected_commit = 'build-sha'
        responses = {
            'repos/test/repo/git/ref/tags/v1.0.0': {'object': {'type': 'tag', 'sha': 'tag-sha'}},
            'repos/test/repo/git/tags/tag-sha': {'object': {'type': 'commit', 'sha': 'build-sha'}},
        }
        release.api = responses.__getitem__
        release.verify_tag()
        release.expected_commit = 'different-sha'
        with self.assertRaisesRegex(RuntimeError, 'no longer points'):
            release.verify_tag()


if __name__ == '__main__':
    unittest.main()
