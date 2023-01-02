import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/transfer_event_model.dart';
import 'package:path/path.dart';

class Receiver extends Transfer {
  Directory tempFolder;
  Receiver({required super.deviceInfo, required super.files, required super.transferPort, required this.tempFolder, required super.uuid});

  @override
  Future<void> start() async {
    dataHandler = DataHandler(_receiveWorker, [files, deviceInfo, transferPort, tempFolder.path]);

    // Set ongoing to false when the transfer is done or an error occurs
    onEvent.listen((event) {
      switch (event.runtimeType) {
        case EndReport:
        case ErrorReport:
          ongoing = false;
          break;
        default:
          break;
      }
    });
  }

  static Future<void> _receiveWorker(List args) async {
    final SendPort sendPort = args[0] as SendPort; // dataHandler sendPort

    final List<FileInfo> queue = args[1] as List<FileInfo>;
    final DeviceInfo deviceInfo = args[2] as DeviceInfo;
    final int transferPort = args[3] as int;
    Directory tempFolder = Directory(args[4] as String);

    Future<void> receiveFile() async {
      RawSocket? socket;
      while (socket == null) {
        try {
          socket = await RawSocket.connect(deviceInfo.ip, transferPort);
        } catch (e) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      int totalRead = 0;

      File tempFile = File(join(tempFolder.path, "${basename(queue.first.path!)}.nocabtmp"));
      FileInfo currentFile = queue.first;

      if (await tempFile.exists()) await tempFile.delete();
      await tempFile.create(recursive: true);

      IOSink currentSink = tempFile.openWrite(mode: FileMode.append);

      socket.write(utf8.encode(queue.first.name));

      sendPort.send(TransferEvent(TransferEventType.start, currentFile: queue.first));

      Uint8List? buffer;
      socket.listen((event) async {
        switch (event) {
          case RawSocketEvent.read:
            buffer = socket?.read();

            if (buffer != null) {
              currentSink.add(buffer!);
              totalRead += buffer!.length;

              sendPort.send(TransferEvent(
                TransferEventType.event,
                currentFile: queue.first,
                writtenBytes: totalRead,
              ));
            }

            if (totalRead == queue.first.byteSize) {
              socket?.close();
              sendPort.send(TransferEvent(TransferEventType.fileEnd, currentFile: queue.first));

              queue.removeAt(0);
              await currentSink.close();

              try {
                await FileOperations.tmpToFile(tempFile, currentFile.path!);
              } catch (e) {
                sendPort.send(TransferEvent(TransferEventType.error, message: e.toString()));
                Isolate.current.kill();
                return;
              }

              if (queue.isEmpty) {
                sendPort.send(TransferEvent(TransferEventType.end));
                Isolate.current.kill();
                return;
              }

              receiveFile();
            }
            break;
          default:
            break;
        }
      });
    }

    receiveFile();
  }
}
