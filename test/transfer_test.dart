import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:nocab_logger/nocab_logger.dart';

void main() {
  test('Transfer Test', () async {
    await Logger.downloadIsarCore();

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
      FileInfo(
        name: "${p.basename(file.path)}1",
        path: file.path,
        byteSize: file.lengthSync(),
        isEncrypted: false,
      ),
      FileInfo(
        name: "${p.basename(file.path)}2",
        path: file.path,
        byteSize: file.lengthSync(),
        isEncrypted: false,
      ),
    ];

    String uuid = Uuid().v4();

    var sender = Sender(deviceInfo: receiverDeviceInfo, files: senderFiles, transferPort: 7814, uuid: uuid);
    await sender.start();

    // override path
    List<FileInfo> receiverFiles = senderFiles.map((e) => e..path = "${e.path!}downloaded${e.name}").toList();

    var receiver = Receiver(
      deviceInfo: senderDeviceInfo,
      files: receiverFiles,
      transferPort: 7814,
      tempFolder: Directory(p.join(Directory.current.path, "test")),
      uuid: uuid,
    );

    await receiver.start();

    await receiver.onEvent.last;

    for (var fileInfo in receiverFiles) {
      File file = File(fileInfo.path!);
      expect(file.existsSync(), equals(true));
      expect(file.lengthSync(), equals(fileInfo.byteSize));
      await file.delete();
    }
  });
}
