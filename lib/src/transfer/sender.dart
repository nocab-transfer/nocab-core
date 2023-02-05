import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/transfer_event_model.dart';
import 'package:nocab_logger/nocab_logger.dart';

class Sender extends Transfer {
  Sender({required super.deviceInfo, required super.files, required super.transferPort, required super.controlPort, required super.uuid});

  @override
  Future<void> start() async {
    setDataHandler(DataHandler(_sendWorker, [files, deviceInfo, transferPort, NoCabCore.logger.sendPort], transferController));
  }

  static Future<void> _sendWorker(List args) async {
    final SendPort sendPort = args[0] as SendPort; // dataHandler sendPort

    final List<FileInfo> queue = args[1] as List<FileInfo>;
    final DeviceInfo deviceInfo = args[2] as DeviceInfo;
    final int transferPort = args[3] as int;
    final SendPort loggerSendPort = args[4] as SendPort;

    loggerSendPort.send(Log(LogLevel.INFO, "_sendWorker started", "overriden", className: 'Sender'));

    RawServerSocket? server;
    try {
      server = await RawServerSocket.bind(InternetAddress.anyIPv4, transferPort);
      loggerSendPort.send(Log(LogLevel.INFO, "_sendWorker server started on port $transferPort", "overriden", className: 'Sender'));
    } catch (e, stackTrace) {
      loggerSendPort
          .send(Log(LogLevel.ERROR, "_sendWorker server binding error", "overriden", className: 'Sender', error: e, stackTrace: stackTrace));

      sendPort.send(TransferEvent(
        TransferEventType.error,
        error: CoreError("Can't bind to port $transferPort", className: 'Sender', methodName: '_sendWorker', stackTrace: stackTrace, error: e),
      ));
      return;
    }

    Future<void> send(FileInfo fileInfo, RawSocket socket) async {
      loggerSendPort.send(Log(LogLevel.INFO, "_sendWorker send started for ${fileInfo.path}", "overriden", className: 'Sender'));
      try {
        final Uint8List buffer = Uint8List(1024 * 8); // Maybe buffer size should be configurable
        RandomAccessFile file = await File(fileInfo.path!).open();
        int bytesWritten = 0;
        int totalWrite = 0;

        int readBytesCountFromFile;

        // Loop until all bytes are written
        while ((readBytesCountFromFile = file.readIntoSync(buffer)) > 0) {
          bytesWritten = socket.write(buffer, 0, readBytesCountFromFile);
          totalWrite += bytesWritten; // Increment total written bytes
          file.setPositionSync(totalWrite); // Set position to the last written byte. Sometimes all bytes are not written at once
          if (bytesWritten == 0) continue; // If no bytes were written don't send event

          sendPort.send(TransferEvent(
            TransferEventType.event,
            currentFile: fileInfo,
            writtenBytes: totalWrite,
          ));
        }
        file.closeSync();
        loggerSendPort.send(Log(LogLevel.INFO, "_sendWorker file ${fileInfo.path} sent, totalWrite: $totalWrite", "overriden", className: 'Sender'));
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

    server.listen((socket) {
      loggerSendPort.send(Log(LogLevel.INFO, "_sendWorker socket connected", "overriden", className: 'Sender'));

      // If the ip address of the device does not match the ip address of the socket send an error and close the socket
      // Sending error will kill the transfer
      if (socket.remoteAddress.address != deviceInfo.ip) {
        loggerSendPort.send(Log(LogLevel.ERROR, "Ip address does not match: ${socket.remoteAddress.address} != ${deviceInfo.ip}", "overriden",
            className: 'Sender', error: Exception("Ip address does not match: ${socket.remoteAddress.address} != ${deviceInfo.ip}")));
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
        loggerSendPort.send(Log(LogLevel.INFO, "_sendWorker socket event: $event", "overriden", className: 'Sender'));

        switch (event) {
          case RawSocketEvent.read:
            try {
              String data = utf8.decode(socket.read()!);
              try {
                FileInfo file = queue.firstWhere((element) => element.name == data); // Find the file in the queue
                loggerSendPort.send(Log(LogLevel.INFO, "_sendWorker socket requested file: ${file.name}", "overriden", className: 'Sender'));
                // Send a start event to the dataHandler. The dataHandler will start the timer.
                sendPort.send(TransferEvent(TransferEventType.start, currentFile: file));
                send(file, socket); // Send the file
              } catch (e) {
                // If the file is not found in the queue send an error and send error event which will kill the transfer
                loggerSendPort
                    .send(Log(LogLevel.ERROR, "_sendWorker socket requested file not found $data", "overriden", className: 'Sender', error: e));
                sendPort.send(TransferEvent(
                  TransferEventType.error,
                  error: CoreError("File not found", className: 'Sender', methodName: '_sendWorker', stackTrace: StackTrace.current, error: e),
                ));
              }
            } catch (e, stackTrace) {
              loggerSendPort
                  .send(Log(LogLevel.ERROR, "_sendWorker socket error", "overriden", className: 'Sender', error: e, stackTrace: stackTrace));
              socket.close();
              sendPort.send(TransferEvent(
                TransferEventType.error,
                error: CoreError("Error while reading socket", className: 'Sender', methodName: '_sendWorker', stackTrace: stackTrace, error: e),
              ));
            }
            break;
          case RawSocketEvent.readClosed:
            // We should wait for the socket to close on the other side. So we can ensure that the file was sent correctly
            socket.close();
            break;
          case RawSocketEvent.closed:
            if (queue.isEmpty) {
              // If the queue is empty send end event and close the server
              loggerSendPort.send(Log(LogLevel.INFO, "_sendWorker queue is empty sending end event", "overriden", className: 'Sender'));
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
