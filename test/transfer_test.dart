import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('Transfer Test', () async {
    var receiverDeviceInfo = DeviceInfo(name: "Receiver", ip: "127.0.0.1", requestPort: 5001, opsystem: Platform.operatingSystemVersion);
    var senderDeviceInfo = DeviceInfo(name: "Sender", ip: "127.0.0.1", requestPort: 5001, opsystem: Platform.operatingSystemVersion);
    File file = File(p.join("test", "_testFile"));

    List<FileInfo> senderFiles = [
      FileInfo(
        name: p.basename(file.path),
        path: file.path,
        byteSize: file.lengthSync(),
        isEncrypted: false,
      ),
    ];

    String uuid = Uuid().v4();

    var sender = Sender(deviceInfo: receiverDeviceInfo, files: senderFiles, transferPort: 7814, uuid: uuid);
    await sender.start();

    // override path
    List<FileInfo> receiverFiles = senderFiles.map((e) => e..path = "${e.path!}downloaded").toList();

    var receiver = Receiver(
      deviceInfo: senderDeviceInfo,
      files: receiverFiles,
      transferPort: 7814,
      tempFolder: Directory(p.join(Directory.current.path, "test")),
      uuid: uuid,
    );

    await receiver.start();

    await receiver.onEvent.last;

    var f = File(receiverFiles.first.path!);
    expect(f.readAsStringSync(), equals("This is a test file"));
    await f.delete();
  });
}
