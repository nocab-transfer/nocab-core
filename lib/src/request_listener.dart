import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/src/device_manager.dart';
import 'package:nocab_core/src/models/share_request.dart';
import 'package:nocab_core/src/models/share_response.dart';

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
  Future<void> start({Function(String)? onError}) async {
    try {
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, DeviceManager().currentDeviceInfo.requestPort);
    } catch (e) {
      onError?.call(e.toString());
    }

    serverSocket?.listen((socket) {
      try {
        if (activeRequest != null) {
          var shareResponse = ShareResponse(response: false, info: "Another request is in progress");
          socket.write(base64.encode(utf8.encode(json.encode(shareResponse.toJson()))));
          socket.close();
          return;
        }
      } catch (e) {
        socket.close();
      }

      socket.listen((event) {
        try {
          String data = utf8.decode(base64.decode(utf8.decode(event)));
          activeRequest = ShareRequest.fromJson(jsonDecode(data));
          activeRequest!.socket = socket;
          _requestHandler(activeRequest!, socket);
        } catch (e) {
          onError?.call(e.toString());
          socket.close();
        }
      }, onDone: () {
        if (activeRequest?.responded == false) activeRequest!.responseController.add(ShareResponse(response: false, info: "Connection lost"));
        activeRequest = null;
      });
    });
  }

  void _requestHandler(ShareRequest request, Socket socket) {
    _requestController.add(request);
  }

  void stop() {
    _requestController.close();
    serverSocket?.close();
  }
}
