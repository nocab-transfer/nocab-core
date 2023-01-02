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
  late String transferUuid;

  late Socket socket; // for response
  late bool _responded = false;
  Transfer? linkedTransfer;

  bool get responded => _responded;

  final responseController = StreamController<ShareResponse>.broadcast();
  Future<ShareResponse> get onResponse => responseController.stream.first;

  ShareRequest({required this.files, required this.deviceInfo, required this.transferPort, required this.transferUuid}) {
    responseController.stream.listen((event) {
      _responded = true;
      responseController.close();
    });
  }

  ShareRequest.fromJson(Map<String, dynamic> json) {
    files = List<FileInfo>.from(json['files'].map((x) => FileInfo.fromJson(x)));
    deviceInfo = DeviceInfo.fromJson(json['deviceInfo']);
    transferPort = json['transferPort'];
    transferUuid = json['transferUuid'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> map = <String, dynamic>{};
    map['files'] = List<dynamic>.from(files.map((x) => x.toJson()));
    map['deviceInfo'] = deviceInfo.toJson();
    map['transferPort'] = transferPort;
    map['transferUuid'] = transferUuid;
    return map;
  }
}
