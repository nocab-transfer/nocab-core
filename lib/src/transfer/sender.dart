import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/transfer_event_model.dart';
import 'package:nocab_logger/nocab_logger.dart';

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

    Logger().info('_sendWorker started', 'Sender');

    RawServerSocket? server;
    try {
      server = await RawServerSocket.bind(InternetAddress.anyIPv4, transferPort);
      Logger().info('_sendWorker server started on port $transferPort', 'Sender');
    } catch (e, stackTrace) {
      Logger().error('_sendWorker server binding error', 'Sender', error: e, stackTrace: stackTrace);

      sendPort.send(TransferEvent(
        TransferEventType.error,
        error: CoreError("Can't bind to port $transferPort", className: 'Sender', methodName: '_sendWorker', stackTrace: stackTrace, error: e),
      ));
    }

    Future<void> send(FileInfo fileInfo, RawSocket socket) async {
      Logger().info('_sendWorker send started for ${fileInfo.path}', 'Sender');
      try {
        final Uint8List buffer = Uint8List(1024 * 8);
        RandomAccessFile file = await File(fileInfo.path!).open();
        int bytesWritten = 0;
        int totalWrite = 0;

        int readBytesCountFromFile;
        while ((readBytesCountFromFile = file.readIntoSync(buffer)) > 0) {
          bytesWritten = socket.write(buffer, 0, readBytesCountFromFile);
          totalWrite += bytesWritten;
          file.setPositionSync(totalWrite);
          if (bytesWritten == 0) continue;
          sendPort.send(TransferEvent(
            TransferEventType.event,
            currentFile: fileInfo,
            writtenBytes: totalWrite,
          ));
        }
        file.closeSync();
        Logger().info('_sendWorker file ${fileInfo.path} sent, totalWrite: $totalWrite', 'Sender');
        sendPort.send(TransferEvent(TransferEventType.fileEnd, currentFile: fileInfo));
        queue.remove(fileInfo);
      } catch (e, stackTrace) {
        socket.close();
        sendPort.send(TransferEvent(
          TransferEventType.error,
          error: CoreError("Can't send file ${fileInfo.path}", className: 'Sender', methodName: '_sendWorker', stackTrace: stackTrace, error: e),
        ));
      }
    }

    server!.listen((socket) {
      Logger().info('_sendWorker server socket connected', 'Sender');

      if (socket.remoteAddress.address != deviceInfo.ip) {
        Logger().info('Ip address does not match: ${socket.remoteAddress.address} != ${deviceInfo.ip}', 'Sender');
        socket.close();
        sendPort.send(TransferEvent(
          TransferEventType.error,
          error: CoreError(
            'Ip address does not match: ${socket.remoteAddress.address} != ${deviceInfo.ip}',
            className: 'Sender',
            methodName: '_sendWorker',
            stackTrace: StackTrace.current,
          ),
        ));
        return;
      }

      socket.listen((event) {
        Logger().info('_sendWorker socket event: $event', 'Sender');

        switch (event) {
          case RawSocketEvent.read:
            try {
              String data = utf8.decode(socket.read()!);
              FileInfo file = queue.firstWhere((element) => element.name == data);
              Logger().info('_sendWorker socket requested file: ${file.name}', 'Sender');
              sendPort.send(TransferEvent(TransferEventType.start, currentFile: file));
              send(file, socket);
            } catch (e, stackTrace) {
              Logger().error('_sendWorker socket error', 'Sender', error: e, stackTrace: stackTrace);
              socket.close();
              sendPort.send(TransferEvent(
                TransferEventType.error,
                error: CoreError("Error while reading socket", className: 'Sender', methodName: '_sendWorker', stackTrace: stackTrace, error: e),
              ));
            }
            break;
          case RawSocketEvent.readClosed:
            socket.close();
            break;
          case RawSocketEvent.closed:
            if (queue.isEmpty) {
              Logger().info('_sendWorker queue is empty sending end event', 'Sender');
              server?.close();
              sendPort.send(TransferEvent(TransferEventType.end));
            }
            break;
          default:
            break;
        }
      });
    });
  }
}
