import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
import 'package:path/path.dart';

extension Responder on ShareRequest {
  Future<void> accept({Function(CoreError)? onError, required Directory downloadDirectory, required Directory tempDirectory}) async {
    try {
      if (!downloadDirectory.existsSync()) downloadDirectory.createSync(recursive: true);

      files = files
          .map<FileInfo>((e) => e
            ..path = FileOperations.findUnusedFilePath(
              downloadPath: joinAll([downloadDirectory.path, ...split(e.subDirectory ?? "")]),
              fileName: e.name,
            ))
          .toList();

      var shareResponse = ShareResponse(response: true);
      linkedTransfer = Receiver(
        transferPort: transferPort,
        deviceInfo: deviceInfo,
        files: files,
        tempFolder: tempDirectory,
        uuid: transferUuid,
      );

      await linkedTransfer!.start();

      socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
      await socket.flush();
      socket.close();
      registerResponse(shareResponse);
    } catch (e, stackTrace) {
      onError?.call(CoreError(e.toString(), className: "RequestResponder", methodName: "accept", stackTrace: stackTrace));
      return;
    }
  }

  void reject({Function(CoreError)? onError, String? info}) {
    try {
      var shareResponse = ShareResponse(response: false, info: info ?? "User rejected the request");
      socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
      socket.flush().then((value) => socket.close());
      registerResponse(shareResponse);
    } catch (e, stackTrace) {
      onError?.call(CoreError(e.toString(), className: "RequestResponder", methodName: "reject", stackTrace: stackTrace));
    }
  }
}
