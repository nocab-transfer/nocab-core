library transfer;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_core/src/transfer/data_handler.dart';
import 'package:nocab_core/src/transfer/transfer_event_model.dart';
import 'package:path/path.dart';

part 'receiver.dart';
part 'sender.dart';

sealed class Transfer {
  DeviceInfo deviceInfo;
  List<FileInfo> files;
  int transferPort;
  String uuid;
  bool ongoing = true;

  late DataHandler dataHandler;
  Stream<Report> get onEvent => dataHandler.onEvent;

  Transfer({required this.deviceInfo, required this.files, required this.transferPort, required this.uuid});

  Future<void> start();
}
