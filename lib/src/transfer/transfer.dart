import 'dart:async';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/transfer_controller.dart';

abstract class Transfer {
  final DeviceInfo deviceInfo;
  final List<FileInfo> files;
  final int transferPort;
  final int controlPort;
  final String uuid;
  bool iscancelled = false;

  late final DataHandler _dataHandler;
  late final TransferController transferController;

  final StreamController<Report> _reportStreamController = StreamController<Report>.broadcast();

  Stream<Report> get onEvent => _reportStreamController.stream;
  Future<void> get done => _reportStreamController.done;
  bool get ongoing => !_reportStreamController.isClosed;

  StreamSubscription? _dataHandlerSubscription;

  void setDataHandler(DataHandler dataHandler) {
    _dataHandler = dataHandler;

    _dataHandlerSubscription = _dataHandler.onEvent.listen((event) {
      if (_reportStreamController.isClosed) return;
      _reportStreamController.add(event);
    });
  }

  Transfer({required this.deviceInfo, required this.files, required this.transferPort, required this.controlPort, required this.uuid}) {
    // initialize transferController
    transferController = TransferController(
      transfer: this,
      onCancelReceived: () => cancel(notifyOther: false),
      onErrorReceived: (error) => cancelWithError(error, notifyOther: false),
    );

    // If transfer is cancelled, error or finished, close the report stream and clean up
    onEvent.listen((event) async {
      switch (event.runtimeType) {
        case EndReport:
        case ErrorReport:
        case CancelReport:
          iscancelled = event is CancelReport;
          await cleanUp(cleanUpDownloaded: iscancelled);
          await _reportStreamController.close();
          NoCabCore.logger.info("Transfer is finished with event: ${event.runtimeType}", className: runtimeType.toString());
          break;
        default:
          break;
      }
    });
  }

  Future<void> start();

  Future<void> cancel({bool notifyOther = true}) async {
    // dont cancel the _dataHandlerSubscription because it must be able to send the cancel report
    _dataHandler.cancel();
    if (notifyOther) await transferController.sendCancel();
    transferController.dispose();
  }

  Future<void> cancelWithError(CoreError error, {bool notifyOther = true}) async {
    _dataHandlerSubscription?.cancel(); // Cancel the dataHandler subscription to prevent further events
    _reportStreamController.add(ErrorReport(error: error));
    await _reportStreamController.close();

    _dataHandler.cancel();
    if (notifyOther) await transferController.sendError(error);
    transferController.dispose();
  }

  Future<void> cleanUp({bool cleanUpDownloaded = false}) => Future.value();
}
