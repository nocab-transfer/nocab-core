library nocab_core;

import 'dart:async';
import 'dart:io';

import 'package:nocab_logger/nocab_logger.dart';
import 'package:nocab_core/src/models/device_info.dart';

class NoCabCore {
  NoCabCore._internal();
  static final NoCabCore _singleton = NoCabCore._internal();
  factory NoCabCore() {
    if (!_singleton._initialized) throw Exception('NoCabCore not initialized. Call NoCabCore.init() first.');
    return _singleton;
  }

  bool _initialized = false;
  static const String version = '1.0.0';

  static late final Logger logger;

  late DeviceInfo _currentDeviceInfo;

  /// Returns the current device info used by the app.
  DeviceInfo get currentDeviceInfo => _currentDeviceInfo;

  final _deviceInfoStreamController = StreamController<DeviceInfo>.broadcast();

  /// The stream that provides [DeviceInfo] updates.
  ///
  /// This stream is used to notify the UI when [DeviceInfo] has changed.
  ///
  /// See also:
  ///
  ///  * [currentDeviceInfo], which returns the most up-to-date information about the device.
  ///  * [updateDeviceInfo], which updates the device info.
  Stream<DeviceInfo> get onDeviceInfoChanged => _deviceInfoStreamController.stream;

  /// Initializes the NoCabCore.
  ///
  /// [deviceName] is the name of the device.
  ///
  /// [deviceIp] is the IP address of the device. Should be a valid IPv4 address. (cant be `localhost`, `0.0.0.0` or `127.0.0.1`)
  ///
  /// [requestPort] is the port on which requests are accepted.
  ///
  /// [logFolderPath] is the path to the folder where logs are stored.
  static void init({
    required String deviceName,
    required String deviceIp,
    required int requestPort,
    required String logFolderPath,
  }) {
    _singleton._initialized = true;
    logger = Logger('NoCabCore', storeInFile: true, logPath: logFolderPath);

    _singleton._currentDeviceInfo = DeviceInfo(
      name: deviceName,
      ip: deviceIp,
      requestPort: requestPort,
      opsystem: Platform.operatingSystemVersion,
    );

    logger.info('Initialized as $deviceName with ip $deviceIp and requestPort $requestPort');
  }

  /// Updates the device info.
  ///
  /// If the parameter is null, the value will not be updated.
  void updateDeviceInfo({String? name, String? ip, int? requestPort}) {
    _currentDeviceInfo = DeviceInfo(
      name: name ?? _currentDeviceInfo.name,
      ip: ip ?? _currentDeviceInfo.ip,
      requestPort: requestPort ?? _currentDeviceInfo.requestPort,
      opsystem: Platform.operatingSystemVersion,
    );

    _deviceInfoStreamController.add(_currentDeviceInfo);

    logger.info('Updated as $name with ip $ip and requestPort $requestPort');
  }

  /// Disposes the NoCabCore.
  ///
  /// Logger itself contains a ReceivePort which is used to receive logs from other isolates.
  /// In order to close the ReceivePort, this method should be called.
  static void dispose() {
    logger.close();
  }
}
