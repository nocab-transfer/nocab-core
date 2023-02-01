import 'dart:async';
import 'dart:io';

import 'package:nocab_core/src/models/device_info.dart';
import 'package:nocab_core/src/models/file_info.dart';
import 'package:nocab_core/src/models/share_response.dart';
import 'package:nocab_core/src/transfer/transfer.dart';

class ShareRequest {
  late List<FileInfo> files;
  late DeviceInfo deviceInfo;
  late int transferPort;
  late int controlPort;
  late String transferUuid;
  String? coreVersion;

  late Socket socket; // for response
  Transfer? linkedTransfer;

  final Completer<ShareResponse> _completer = Completer<ShareResponse>();
  Future<ShareResponse> get onResponse => _completer.future;
  bool get isResponded => _completer.isCompleted;

  void registerResponse(ShareResponse response) {
    if (isResponded) return;
    _completer.complete(response);
  }

  ShareRequest(
      {required this.files,
      required this.deviceInfo,
      required this.transferPort,
      required this.controlPort,
      required this.transferUuid,
      required this.coreVersion});

  ShareRequest.fromJson(Map<String, dynamic> json) {
    files = List<FileInfo>.from(json['files'].map((x) => FileInfo.fromJson(x)));
    deviceInfo = DeviceInfo.fromJson(json['deviceInfo']);
    transferPort = json['transferPort'];
    controlPort = json['controlPort'];
    transferUuid = json['transferUuid'];
    coreVersion = json['coreVersion'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> map = <String, dynamic>{};
    map['files'] = List<dynamic>.from(files.map((x) => x.toJson()));
    map['deviceInfo'] = deviceInfo.toJson();
    map['transferPort'] = transferPort;
    map['controlPort'] = controlPort;
    map['transferUuid'] = transferUuid;
    map['coreVersion'] = coreVersion;
    return map;
  }
}
