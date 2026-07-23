from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

old_lookup = """  Future<Router1ClientLookup> _lookupOrCreateTrial() async {
    final current = await _lookupVpnAccess(null, attempts: 3);
    if (current != null && _fabulaConfigs(current).isNotEmpty) return current;
    throw const FormatException('vpn_access_required');
  }
"""
new_lookup = """  Future<Router1ClientLookup> _lookupOrCreateTrial() async {
    final deviceType = Platform.isWindows ? 'laptop_test' : 'smartphone_test';
    final platformAccess = await _lookupVpnAccess(deviceType, attempts: 3);
    if (platformAccess != null && _fabulaConfigs(platformAccess).isNotEmpty) {
      return platformAccess;
    }
    final fallback = await _lookupVpnAccess(null, attempts: 2);
    if (fallback != null && _fabulaConfigs(fallback).isNotEmpty) return fallback;
    throw const FormatException('vpn_access_required');
  }
"""

old_prepare = """        final text = await _fetchVpnConfigWithRetry(config.id);
        await tunnel.prepare();
        vpn = await tunnel.connect(text, serverCode: config.serverCode);
"""
new_prepare = """        final text = await _fetchVpnConfigWithRetry(config.id);
        final prepared = await tunnel.prepare();
        if (!prepared) {
          throw const FormatException('vpn_permission_denied');
        }
        vpn = await tunnel.connect(text, serverCode: config.serverCode);
"""

if old_lookup not in text:
    raise SystemExit('VPN lookup block not found; refusing an unsafe patch')
if old_prepare not in text:
    raise SystemExit('VPN prepare block not found; refusing an unsafe patch')

text = text.replace(old_lookup, new_lookup, 1)
text = text.replace(old_prepare, new_prepare, 1)
path.write_text(text, encoding='utf-8')
print('FABULA_VPN_PREPARE_HOTFIX_OK')
