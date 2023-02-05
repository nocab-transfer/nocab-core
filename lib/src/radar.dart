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

  ServerSocket? radarSocket;

  /// Start the radar to be discoverable on the network.
  ///
  /// Use `searchForDevices()` if you want to find other devices
  Future<void> start({int radarPort = 62193, Function(CoreError)? onError}) async {
    NoCabCore.logger.info('Started on port $radarPort', className: 'Radar');

    try {
      radarSocket = await ServerSocket.bind(InternetAddress.anyIPv4, radarPort);
      NoCabCore.logger.info('Succesfully binded to port $radarPort', className: 'Radar');

      radarSocket?.listen((socket) async {
        NoCabCore.logger.info('Received connection from ${socket.remoteAddress.address} trying to write current deviceInfo', className: 'Radar');
        try {
          socket.write(base64.encode(utf8.encode(json.encode(NoCabCore().currentDeviceInfo.toJson()))));
        } catch (e) {
          NoCabCore.logger.error('Failed to write current deviceInfo', className: 'Radar', error: e);
        } finally {
          socket.flush().then((value) => socket.destroy());
        }
      });
    } catch (e, stackTrace) {
      NoCabCore.logger.error('failed to start on port $radarPort', className: 'Radar', error: e, stackTrace: stackTrace);
      onError?.call(CoreError('Failed to start on port $radarPort', className: "Radar", methodName: "start", stackTrace: stackTrace, error: e));
    }
  }

  /// Stop the radar to stop being discoverable on the network.
  void stop() {
    NoCabCore.logger.info('Stopped', className: 'Radar');
    radarSocket?.close();
  }

  /// This function searches for devices on the local network by connecting to each IP address and port on the local network
  /// and sending a request to the radar server. It returns a stream of lists of DeviceInfo objects, each list containing
  /// the devices found so far. It takes an optional radarPort parameter, which defaults to 62193, and a baseIp parameter,
  /// which defaults to the current device's IP address. It also takes an optional skipCurrentDevice parameter, which
  /// defaults to true, which tells the function whether or not to skip the current device's IP address.
  static Stream<List<DeviceInfo>> searchForDevices({int radarPort = 62193, String? baseIp, bool skipCurrentDevice = true}) async* {
    NoCabCore.logger.info('Searching for devices on port $radarPort', className: 'Radar');

    List<DeviceInfo> devices = [];
    baseIp ??= NoCabCore().currentDeviceInfo.ip.split('.').sublist(0, 3).join('.');
    Socket? socket;

    for (int i = 1; i < 255; i++) {
      if (skipCurrentDevice && i == int.parse(NoCabCore().currentDeviceInfo.ip.split('.').last)) continue;
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

        socket.destroy();
      } on SocketException {
        socket?.destroy();
      }
    }
    yield devices;
  }
}
