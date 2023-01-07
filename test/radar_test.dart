import 'package:nocab_core/nocab_core.dart';
import 'package:test/test.dart';

void main() {
  test('Radar Test', () async {
    DeviceManager().initialize("Radar", "127.0.0.1", 5001);
    await Radar().start(radarPort: 62193, onError: (p0) => throw p0);

    List<DeviceInfo> devices = [];
    devices = await Radar.searchForDevices(62193, baseIp: "127.0.0", skipCurrentDevice: false).last;
    expect(devices.length, greaterThan(0));
    expect(devices.map((e) => e.name), contains("Radar"));

    DeviceManager().updateDeviceInfo(name: "Radar 2", ip: "127.0.0.1", requestPort: 5001);

    devices = await Radar.searchForDevices(62193, baseIp: "127.0.0", skipCurrentDevice: false).last;

    expect(devices.length, greaterThan(0));
    expect(devices.map((e) => e.name), contains("Radar 2"));

    Radar().stop();
  });
}
