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

    Logger().info('_receiveWorker started', 'Receiver');

    Future<void> receiveFile() async {
      RawSocket? socket;
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
            error: CoreError(e.toString(), className: "Receiver", methodName: "_receiveWorker", stackTrace: stackTrace),
          ),
        );
      }

      IOSink currentSink = tempFile.openWrite(mode: FileMode.append);

      Logger().info('_receiveWorker requesting file ${queue.first.name}', 'Receiver');
      socket.write(utf8.encode(queue.first.name));

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
                  error: CoreError(e.toString(), className: "Receiver", methodName: "_receiveWorker", stackTrace: stackTrace),
                ),
              );
            }

            if (totalRead == queue.first.byteSize) {
              Logger().info('_receiveWorker file received ${currentFile.name}', 'Receiver');
              sendPort.send(TransferEvent(TransferEventType.fileEnd, currentFile: queue.first));

              queue.removeAt(0);
              await currentSink.close();

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
                      e.toString(),
                      className: "Receiver",
                      methodName: "_receiveWorker",
                      stackTrace: stackTrace,
                    ),
                  ),
                );
                return;
              }

              socket?.close();

              if (queue.isEmpty) {
                Logger().info('_receiveWorker queue is empty sending end event', 'Receiver');
                sendPort.send(TransferEvent(TransferEventType.end));
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
