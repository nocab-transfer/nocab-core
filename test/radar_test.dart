import 'package:nocab_core/nocab_core.dart';
import 'package:test/test.dart';

void main() {
  setUp(() => NoCabCore.init(
        deviceName: "Radar",
        deviceIp: "127.0.0.1",
        requestPort: 5001,
        logFolderPath: 'test',
      ));

  test('Radar Test', () async {
    await Radar().start(onError: (p0) => throw p0);

    List<DeviceInfo> devices = [];
    devices = await Radar.searchForDevices(baseIp: "127.0.0", skipCurrentDevice: false).last;
    expect(devices.length, greaterThan(0));
    expect(devices.map((e) => e.name), contains("Radar"));

    NoCabCore().updateDeviceInfo(name: "Radar 2", ip: "127.0.0.1", requestPort: 5001);

    devices = await Radar.searchForDevices(baseIp: "127.0.0", skipCurrentDevice: false).last;

    expect(devices.length, greaterThan(0));
    expect(devices.map((e) => e.name), contains("Radar 2"));

    Radar().stop();
  });

  tearDown(() async => await NoCabCore.logger.close(deleteFile: true));
}
