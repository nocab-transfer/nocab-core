import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Request Test',
    () async {
      DeviceManager().initialize("Sender", "127.0.0.1", 5001);
      await RequestListener().start(onError: (p0) => throw Exception(p0));

      File file = File("test/_testFile");

      var request = RequestMaker.create(files: [file], transferPort: 1234);

      RequestMaker.requestTo(
        DeviceInfo(name: "Listener", ip: "127.0.0.1", requestPort: 5001, opsystem: Platform.operatingSystemVersion),
        request: request,
      );

      var listenedRequest = await RequestListener().onRequest.first;
      expect(listenedRequest.deviceInfo.name, equals("Sender"));

      listenedRequest.reject();

      var response = await request.onResponse;
      expect(response.response, equals(false));
    },
    timeout: Timeout(Duration(seconds: 5)),
  );
}
