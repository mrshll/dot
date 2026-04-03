#!/usr/bin/env python3
"""
Generate an ffmetadata file with chapter markers for embedding into an MP3.

Usage:
    python write_chapters.py chapters.json output.ffmetadata [--duration SECONDS]

chapters.json format:
[
    {"time": "00:00:03", "title": "Intro"},
    {"time": "00:02:39", "title": "Abstract"},
    {"time": "00:09:03", "title": "A taxonomy of bias"}
]

The script converts timestamps to milliseconds and writes ffmetadata format
that ffmpeg can use with -i to embed chapters.
"""

import json
import sys
import re


def parse_timestamp(ts: str) -> int:
    """Convert HH:MM:SS or MM:SS to milliseconds."""
    parts = ts.strip().split(":")
    if len(parts) == 3:
        h, m, s = int(parts[0]), int(parts[1]), int(parts[2])
    elif len(parts) == 2:
        h, m, s = 0, int(parts[0]), int(parts[1])
    else:
        raise ValueError(f"Cannot parse timestamp: {ts}")
    return (h * 3600 + m * 60 + s) * 1000


def write_ffmetadata(chapters: list, output_path: str, duration_ms: int | None = None):
    """Write an ffmetadata file with chapter markers.

    If duration_ms is not provided, the last chapter extends 1 hour past its start
    (ffmpeg will clamp to actual audio duration).
    """
    lines = [";FFMETADATA1", ""]

    for i, chapter in enumerate(chapters):
        start_ms = parse_timestamp(chapter["time"])

        # End time is the start of the next chapter, or duration, or start + 1hr
        if i + 1 < len(chapters):
            end_ms = parse_timestamp(chapters[i + 1]["time"])
        elif duration_ms:
            end_ms = duration_ms
        else:
            end_ms = start_ms + 3600000  # 1 hour fallback

        lines.append("[CHAPTER]")
        lines.append("TIMEBASE=1/1000")
        lines.append(f"START={start_ms}")
        lines.append(f"END={end_ms}")
        lines.append(f"title={chapter['title']}")
        lines.append("")

    with open(output_path, "w") as f:
        f.write("\n".join(lines))

    print(f"Wrote {len(chapters)} chapters to {output_path}")


def parse_chapters_from_text(text: str) -> list:
    """Extract chapters from freeform text (e.g., Google Doc export).

    Looks for lines matching patterns like:
        00:00:03 - Intro
        00:02:39 Abstract
        **00:02:39** - Abstract
        - 00:02:39 - Abstract
    """
    chapters = []
    # Match optional markdown/bullets, then timestamp, then separator, then title
    pattern = r'[-*•]?\s*\**(\d{1,2}:\d{2}(?::\d{2})?)\**\s*[-–—:]?\s*(.+)'

    for line in text.split("\n"):
        line = line.strip()
        match = re.match(pattern, line)
        if match:
            time_str = match.group(1)
            title = match.group(2).strip().rstrip("*").strip()
            # Normalize to HH:MM:SS
            if time_str.count(":") == 1:
                time_str = "00:" + time_str
            chapters.append({"time": time_str, "title": title})

    return chapters


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: write_chapters.py <chapters.json | --parse TEXT_FILE> <output.ffmetadata> [--duration SECONDS]")
        sys.exit(1)

    duration_ms = None
    for i, arg in enumerate(sys.argv):
        if arg == "--duration" and i + 1 < len(sys.argv):
            duration_ms = int(float(sys.argv[i + 1]) * 1000)

    if sys.argv[1] == "--parse":
        with open(sys.argv[2]) as f:
            text = f.read()
        chapters = parse_chapters_from_text(text)
        output_path = sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith("--") else "chapters.ffmetadata"
    else:
        with open(sys.argv[1]) as f:
            chapters = json.load(f)
        output_path = sys.argv[2]

    if not chapters:
        print("No chapters found!")
        sys.exit(1)

    print(f"Found {len(chapters)} chapters:")
    for ch in chapters:
        print(f"  {ch['time']} - {ch['title']}")

    write_ffmetadata(chapters, output_path, duration_ms)
