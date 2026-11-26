#!/usr/bin/env python3
"""Adds one release to appcast.xml, the Sparkle feed the app checks (newest item first).

  scripts/appcast.py appcast.xml --version 0.4.0 --url <dmg url> --length <bytes> \
      --signature <sparkle:edSignature> --notes-html <file> --release-page <url>

The feed is served from main (Info.plist SUFeedURL), so an item only goes in after its DMG is
uploaded. Re-adding a version that is already listed is refused.
"""
import argparse
import email.utils
import sys
from xml.sax.saxutils import escape, quoteattr

MARKER = "<!-- releases: newest first, added by scripts/publish-release.sh -->"

EMPTY = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Marky</title>
    <link>https://github.com/stefanskotte/marky</link>
    <description>Marky updates</description>
    <language>en</language>
    {MARKER}
  </channel>
</rss>
"""


def item(version, url, length, signature, notes_html, release_page, min_os, pub_date):
    notes = notes_html.replace("]]>", "]]]]><![CDATA[>")
    return f"""<item>
      <title>Marky {escape(version)}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{escape(version)}</sparkle:version>
      <sparkle:shortVersionString>{escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{escape(min_os)}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{escape(release_page)}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{notes}]]></description>
      <enclosure url={quoteattr(url)} length={quoteattr(str(length))} type="application/x-apple-diskimage"
                 sparkle:edSignature={quoteattr(signature)}/>
    </item>"""


def add(feed, version, **fields):
    if MARKER not in feed:
        raise ValueError("appcast.xml has no release marker")
    if f"<sparkle:version>{escape(version)}</sparkle:version>" in feed:
        raise ValueError(f"{version} is already in the appcast")
    return feed.replace(MARKER, MARKER + "\n    " + item(version, **fields), 1)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("appcast")
    p.add_argument("--init", action="store_true", help="write an empty feed and stop")
    p.add_argument("--version")
    p.add_argument("--url")
    p.add_argument("--length", type=int)
    p.add_argument("--signature")
    p.add_argument("--notes-html")
    p.add_argument("--release-page")
    p.add_argument("--min-os", default="14.0")
    a = p.parse_args()
    if a.init:
        with open(a.appcast, "w") as f:
            f.write(EMPTY)
        return
    missing = [n for n in ("version", "url", "length", "signature", "notes_html", "release_page")
               if getattr(a, n) is None]
    if missing:
        p.error("missing " + ", ".join("--" + m.replace("_", "-") for m in missing))
    with open(a.notes_html) as f:
        notes = f.read()
    with open(a.appcast) as f:
        feed = f.read()
    try:
        feed = add(feed, a.version, url=a.url, length=a.length, signature=a.signature, notes_html=notes,
                   release_page=a.release_page, min_os=a.min_os,
                   pub_date=email.utils.formatdate(usegmt=True))
    except ValueError as e:
        sys.exit(f"appcast.py: {e}")
    with open(a.appcast, "w") as f:
        f.write(feed)


if __name__ == "__main__":
    main()
