import importlib.util
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock
import zipfile
import re

tool = Path(__file__).resolve().parents[1] / "tools" / "package.py"
spec = importlib.util.spec_from_file_location("marketsync_package", tool)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PackageTests(unittest.TestCase):
    def test_package_is_complete_and_standalone(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "MarketSync.zip"
            manifest = module.build(output)
            self.assertEqual(manifest["addon"], "MarketSync")
            source_toc = (module.ROOT / "MarketSync" / "MarketSync.toc").read_text()
            expected_version = re.search(r"^## Version: (.+)$", source_toc, re.MULTILINE).group(1)
            self.assertEqual(manifest["version"], expected_version)
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                self.assertTrue(all(n.startswith("MarketSync/") for n in names))
                self.assertIn("MarketSync/MarketSync.toc", names)
                self.assertIn("MarketSync/DATA_EXTRACTION_GUIDE.md", names)
                self.assertIn("MarketSync/OBSERVATION_API.md", names)
                self.assertIn("MarketSync/PERFORMANCE_AND_SCALE.md", names)
                self.assertIn("MarketSync/Scanner.lua", names)
                self.assertIn("MarketSync/Favorites.lua", names)
                self.assertIn("MarketSync/AuctionHouse.lua", names)
                self.assertIn("MarketSync/UI_AHScanner.lua", names)
                self.assertIn("MarketSync/InventoryTracking.lua", names)
                self.assertIn("MarketSync/Media/LegacyStoneCanvas.tga", names)
                self.assertFalse(any(name.startswith("MarketSync/Ledger/") for name in names))
                toc = archive.read("MarketSync/MarketSync.toc").decode()
                self.assertIn("## AllowLoadGameType: camelot, classic, tbc", toc)
                self.assertIn("LegacyScanner.lua", toc)
                self.assertIn("MarketSync/LegacyScanner.lua", names)
                self.assertIn("PostingWarning.lua", toc)
                self.assertIn("MarketSync/PostingWarning.lua", names)
                self.assertIn("## Version: " + expected_version, toc)
            self.assertEqual(manifest["auctionHouseEntry"], "embedded-tab")
            self.assertTrue(manifest["embeddedAuctionHousePanel"])
            self.assertTrue(manifest["nativeScanner"])
            self.assertTrue(manifest["preferredLists"])

    def test_supplied_interface(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "test.zip"
            manifest = module.build(output, 11509)
            self.assertEqual(manifest["interface"], 11509)
            with zipfile.ZipFile(output) as archive:
                toc = archive.read("MarketSync/MarketSync.toc").decode()
                self.assertIn("## Interface: 11509", toc)

    def test_ledger_has_its_own_load_manifest(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "MarketSyncLedger.zip"
            manifest = module.build(output, ledger=True)
            self.assertEqual(manifest["dependency"], "MarketSync")
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                self.assertTrue(all(name.startswith("MarketSyncLedger/") for name in names))
                self.assertNotIn("MarketSyncLedger/InventoryTracking.lua", names)
                toc = archive.read("MarketSyncLedger/MarketSyncLedger.toc").decode()
                self.assertIn("## Dependencies: MarketSync", toc)
                self.assertIn("## SavedVariables: MarketSyncLedgerDB", toc)
                for entry in toc.splitlines():
                    if entry.endswith(".lua"):
                        self.assertIn(f"MarketSyncLedger/{entry}", names)

    def test_legacy_flavor_package(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "MarketSync-Era.zip"
            manifest = module.build(output, 11509, "classic")
            self.assertEqual(manifest["gameType"], "classic")
            self.assertEqual(manifest["targetVersion"], "1.15.9")
            self.assertIsNone(manifest["targetBuild"])
            with zipfile.ZipFile(output) as archive:
                toc = archive.read("MarketSync/MarketSync.toc").decode()
                self.assertIn("## Interface: 11509", toc)
                self.assertIn("## AllowLoadGameType: classic", toc)
                self.assertIn("LegacyScanner.lua", toc)
            with self.assertRaises(ValueError):
                module.build(Path(folder) / "no-interface.zip", game_type="tbc")

    def test_unified_source_packages_each_client_flavor(self):
        flavors = (
            ("forever", 16001, "camelot", True),
            ("era", 11509, "classic", False),
            ("anniversary", 11509, "classic", False),
            ("sod", 11509, "classic", False),
            ("tbc", 20506, "tbc", False),
        )
        with tempfile.TemporaryDirectory() as folder:
            for flavor, interface, game_type, embedded in flavors:
                with self.subTest(flavor=flavor):
                    output = Path(folder) / f"MarketSync-{flavor}.zip"
                    manifest = module.build(output, interface=interface, flavor=flavor)
                    self.assertEqual(manifest["flavor"], flavor)
                    self.assertEqual(manifest["gameType"], game_type)
                    self.assertEqual(manifest["targetVersion"], {"camelot": "1.60.1", "classic": "1.15.9", "tbc": "2.5.6"}[game_type])
                    self.assertEqual(manifest["embeddedAuctionHousePanel"], embedded)
                    self.assertEqual(manifest["interface"], interface)
                    with zipfile.ZipFile(output) as archive:
                        names = set(archive.namelist())
                        self.assertTrue(all(name.startswith("MarketSync/") for name in names))
                        self.assertFalse(any(".Examples" in name or name.startswith("tests/") for name in names))
                        self.assertFalse(any(name.startswith("MarketSync/Ledger/") for name in names))
                        self.assertEqual(
                            archive.read("MarketSync/InventoryTracking.lua"),
                            (module.ROOT / "MarketSync" / "InventoryTracking.lua").read_bytes(),
                        )
                        toc = archive.read("MarketSync/MarketSync.toc").decode()
                        self.assertIn(f"## Interface: {interface}", toc)
                        self.assertIn(f"## AllowLoadGameType: {game_type}", toc)
                        for entry in re.findall(r"^(?!#|##)([^\r\n]+\.lua)$", toc, re.M):
                            self.assertIn("MarketSync/" + entry.replace("\\", "/"), names)
                    self.assertTrue(output.with_suffix(".zip.sha256").exists())
                    self.assertTrue(output.with_suffix(".zip.manifest.json").exists())

    def test_zip_timestamp_follows_source_date_epoch(self):
        with tempfile.TemporaryDirectory() as folder:
            pinned = Path(folder) / "pinned.zip"
            with mock.patch.dict(os.environ, {"SOURCE_DATE_EPOCH": "1700000000"}):
                module.build(pinned)
            with zipfile.ZipFile(pinned) as archive:
                self.assertEqual(archive.infolist()[0].date_time, time.gmtime(1700000000)[:6])
            fallback = Path(folder) / "fallback.zip"
            with mock.patch.dict(os.environ, {}):
                os.environ.pop("SOURCE_DATE_EPOCH", None)
                module.build(fallback)
            with zipfile.ZipFile(fallback) as archive:
                self.assertEqual(archive.infolist()[0].date_time, (2026, 9, 17, 0, 0, 0))

    def test_lua_texture_paths_resolve_in_repo(self):
        # Textures referenced by the addon Lua that are not shipped yet. Remove an entry once the asset exists.
        known_missing = {"Media/MarketSyncIcon"}
        pattern = re.compile(r'Interface\\\\AddOns\\\\MarketSync\\\\([^"]+)"')
        addon_dir = module.ROOT / "MarketSync"
        references = set()
        for lua in addon_dir.rglob("*.lua"):
            for match in pattern.finditer(lua.read_text(encoding="utf-8")):
                references.add(match.group(1).replace("\\\\", "/"))
        self.assertTrue(references, "No MarketSync texture paths were found in the Lua source")
        missing = set()
        for rel in references:
            target = addon_dir / rel
            candidates = [target] + [target.with_name(target.name + ext) for ext in (".tga", ".blp", ".png", ".jpg")]
            if not any(candidate.is_file() for candidate in candidates):
                missing.add(rel)
        self.assertEqual(missing, known_missing, "Texture paths in Lua must resolve to files in MarketSync/")

    def test_flavor_cannot_conflict_with_game_type(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                module.build(Path(folder) / "bad.zip", 11509, "tbc", "era")

    def test_rejects_known_build_id_and_invalid_interface_values(self):
        with tempfile.TemporaryDirectory() as folder:
            for value in [69893, 70205, 0, -1, 1000000]:
                with self.subTest(value=value), self.assertRaises(ValueError):
                    module.build(Path(folder) / (str(value) + ".zip"), value)

    def test_refuses_overwrite_and_archives_are_reproducible(self):
        with tempfile.TemporaryDirectory() as folder:
            one, two = Path(folder) / "one.zip", Path(folder) / "two.zip"
            first, second = module.build(one), module.build(two)
            self.assertEqual(first["sha256"], second["sha256"])
            with self.assertRaises(ValueError):
                module.build(one)


if __name__ == "__main__":
    unittest.main()
