# NoCab Core

The core library for the NoCab Transfer, built with pure Dart and responsible for managing file transfers and requests within a local network.

## Requirements

- Dart 2.19.0 or higher

## Features

- Manage file transfers between devices on the same network
- Handle send requests from other devices on the network

## Getting started

1. Install the library in your project:

```yaml
  nocab_core:
    git:
      url: https://github.com/nocab-transfer/nocab-core.git
```

2. Import the library in your project with import 'package:nocab_core/nocab_core.dart';


## Example

### 1. Finding devices on the network

```dart
import 'package:nocab_core/nocab_core.dart';
import 'dart:async';

Future<void> main() async {
  // NoCabCore should be initialized with the device name and the device IP address and request port
  NoCabCore.init(deviceName: "Cli", requestPort: 5001, deviceIp: "127.0.0.1", logFolderPath: "path/to/log/folder");

  // Start radar to be discovered by other devices on the network
  Radar().start(radarPort: 62193);

  // Find devices on the network
  // This will return a list of devices that are currently on the network
  // Port is the port that the another device's radar is listening to
  // Base IP is the base IP address of the network. If not provided, it will get from device manager.
  // searchForDevices() also a stream. It scans for one time but you it can return multiple times while scanning
  List<DeviceInfo> devices = await Radar.searchForDevices(baseIp: "127.0.0", radarPort: 62193).last;

  // Use a timer to scan continuously
  Timer.periodic(Duration(seconds: 5), (timer) async {
    List<DeviceInfo> devices = await Radar.searchForDevices(baseIp: "127.0.0", radarPort: 62193).last;
  });

  // If you dont want to be found in network, you can stop the radar
  // You can still find devices on the network even if you stop the radar
  Radar().stop();

}
```

### 2. Sending requests

```dart
import 'package:nocab_core/nocab_core.dart';
import 'dart:io';

Future<void> main() async {
  // NoCabCore should be initialized with the device name and the device IP address and request port
  NoCabCore.init(deviceName: "Cli", requestPort: 5001, deviceIp: "127.0.0.1", logFolderPath: "path/to/log/folder");

  // List of files to be sent
  var files = [
    File("path/to/file1"),
    File("path/to/file2"),
    File("path/to/file3"),
  ];

  // Create request, transfer port is the port that the receiver device will listen to for incoming files
  // You can use any port you want
  // Control port is the port that the controlling (e.g. cancelling) messages will be sent to
  // both ports should be not used by any other application
  var request = RequestMaker.create(files: files, transferPort: 1234, controlPort: 1235);

  // Receiver device info. You should obtain this from the receiver device.
  DeviceInfo receiverDeviceInfo = ...;

  RequestMaker.requestTo(receiverDeviceInfo, request: request);

  var response = await request.onResponse;
  if (response.response) {
    // Request accepted
    // It will automatically start transferring files
    // You can listen to the progress of the transfer from automatically attached linkedTransfer to the request
    request.linkedTransfer!.onEvent.listen((event) {
      print("-" * 50);
      switch (event.runtimeType) {
        case StartReport:
          event as StartReport;
          print("Transfer started. Start Time ${event.startTime}");
          break;
        case ProgressReport:
          event as ProgressReport;
          print("Current File: ${event.currentFile.name}\n"
              "${event.filesTransferred.length} files transferred\n"
              "Progress: ${event.progress * 100}%\n"
              "Speed: ${(event.speed / 1024 / 1024).toStringAsFixed(2)} MB/s");
          break;
        case EndReport:
          event as EndReport;
          print("Transfer completed. End Time ${event.endTime}");
          break;
        case ErrorReport:
          event as ErrorReport;
          print("Error occured. Error: ${event.error.title}");
          break;
        default:
          break;
      }
    });
  } else {
    // Request rejected
    print(response.info);
  }

}
```

### 3. Receiving requests

```dart
import 'package:nocab_core/nocab_core.dart';
import 'dart:io';

Future<void> main() async {
  // NoCabCore should be initialized with the device name and the device IP address and request port
  NoCabCore.init(deviceName: "Cli", requestPort: 5001, deviceIp: "127.0.0.1", logFolderPath: "path/to/log/folder");

  // Start listening to incoming requests
  await RequestListener().start();

  // Handle incoming requests
  RequestListener().onRequest.listen((request) async {
    print("Request from ${request.deviceInfo.name} with ${request.files.length} files\n"
        "Files:\n"
        "${request.files.map((e) => e.name).join(", ")}");

    // Accept or reject the request
    await request.accept(downloadDirectory: Directory("download folder"), tempDirectory: Directory.systemTemp);
    // request.reject();

    // If the request accepted it will automatically start transferring files
    // You can listen to the progress of the transfer from automatically attached linkedTransfer to the request
    request.linkedTransfer!.onEvent.listen((event) {
      print("-" * 50);
      switch (event.runtimeType) {
        case StartReport:
          event as StartReport;
          print("Transfer started. Start Time ${event.startTime}");
          break;
        case ProgressReport:
          event as ProgressReport;
          print("Current File: ${event.currentFile.name}\n"
              "${event.filesTransferred.length} files transferred\n"
              "Progress: ${event.progress * 100}%\n"
              "Speed: ${(event.speed / 1024 / 1024).toStringAsFixed(2)} MB/s");
          break;
        case EndReport:
          event as EndReport;
          print("Transfer completed. End Time ${event.endTime}");
          break;
        case ErrorReport:
          event as ErrorReport;
          print("Error occured. Error: ${event.error.title}");
          break;
        default:
          break;
      }
    });
  });
}

```

## Contributing

If you would like to contribute to the project, please follow these guidelines:

1. Fork the repository
2. Create a new branch for your feature or bug fix
3. Commit your changes
4. Create a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
