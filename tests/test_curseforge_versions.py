import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cf_versions", Path(__file__).resolve().parents[1] / "tools/curseforge_versions.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CurseForgeVersionTests(unittest.TestCase):
    def setUp(self):
        self.toc = "## Interface: 16001, 11509, 20506"
        self.catalog = [{"id": 1, "name": "1.60.1", "gameVersionTypeID": 88568},
                        {"id": 2, "name": "1.15.9", "gameVersionTypeID": 1},
                        {"id": 3, "name": "2.5.6", "gameVersionTypeID": 2}]

    def test_exact_multi_client_ids(self):
        self.assertEqual(module.resolve(self.catalog, self.toc), [1, 2, 3])

    def test_missing_or_ambiguous_version_stops_publication(self):
        with self.assertRaises(ValueError):
            module.resolve(self.catalog[:-1], self.toc)
        with self.assertRaises(ValueError):
            module.resolve(self.catalog + [{"id": 4, "name": "2.5.6"}], self.toc)

    def test_toc_and_forever_type_must_match(self):
        with self.assertRaises(ValueError):
            module.resolve(self.catalog, "## Interface: 16001, 11509")
        self.catalog[0]["gameVersionTypeID"] = 0
        with self.assertRaises(ValueError):
            module.resolve(self.catalog, self.toc)
