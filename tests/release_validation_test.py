import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_validation', ROOT / 'scripts/verify-release.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        for name in ('TokMac-1.0.0.dmg', 'TokMac-Setup-1.0.0.exe', 'TokMac-Windows-Portable.zip'):
            (self.directory / name).write_bytes(b'test-package')
        self.status = dict(version='1.0.0', file='TokMac-1.0.0.dmg', signing_mode='distribution',
                           notarized=True, sha256=hashlib.sha256(b'test-package').hexdigest())
        self.save()

    def save(self):
        (self.directory / 'macos-release-status.json').write_text(json.dumps(self.status))

    def test_valid_distribution(self):
        module.verify(self.directory, '1.0.0')

    def test_development_artifact_cannot_be_published(self):
        self.status.update(signing_mode='development', notarized=False)
        self.save()
        with self.assertRaises(ValueError):
            module.verify(self.directory, '1.0.0')

    def test_stale_or_modified_dmg_is_rejected(self):
        (self.directory / 'TokMac-1.0.0.dmg').write_bytes(b'changed')
        with self.assertRaises(ValueError):
            module.verify(self.directory, '1.0.0')

    def test_version_mismatch_is_rejected(self):
        with self.assertRaises(ValueError):
            module.verify(self.directory, '1.0.1')

    def test_missing_windows_package_is_rejected(self):
        (self.directory / 'TokMac-Setup-1.0.0.exe').unlink()
        with self.assertRaises(ValueError):
            module.verify(self.directory, '1.0.0')


if __name__ == '__main__':
    unittest.main()
