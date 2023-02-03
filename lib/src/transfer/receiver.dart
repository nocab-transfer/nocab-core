import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/transfer_event_model.dart';
import 'package:nocab_logger/nocab_logger.dart';
import 'package:path/path.dart';

class Receiver extends Transfer {
  Directory temp;
  Receiver({
    required super.deviceInfo,
    required super.files,
    required super.transferPort,
    required super.controlPort,
    required Directory tempFolder,
    required super.uuid,
  }) : temp = (Directory(tempFolder.path)..createSync(recursive: true)).createTempSync('nocabCoreTemp_');

  @override
  Future<void> start() async {
    dataHandler = DataHandler(_receiveWorker, [files, deviceInfo, transferPort, temp.path, NoCabCore.logger.sendPort], transferController);
    pipeReport(dataHandler.onEvent); // Pipe dataHandler events to this transfer
  }

  @override
  Future<void> cleanUp() async {
    NoCabCore.logger.info('CleanUp started', className: 'Receiver');
    if (temp.existsSync()) {
      int tempRetry = 0;
      int cancelFileRetry = 0;

      while (tempRetry < 5) {
        try {
          if (tempRetry > 0) NoCabCore.logger.info('Trying to delete temp files, (RetryCount:$tempRetry)', className: 'Receiver');
          await Future.delayed(Duration(seconds: 1));
          temp.deleteSync(recursive: true);
          NoCabCore.logger.info('Temp files deleted successfully', className: 'Receiver');
          break;
        } catch (e, stackTrace) {
          NoCabCore.logger.error('Temp files cannot delete', className: 'Receiver', error: e, stackTrace: stackTrace);
          tempRetry++;
        }
      }

      if (iscancelled) {
        while (cancelFileRetry < 5) {
          try {
            if (cancelFileRetry > 0) NoCabCore.logger.info('Trying to delete downloaded files, (RetryCount:$cancelFileRetry)', className: 'Receiver');
            await Future.delayed(Duration(seconds: 1));
            for (final file in files) {
              if (file.path == null || file.path!.isEmpty) return;
              if (File(file.path!).existsSync()) File(file.path!).deleteSync();
            }
            NoCabCore.logger.info('Downloaded files deleted successfully', className: 'Receiver');
            break;
          } catch (e, stackTrace) {
            NoCabCore.logger.error('Downloaded files cannot delete', className: 'Receiver', error: e, stackTrace: stackTrace);
            cancelFileRetry++;
          }
        }
      }

      NoCabCore.logger.info('CleanUp finished', className: 'Receiver');
    }
  }

