import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/transfer_event_model.dart';
import 'package:path/path.dart';
import 'package:nocab_logger/nocab_logger.dart';

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
    dataHandler = DataHandler(_receiveWorker, [files, deviceInfo, transferPort, temp.path], transferController);
    pipeReport(dataHandler.onEvent); // Pipe dataHandler events to this transfer
  }

  @override
  Future<void> cleanUp() async {
    if (temp.existsSync()) {
      try {
        await temp.delete(recursive: true);
      } catch (e, stackTrace) {
        Logger().error('Receiver cleanUp error', 'Receiver', error: e, stackTrace: stackTrace);
      }
    }
  }

  static Future<void> _receiveWorker(List args) async {
    final SendPort sendPort = args[0] as SendPort; // dataHandler sendPort

    final List<FileInfo> queue = args[1] as List<FileInfo>;
    final DeviceInfo deviceInfo = args[2] as DeviceInfo;
    final int transferPort = args[3] as int;
    Directory tempFolder = Directory(args[4] as String);

    Logger().info('_receiveWorker started', 'Receiver');

    Future<void> receiveFile() async {
      RawSocket? socket;
      Logger().info('_receiveWorker trying to connect ${deviceInfo.ip}:$transferPort', 'Receiver');
      // Try to connect to the socket. Sometimes it fails to connect, so we try again. After 30 seconds, dataHandler will cancel the transfer.
      while (socket == null) {
        try {
          socket = await RawSocket.connect(deviceInfo.ip, transferPort);
          Logger().info('_receiveWorker socket connected', 'Receiver');
        } catch (e, stackTrace) {
          await Future.delayed(const Duration(milliseconds: 100));
          Logger().info('_receiveWorker socket cannot connect waiting 100ms', 'Receiver', error: e, stackTrace: stackTrace);
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
        Logger().info('_receiveWorker tempFile created', 'Receiver');
      } catch (e, stackTrace) {
        Logger().error('_receiveWorker tempFile cannot create', 'Receiver', error: e, stackTrace: stackTrace);

        sendPort.send(
          TransferEvent(
            TransferEventType.error,
            error: CoreError("tempFile cannot create", className: "Receiver", methodName: "_receiveWorker", stackTrace: stackTrace, error: e),
          ),
        );
      }

      // Open the file to write.
      // (For now it probably causes an error when the transfer is canceled. Sink is stays open even after the isolate is killed. So the clean up function throws an error.)
      IOSink currentSink = tempFile.openWrite();

      Logger().info('_receiveWorker requesting file ${queue.first.name}', 'Receiver');
      try {
        // Send the file name to the socket. So the sender knows which file to send.
        socket.write(utf8.encode(queue.first.name));
      } catch (e, stackTrace) {
        Logger().error('_receiveWorker socket cannot write on ${currentFile.name}', 'Receiver', error: e, stackTrace: stackTrace);

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
              Logger().error('_receiveWorker socket cannot read on ${currentFile.name}', 'Receiver', error: e, stackTrace: stackTrace);

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
              Logger().info('_receiveWorker file received ${currentFile.name}', 'Receiver');
              sendPort.send(TransferEvent(TransferEventType.fileEnd, currentFile: queue.first));

              queue.removeAt(0); // remove the first element from the queue (the file that was just received)
              await currentSink.close(); // close the sink to prevent memory leaks

              try {
                await FileOperations.tmpToFile(tempFile, currentFile.path!);
                Logger().info('_receiveWorker file moved to ${currentFile.path}', 'Receiver');
              } catch (e, stackTrace) {
                Logger().error('_receiveWorker file cannot move to ${currentFile.path} from ${tempFile.path}', 'Receiver',
                    error: e, stackTrace: stackTrace);

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
                Logger().info('_receiveWorker queue is empty sending end event', 'Receiver');
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
