import 'package:nocab_core/src/models/file_info.dart';

class TransferEvent {
  TransferEventType type;

  FileInfo? currentFile;
  int? writtenBytes;

  String? message; // for error

  TransferEvent(this.type, {this.currentFile, this.writtenBytes, this.message});
}

enum TransferEventType {
  start,
  event,
  fileEnd,
  end,
  error,
}
