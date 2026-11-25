"""Package MarketSync or its optional Ledger addon with a manifest and checksum."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ADDON = "MarketSync"
DEFAULT_ZIP_TIME = (2026, 9, 17, 0, 0, 0)

# Client build each game type is verified against (matches the TOC Interface lists).
CLIENT_VERSIONS = {"camelot": "1.60.1", "classic": "1.15.9", "tbc": "2.5.6"}


def zip_time():
    """Use SOURCE_DATE_EPOCH for reproducible archives when it is set."""
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch is None or epoch.strip() == "":
        return DEFAULT_ZIP_TIME
    return time.gmtime(int(epoch))[:6]


FLAVORS = {
    "forever": "camelot",
    "era": "classic",
    "anniversary": "classic",
    "sod": "classic",
    "tbc": "tbc",
}


def build(output, interface=None, game_type=None, flavor=None, *, ledger=False):
    output = Path(output).resolve()
    if output.exists() or output.with_suffix(output.suffix + ".manifest.json").exists():
        raise ValueError("Output already exists; choose a new file")
    if interface is not None and (not 1 <= interface <= 999999 or interface in (69893, 70205)):
        raise ValueError("Supply an Interface number, not a GetBuildInfo() build number")
    if game_type not in (None, "camelot", "classic", "tbc"):
        raise ValueError("Unsupported game type")
    if flavor not in (None, *FLAVORS):
        raise ValueError("Unsupported flavor")
    if flavor is not None:
        expected_type = FLAVORS[flavor]
        if game_type is not None and game_type != expected_type:
            raise ValueError("Flavor and game type disagree")
        game_type = expected_type
    if game_type in ("classic", "tbc") and interface is None:
        raise ValueError("Legacy packages require an explicit client Interface number")

    addon_dir = ROOT / ADDON
    archive_addon = "MarketSyncLedger" if ledger else ADDON
    ledger_dir = addon_dir / "Ledger"
    files = {}
    if ledger:
        for path in ledger_dir.iterdir():
            if path.is_file():
                files[f"{archive_addon}/{path.name}"] = path.read_bytes()
    else:
        for path in addon_dir.rglob("*"):
            if path.is_file() and ledger_dir not in path.parents:
                files[path.relative_to(ROOT).as_posix()] = path.read_bytes()

    docs_dir = ROOT / "docs"
    doc_names = ["LICENSE"] if ledger else ["README.md", "DATA_EXTRACTION_GUIDE.md", "OBSERVATION_API.md", "PERFORMANCE_AND_SCALE.md", "LICENSE"]
    for doc_name in doc_names:
        doc_path = ROOT / doc_name
        if not doc_path.exists():
            doc_path = docs_dir / doc_name
        if doc_path.exists():
            files[f"{archive_addon}/{doc_name}"] = doc_path.read_bytes()

    toc_name = f"{archive_addon}/{archive_addon}.toc"
    toc = files[toc_name].decode("utf-8")
    version_match = re.search(r"^## Version:\s*(\S+)\s*$", toc, flags=re.M)
    if not version_match:
        raise ValueError(f"{archive_addon}.toc is missing a Version field")
    version = version_match.group(1)
    if interface is not None:
        toc = re.sub(r"^## Interface:.*$", f"## Interface: {interface}", toc, flags=re.M)
    if game_type is not None:
        toc = re.sub(r"^## AllowLoadGameType:.*$", f"## AllowLoadGameType: {game_type}", toc, flags=re.M)
    files[toc_name] = toc.encode("utf-8")

    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, contents in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=zip_time())
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, contents)

    manifest = {
        "addon": archive_addon,
        "version": version,
        "targetVersion": CLIENT_VERSIONS[game_type or "camelot"],
        "targetBuild": "70205" if game_type in (None, "camelot") else None,
        "gameType": game_type or "multi",
        "flavor": flavor or "multi",
        "interface": interface,
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "files": {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())},
    }
    if ledger:
        manifest["dependency"] = ADDON
    else:
        manifest.update({
            "auctionHouseEntry": "embedded-tab" if game_type in (None, "camelot") else "legacy-auction-tabs",
            "embeddedAuctionHousePanel": game_type in (None, "camelot"),
            "portableWindow": True,
            "nativeScanner": True,
            "preferredLists": True,
            "guildSync": True,
        })
    output.with_suffix(output.suffix + ".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    output.with_suffix(output.suffix + ".sha256").write_text(manifest["sha256"] + "  " + output.name + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--interface", type=int)
    parser.add_argument("--game-type", choices=["camelot", "classic", "tbc"])
    parser.add_argument("--flavor", choices=list(FLAVORS))
    parser.add_argument("--ledger", action="store_true", help="Build the optional MarketSyncLedger addon")
    args = parser.parse_args()
    try:
        result = build(args.output, args.interface, args.game_type, args.flavor, ledger=args.ledger)
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + "\n")
    print(json.dumps(result, indent=2))
