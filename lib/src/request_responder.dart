import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
import 'package:path/path.dart';

extension Responder on ShareRequest {
  Future<void> accept({Function(CoreError)? onError, required Directory downloadDirectory, required Directory tempDirectory}) async {
    Logger().info("Accepting request", "RequestResponder");
    try {
      if (!downloadDirectory.existsSync()) {
        Logger().info("Download directory does not exist, creating it", "RequestResponder");
        downloadDirectory.createSync(recursive: true);
      }

      files = files
          .map<FileInfo>((e) => e
            ..path = FileOperations.findUnusedFilePath(
              downloadPath: joinAll([downloadDirectory.path, ...split(e.subDirectory ?? "")]),
              fileName: e.name,
            ))
          .toList();

      Logger().info("Successfully find unused file paths for ${files.length} files", "RequestResponder");

      var shareResponse = ShareResponse(response: true);

      linkedTransfer = Receiver(
        transferPort: transferPort,
        deviceInfo: deviceInfo,
        files: files,
        tempFolder: tempDirectory,
        uuid: transferUuid,
      );

      Logger().info("Starting linked transfer", "RequestResponder");
      await linkedTransfer!.start();

      Logger().info("Writing accept response", "RequestResponder");
      socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
      await socket.flush();
      socket.close();

      Logger().info("Registering response", "RequestResponder");
      registerResponse(shareResponse);
    } catch (e, stackTrace) {
      Logger().error("Error while accepting request", "RequestResponder", error: e, stackTrace: stackTrace);
      onError?.call(CoreError(e.toString(), className: "RequestResponder", methodName: "accept", stackTrace: stackTrace));
      return;
    }
  }

  void reject({Function(CoreError)? onError, String? info}) {
    Logger().info("Rejecting request", "RequestResponder");
    try {
      var shareResponse = ShareResponse(response: false, info: info ?? "User rejected the request");
      Logger().info("Writing reject response", "RequestResponder");
      socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
      socket.flush().then((value) => socket.close());
      Logger().info("Registering response", "RequestResponder");
      registerResponse(shareResponse);
    } catch (e, stackTrace) {
      Logger().error("Error while rejecting request", "RequestResponder", error: e, stackTrace: stackTrace);
      onError?.call(CoreError(e.toString(), className: "RequestResponder", methodName: "reject", stackTrace: stackTrace));
    }
  }
}
