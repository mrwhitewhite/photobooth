import 'dart:async';

import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothDeviceInfo {
  final String id;
  final String name;
  final int rssi;

  const BluetoothDeviceInfo({
    required this.id,
    required this.name,
    this.rssi = -60,
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
  final List<BluetoothDeviceInfo> _devices = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
  }

  Future<void> _loadPairedDevices() async {
    setState(() {
      _loading = true;
      _error = null;
      _devices.clear();
    });

    try {
      final bool btEnabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!btEnabled) {
        setState(() =>
            _error = 'Bluetooth is disabled. Please enable it and try again.');
        return;
      }

      final List<BluetoothInfo> paired =
          await PrintBluetoothThermal.pairedBluetooths;

      if (mounted) {
        setState(() {
          _devices.addAll(
            paired.map(
              (d) => BluetoothDeviceInfo(
                id: d.macAdress,
                name: d.name.isNotEmpty ? d.name : d.macAdress,
              ),
            ),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(BluetoothDeviceInfo info) {
    Navigator.of(context).pop(info);
  }

  @override
  Widget build(BuildContext context) {
    final devices = List<BluetoothDeviceInfo>.from(_devices)
      ..sort((a, b) {
        final aScore = _printerScore(a.name);
        final bScore = _printerScore(b.name);
        return bScore.compareTo(aScore);
      });

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
                const Icon(Icons.bluetooth, color: Color(0xFFE8C8A0), size: 22),
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
                if (_loading)
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
            const Text(
              'Showing paired Classic Bluetooth devices.\nPair your XP-N160II in phone Settings → Bluetooth first.',
              style: TextStyle(color: Color(0xFF888888), fontSize: 12),
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
                          _loading
                              ? 'Loading paired devices…'
                              : 'No paired devices found.\nPair the printer in Bluetooth Settings first.',
                          textAlign: TextAlign.center,
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
                        final isXprinter = _printerScore(d.name) > 0;
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
                            '${d.id}  •  Paired (Classic BT)',
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
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _loading ? null : _loadPairedDevices,
                  icon: const Icon(Icons.refresh,
                      size: 16, color: Color(0xFFE8C8A0)),
                  label: const Text('Refresh',
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

  int _printerScore(String name) {
    final n = name.toLowerCase();
    if (n.contains('xprinter') || n.contains('xp-n')) return 3;
    if (n.contains('btp') || n.contains('pos')) return 2;
    if (n.contains('printer') || n.contains('print')) return 1;
    return 0;
  }
}
