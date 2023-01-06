import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/transfer_event_model.dart';

class Sender extends Transfer {
  Sender({required super.deviceInfo, required super.files, required super.transferPort, required super.uuid});

  @override
  Future<void> start() async {
    dataHandler = DataHandler(_sendWorker, [files, deviceInfo, transferPort]);

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

  static Future<void> _sendWorker(List args) async {
    final SendPort sendPort = args[0] as SendPort; // dataHandler sendPort

    final List<FileInfo> queue = args[1] as List<FileInfo>;
    final DeviceInfo deviceInfo = args[2] as DeviceInfo;
    final int transferPort = args[3] as int;

    RawServerSocket server = await RawServerSocket.bind(InternetAddress.anyIPv4, transferPort);

    Future<void> send(FileInfo fileInfo, RawSocket socket) async {
      try {
        final Uint8List buffer = Uint8List(1024 * 8);
        RandomAccessFile file = await File(fileInfo.path!).open();

        int bytesWritten = 0;
        int totalWrite = 0;

        int readBytesCountFromFile;
        while ((readBytesCountFromFile = file.readIntoSync(buffer)) > 0) {
          bytesWritten = socket.write(buffer.getRange(0, readBytesCountFromFile).toList());
          totalWrite += bytesWritten;
          file.setPositionSync(totalWrite);

          sendPort.send(TransferEvent(
            TransferEventType.event,
            currentFile: fileInfo,
            writtenBytes: totalWrite,
          ));
        }
        sendPort.send(TransferEvent(TransferEventType.fileEnd, currentFile: fileInfo));
        queue.remove(fileInfo);
        if (queue.isEmpty) sendPort.send(TransferEvent(TransferEventType.end));
      } catch (e) {
        socket.close();
        sendPort.send(TransferEvent(TransferEventType.error, message: e.toString()));
      }
    }

    server.listen((socket) {
      if (socket.remoteAddress.address != deviceInfo.ip) {
        socket.close();
        sendPort.send(TransferEvent(TransferEventType.error, message: 'Ip address does not match'));
        return;
      }

      socket.listen((event) {
        switch (event) {
          case RawSocketEvent.read:
            String data = utf8.decode(socket.read()!);
            FileInfo file = queue.firstWhere((element) => element.name == data);
            sendPort.send(TransferEvent(TransferEventType.start, currentFile: file));
            send(file, socket);
            break;
          default:
            break;
        }
      });
    });
  }
}