  static Future<void> _receiveWorker(List args) async {
    final SendPort sendPort = args[0] as SendPort; // dataHandler sendPort

    final List<FileInfo> queue = args[1] as List<FileInfo>;
    final DeviceInfo deviceInfo = args[2] as DeviceInfo;
    final int transferPort = args[3] as int;
    final Directory tempFolder = Directory(args[4] as String);
    final SendPort loggerSendPort = args[5] as SendPort;

    loggerSendPort.send(Log(LogLevel.INFO, 'Receiver _receiveWorker started', "overriden", className: 'Receiver'));

    Future<void> receiveFile() async {
      RawSocket? socket;
      loggerSendPort.send(Log(LogLevel.INFO, '_receiveWorker trying to connect ${deviceInfo.ip}:$transferPort', "overriden", className: 'Receiver'));
      // Try to connect to the socket. Sometimes it fails to connect, so we try again. After 30 seconds, dataHandler will cancel the transfer.
      while (socket == null) {
        try {
          socket = await RawSocket.connect(deviceInfo.ip, transferPort);
          loggerSendPort.send(Log(LogLevel.INFO, '_receiveWorker connected to ${deviceInfo.ip}:$transferPort', "overriden", className: 'Receiver'));
        } catch (e, stackTrace) {
          await Future.delayed(const Duration(milliseconds: 100));
          loggerSendPort.send(Log(LogLevel.INFO, '_receiveWorker socket cannot connect waiting 100ms', "overriden",
              className: 'Receiver', error: e, stackTrace: stackTrace));
        }
      }

      int totalRead = 0;

      // nocabtmp is a temporary file that will be renamed to the original file name when the transfer is complete.
      // we copy the file to a temporary file to avoid having a corrupted file if the transfer is interrupted.
      File tempFile = File(join(tempFolder.path, "${basename(queue.first.path!)}.nocabtmp"));
      FileInfo currentFile = queue.first;

      try {
        if (await tempFile.exists()) await tempFile.delete();
        await tempFile.create(recursive: true);
        loggerSendPort.send(Log(LogLevel.INFO, '_receiveWorker tempFile created', "overriden", className: 'Receiver'));
      } catch (e, stackTrace) {
        loggerSendPort
            .send(Log(LogLevel.ERROR, '_receiveWorker tempFile cannot create', "overriden", className: 'Receiver', error: e, stackTrace: stackTrace));

        sendPort.send(
          TransferEvent(
            TransferEventType.error,
            error: CoreError("tempFile cannot create", className: "Receiver", methodName: "_receiveWorker", stackTrace: stackTrace, error: e),
          ),
        );
      }

      // Open the file to write.
      // (For now it probably causes an error when the transfer is canceled. Sink is stays open even after the isolate is killed. So the clean up function throws an error.)
      // TODO: Find a way to close the sink when the transfer is canceled.
      IOSink currentSink = tempFile.openWrite();

      loggerSendPort.send(Log(LogLevel.INFO, '_receiveWorker requesting file ${queue.first.name}', "overriden", className: 'Receiver'));
      try {
        // Send the file name to the socket. So the sender knows which file to send.
        socket.write(utf8.encode(queue.first.name));
      } catch (e, stackTrace) {
        loggerSendPort.send(Log(LogLevel.ERROR, '_receiveWorker socket cannot write on ${currentFile.name}', "overriden",
            className: 'Receiver', error: e, stackTrace: stackTrace));

        // If the socket cannot write, we send an error event to the dataHandler. The dataHandler will cancel the transfer.
        sendPort.send(
          TransferEvent(
            TransferEventType.error,
            error: CoreError("Socket cannot write on ${currentFile.name}",
                className: "Receiver", methodName: "_receiveWorker", stackTrace: stackTrace, error: e),
          ),
        );
      }

      // Send a start event to the dataHandler. The dataHandler will start the timer.
      sendPort.send(TransferEvent(TransferEventType.start, currentFile: queue.first));

      Uint8List? buffer;
      socket.listen((event) async {
        switch (event) {
          case RawSocketEvent.read:
            try {
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
            } catch (e, stackTrace) {
              loggerSendPort.send(Log(LogLevel.ERROR, '_receiveWorker socket cannot read on ${currentFile.name}', "overriden",
                  className: 'Receiver', error: e, stackTrace: stackTrace));

              sendPort.send(
                TransferEvent(
                  TransferEventType.error,
                  error: CoreError("Socket cannot read on ${currentFile.name}",
                      className: "Receiver", methodName: "_receiveWorker", stackTrace: stackTrace, error: e),
                ),
              );
            }

            // If the total read bytes is equal to the file size that requested from the sender, the file is received.
            if (totalRead == queue.first.byteSize) {
              loggerSendPort.send(Log(LogLevel.INFO, '_receiveWorker file received ${currentFile.name}', "overriden", className: 'Receiver'));
              sendPort.send(TransferEvent(TransferEventType.fileEnd, currentFile: queue.first));

              queue.removeAt(0); // remove the first element from the queue (the file that was just received)
              await currentSink.close(); // close the sink to prevent memory leaks

              try {
                await FileOperations.tmpToFile(tempFile, currentFile.path!);
                loggerSendPort.send(Log(LogLevel.INFO, '_receiveWorker file moved to ${currentFile.path}', "overriden", className: 'Receiver'));
              } catch (e, stackTrace) {
                loggerSendPort.send(Log(LogLevel.ERROR, '_receiveWorker file cannot move to ${currentFile.path} from ${tempFile.path}', "overriden",
                    className: 'Receiver', error: e, stackTrace: stackTrace));

                sendPort.send(
                  TransferEvent(
                    TransferEventType.error,
                    error: CoreError(
                      "File cannot move to ${currentFile.path} from ${tempFile.path}",
                      className: "Receiver",
                      methodName: "_receiveWorker",
                      stackTrace: stackTrace,
                      error: e,
                    ),
                  ),
                );
                return;
              }

              // Closing the socket will trigger the RawSocketEvent.readClosed event on sender side. So the sender will know that the transfer is complete.
              await socket?.close();

              if (queue.isEmpty) {
                // If the queue is empty, we send an end event to the dataHandler. The dataHandler will stop the timer and close the transfer.
                loggerSendPort.send(Log(LogLevel.INFO, '_receiveWorker queue is empty sending end event', "overriden", className: 'Receiver'));
                sendPort.send(TransferEvent(TransferEventType.end));
                return;
              }

              // If the queue is not empty, we call the receiveFile function again to receive the next file.
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
