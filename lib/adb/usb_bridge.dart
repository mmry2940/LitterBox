import 'dart:async';
import 'package:flutter/services.dart';

class UsbDeviceInfo {
  final int vendorId;
  final int productId;
  final int deviceId;
  final String? serial;
  final String name;
  final bool hasPermission;
  UsbDeviceInfo({
    required this.vendorId,
    required this.productId,
    required this.deviceId,
    required this.name,
    required this.hasPermission,
    this.serial,
  });

  factory UsbDeviceInfo.fromMap(Map<dynamic, dynamic> m) => UsbDeviceInfo(
        vendorId: m['vendorId'] ?? 0,
        productId: m['productId'] ?? 0,
        deviceId: m['deviceId'] ?? 0,
        name: m['name'] ?? '',
        hasPermission: m['hasPermission'] ?? false,
        serial: m['serial'],
      );
}

class UsbBridge {
  static const MethodChannel _ch = MethodChannel('adb_usb');

  static Future<List<UsbDeviceInfo>> listDevices() async {
    try {
      final list = await _ch.invokeMethod<List<dynamic>>('listDevices');
      if (list == null) return [];
      return list.map((e) => UsbDeviceInfo.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> requestPermission(int deviceId) async {
    try {
      final ok = await _ch
          .invokeMethod<bool>('requestPermission', {'deviceId': deviceId});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
