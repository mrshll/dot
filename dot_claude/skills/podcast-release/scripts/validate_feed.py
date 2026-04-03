#!/usr/bin/env python3
"""
Validate a podcast RSS feed for common issues.

Usage:
    python validate_feed.py [URL]

Defaults to https://dynamical.org/feed/podcast.xml
"""

import sys
import urllib.request
import xml.etree.ElementTree as ET


ITUNES_NS = "http://www.itunes.com/dtds/podcast-1.0.dtd"
REQUIRED_CHANNEL_FIELDS = ["title", "description", "link", "language"]
REQUIRED_ITEM_FIELDS = ["title", "link", "guid", "pubDate"]


def validate(url: str) -> list[str]:
    """Return a list of warnings/errors. Empty list = valid."""
    issues = []

    # Fetch
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            xml_bytes = resp.read()
    except Exception as e:
        return [f"FATAL: Could not fetch feed: {e}"]

    # Parse XML
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError as e:
        return [f"FATAL: Invalid XML: {e}"]

    channel = root.find("channel")
    if channel is None:
        return ["FATAL: No <channel> element found"]

    # Channel-level checks
    for field in REQUIRED_CHANNEL_FIELDS:
        el = channel.find(field)
        if el is None or not (el.text or "").strip():
            issues.append(f"WARNING: Missing or empty <{field}> in channel")

    itunes_image = channel.find(f"{{{ITUNES_NS}}}image")
    if itunes_image is None:
        issues.append("WARNING: Missing <itunes:image> in channel")

    # Episode checks
    items = channel.findall("item")
    if not items:
        issues.append("WARNING: No episodes found in feed")

    for i, item in enumerate(items):
        ep_title = (item.findtext("title") or "").strip()
        label = ep_title or f"item[{i}]"

        for field in REQUIRED_ITEM_FIELDS:
            el = item.find(field)
            if el is None or not (el.text or "").strip():
                issues.append(f"WARNING [{label}]: Missing or empty <{field}>")

        enclosure = item.find("enclosure")
        if enclosure is None:
            issues.append(f"WARNING [{label}]: Missing <enclosure> (no audio)")
        else:
            enc_url = enclosure.get("url", "")
            enc_type = enclosure.get("type", "")
            if not enc_url:
                issues.append(f"WARNING [{label}]: <enclosure> has no url")
            if enc_type != "audio/mpeg":
                issues.append(f"INFO [{label}]: <enclosure> type is '{enc_type}', expected 'audio/mpeg'")

        itunes_ep = item.find(f"{{{ITUNES_NS}}}episode")
        if itunes_ep is None:
            issues.append(f"INFO [{label}]: No <itunes:episode> number")

    return issues


if __name__ == "__main__":
    url = sys.argv[1] if len(sys.argv) > 1 else "https://dynamical.org/feed/podcast.xml"
    print(f"Validating: {url}\n")

    issues = validate(url)

    if not issues:
        print("✓ Feed is valid. No issues found.")
    else:
        for issue in issues:
            print(f"  {issue}")
        fatals = [i for i in issues if i.startswith("FATAL")]
        warnings = [i for i in issues if i.startswith("WARNING")]
        infos = [i for i in issues if i.startswith("INFO")]
        print(f"\nSummary: {len(fatals)} fatal, {len(warnings)} warnings, {len(infos)} info")

    sys.exit(1 if any(i.startswith("FATAL") for i in issues) else 0)
