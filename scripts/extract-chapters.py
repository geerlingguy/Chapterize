#!/usr/bin/env python3
"""Pull chapter titles from the '## YouTube Description' section of video notes.

  scripts/extract-chapters.py "/Volumes/jupiter/YouTube Videos/2025"            # every title, grouped by video
  scripts/extract-chapters.py "/Volumes/jupiter/YouTube Videos/2025" --sample 30 # random titles for Settings
"""
import argparse
import random
import re
from pathlib import Path

SECTION = re.compile(r"^##\s*YouTube Description\s*$", re.I | re.M)
NEXT_HEADING = re.compile(r"^#{1,2}\s", re.M)
CHAPTER = re.compile(r"^\s*(?:\d{1,2}:)?\d{1,2}:\d{2}\s*[-–—]\s*(.+?)\s*$", re.M)


def chapters(md: Path) -> list[str]:
    text = md.read_text(encoding="utf-8", errors="replace")
    m = SECTION.search(text)
    if not m:
        return []
    body = text[m.end():]
    end = NEXT_HEADING.search(body)
    return CHAPTER.findall(body[: end.start()] if end else body)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("root", type=Path)
    p.add_argument("--sample", type=int, help="print N random titles, at most 2 per video")
    p.add_argument("--seed", type=int, help="random seed, for a repeatable sample")
    args = p.parse_args()

    videos = {}
    for md in sorted(args.root.rglob("*.md")):
        if titles := chapters(md):
            videos.setdefault(md.parent.name, []).extend(titles)

    if args.sample:
        rng = random.Random(args.seed)
        pool = [t for titles in videos.values() for t in rng.sample(titles, min(2, len(titles)))]
        print("\n".join(rng.sample(pool, min(args.sample, len(pool)))))
    else:
        for name, titles in videos.items():
            print(f"# {name}\n" + "\n".join(titles) + "\n")

    total = sum(map(len, videos.values()))
    print(f"\n({total} titles from {len(videos)} videos)" if not args.sample else "", end="")


if __name__ == "__main__":
    main()
