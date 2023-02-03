library nocab_core;

import 'package:nocab_logger/nocab_logger.dart';

export 'src/device_manager.dart';
export 'src/request_listener.dart';
export 'src/request_maker.dart';
export 'src/request_responder.dart';
export 'src/radar.dart';

export 'src/file_operations/file_operations.dart';

export 'src/models/device_info.dart';
export 'src/models/file_info.dart';
export 'src/models/share_request.dart';
export 'src/models/share_response.dart';
export 'src/models/core_error.dart';

export 'src/transfer/report_models/base_report.dart';

export 'src/transfer/transfer.dart';
export 'src/transfer/sender.dart';
export 'src/transfer/receiver.dart';

class NoCabCore {
  NoCabCore._internal();
  static final NoCabCore _singleton = NoCabCore._internal();
  factory NoCabCore() {
    if (!_singleton._initialized) throw Exception('NoCabCore not initialized. Call NoCabCore.init() first.');
    return _singleton;
  }

  bool _initialized = false;
  static const String version = '1.0.0';

  static late final Logger logger;
  static void init({required String logFolderPath}) {
    _singleton._initialized = true;
    logger = Logger('NoCabCore', storeInFile: true, logPath: logFolderPath);
  }

  static void dispose() {
    logger.close();
  }
}
