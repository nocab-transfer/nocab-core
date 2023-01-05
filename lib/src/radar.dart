import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nocab_core/src/device_manager.dart';
import 'package:nocab_core/src/models/device_info.dart';

class Radar {
  static final Radar _singleton = Radar._internal();
  Radar._internal();
  factory Radar() {
    return _singleton;
  }

  final _deviceController = StreamController<DeviceInfo>.broadcast();
  Stream<DeviceInfo> get listen => _deviceController.stream;

  ServerSocket? radarSocket;

  Future<void> start({int radarPort = 62193, Function(String)? onError}) async {
    try {
      radarSocket = await ServerSocket.bind(InternetAddress.anyIPv4, radarPort);

      radarSocket?.listen((socket) {
        socket.write(base64.encode(utf8.encode(json.encode(DeviceManager().currentDeviceInfo.toJson()))));
      });
    } catch (e) {
      onError?.call(e.toString());
    }
  }

  void stop() {
    _deviceController.close();
    radarSocket?.close();
  }

  static Stream<List<DeviceInfo>> searchForDevices(int radarPort, {String? baseIp}) async* {
    List<DeviceInfo> devices = [];
    baseIp ??= DeviceManager().currentDeviceInfo.ip.split('.').sublist(0, 3).join('.');
    Socket? socket;
    for (int i = 1; i < 255; i++) {
      try {
        socket = await Socket.connect('$baseIp.$i', radarPort, timeout: const Duration(milliseconds: 10));
        Uint8List data = await socket.first.timeout(const Duration(seconds: 5));
        if (data.isNotEmpty) {
          var device = DeviceInfo.fromJson(json.decode(utf8.decode(base64.decode(utf8.decode(data)))));
          if (device.ip == DeviceManager().currentDeviceInfo.ip && device.requestPort == DeviceManager().currentDeviceInfo.requestPort) continue;
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
