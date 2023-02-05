import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
import 'package:path/path.dart';

extension Responder on ShareRequest {
  /// Accepts the request and starts the transfer
  Future<Receiver> accept({required Directory downloadDirectory, required Directory tempDirectory}) async {
    NoCabCore.logger.info("Accepting request", className: "RequestResponder");
    try {
      if (!downloadDirectory.existsSync()) {
        NoCabCore.logger.info("Download directory does not exist, creating it", className: "RequestResponder");
        downloadDirectory.createSync(recursive: true);
      }

      files = files
          .map<FileInfo>((e) => e
            ..path = FileOperations.findUnusedFilePath(
              downloadPath: joinAll([downloadDirectory.path, ...split(e.subDirectory ?? "")]),
              fileName: e.name,
            ))
          .toList();

      NoCabCore.logger.info("Successfully find unused file paths for ${files.length} files", className: "RequestResponder");

      var shareResponse = ShareResponse(response: true);

      linkedTransfer = Receiver(
        transferPort: transferPort,
        controlPort: controlPort,
        deviceInfo: deviceInfo,
        files: files,
        tempFolder: tempDirectory,
        uuid: transferUuid,
      );

      NoCabCore.logger.info("Starting linked transfer", className: "RequestResponder");
      await linkedTransfer!.start();

      NoCabCore.logger.info("Writing accept response", className: "RequestResponder");
      socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
      await socket.flush();
      socket.destroy();

      NoCabCore.logger.info("Registering response", className: "RequestResponder");
      registerResponse(shareResponse);
      return linkedTransfer as Receiver;
    } catch (e, stackTrace) {
      NoCabCore.logger.error("Error while accepting request", className: "RequestResponder", error: e, stackTrace: stackTrace);
      throw CoreError(
        "Error while accepting request: ${e.toString()}",
        className: "RequestResponder",
        methodName: "accept",
        stackTrace: stackTrace,
        error: e,
      );
    }
  }

  /// Rejects the request
  void reject({String? info}) {
    NoCabCore.logger.info("Rejecting request", className: "RequestResponder");
    try {
      var shareResponse = ShareResponse(response: false, info: info ?? "User rejected the request");
      NoCabCore.logger.info("Writing reject response", className: "RequestResponder");
      socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
      socket.flush().then((value) => socket.destroy());
      NoCabCore.logger.info("Registering response", className: "RequestResponder");
      registerResponse(shareResponse);
    } catch (e, stackTrace) {
      NoCabCore.logger.error("Error while rejecting request", className: "RequestResponder", error: e, stackTrace: stackTrace);
      throw CoreError(
        "Error while rejecting request: ${e.toString()}",
        className: "RequestResponder",
        methodName: "reject",
        stackTrace: stackTrace,
        error: e,
      );
    }
  }
}
