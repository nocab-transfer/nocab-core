import 'dart:async';
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

  final _deviceInfoStreamController = StreamController<DeviceInfo>.broadcast();
  Stream<DeviceInfo> get onDeviceInfoChanged => _deviceInfoStreamController.stream;

  void initialize(String name, String ip, int requestPort) {
    _currentDeviceInfo = DeviceInfo(
      name: name,
      ip: ip,
      requestPort: requestPort,
      opsystem: Platform.operatingSystemVersion,
    );
  }

  void updateDeviceInfo({String? name, String? ip, int? requestPort}) {
    _currentDeviceInfo = DeviceInfo(
      name: name ?? _currentDeviceInfo.name,
      ip: ip ?? _currentDeviceInfo.ip,
      requestPort: requestPort ?? _currentDeviceInfo.requestPort,
      opsystem: Platform.operatingSystemVersion,
    );
    _deviceInfoStreamController.add(_currentDeviceInfo);
  }
}
