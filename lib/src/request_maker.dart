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
  static ShareRequest create({required List<dynamic> files, required int transferPort, required int controlPort}) {
    List<FileInfo> fileInfos = [];

    try {
      fileInfos = files.fold(
        <FileInfo>[],
        (previousValue, element) => previousValue..add(element is File ? FileInfo.fromFile(element) : element as FileInfo),
      );
      NoCabCore.logger.info("FileInfo list successfully created", className: "RequestMaker");
    } catch (e) {
      NoCabCore.logger.error("Invalid file list. Must be a list of File or FileInfo", className: "RequestMaker");
      throw ArgumentError("Invalid file list. Must be a list of File or FileInfo");
    }

    return ShareRequest(
      deviceInfo: NoCabCore().currentDeviceInfo,
      files: fileInfos,
      transferPort: transferPort,
      controlPort: controlPort,
      transferUuid: Uuid().v4(),
      coreVersion: NoCabCore.version,
    );
  }

  /// Sends a [ShareRequest] to the other device.
  ///
  /// [receiverDeviceInfo] is the [DeviceInfo] of the receiver.
  ///
  /// [request] is the [ShareRequest] object.
  static Future<void> requestTo(DeviceInfo receiverDeviceInfo, {required ShareRequest request}) async {
    Socket socket;

    try {
      socket = await Socket.connect(receiverDeviceInfo.ip, receiverDeviceInfo.requestPort);
      socket.write(base64.encode(utf8.encode(json.encode(request.toJson()))));
      NoCabCore.logger.info(
          "Request sent to ${receiverDeviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort}) with ${request.files.length} files",
          className: "RequestMaker");
    } catch (e, stackTrace) {
      NoCabCore.logger.error(
        "Cannot request to ${receiverDeviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})",
        className: "RequestMaker",
        error: e,
        stackTrace: stackTrace,
      );

      throw CoreError(
        "Cannot request to ${receiverDeviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})",
        className: "RequestMaker",
        methodName: "requestTo",
        stackTrace: stackTrace,
        error: e,
      );
    }

    ShareResponse shareResponse;
    try {
      shareResponse = ShareResponse.fromJson(
        json.decode(
          utf8.decode(base64.decode(utf8.decode(await socket.first.timeout(Duration(minutes: 2), onTimeout: () {
            socket.close();
            NoCabCore.logger.error("Request timed out after 2 minutes", className: "RequestMaker");
            throw StateError("Request timed out");
          })))),
        ),
      );
    } catch (e, stackTrace) {
      NoCabCore.logger.error(
        "Cannot parse response from ${receiverDeviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})",
        className: "RequestMaker",
        error: e,
        stackTrace: stackTrace,
      );
      throw CoreError("Cannot parse response from ${receiverDeviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})",
          className: "RequestMaker", methodName: "requestTo", stackTrace: stackTrace, error: e);
    }

    if (!shareResponse.response) {
      request.registerResponse(shareResponse);
      NoCabCore.logger.info(
          "Request rejected by ${receiverDeviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort}), reason: ${shareResponse.info}",
          className: "RequestMaker");
      return;
    }

    NoCabCore.logger.info("Request accepted by ${receiverDeviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})",
        className: "RequestMaker");

    request.linkedTransfer = Sender(
      deviceInfo: receiverDeviceInfo,
      files: request.files,
      transferPort: request.transferPort,
      controlPort: request.controlPort,
      uuid: request.transferUuid,
    );

    NoCabCore.logger.info("Starting transfer to ${receiverDeviceInfo.name}(${receiverDeviceInfo.ip}:${receiverDeviceInfo.requestPort})",
        className: "RequestMaker");

    await request.linkedTransfer!.start();

    request.registerResponse(shareResponse);
  }
}
