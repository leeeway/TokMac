import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SigningFlowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='tokmac signing ')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.target = self.directory / 'TokMac.app'
        self.target.mkdir()
        self.log = self.directory / 'calls.jsonl'
        self.env = dict(os.environ, TOKMAC_SIGNING_MODE='distribution',
                        CODE_SIGN_IDENTITY='Developer ID Application: Test Identity',
                        NOTARY_KEYCHAIN_PROFILE='test-profile', SIGNING_TEST_LOG=str(self.log))
        for key in ('CODE_SIGN_KEYCHAIN', 'NOTARY_KEY_PATH', 'NOTARY_KEY_ID', 'NOTARY_ISSUER_ID'):
            self.env.pop(key, None)
        self.env['PATH'] = str(self.directory) + os.pathsep + os.environ['PATH']
        for tool in ('codesign', 'xcrun'):
            path = self.directory / tool
            path.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ['SIGNING_TEST_LOG'], 'a') as log:
    log.write(json.dumps([Path(sys.argv[0]).name] + sys.argv[1:]) + '\\n')
if Path(sys.argv[0]).name == 'codesign' and '-dv' in sys.argv:
    print('Authority=' + os.environ.get('SIGNING_TEST_AUTHORITY', 'Developer ID Application: Test Identity'), file=sys.stderr)
if Path(sys.argv[0]).name == 'xcrun':
    print(json.dumps({'status': os.environ.get('SIGNING_TEST_NOTARY_STATUS', 'Accepted')}))
''')
            path.chmod(0o755)

    def run_flow(self, commands):
        return subprocess.run(['/bin/bash', '-euc', 'source "$1"; ' + commands,
                               'signing-test', str(ROOT / 'scripts/macos-signing.sh'), str(self.target)],
                              env=self.env, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_distribution_rejects_missing_identity_before_tools_run(self):
        self.env.pop('CODE_SIGN_IDENTITY')
        result = self.run_flow('validate_signing_configuration')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CODE_SIGN_IDENTITY', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_distribution_rejects_missing_notary_credentials(self):
        self.env.pop('NOTARY_KEYCHAIN_PROFILE')
        result = self.run_flow('validate_signing_configuration')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_development_mode_needs_no_apple_credentials(self):
        self.env['TOKMAC_SIGNING_MODE'] = 'development'
        self.env.pop('CODE_SIGN_IDENTITY')
        self.env.pop('NOTARY_KEYCHAIN_PROFILE')
        self.assertEqual(self.run_flow('validate_signing_configuration').returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_distribution_requires_developer_id_and_hardened_runtime(self):
        result = self.run_flow('validate_signing_configuration; sign_distribution_file "$2"; notarize_file "$2"')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertIn('runtime', calls[0])
        self.assertIn('--timestamp', calls[0])
        self.assertEqual(calls[0][-1], str(self.target))
        self.assertIn('--keychain-profile', calls[-1])
        self.assertTrue(Path(str(self.target) + '.notary-result.json').is_file())

    def test_non_developer_id_certificate_is_rejected(self):
        self.env['SIGNING_TEST_AUTHORITY'] = 'Apple Development: Local Certificate'
        result = self.run_flow('validate_signing_configuration; sign_distribution_file "$2"; notarize_file "$2"')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(all(call[0] != 'xcrun' for call in self.calls()))

    def test_notary_rejection_is_failure_even_when_tool_exits_successfully(self):
        self.env['SIGNING_TEST_NOTARY_STATUS'] = 'Invalid'
        result = self.run_flow('validate_signing_configuration; notarize_file "$2"')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not accepted', result.stderr)


if __name__ == '__main__':
    unittest.main()
