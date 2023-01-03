import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/src/device_manager.dart';
import 'package:nocab_core/src/models/device_info.dart';
import 'package:nocab_core/src/models/file_info.dart';
import 'package:nocab_core/src/models/share_request.dart';
import 'package:nocab_core/src/models/share_response.dart';
import 'package:nocab_core/src/transfer/sender.dart';
import 'package:uuid/uuid.dart';

class RequestMaker {
  /// Creates a [ShareRequest] object.
  ///
  /// [files] can be a list of [File] or [FileInfo].
  ///
  /// [transferPort] is the port that the receiver will use to connect to the sender.
  /// Can be any port that is not being used.
  static ShareRequest create({required List<dynamic> files, required int transferPort}) {
    List<FileInfo> fileInfos = [];

    try {
      if (files.runtimeType == List<File>) {
        fileInfos = files.map((e) => FileInfo.fromFile(e)).toList();
      } else if (files.runtimeType == List<FileInfo>) {
        fileInfos = files as List<FileInfo>;
      }
    } catch (e) {
      throw ArgumentError("Invalid file list. Must be a list of File or FileInfo");
    }

    return ShareRequest(
      deviceInfo: DeviceManager().currentDeviceInfo,
      files: fileInfos,
      transferPort: transferPort,
      transferUuid: Uuid().v4(),
    );
  }

  static Future<void> requestTo(DeviceInfo receiverDeviceInfo, {required ShareRequest request, Function(String)? onError}) async {
    Socket socket;

    try {
      socket = await Socket.connect(receiverDeviceInfo.ip, receiverDeviceInfo.requestPort);
      socket.write(base64.encode(utf8.encode(json.encode(request.toJson()))));
    } on SocketException catch (e) {
      onError?.call(e.message);
      return;
    } catch (e) {
      onError?.call(e.toString());
      return;
    }

    ShareResponse shareResponse;
    try {
      shareResponse = ShareResponse.fromJson(
        json.decode(
          utf8.decode(base64.decode(utf8.decode(await socket.first.timeout(Duration(minutes: 2), onTimeout: () {
            throw StateError("Connection lost, cannot read response");
          })))),
        ),
      );
    } on TimeoutException {
      onError?.call("Timeout, cannot read response");
      return;
    } on StateError {
      onError?.call("Connection lost, cannot read response");
      return;
    } catch (e) {
      onError?.call(e.toString());
      return;
    }

    if (!shareResponse.response) {
      request.responseController.add(shareResponse);
      return;
    }

    request.linkedTransfer = Sender(
      deviceInfo: receiverDeviceInfo,
      files: request.files,
      transferPort: request.transferPort,
      uuid: request.transferUuid,
    )..start();

    request.responseController.add(shareResponse);
  }
}
