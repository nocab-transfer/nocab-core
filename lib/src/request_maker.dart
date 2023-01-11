import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
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
      fileInfos = files.fold(
        <FileInfo>[],
        (previousValue, element) => previousValue..add(element is File ? FileInfo.fromFile(element) : element as FileInfo),
      );
      Logger().info("FileInfo list successfully created", "RequestMaker");
    } catch (e) {
      Logger().error("Invalid file list. Must be a list of File or FileInfo", "RequestMaker");
      throw ArgumentError("Invalid file list. Must be a list of File or FileInfo");
    }

    return ShareRequest(
      deviceInfo: DeviceManager().currentDeviceInfo,
      files: fileInfos,
      transferPort: transferPort,
      transferUuid: Uuid().v4(),
    );
  }

  static Future<void> requestTo(DeviceInfo receiverDeviceInfo, {required ShareRequest request, Function(CoreError)? onError}) async {
    Socket socket;

    try {
      socket = await Socket.connect(receiverDeviceInfo.ip, receiverDeviceInfo.requestPort);
      socket.write(base64.encode(utf8.encode(json.encode(request.toJson()))));
      Logger().info(
          "Request sent to ${request.deviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort}) with ${request.files.length} files",
          "RequestMaker");
    } catch (e, stackTrace) {
      Logger().error("Cannot request to ${request.deviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})", "RequestMaker",
          error: e, stackTrace: stackTrace);
      onError?.call(CoreError(e.toString(), className: "RequestMaker", methodName: "requestTo", stackTrace: stackTrace));
      return;
    }

    ShareResponse shareResponse;
    try {
      shareResponse = ShareResponse.fromJson(
        json.decode(
          utf8.decode(base64.decode(utf8.decode(await socket.first.timeout(Duration(minutes: 2), onTimeout: () {
            socket.close();
            Logger().error("Request timed out after 2 minutes", "RequestMaker");
            throw StateError("Request timed out");
          })))),
        ),
      );
    } catch (e, stackTrace) {
      Logger().error(
        "Cannot parse response from ${request.deviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})",
        "RequestMaker",
        error: e,
        stackTrace: stackTrace,
      );
      onError?.call(CoreError(e.toString(), className: "RequestMaker", methodName: "requestTo", stackTrace: stackTrace));
      return;
    }

    if (!shareResponse.response) {
      request.registerResponse(shareResponse);
      Logger().info("Request rejected by ${request.deviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})", "RequestMaker");
      return;
    }

    Logger().info("Request accepted by ${request.deviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})", "RequestMaker");

    Logger().info("Starting transfer to ${request.deviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})", "RequestMaker");
    request.linkedTransfer = Sender(
      deviceInfo: receiverDeviceInfo,
      files: request.files,
      transferPort: request.transferPort,
      uuid: request.transferUuid,
    )..start();

    request.registerResponse(shareResponse);
  }
}
