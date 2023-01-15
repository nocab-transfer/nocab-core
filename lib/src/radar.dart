import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nocab_core/nocab_core.dart';

class Radar {
  static final Radar _singleton = Radar._internal();
  Radar._internal();
  factory Radar() {
    return _singleton;
  }

  final _deviceController = StreamController<DeviceInfo>.broadcast();
  Stream<DeviceInfo> get listen => _deviceController.stream;

  ServerSocket? radarSocket;

  Future<void> start({int radarPort = 62193, Function(CoreError)? onError}) async {
    Logger().info('Started on port $radarPort', 'Radar');

    try {
      radarSocket = await ServerSocket.bind(InternetAddress.anyIPv4, radarPort);
      Logger().info('Succesfully binded to port $radarPort', 'Radar');

      radarSocket?.listen((socket) {
        Logger().info('Received connection from ${socket.remoteAddress.address} writing current deviceInfo', 'Radar');
        socket.write(base64.encode(utf8.encode(json.encode(DeviceManager().currentDeviceInfo.toJson()))));
      });
    } catch (e, stackTrace) {
      Logger().error('failed to start on port $radarPort', 'Radar', error: e, stackTrace: stackTrace);
      onError?.call(CoreError('Failed to start on port $radarPort', className: "Radar", methodName: "start", stackTrace: stackTrace, error: e));
    }
  }

  void stop() {
    Logger().info('Stopped', 'Radar');
    _deviceController.close();
    radarSocket?.close();
  }

  static Stream<List<DeviceInfo>> searchForDevices(int radarPort, {String? baseIp, bool skipCurrentDevice = true}) async* {
    Logger().info('Searching for devices on port $radarPort', 'Radar');

    List<DeviceInfo> devices = [];
    baseIp ??= DeviceManager().currentDeviceInfo.ip.split('.').sublist(0, 3).join('.');
    Socket? socket;
    for (int i = 1; i < 255; i++) {
      try {
        socket = await Socket.connect('$baseIp.$i', radarPort, timeout: const Duration(milliseconds: 10));
        Uint8List data = await socket.first.timeout(const Duration(seconds: 5));
        if (data.isNotEmpty) {
          var device = DeviceInfo.fromJson(json.decode(utf8.decode(base64.decode(utf8.decode(data)))));
          if (skipCurrentDevice &&
              device.ip == DeviceManager().currentDeviceInfo.ip &&
              device.requestPort == DeviceManager().currentDeviceInfo.requestPort) continue;
          devices.add(device);
          yield devices;
        }

        socket.close();
      } on SocketException {
        socket?.close();
      }
    }
    yield devices;
  }
}
