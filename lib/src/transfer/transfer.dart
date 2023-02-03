import 'dart:async';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/transfer_controller.dart';

abstract class Transfer {
  DeviceInfo deviceInfo;
  List<FileInfo> files;
  int transferPort;
  int controlPort;
  String uuid;
  bool iscancelled = false;

  late DataHandler dataHandler;
  late TransferController transferController;

  final StreamController<Report> _reportStreamController = StreamController<Report>.broadcast();

  Stream<Report> get onEvent => _reportStreamController.stream;
  Future<void> get done => _reportStreamController.done;
  bool get ongoing => !_reportStreamController.isClosed;

  report(Report report) => !_reportStreamController.isClosed ? _reportStreamController.add(report) : null;
  pipeReport(Stream<Report> reportStream) => reportStream.listen(report);

  Transfer({required this.deviceInfo, required this.files, required this.transferPort, required this.controlPort, required this.uuid}) {
    transferController = TransferController(transfer: this); // initialize transferController

    // If transfer is cancelled, error or finished, close the report stream and clean up
    onEvent.listen((event) async {
      switch (event.runtimeType) {
        case EndReport:
        case ErrorReport:
        case CancelReport:
          NoCabCore.logger.info("Transfer is finished with event: ${event.runtimeType}", className: runtimeType.toString());
          await cleanUp();
          iscancelled = event is CancelReport;
          _reportStreamController.close();
          break;
        default:
          break;
      }
    });
  }

  Future<void> start() async => throw UnimplementedError("Transfer start() is not implemented");

  Future<void> cancel({bool isError = false, CoreError? error}) async => transferController.cancel(isError: isError, error: error);

  Future<void> cleanUp() async => throw UnimplementedError("Transfer cleanUp() is not implemented");
}
