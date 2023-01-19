import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/nocab_core.dart';

class RequestListener {
  static final RequestListener _singleton = RequestListener._internal();
  RequestListener._internal();
  factory RequestListener() {
    return _singleton;
  }

  final _requestController = StreamController<ShareRequest>.broadcast();
  Stream<ShareRequest> get onRequest => _requestController.stream;

  ServerSocket? serverSocket;

  ShareRequest? latestRequest;
  Future<void> start({Function(CoreError)? onError}) async {
    Logger().info("Starting listening", "RequestListener");

    try {
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, DeviceManager().currentDeviceInfo.requestPort);
      Logger().info("Listening on ${serverSocket!.address.address}:${serverSocket!.port}", "RequestListener");
    } catch (e, stackTrace) {
      Logger().error("Socket binding error", "RequestListener", error: e, stackTrace: stackTrace);
      onError?.call(CoreError("Socket binding error", className: "RequestListener", methodName: "start", stackTrace: stackTrace, error: e));
    }

    serverSocket?.listen((socket) {
      try {
        if (latestRequest?.isResponded == false) {
          Logger().info(
              "${socket.remoteAddress.address}:${socket.remotePort} has been rejected because another request is in progress", "RequestListener");
          var shareResponse = ShareResponse(response: false, info: "Another request is in progress");
          socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
          socket.flush().then((value) => socket.close());
          return;
        }
      } catch (e, stackTrace) {
        onError?.call(CoreError("Socket error", className: "RequestListener", methodName: "start", stackTrace: stackTrace, error: e));
        Logger().error("Socket error", "RequestListener", error: e, stackTrace: stackTrace);
        socket.close();
      }

      socket.listen(
        (event) {
          try {
            String data = utf8.decode(base64.decode(utf8.decode(event)));
            latestRequest = ShareRequest.fromJson(jsonDecode(data));
            latestRequest!.socket = socket;

            socket.done.then((value) {
              if (latestRequest?.isResponded == false) {
                latestRequest!.registerResponse(ShareResponse(response: false, info: "Connection lost"));
                Logger().info(
                    "${socket.remoteAddress.address}:${socket.remotePort} has been automatically rejected because the connection has been lost",
                    "RequestListener");
              }
            });
            _requestHandler(latestRequest!, socket);
          } catch (e, stackTrace) {
            Logger().error("Socket error while parsing request", "RequestListener", error: e, stackTrace: stackTrace);
            onError?.call(
                CoreError("Socket error while parsing request", className: "RequestListener", methodName: "start", stackTrace: stackTrace, error: e));
            socket.close();
          }
        },
      );
    });
  }

  void _requestHandler(ShareRequest request, Socket socket) {
    Logger().info(
      "${request.deviceInfo.name}(${socket.remoteAddress.address}:${socket.remotePort}) has requested to share ${request.files.length} files",
      "RequestListener",
    );

    _requestController.add(request);

    if (request.coreVersion == null) {
      Logger().info(
          "${request.deviceInfo.name}(${socket.remoteAddress.address}:${socket.remotePort}) has been rejected because of the core version missing",
          "RequestListener");
      request.reject(info: "Core version missing in the request. Can't proceed. Please update the requester app");
      return;
    }

    if (request.coreVersion != NoCabCore.version) {
      // find which version is older
      var currentVersion = NoCabCore.version.split(".");
      var requestVersion = request.coreVersion!.split(".");
      var isCurrentVersionOlder = false;

      try {
        for (var i = 0; i < currentVersion.length; i++) {
          if (int.parse(currentVersion[i]) < int.parse(requestVersion[i])) {
            isCurrentVersionOlder = true;
            break;
          }
        }

        Logger().info(
            "${request.deviceInfo.name}(${socket.remoteAddress.address}:${socket.remotePort}) has been rejected because of the core version mismatch",
            "RequestListener");
        request.reject(info: "Core version mismatch. Please update the ${isCurrentVersionOlder ? "requester" : "receiver"} app}");
        return;
      } catch (e, stackTrace) {
        Logger().error("Core version parsing error", "RequestListener", error: e, stackTrace: stackTrace);
        request.reject(info: "Core version parsing error. Can't proceed");
        return;
      }
    }
  }

  void stop() {
    Logger().info("Stopped listening", "RequestListener");
    serverSocket?.close();
  }
}
