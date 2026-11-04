#!/usr/bin/env python3
"""Create and verify Sparkle's signed feed and archive using the user's Keychain."""
import hashlib
import json
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path

archive, info_path, output = map(Path, sys.argv[1:])
root = Path(__file__).resolve().parent.parent
signer = root / '.build/artifacts/sparkle/Sparkle/bin/sign_update'
info = plistlib.loads(info_path.read_bytes())
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
account = ['--account', 'local.pathfind.app']
signature = subprocess.check_output([str(signer), *account, '-p', str(archive)], text=True).strip()
subprocess.run([str(signer), *account, '--verify', str(archive), signature], check=True)
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
rss = ET.Element('rss', {'version': '2.0'})
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'Explorer Updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = f'Explorer {version}'
ET.SubElement(item, 'pubDate').text = format_datetime(datetime.now(timezone.utc))
ET.SubElement(item, 'link').text = f'https://github.com/phaed-one/macOS-Explorer/releases/tag/v{version}'
ET.SubElement(item, f'{{{ns}}}version').text = build
ET.SubElement(item, f'{{{ns}}}shortVersionString').text = version
ET.SubElement(item, f'{{{ns}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
asset_name = f'Explorer-{version}.zip'
ET.SubElement(item, 'enclosure', {
    'url': f'https://github.com/phaed-one/macOS-Explorer/releases/download/v{version}/{asset_name}',
    'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    f'{{{ns}}}edSignature': signature, f'{{{ns}}}os': 'macos',
})
feed = output / 'appcast.xml'
ET.indent(rss)
ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
subprocess.run([str(signer), *account, str(feed)], check=True)
subprocess.run([str(signer), *account, '--verify', str(feed)], check=True)
(output / 'release.json').write_text(json.dumps({
    'version': version, 'build': build, 'archive': archive.name, 'asset': asset_name,
    'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
    'appcast_sha256': hashlib.sha256(feed.read_bytes()).hexdigest(),
}, indent=2) + '\n')
print(f'Signed update archive and appcast for Explorer {version}, build {build}')
