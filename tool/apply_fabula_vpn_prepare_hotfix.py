from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

required_blocks = (
    "  Future<void> _toggleVpn() async {\n",
    "        await tunnel.prepare();\n",
    "        vpn = await tunnel.connect(text, serverCode: config.serverCode);\n",
    "  Future<Router1ClientLookup> _lookupOrCreateTrial() async {\n",
    "    final current = await _lookupVpnAccess(null, attempts: 3);\n",
)

missing = [block.strip() for block in required_blocks if block not in text]
if missing:
    raise SystemExit(f'Working VPN baseline is incomplete: {missing}')

print('FABULA_WORKING_VPN_BASELINE_OK')
