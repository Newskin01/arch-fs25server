#!/bin/bash
set -euo pipefail

CONFIG_FILE="$1"
shift || true

if [[ ! -f "$CONFIG_FILE" || $# -eq 0 ]]; then
  exit 0
fi

python3 - "$CONFIG_FILE" "$@" <<'PY'
import sys
import xml.etree.ElementTree as ET

config = sys.argv[1]
kv_pairs = sys.argv[2:]
params = {}
for pair in kv_pairs:
    if '=' in pair:
        key, value = pair.split('=', 1)
        params[key] = value

try:
    tree = ET.parse(config)
except Exception:
    sys.exit(1)

root = tree.getroot()
webserver = root.find('webserver')
if webserver is None:
    webserver = ET.SubElement(root, 'webserver')

changed = False
port = params.get('WEB_PORT')
if port is not None and webserver.get('port') != port:
    webserver.set('port', port)
    changed = True

initial_admin = webserver.find('initial_admin')
if initial_admin is None:
    initial_admin = ET.SubElement(webserver, 'initial_admin')

username = params.get('WEB_USERNAME')
if username is not None:
    elem = initial_admin.find('username')
    if elem is None:
        elem = ET.SubElement(initial_admin, 'username')
    if elem.text != username:
        elem.text = username
        changed = True

password = params.get('WEB_PASSWORD')
if password is not None:
    elem = initial_admin.find('passphrase')
    if elem is None:
        elem = ET.SubElement(initial_admin, 'passphrase')
    if elem.text != password:
        elem.text = password
        changed = True

scheme = params.get('WEB_SCHEME')
if scheme is not None:
    tls = webserver.find('tls')
    if tls is None:
        tls = ET.SubElement(webserver, 'tls')
    desired_active = 'true' if scheme == 'https' else 'false'
    if tls.get('active') != desired_active:
        tls.set('active', desired_active)
        changed = True
    port_val = port or tls.get('port')
    if port_val and tls.get('port') != port_val:
        tls.set('port', port_val)
        changed = True

game = root.find('game')
if game is None:
    game = ET.SubElement(root, 'game')

logos = game.find('logos')
if logos is None:
    logos = ET.SubElement(game, 'logos')

login_logo = params.get('LOGIN_LOGO')
if login_logo is not None:
    elem = logos.find('login')
    if elem is None:
        elem = ET.SubElement(logos, 'login')
    if elem.text != login_logo:
        elem.text = login_logo
        changed = True

bottom_logo = params.get('BOTTOM_LOGO')
if bottom_logo is not None:
    elem = logos.find('bottom')
    if elem is None:
        elem = ET.SubElement(logos, 'bottom')
    if elem.text != bottom_logo:
        elem.text = bottom_logo
        changed = True

if changed:
    tree.write(config, encoding='utf-8', xml_declaration=True)
PY
