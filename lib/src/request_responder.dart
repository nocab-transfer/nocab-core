import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/src/file_operations/file_operations.dart';
import 'package:nocab_core/src/models/file_info.dart';
import 'package:nocab_core/src/models/share_request.dart';
import 'package:nocab_core/src/models/share_response.dart';
import 'package:nocab_core/src/transfer/receiver.dart';
import 'package:path/path.dart';

extension Responder on ShareRequest {
  Future<void> accept({Function(String)? onError, required Directory downloadDirectory, required Directory tempDirectory}) async {
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
      socket.close();
      responseController.add(shareResponse);
    } catch (e) {
      onError?.call(e.toString());
      return;
    }
  }

  void reject({Function(String)? onError, String? info}) {
    try {
      var shareResponse = ShareResponse(response: false, info: info ?? "User rejected the request");
      socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
      socket.close();
      responseController.add(shareResponse);
    } catch (e) {
      onError?.call(e.toString());
    }
  }
}
