#!/usr/bin/env bash
# Puts a release at the top of a Sparkle appcast, keeping the newest 20.
# Usage: scripts/appcast.sh <appcast.xml> <version> <build> <zip url> <"sparkle:edSignature=… length=…">
set -euo pipefail
file="$1" version="$2" build="$3" url="$4" sig="$5"
min_os="14.0"
date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
notes="https://github.com/pseudobun/paw/releases/tag/v$version"

item="    <item>
      <title>paw $version</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$min_os</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$notes</sparkle:releaseNotesLink>
      <enclosure url=\"$url\" type=\"application/octet-stream\" $sig/>
    </item>"

if [ ! -s "$file" ]; then
  cat > "$file" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>paw</title>
    <link>https://github.com/pseudobun/paw</link>
    <description>paw releases</description>
    <language>en</language>
  </channel>
</rss>
XML
fi

python3 - "$file" "$item" "$version" <<'PY'
import re, sys
path, item, version = sys.argv[1:]
xml = open(path).read()
items = re.findall(r"    <item>.*?</item>\n", xml, re.S)
items = [i for i in items if f"<sparkle:shortVersionString>{version}<" not in i]
items = ([item + "\n"] + items)[:20]
head = re.sub(r"    <item>.*?</item>\n", "", xml, flags=re.S)
xml = head.replace("  </channel>", "".join(items) + "  </channel>")
open(path, "w").write(xml)
PY
