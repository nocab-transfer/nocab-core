import 'dart:io';

import 'package:nocab_core/nocab_core.dart';

class DeviceManager {
  static final DeviceManager _singleton = DeviceManager._internal();
  DeviceManager._internal();
  factory DeviceManager() {
    return _singleton;
  }

  late DeviceInfo _currentDeviceInfo;
  DeviceInfo get currentDeviceInfo => _currentDeviceInfo;

  void initialize(String name, String ip, int requestPort) {
    _currentDeviceInfo = DeviceInfo(
      name: name,
      ip: ip,
      requestPort: requestPort,
      opsystem: Platform.operatingSystemVersion,
    );
  }

  void updateDeviceInfo(String name, String ip, int requestPort) {
    _currentDeviceInfo = DeviceInfo(
      name: name,
      ip: ip,
      requestPort: requestPort,
      opsystem: Platform.operatingSystemVersion,
    );
  }
}
