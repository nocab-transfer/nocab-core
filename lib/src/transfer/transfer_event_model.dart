import 'package:nocab_core/src/models/core_error.dart';
import 'package:nocab_core/src/models/file_info.dart';

class TransferEvent {
  TransferEventType type;

  FileInfo? currentFile;
  int? writtenBytes;

  CoreError? error; // Only used when type is error

  TransferEvent(this.type, {this.currentFile, this.writtenBytes, this.error});
}

enum TransferEventType {
  start,
  event,
  fileEnd,
  end,
  error,
}
