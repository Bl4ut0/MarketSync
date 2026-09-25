import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

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
            self.assertEqual(manifest["version"], "0.9.1")
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                self.assertTrue(all(n.startswith("MarketSync/") for n in names))
                self.assertIn("MarketSync/MarketSync.toc", names)
                self.assertIn("MarketSync/DATA_EXTRACTION_GUIDE.md", names)
                self.assertIn("MarketSync/FOREVERLEDGER_INTEGRATION.md", names)
                self.assertIn("MarketSync/Scanner.lua", names)
                self.assertIn("MarketSync/Favorites.lua", names)
                self.assertIn("MarketSync/AuctionHouse.lua", names)
                self.assertIn("MarketSync/UI_AHScanner.lua", names)
                toc = archive.read("MarketSync/MarketSync.toc").decode()
                self.assertIn("## AllowLoadGameType: camelot", toc)
                self.assertIn("## Version: 0.9.1", toc)
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

    def test_rejects_known_build_id_and_invalid_interface_values(self):
        with tempfile.TemporaryDirectory() as folder:
            for value in [69893, 0, -1, 1000000]:
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
