"""Resolve exact supported client versions from CurseForge's authenticated catalog."""
import json
from pathlib import Path
import sys


# Required client versions verified live in CurseForge's WoW catalog and declared in MarketSync.toc.
REQUIRED_TARGETS = (
    ("1.60.1", 16001, 88568),
    ("1.15.8", 11508, None),
    ("1.15.9", 11509, None),
    ("2.5.5", 20505, None),
    ("2.5.6", 20506, None),
    ("3.8.0", 38000, None),
    ("5.5.3", 50503, None),
    ("12.0.0", 120000, None),
    ("12.0.1", 120001, None),
)

# Newer Retail / Classic progression patches listed in MarketSync.toc; included when present in the catalog.
OPTIONAL_TARGETS = (
    ("5.5.4", 50504, None),
    ("12.0.5", 120005, None),
    ("12.0.7", 120007, None),
    ("12.1.0", 120100, None),
    ("12.1.5", 120105, None),
    ("12.1.7", 120107, None),
)

TARGETS = REQUIRED_TARGETS


def _resolve_target(catalog, interfaces, name, interface, version_type, *, required):
    if interface not in interfaces:
        if required:
            raise ValueError(f"Supported version {name} requires TOC Interface {interface}")
        return None
    matches = {
        row["id"]
        for row in catalog
        if row.get("name") == name
        and (version_type is None or row.get("gameVersionTypeID") == version_type)
    }
    if len(matches) == 1:
        return matches.pop()
    if len(matches) > 1 or required:
        raise ValueError(f"Expected exactly one CurseForge ID for {name}; found {len(matches)}")
    return None


def resolve(catalog, toc):
    """Map MarketSync.toc Interface declarations to unique CurseForge WoW version IDs."""
    interfaces_line = next(
        line.split(":", 1)[1] for line in toc.splitlines() if line.startswith("## Interface:")
    )
    interfaces = {int(value.strip()) for value in interfaces_line.split(",")}

    seen = set()
    result = []
    for target_group, is_required in ((REQUIRED_TARGETS, True), (OPTIONAL_TARGETS, False)):
        for name, interface, version_type in target_group:
            version_id = _resolve_target(
                catalog,
                interfaces,
                name,
                interface,
                version_type,
                required=is_required,
            )
            if version_id is not None and version_id not in seen:
                seen.add(version_id)
                result.append(version_id)
    return result


if __name__ == "__main__":
    print(json.dumps(resolve(json.load(sys.stdin), Path("MarketSync/MarketSync.toc").read_text())))
