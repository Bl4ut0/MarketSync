import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("cf_versions", Path(__file__).resolve().parents[1] / "tools/curseforge_versions.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CurseForgeVersionTests(unittest.TestCase):
    def setUp(self):
        self.toc = "## Interface: 16001, 120001, 50503, 20506, 11509"
        self.catalog = [
            {"id": 1, "name": "1.60.1", "gameVersionTypeID": 88568},
            {"id": 2, "name": "1.15.9", "gameVersionTypeID": 67408},
            {"id": 3, "name": "2.5.6", "gameVersionTypeID": 73246},
            {"id": 4, "name": "5.5.3", "gameVersionTypeID": 517},
            {"id": 5, "name": "12.0.1", "gameVersionTypeID": 517},
        ]

    def test_exact_multi_client_ids(self):
        self.assertEqual(module.resolve(self.catalog, self.toc), [1, 2, 3, 4, 5])

    def test_optional_versions_included_when_present_in_toc_and_catalog(self):
        toc = self.toc + ", 120000, 11508, 20505, 50504, 120107"
        catalog = self.catalog + [
            {"id": 6, "name": "1.15.8", "gameVersionTypeID": 67408},
            {"id": 7, "name": "2.5.5", "gameVersionTypeID": 73246},
            {"id": 8, "name": "5.5.4", "gameVersionTypeID": 517},
            {"id": 9, "name": "12.0.0", "gameVersionTypeID": 517},
            {"id": 10, "name": "12.1.7", "gameVersionTypeID": 517},
        ]
        self.assertEqual(module.resolve(catalog, toc), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])

    def test_optional_versions_skipped_cleanly_when_missing_or_ambiguous(self):
        toc = self.toc + ", 38000, 120107"
        catalog = self.catalog + [
            {"id": 98, "name": "12.1.7", "gameVersionTypeID": 517},
            {"id": 99, "name": "12.1.7", "gameVersionTypeID": 518},
        ]
        self.assertEqual(module.resolve(catalog, toc), [1, 2, 3, 4, 5])

    def test_missing_or_ambiguous_required_version_stops_publication(self):
        with self.assertRaises(ValueError):
            module.resolve(self.catalog[:-1], self.toc)
        with self.assertRaises(ValueError):
            module.resolve(self.catalog + [{"id": 99, "name": "2.5.6"}], self.toc)

    def test_toc_and_forever_type_must_match(self):
        with self.assertRaises(ValueError):
            module.resolve(self.catalog, "## Interface: 16001, 11509")
        self.catalog[0]["gameVersionTypeID"] = 0
        with self.assertRaises(ValueError):
            module.resolve(self.catalog, self.toc)
