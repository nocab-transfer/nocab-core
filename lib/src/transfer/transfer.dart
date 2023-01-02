import 'dart:async';

import 'package:nocab_core/src/models/device_info.dart';
import 'package:nocab_core/src/models/file_info.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/report_models/base_report.dart';

abstract class Transfer {
  DeviceInfo deviceInfo;
  List<FileInfo> files;
  int transferPort;
  String uuid;
  bool ongoing = true;

  late DataHandler dataHandler;
  Stream<Report> get onEvent => dataHandler.onEvent;

  Transfer({required this.deviceInfo, required this.files, required this.transferPort, required this.uuid});

  Future<void> start() async {
    throw UnimplementedError("Transfer start() is not implemented");
  }
}
