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

  /// Starts listening for requests.
  ///
  /// [onError] is the callback that is called when an error occurs.
  Future<void> start({Function(CoreError)? onError}) async {
    NoCabCore.logger.info("Starting listening", className: "RequestListener");

    try {
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, NoCabCore().currentDeviceInfo.requestPort);
      NoCabCore.logger.info("Listening on ${serverSocket!.address.address}:${serverSocket!.port}", className: "RequestListener");
    } catch (e, stackTrace) {
      NoCabCore.logger.error("Socket binding error", className: "RequestListener", error: e, stackTrace: stackTrace);
      onError?.call(CoreError("Socket binding error", className: "RequestListener", methodName: "start", stackTrace: stackTrace, error: e));
    }

    serverSocket?.listen((socket) {
      try {
        if (latestRequest?.isResponded == false) {
          NoCabCore.logger.info("${socket.remoteAddress.address}:${socket.remotePort} has been rejected because another request is in progress",
              className: "RequestListener");
          var shareResponse = ShareResponse(response: false, info: "Another request is in progress");
          socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
          socket.flush().then((value) => socket.destroy());
          return;
        }
      } catch (e, stackTrace) {
        onError?.call(CoreError("Socket error", className: "RequestListener", methodName: "start", stackTrace: stackTrace, error: e));
        NoCabCore.logger.error("Socket error", className: "RequestListener", error: e, stackTrace: stackTrace);
        socket.destroy();
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
                NoCabCore.logger.info(
                    "${socket.remoteAddress.address}:${socket.remotePort} has been automatically rejected because the connection has been lost",
                    className: "RequestListener");
              }
            });
            _requestHandler(latestRequest!, socket);
          } catch (e, stackTrace) {
            NoCabCore.logger.error("Socket error while parsing request", className: "RequestListener", error: e, stackTrace: stackTrace);
            onError?.call(
                CoreError("Socket error while parsing request", className: "RequestListener", methodName: "start", stackTrace: stackTrace, error: e));
            socket.destroy();
          }
        },
      );
    });
  }

  void _requestHandler(ShareRequest request, Socket socket) {
    NoCabCore.logger.info(
      "${request.deviceInfo.name}(${socket.remoteAddress.address}:${socket.remotePort}) has requested to share ${request.files.length} files",
      className: "RequestListener",
    );

    _requestController.add(request);

    if (request.coreVersion == null) {
      NoCabCore.logger.info(
          "${request.deviceInfo.name}(${socket.remoteAddress.address}:${socket.remotePort}) has been rejected because of the core version missing",
          className: "RequestListener");
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

        NoCabCore.logger.info(
            "${request.deviceInfo.name}(${socket.remoteAddress.address}:${socket.remotePort}) has been rejected because of the core version mismatch",
            className: "RequestListener");
        request.reject(info: "Core version mismatch. Please update the ${isCurrentVersionOlder ? "requester" : "receiver"} app}");
        return;
      } catch (e, stackTrace) {
        NoCabCore.logger.error("Core version parsing error", className: "RequestListener", error: e, stackTrace: stackTrace);
        request.reject(info: "Core version parsing error. Can't proceed");
        return;
      }
    }
  }

  /// Stops listening for requests.
  void stop() {
    NoCabCore.logger.info("Stopped listening", className: "RequestListener");
    serverSocket?.close();
  }
}
