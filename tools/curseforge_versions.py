"""Resolve exact supported client versions from CurseForge's authenticated catalog."""
import json
from pathlib import Path
import sys


TARGETS = (("1.60.1", 16001, 88568), ("1.15.9", 11509, None), ("2.5.6", 20506, None))


def resolve(catalog, toc):
    interfaces = next(line.split(":", 1)[1] for line in toc.splitlines()
                      if line.startswith("## Interface:"))
    interfaces = {int(value.strip()) for value in interfaces.split(",")}
    result = []
    for name, interface, version_type in TARGETS:
        if interface not in interfaces:
            raise ValueError(f"Supported version {name} requires TOC Interface {interface}")
        matches = {row["id"] for row in catalog if row.get("name") == name
                   and (version_type is None or row.get("gameVersionTypeID") == version_type)}
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one CurseForge ID for {name}; found {len(matches)}")
        result.append(matches.pop())
    return result


if __name__ == "__main__":
    print(json.dumps(resolve(json.load(sys.stdin), Path("MarketSync/MarketSync.toc").read_text())))
