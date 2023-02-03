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
    NoCabCore.logger.info('Started on port $radarPort', className: 'Radar');

    try {
      radarSocket = await ServerSocket.bind(InternetAddress.anyIPv4, radarPort);
      NoCabCore.logger.info('Succesfully binded to port $radarPort', className: 'Radar');

      radarSocket?.listen((socket) async {
        NoCabCore.logger.info('Received connection from ${socket.remoteAddress.address} trying to write current deviceInfo', className: 'Radar');
        try {
          socket.write(base64.encode(utf8.encode(json.encode(DeviceManager().currentDeviceInfo.toJson()))));
        } catch (e) {
          NoCabCore.logger.error('Failed to write current deviceInfo', className: 'Radar', error: e);
        } finally {
          socket.flush().then((value) => socket.close());
        }
      });
    } catch (e, stackTrace) {
      NoCabCore.logger.error('failed to start on port $radarPort', className: 'Radar', error: e, stackTrace: stackTrace);
      onError?.call(CoreError('Failed to start on port $radarPort', className: "Radar", methodName: "start", stackTrace: stackTrace, error: e));
    }
  }

  void stop() {
    NoCabCore.logger.info('Stopped', className: 'Radar');
    _deviceController.close();
    radarSocket?.close();
  }

  static Stream<List<DeviceInfo>> searchForDevices(int radarPort, {String? baseIp, bool skipCurrentDevice = true}) async* {
    NoCabCore.logger.info('Searching for devices on port $radarPort', className: 'Radar');

    List<DeviceInfo> devices = [];
    baseIp ??= DeviceManager().currentDeviceInfo.ip.split('.').sublist(0, 3).join('.');
    Socket? socket;

    for (int i = 1; i < 255; i++) {
      if (skipCurrentDevice && i == int.parse(DeviceManager().currentDeviceInfo.ip.split('.').last)) continue;
      if (baseIp == "127.0.0" && i != 1) continue;
      try {
        socket = await Socket.connect('$baseIp.$i', radarPort, timeout: const Duration(milliseconds: 20));
        Uint8List data = await socket.first.timeout(const Duration(seconds: 5));
        if (data.isNotEmpty) {
          var device = DeviceInfo.fromJson(json.decode(utf8.decode(base64.decode(utf8.decode(data)))));
          if (devices.any((element) => element.ip == device.ip)) continue;
          NoCabCore.logger.info('Found device ${device.name} at ${device.ip}:$radarPort', className: 'Radar');
          devices.add(device);
          yield devices;
        }

        socket.close();
        print("socket closed");
      } on SocketException catch (e, stackTrace) {
        socket?.close();
        print("socket closed on exception $e, $stackTrace");
      }
    }
    yield devices;
  }
}
