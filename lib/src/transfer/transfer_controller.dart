import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/nocab_core.dart';

class TransferController {
  Transfer transfer;

  Socket? _controlSocket;
  ServerSocket? _serverSocket;
  final Completer<void> controlSocketCompleter = Completer<void>();

  Function()? onCancelReceived;
  Function(CoreError error)? onErrorReceived;

  TransferController({required this.transfer, this.onCancelReceived, this.onErrorReceived}) {
    _initControlSocket();
  }

  void dispose() {
    _controlSocket?.destroy();
    _serverSocket?.close();
  }

  Future<void> _initControlSocket() async {
    // Request created by Sender. We should listen for a connection on Receiver side
    if (transfer is Sender) {
      try {
        _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, transfer.controlPort).then((server) {
          NoCabCore.logger.info(
            'Listening for initial control connection on ${server.address.address}:${server.port}',
            className: 'TransferController(${transfer.runtimeType})',
          );

          server.listen((socket) async {
            // if ip is not the same as the one we expect, close the socket
            if (transfer.deviceInfo.ip != socket.remoteAddress.address) {
              socket.destroy();

              NoCabCore.logger.warning(
                'Received connection from ${socket.remoteAddress.address} but expected ${transfer.deviceInfo.ip}',
                className: 'TransferController(${transfer.runtimeType})',
              );

              return;
            }

            NoCabCore.logger.info(
              'Received initial control connection from ${socket.remoteAddress.address}',
              className: 'TransferController(${transfer.runtimeType})',
            );

            _controlSocket = socket;
            _listenSocket(_controlSocket!);

            NoCabCore.logger.info('Closing control server', className: 'TransferController(${transfer.runtimeType})');
            server.close();
          });
          return null;
        });
      } catch (e, stackTrace) {
        NoCabCore.logger.error(
          'Error binding to control socket',
          className: 'TransferController(${transfer.runtimeType})',
          error: e,
          stackTrace: stackTrace,
        );
        _controlSocket?.destroy();
      }
    } else {
      // On receiver side, we should connect to sender control socket
      try {
        Socket.connect(transfer.deviceInfo.ip, transfer.controlPort).then((socket) {
          NoCabCore.logger.info(
            'Connected to control socket ${socket.remoteAddress.address}:${socket.remotePort}',
            className: 'TransferController(${transfer.runtimeType})',
          );

          _controlSocket = socket;
          _listenSocket(socket);
        });
      } catch (e, stackTrace) {
        NoCabCore.logger.error(
          'Error connecting to control socket',
          className: 'TransferController(${transfer.runtimeType})',
          error: e,
          stackTrace: stackTrace,
        );

        _controlSocket?.destroy();
      }
    }
  }

  void _listenSocket(Socket socket) {
    NoCabCore.logger.info(
      'Listening to control socket ${socket.remoteAddress.address}:${socket.remotePort}',
      className: 'TransferController(${transfer.runtimeType})',
    );

    controlSocketCompleter.complete();

    socket.listen((event) {
      try {
        String dataString = utf8.decode(base64.decode(utf8.decode(event)));
        Map<String, dynamic> data = jsonDecode(dataString);

        // if transferUuid is not the same as the one we expect, ignore the data
        if (data['transferUuid'] != transfer.uuid) {
          NoCabCore.logger.warning(
            'Incoming control data has invalid transferUuid ${data['transferUuid']}, expected ${transfer.uuid}',
            className: 'TransferController(${transfer.runtimeType})',
          );
          return;
        }

        switch (data['type']) {
          case 'cancel':
            NoCabCore.logger.info('Received cancel from control socket', className: 'TransferController(${transfer.runtimeType})');
            onCancelReceived?.call();
            break;
          case 'error':
            data['error'] ??= {
              'title': 'An error occured on the other side but no error was provided',
              'className': 'TransferController',
              'methodName': 'start',
              'stackTrace': StackTrace.current.toString(),
            };

            CoreError error = CoreError.fromJson(data['error']);
            NoCabCore.logger.info('Received error from control socket',
                className: 'TransferController(${transfer.runtimeType})', error: error.error, stackTrace: error.stackTrace);
            onErrorReceived?.call(error);
            break;
          default:
            NoCabCore.logger.warning(
              'Received invalid control data type ${data['type']}',
              className: 'TransferController(${transfer.runtimeType})',
            );
            break;
        }
      } catch (e) {
        NoCabCore.logger.warning('Received invalid data', className: 'TransferController(${transfer.runtimeType})', error: e);
      }
    }, onDone: () => _handleDoneOrError(socket), onError: (e) => _handleDoneOrError(socket));
  }

  Future<void> sendCancel() async {
    if (!await _waitForControlSocket()) return;

    NoCabCore.logger.info('Sending cancel to control socket ${_controlSocket?.remoteAddress.address}:${_controlSocket?.remotePort}',
        className: 'TransferController(${transfer.runtimeType})');

    try {
      _controlSocket?.write(base64.encode(utf8.encode(jsonEncode({
        'transferUuid': transfer.uuid,
        'type': 'cancel',
      }))));

      await _controlSocket?.flush();
    } catch (e, stackTrace) {
      NoCabCore.logger.warning(
        'Failed to send cancel message',
        className: 'TransferController(${transfer.runtimeType})',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> sendError(CoreError error) async {
    if (!await _waitForControlSocket()) return;

    try {
      NoCabCore.logger.info('Sending error to control socket ${_controlSocket?.remoteAddress.address}:${_controlSocket?.remotePort}',
          className: 'TransferController(${transfer.runtimeType})');

      _controlSocket?.write(base64.encode(utf8.encode(jsonEncode({
        'transferUuid': transfer.uuid,
        'type': 'error',
        'error': error.toJson(),
      }))));

      await _controlSocket?.flush();
    } catch (e, stackTrace) {
      NoCabCore.logger.warning(
        'Failed to send error message',
        className: 'TransferController(${transfer.runtimeType})',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _waitForControlSocket() async {
    if (_controlSocket == null) {
      int retries = 0;
      do {
        await Future.delayed(Duration(milliseconds: 200));
        NoCabCore.logger.info('Waiting for control socket to be ready (200ms:$retries)', className: 'TransferController(${transfer.runtimeType})');
        retries++;
      } while (_controlSocket == null && retries < 10);

      if (_controlSocket == null) {
        NoCabCore.logger.warning('Control socket is not ready, aborting', className: 'TransferController(${transfer.runtimeType})');
        return false;
      }

      return true;
    } else {
      NoCabCore.logger.info('Control socket is ready', className: 'TransferController(${transfer.runtimeType})');
      return true;
    }
  }

  _handleDoneOrError(Socket socket) {
    if (transfer.ongoing) {
      NoCabCore.logger.warning('Control socket closed while transfer is ongoing', className: 'TransferController(${transfer.runtimeType})');
    }
    socket.close();
  }
}
