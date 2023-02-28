import 'dart:async';
import 'dart:isolate';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/transfer_controller.dart';
import 'package:nocab_core/src/transfer/transfer_event_model.dart';
import 'package:nocab_logger/nocab_logger.dart';

class DataHandler {
  final _eventController = StreamController<Report>.broadcast();
  Stream<Report> get onEvent => _eventController.stream;

  SendPort? mainToDataHandlerControlPort;

  final void Function(List args) mainTransferFunc; // This is the transfer that we will track data from
  final List transferArgs; // This is the arguments that we will pass to the isolate
  final TransferController transferController; // For reporting errors on other side

  DataHandler(this.mainTransferFunc, this.transferArgs, this.transferController) {
    ReceivePort dataHandlerPort = ReceivePort();

    Isolate.spawn(_handleData, [mainTransferFunc, dataHandlerPort.sendPort, transferArgs, NoCabCore.logger.sendPort]);

    // Listen for data from the isolate
    dataHandlerPort.listen((data) {
      if (data is SendPort) {
        mainToDataHandlerControlPort = data;
        return;
      }

      // If the stream is closed, return and log
      // Can happen if the isolate is not closed properly
      if (_eventController.isClosed) {
        NoCabCore.logger.warning("Stream is closed. This should not happen.", className: "DataHandler(mainIsolate:$mainTransferFunc)");
        return;
      }

      if (data is Report) _eventController.add(data); // Add the data to the stream

      // If transfer is complete or failed, close the stream
      switch (data.runtimeType) {
        case EndReport:
        case CancelReport:
        case ErrorReport:
          _eventController.close();
          dataHandlerPort.close();
          if (data is ErrorReport) transferController.sendError(data.error);
          break;
        default:
          break;
      }
    });
  }

  void cancel() {
    if (mainToDataHandlerControlPort == null) {
      NoCabCore.logger
          .warning("mainToDataHandlerControlPort is null. This should not happen.", className: "DataHandler(mainIsolate:$mainTransferFunc)");
      return;
    }

    mainToDataHandlerControlPort!.send("cancel");
  }

  static Future<void> _handleData(List<dynamic> args) async {
    Function(List args) mainTransferFunc = args[0]; // This is the transfer that we will track data from
    SendPort sendPort = args[1]; // This is the port that the isolate will send data to
    List transferArgs = args[2]; // This is the arguments that we will pass to the isolate
    Logger logger = Logger.chained(args[3] as SendPort); // This is the logger that we will use

    ReceivePort handledReceiverPort = ReceivePort(); // This is the port that we will track data from

    ReceivePort mainControlPort = ReceivePort(); // This is the port that we will listen for control messages from
    sendPort.send(mainControlPort.sendPort); // Send the control port to the main isolate

    var workerIsolate = await Isolate.spawn(mainTransferFunc, [
      handledReceiverPort.sendPort, // arg 0 should be reserved for the port
      ...transferArgs,
    ]);
    String isolateName = workerIsolate.debugName ?? "Unknown"; // We will use this to identify the isolate in the logs

    int writtenBytes = 0;
    Duration sendDuration = const Duration(milliseconds: 100);

    Stopwatch stopwatch = Stopwatch()..start();

    FileInfo? currentFile;
    List<FileInfo> filesTransferred = [];

    int timeoutIndicatorMilliseconds = 0;

    Timer timer = Timer.periodic(sendDuration, (timer) {
      // If the stopwatch is not running or the elapsed time is 0, return to prevent division by 0 and false reports
      if (!stopwatch.isRunning || stopwatch.elapsedMilliseconds == 0) return;
      // timeout if the speed is 0 for 30 seconds
      if (writtenBytes / stopwatch.elapsedMilliseconds * 1000 == 0) {
        timeoutIndicatorMilliseconds += sendDuration.inMilliseconds;
        if (timeoutIndicatorMilliseconds >= 30000) {
          logger.info("Transfer timed out", className: "DataHandler($isolateName)");
          sendPort.send(ErrorReport(
            error: CoreError(
              'Transfer timed out',
              className: 'DataHandler',
              methodName: '_handleData',
              stackTrace: StackTrace.current,
            ),
          ));
          timer.cancel();
          workerIsolate.kill(priority: Isolate.immediate);
          Isolate.current.kill(priority: Isolate.immediate);
          return;
        }
      } else {
        timeoutIndicatorMilliseconds = 0;
      }

      // prevent division by 0 and false reports
      if (currentFile == null || currentFile!.byteSize == 0) return;

      // calculate speed and progress and send it to the main isolate
      sendPort.send(
        ProgressReport(
          filesTransferred: filesTransferred,
          currentFile: currentFile!,
          speed: writtenBytes / stopwatch.elapsedMilliseconds * 1000,
          progress: writtenBytes / currentFile!.byteSize,
        ),
      );

      writtenBytes = 0; // reset written bytes
    });

    mainControlPort.listen((message) async {
      if (message == "cancel") {
        logger.info("Received cancel message", className: "DataHandler($isolateName)");
        workerIsolate.kill(priority: Isolate.immediate);
        handledReceiverPort.close();
        sendPort.send(CancelReport(cancelTime: DateTime.now()));
        logger.info("Sent cancel report to main isolate", className: "DataHandler($isolateName)");
        mainControlPort.close();
        timer.cancel();
        Isolate.exit();
      }
    });

    // Send the start event to the main isolate
    sendPort.send(StartReport(startTime: DateTime.now()));

    // listen for data from sender/receiver isolate
    handledReceiverPort.listen((data) {
      if (data is! TransferEvent) return;
      switch (data.type) {
        case TransferEventType.start:
          logger.info("Received start event resetting stopwatch", className: "DataHandler($isolateName)");
          stopwatch.reset();
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
          logger.info("Received file end event resetting stopwatch", className: "DataHandler($isolateName)");
          stopwatch.stop();
          stopwatch.reset();
          sendPort.send(FileEndReport(fileInfo: data.currentFile!));
          filesTransferred.add(data.currentFile!);
          break;
        case TransferEventType.end:
          logger.info("Received end event resetting stopwatch", className: "DataHandler($isolateName)");
          stopwatch.stop();
          workerIsolate.kill();
          handledReceiverPort.close();
          mainControlPort.close();
          sendPort.send(EndReport(endTime: DateTime.now()));
          Isolate.current.kill();
          break;
        case TransferEventType.error:
          logger.error("Received error event resetting stopwatch", className: "DataHandler($isolateName)");
          stopwatch.stop();
          workerIsolate.kill(priority: Isolate.immediate);
          handledReceiverPort.close();
          mainControlPort.close();
          sendPort.send(ErrorReport(error: data.error!));
          Isolate.current.kill(priority: Isolate.immediate);
          break;
      }
    });
  }
}
