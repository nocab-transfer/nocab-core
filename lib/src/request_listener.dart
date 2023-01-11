import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_logger/nocab_logger.dart';

class RequestListener {
  static final RequestListener _singleton = RequestListener._internal();
  RequestListener._internal();
  factory RequestListener() {
    return _singleton;
  }

  final _requestController = StreamController<ShareRequest>.broadcast();
  Stream<ShareRequest> get onRequest => _requestController.stream;

  ServerSocket? serverSocket;

  ShareRequest? activeRequest;
  Future<void> start({Function(CoreError)? onError}) async {
    Logger().info("Starting listening", "RequestListener");

    try {
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, DeviceManager().currentDeviceInfo.requestPort);
      Logger().info("Listening on ${serverSocket!.address.address}:${serverSocket!.port}", "RequestListener");
    } catch (e, stackTrace) {
      Logger().error("Socket binding error", "RequestListener", error: e, stackTrace: stackTrace);
      onError?.call(CoreError(e.toString(), className: "RequestListener", methodName: "start", stackTrace: stackTrace));
    }

    serverSocket?.listen((socket) {
      try {
        if (activeRequest != null) {
          Logger().info(
              "${socket.remoteAddress.address}:${socket.remotePort} has been rejected because another request is in progress", "RequestListener");
          var shareResponse = ShareResponse(response: false, info: "Another request is in progress");
          socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
          socket.flush().then((value) => socket.close());
          return;
        }
      } catch (e, stackTrace) {
        onError?.call(CoreError(e.toString(), className: "RequestListener", methodName: "start", stackTrace: stackTrace));
        Logger().error("Socket error", "RequestListener", error: e, stackTrace: stackTrace);
        socket.close();
      }

      socket.listen(
        (event) {
          try {
            String data = utf8.decode(base64.decode(utf8.decode(event)));
            activeRequest = ShareRequest.fromJson(jsonDecode(data));
            activeRequest!.socket = socket;

            socket.done.then((value) {
              if (activeRequest?.isResponded == false) {
                activeRequest!.registerResponse(ShareResponse(response: false, info: "Connection lost"));
                Logger().info(
                    "${socket.remoteAddress.address}:${socket.remotePort} has been automatically rejected because the connection has been lost",
                    "RequestListener");
              }
              activeRequest = null;
            });
            _requestHandler(activeRequest!, socket);
          } catch (e, stackTrace) {
            Logger().error("Socket error while parsing request", "RequestListener", error: e, stackTrace: stackTrace);
            onError?.call(CoreError(e.toString(), className: "RequestListener", methodName: "start", stackTrace: stackTrace));
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
  }

  void stop() {
    Logger().info("Stopped listening", "RequestListener");
    serverSocket?.close();
  }
}
