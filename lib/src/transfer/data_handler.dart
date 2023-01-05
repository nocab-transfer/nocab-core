import 'dart:async';
import 'dart:isolate';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/transfer_event_model.dart';

class DataHandler {
  final _eventController = StreamController<Report>.broadcast();
  Stream<Report> get onEvent => _eventController.stream;

  DataHandler(
    void Function(List args) mainTransferFunc, // This is the transfer that we will track data from
    List transferArgs, // This is the arguments that we will pass to the isolate
  ) {
    ReceivePort dataHandlerPort = ReceivePort();

    // Listen for data from the isolate
    Isolate.spawn(_handleData, [mainTransferFunc, dataHandlerPort.sendPort, transferArgs]);
    dataHandlerPort.listen((data) {
      _eventController.add(data); // Add the data to the stream

      // If transfer is complete or failed, close the stream
      switch (data.runtimeType) {
        case EndReport:
        case ErrorReport:
          _eventController.close();
          break;
        default:
          break;
      }
    });
  }

  static Future<void> _handleData(List<dynamic> args) async {
    Function(List args) mainTransferFunc = args[0]; // This is the transfer that we will track data from
    SendPort sendPort = args[1]; // This is the port that the isolate will send data to
    List transferArgs = args[2]; // This is the arguments that we will pass to the isolate

    ReceivePort handledReceiverPort = ReceivePort(); // This is the port that we will track data from
    var workerIsolate =
        await Isolate.spawn(mainTransferFunc, [handledReceiverPort.sendPort, ...transferArgs]); // arg 0 should be reserved for the port

    int writtenBytes = 0;
    Duration sendDuration = const Duration(milliseconds: 100);

    Stopwatch stopwatch = Stopwatch();

    FileInfo? currentFile;
    List<FileInfo> filesTransferred = [];

    int timeoutIndicatorMilliseconds = 0;

    Timer.periodic(sendDuration, (timer) {
      // If the stopwatch is not running or the elapsed time is 0, return to prevent division by 0 and false reports
      if (!stopwatch.isRunning || stopwatch.elapsedMilliseconds == 0) return;

      // prevent division by 0 and false reports
      if (currentFile == null || currentFile!.byteSize == 0 || writtenBytes == 0) return;

      // timeout if the speed is 0 for 30 seconds
      if (writtenBytes / stopwatch.elapsedMilliseconds * 1000 == 0) {
        timeoutIndicatorMilliseconds += sendDuration.inMilliseconds;
        if (timeoutIndicatorMilliseconds >= 30000) {
          sendPort.send(ErrorReport(message: "Transfer timed out"));
          timer.cancel();
          return;
        }
      } else {
        timeoutIndicatorMilliseconds = 0;
      }

      // calculate speed and progress and send it to the main isolate
      sendPort.send(
        ProgressReport(
          filesTransferred: filesTransferred,
          currentFile: currentFile!,
          speed: writtenBytes / stopwatch.elapsedMilliseconds * 1000,
          progress: writtenBytes / currentFile!.byteSize,
        ),
      );
    });

    // Send the start event to the main isolate
    sendPort.send(StartReport(startTime: DateTime.now()));

    // listen for data from sender/receiver isolate
    handledReceiverPort.listen((data) {
      data as TransferEvent;
      switch (data.type) {
        case TransferEventType.start:
          stopwatch.start();
          writtenBytes = 0;
          currentFile = data.currentFile;
          sendPort.send(ProgressReport(filesTransferred: filesTransferred, currentFile: currentFile!, speed: 0, progress: 0));
          break;
        case TransferEventType.event:
          writtenBytes = data.writtenBytes!;
          currentFile = data.currentFile;
          break;
        case TransferEventType.fileEnd:
          stopwatch.stop();
          stopwatch.reset();
          sendPort.send(FileEndReport(fileInfo: data.currentFile!));
          filesTransferred.add(data.currentFile!);
          break;
        case TransferEventType.end:
          stopwatch.stop();
          sendPort.send(EndReport(endTime: DateTime.now()));
          workerIsolate.kill();
          Isolate.current.kill();
          break;
        case TransferEventType.error:
          stopwatch.stop();
          sendPort.send(ErrorReport(message: data.message!));
          workerIsolate.kill();
          Isolate.current.kill();
          break;
      }
    });
  }
}
