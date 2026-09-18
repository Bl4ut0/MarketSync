import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

tool = Path(__file__).resolve().parents[1] / "tools" / "package.py"
spec = importlib.util.spec_from_file_location("scanner_package", tool)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PackageTests(unittest.TestCase):
    def test_draft_is_explicit_and_standalone(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "test.zip"
            manifest = module.build(output)
            self.assertIsNone(manifest["interface"])
            self.assertEqual(manifest["interfaceStatus"], "unverified-draft")
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(len(archive.namelist()), 8)
                self.assertTrue(all(n.startswith("MarketSyncForeverScanner/") for n in archive.namelist()))
                toc = archive.read("MarketSyncForeverScanner/MarketSyncForeverScanner.toc").decode()
                self.assertNotIn("Dependencies:", toc)
                self.assertIn("unverified-draft", toc)
                self.assertIn("## AllowLoadGameType: camelot", toc)
                self.assertIn("AuctionHouse.lua [AllowLoadGameType camelot]", toc)
                self.assertIn("## Version: 0.2.0", toc)
            self.assertEqual(manifest["auctionHouseEntry"], "portable-launcher")
            self.assertFalse(manifest["embeddedAuctionHousePanel"])
            self.assertFalse(manifest["alerts"])

    def test_supplied_interface_does_not_claim_native_acceptance(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "test.zip"
            manifest = module.build(output, 987654)  # Test sentinel, not a real client number.
            self.assertEqual(manifest["nativeAcceptance"], "pending")
            with zipfile.ZipFile(output) as archive:
                toc = archive.read("MarketSyncForeverScanner/MarketSyncForeverScanner.toc").decode()
                self.assertIn("## Interface: 987654", toc)
                self.assertIn("supplied-for-local-test", toc)

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
