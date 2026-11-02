import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('service_cleanup', Path(__file__).with_name('clean-finder-services.py'))
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class ServiceCleanupTest(unittest.TestCase):
    def test_preserve_installed_and_other_apps(self):
        dump = '''------------------------------
path: /Applications/归屿.app (0x1)
identifier: local.guiyu.workspace
------------------------------
path: /tmp/PreviousVersionProbe.app (0x2)
identifier: local.guiyu.releaseverify.test
------------------------------
path: /Applications/Other.app (0x3)
identifier: com.example.guiyu
------------------------------
path: /Applications/Similar.app (0x4)
identifier: local.guiyuish.app
'''
        self.assertEqual(cleanup.candidates(dump, Path('/Applications/归屿.app')), ['/tmp/PreviousVersionProbe.app'])

    def test_duplicate_records_and_paths_with_spaces(self):
        entry = '------------------------------\npath: /tmp/Guiyu Test (old)/归屿.app (0xabc)\nidentifier: local.guiyu.updatefixture.test\n'
        self.assertEqual(cleanup.candidates(entry + entry, Path('/Applications/归屿.app')), ['/tmp/Guiyu Test (old)/归屿.app'])

    def test_missing_or_unrecognized_records_do_not_expand_scope(self):
        self.assertEqual(cleanup.candidates('path: /Applications/Other.app\nname: 归屿\n', Path('/Applications/归屿.app')), [])


if __name__ == '__main__':
    unittest.main()
