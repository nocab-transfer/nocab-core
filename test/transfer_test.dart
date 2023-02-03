import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('Transfer Test', () {
    setUpAll(() => NoCabCore.init(logFolderPath: 'test'));

    test('Normal', () async {
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

      var sender = Sender(deviceInfo: receiverDeviceInfo, files: senderFiles, transferPort: 7814, controlPort: 7815, uuid: uuid);
      await sender.start();

      // override path
      List<FileInfo> receiverFiles = senderFiles.map((e) => e..path = "${e.path!}downloaded${e.name}").toList();

      var receiver = Receiver(
        deviceInfo: senderDeviceInfo,
        files: receiverFiles,
        transferPort: 7814,
        controlPort: 7815,
        tempFolder: Directory(p.join(Directory.current.path, "test")),
        uuid: uuid,
      );

      await receiver.start();

      await Future.wait([receiver.done, sender.done]);

      for (var fileInfo in receiverFiles) {
        File file = File(fileInfo.path!);
        expect(file.existsSync(), equals(true));
        expect(file.lengthSync(), equals(fileInfo.byteSize));
        await file.delete();
      }
    });

    test('Cancellation', () async {
      var receiverDeviceInfo = DeviceInfo(name: "Receiver", ip: "127.0.0.1", requestPort: 5001, opsystem: Platform.operatingSystemVersion);
      var senderDeviceInfo = DeviceInfo(name: "Sender", ip: "127.0.0.1", requestPort: 5001, opsystem: Platform.operatingSystemVersion);
      File file = File(p.join('test', "_testFile"));
      print(Directory.current.path);
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

      var sender = Sender(deviceInfo: receiverDeviceInfo, files: senderFiles, transferPort: 7814, controlPort: 7815, uuid: uuid);
      await sender.start();

      // override path
      List<FileInfo> receiverFiles = senderFiles.map((e) => e..path = p.join('test', 'cancellation_test', "downloaded${e.name}")).toList();

      var receiver = Receiver(
        deviceInfo: senderDeviceInfo,
        files: receiverFiles,
        transferPort: 7814,
        controlPort: 7815,
        tempFolder: Directory(p.join(Directory.current.path, "test", "cancellation_test")),
        uuid: uuid,
      );

      await receiver.start();

      sender.onEvent.listen((event) {
        if (event is ProgressReport && event.currentFile.name == senderFiles[1].name) {
          sender.cancel();
        }
      });

      await Future.wait([sender.done, receiver.done]);

      expect(receiver.iscancelled, equals(true));

      await NoCabCore.logger.close();

      await Directory(p.join(Directory.current.path, "test", "cancellation_test")).delete(recursive: true);
    });

    //tearDownAll(() async => await NoCabCore.logger.close(deleteFile: true));
  });
}
