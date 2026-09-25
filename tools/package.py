"""Package the standalone unified MarketSync addon and its manifest/checksums."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = "MarketSync"


def build(output, interface=None):
    output = Path(output).resolve()
    if output.exists() or output.with_suffix(output.suffix + ".manifest.json").exists():
        raise ValueError("Output already exists; choose a new file")
    if interface is not None and (not 1 <= interface <= 999999 or interface == 69893):
        raise ValueError("Supply the fourth GetBuildInfo() value; build 69893 is not an Interface number")

    files = {}
    addon_dir = ROOT / ADDON
    for p in addon_dir.rglob("*"):
        if p.is_file():
            rel = p.relative_to(ROOT).as_posix()
            files[rel] = p.read_bytes()

    if (ROOT / "README.md").exists():
        files[ADDON + "/README.md"] = (ROOT / "README.md").read_bytes()
    if (ROOT / "DATA_EXTRACTION_GUIDE.md").exists():
        files[ADDON + "/DATA_EXTRACTION_GUIDE.md"] = (ROOT / "DATA_EXTRACTION_GUIDE.md").read_bytes()
    if (ROOT / "FOREVERLEDGER_INTEGRATION.md").exists():
        files[ADDON + "/FOREVERLEDGER_INTEGRATION.md"] = (ROOT / "FOREVERLEDGER_INTEGRATION.md").read_bytes()
    if (ROOT / "LICENSE").exists():
        files[ADDON + "/LICENSE"] = (ROOT / "LICENSE").read_bytes()

    toc_name = ADDON + "/" + ADDON + ".toc"
    toc = files[toc_name].decode("utf-8")
    if interface is not None:
        toc = re.sub(r"^## Interface:.*$", f"## Interface: {interface}", toc, flags=re.M)
        files[toc_name] = toc.encode("utf-8")

    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, contents in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 9, 17, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, contents)

    manifest = {
        "addon": "MarketSync",
        "version": "0.9.1",
        "targetVersion": "1.60.1",
        "targetBuild": "69893",
        "interface": interface,
        "auctionHouseEntry": "embedded-tab",
        "embeddedAuctionHousePanel": True,
        "portableWindow": True,
        "nativeScanner": True,
        "preferredLists": True,
        "guildSync": True,
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "files": {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())},
    }
    output.with_suffix(output.suffix + ".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    output.with_suffix(output.suffix + ".sha256").write_text(manifest["sha256"] + "  " + output.name + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--interface", type=int)
    args = parser.parse_args()
    try:
        result = build(args.output, args.interface)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + "\n")
    print(json.dumps(result, indent=2))
