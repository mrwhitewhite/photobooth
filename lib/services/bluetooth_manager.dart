import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothDeviceInfo {
  final String id;
  final String name;
  final int rssi;

  const BluetoothDeviceInfo({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

class BluetoothManager {
  static const _prefKeyDeviceId = 'saved_bt_device_id';
  static const _prefKeyDeviceName = 'saved_bt_device_name';

  static Future<({String id, String name})?> getSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_prefKeyDeviceId);
    final name = prefs.getString(_prefKeyDeviceName) ?? 'Saved Printer';
    if (id == null || id.isEmpty) return null;
    return (id: id, name: name);
  }

  static Future<void> saveDevice(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyDeviceId, id);
    await prefs.setString(_prefKeyDeviceName, name);
  }

  static Future<void> clearSavedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyDeviceId);
    await prefs.remove(_prefKeyDeviceName);
  }

  static Future<BluetoothDeviceInfo?> showPickerDialog(
      BuildContext context) async {
    return showDialog<BluetoothDeviceInfo>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _BluetoothPickerDialog(),
    );
  }
}

class _BluetoothPickerDialog extends StatefulWidget {
  const _BluetoothPickerDialog();

  @override
  State<_BluetoothPickerDialog> createState() => _BluetoothPickerDialogState();
}

class _BluetoothPickerDialogState extends State<_BluetoothPickerDialog> {
  final Map<String, BluetoothDeviceInfo> _found = {};
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _found.clear();
    });

    try {
      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      if (mounted) {
        setState(() {
          for (final d in bonded) {
            final name = (d.name?.isNotEmpty == true) ? d.name! : d.address;
            _found[d.address] = BluetoothDeviceInfo(
              id: d.address,
              name: name,
              rssi: -60,
            );
          }
        });
      }

      await for (final result
          in FlutterBluetoothSerial.instance.startDiscovery()) {
        if (!mounted) break;
        final d = result.device;
        final name = (d.name?.isNotEmpty == true) ? d.name! : d.address;
        setState(() {
          _found[d.address] = BluetoothDeviceInfo(
            id: d.address,
            name: name,
            rssi: result.rssi,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _select(BluetoothDeviceInfo info) {
    FlutterBluetoothSerial.instance.cancelDiscovery();
    Navigator.of(context).pop(info);
  }

  Future<void> _confirmRemove(BluetoothDeviceInfo d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Remove device?',
          style: TextStyle(color: Color(0xFFF0EDE8), fontSize: 15),
        ),
        content: Text(
          'Remove "${d.name}" from the list?\n\nThis only hides it here — to fully unpair, go to your phone\'s Bluetooth settings.',
          style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _found.remove(d.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = _found.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth_searching,
                    color: Color(0xFFE8C8A0), size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Select Bluetooth Printer',
                    style: TextStyle(
                      color: Color(0xFFF0EDE8),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_scanning)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFE8C8A0),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _scanning
                  ? 'Scanning… paired Classic BT printers shown immediately'
                  : 'Scan complete — paired Classic BT printers listed above',
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
            const SizedBox(height: 14),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Error: $_error',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: devices.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          _scanning
                              ? 'Looking for devices…'
                              : 'No devices found.',
                          style: const TextStyle(color: Color(0xFF888888)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Color(0xFF333333), height: 1),
                      itemBuilder: (_, i) {
                        final d = devices[i];
                        final isXprinter =
                            d.name.toLowerCase().contains('xprinter') ||
                                d.name.toLowerCase().contains('xp-n') ||
                                d.name.toLowerCase().contains('btp') ||
                                d.name.toLowerCase().contains('pos') ||
                                d.name.toLowerCase().contains('printer');
                        return ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: Icon(
                            Icons.print,
                            color: isXprinter
                                ? const Color(0xFFE8C8A0)
                                : const Color(0xFF666666),
                            size: 20,
                          ),
                          title: Text(
                            d.name,
                            style: TextStyle(
                              color: isXprinter
                                  ? const Color(0xFFE8C8A0)
                                  : const Color(0xFFF0EDE8),
                              fontSize: 14,
                              fontWeight: isXprinter
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            '${d.id}  •  ${d.rssi > -70 ? '${d.rssi} dBm' : 'Paired'}',
                            style: const TextStyle(
                                color: Color(0xFF888888), fontSize: 11),
                          ),
                          trailing: isXprinter
                              ? const Text('Recommended',
                                  style: TextStyle(
                                      color: Color(0xFFE8C8A0), fontSize: 10))
                              : const Icon(Icons.bluetooth,
                                  color: Color(0xFF5599FF), size: 14),
                          onTap: () => _select(d),
                          onLongPress: () => _confirmRemove(d),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _scanning ? null : _startScan,
                  icon: const Icon(Icons.refresh,
                      size: 16, color: Color(0xFFE8C8A0)),
                  label: const Text('Rescan',
                      style: TextStyle(color: Color(0xFFE8C8A0))),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel',
                      style: TextStyle(color: Color(0xFF888888))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
