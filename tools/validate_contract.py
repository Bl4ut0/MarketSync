"""Check scanner API/event/template references against the user's exported beta interface."""
import argparse
import hashlib
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--blizzard", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1] / "MarketSyncForeverScanner"
doc_root = args.blizzard / "Blizzard_APIDocumentationGenerated"
auction_doc = doc_root / "AuctionHouseDocumentation.lua"
auction_text = auction_doc.read_text(encoding="utf-8")
functions = set(re.findall(r'Name = "([^\"]+)",\s+Type = "Function"', auction_text))
source = "\n".join(p.read_text(encoding="utf-8") for p in root.glob("*.lua"))
called = set(re.findall(r'(?:C_AuctionHouse|\bA)\.([A-Za-z]+)\s*\(', source))
quoted = set(re.findall(r'"((?:GetNum|GetItemSearch|GetCommoditySearch|HasFull|Send|RequestMore|SearchFor|IsThrottled)[A-Za-z]+)"', source))
used = called | quoted
assert not used - functions, f"Undocumented auction function(s): {used-functions}"
core = (root / "Core.lua").read_text(encoding="utf-8")
event_block = core.split("for _, event in ipairs({", 1)[1].split("}) do", 1)[0]
events = set(re.findall(r'"([A-Z_]+)"', event_block))
documented = set()
for path in doc_root.glob("*Documentation.lua"):
    documented.update(re.findall(r'LiteralName = "([^\"]+)"', path.read_text(encoding="utf-8")))
assert not events - documented, f"Undocumented event(s): {events-documented}"
templates = args.blizzard / "Blizzard_UIPanelTemplates" / "Mainline" / "UIPanelTemplates.xml"
template_text = templates.read_text(encoding="utf-8")
assert 'name="BasicFrameTemplateWithInset"' in template_text
assert 'parentKey="TitleText"' in template_text
tab_templates = args.blizzard / "Blizzard_AuctionHouseUI" / "Mainline" / "Blizzard_AuctionHouseTab.xml"
assert 'name="AuctionHouseFrameTabTemplate"' in tab_templates.read_text(encoding="utf-8")
frame_xml = args.blizzard / "Blizzard_AuctionHouseUI" / "Shared" / "Blizzard_AuctionHouseFrame.xml"
assert 'parentKey="AuctionsTab"' in frame_xml.read_text(encoding="utf-8")
for forbidden in ["PostItem", "PostCommodity", "PlaceBid", "CancelAuction", "StartCommoditiesPurchase",
                  "ConfirmCommoditiesPurchase", "SendAddonMessage", "SendChatMessage"]:
    assert not re.search(r"\b" + forbidden + r"\s*\(", source), f"Unexpected mutation/messaging API: {forbidden}"
assert "GetNumCommoditySearchResults" in source and "GetNumItemSearchResults" in source
assert 'Name = "SendSearchQuery"' in auction_text and "100 calls per minute" in auction_text
print(json.dumps({
    "auctionFunctionReferences": sorted(used), "registeredEvents": sorted(events),
    "auctionDocumentationSHA256": hashlib.sha256(auction_doc.read_bytes()).hexdigest(),
    "physicalTemplatePresent": True, "auctionHouseTabTemplatePresent": True,
    "transactionsOrMessages": False,
    "nativeAcceptance": "pending",
}, indent=2))
