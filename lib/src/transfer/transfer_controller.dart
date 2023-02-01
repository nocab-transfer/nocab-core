import 'dart:convert';
import 'dart:io';

import 'package:nocab_core/nocab_core.dart';
import 'package:nocab_logger/nocab_logger.dart';

class TransferController {
  Transfer transfer;

  Socket? _controlSocket;
  ServerSocket? _serverSocket;

  TransferController({required this.transfer}) {
    _initControlSocket();

    // Close control socket when transfer is done
    transfer.done.then((value) {
      _controlSocket?.close();

      // If no connection was made, server socket will still be open. We should close it.
      _serverSocket?.close(); // it always be null on Receiver side
    });
  }

  Future<void> _initControlSocket() async {
    // Request created by Sender. We should listen for a connection on Receiver side
    if (transfer is Sender) {
      try {
        ServerSocket.bind(InternetAddress.anyIPv4, transfer.controlPort).then((server) {
          _serverSocket = server;

          Logger().info('Listening for initial control connection on ${server.address.address}:${server.port}', 'TransferController');
          server.listen((socket) async {
            // if ip is not the same as the one we expect, close the socket
            if (transfer.deviceInfo.ip != socket.remoteAddress.address) {
              socket.close();
              Logger().warning(
                'Received connection from ${socket.remoteAddress.address} but expected ${transfer.deviceInfo.ip}',
                'TransferController',
              );
              return;
            }

            Logger().info('Received initial control connection from ${socket.remoteAddress.address}', 'TransferController');
            _controlSocket = socket;
            _listenSocket(socket);
            Logger().info('Closing control server', 'TransferController');
            server.close();
          });
          return null;
        });
      } catch (e, stackTrace) {
        Logger().error('Error binding to control socket', 'TransferController', error: e, stackTrace: stackTrace);
        _controlSocket?.close();
      }
    } else {
      // On receiver side, we should connect to sender control socket
      try {
        Socket.connect(transfer.deviceInfo.ip, transfer.controlPort).then((socket) {
          Logger().info('Connected to control socket ${socket.remoteAddress.address}:${socket.remotePort}', 'TransferController');
          _controlSocket = socket;
          _listenSocket(socket);
        });
      } catch (e, stackTrace) {
        Logger().error('Error connecting to control socket', 'TransferController', error: e, stackTrace: stackTrace);
        _controlSocket?.close();
      }
    }
  }

  void _listenSocket(Socket socket) {
    Logger().info('Listening to control socket ${socket.remoteAddress.address}:${socket.remotePort}', 'TransferController');

    socket.listen((event) {
      try {
        String dataString = utf8.decode(base64.decode(utf8.decode(event)));
        Map<String, dynamic> data = jsonDecode(dataString);

        // if transferUuid is not the same as the one we expect, ignore the data
        if (data['transferUuid'] != transfer.uuid) {
          Logger().warning(
            'Incoming control data has invalid transferUuid ${data['transferUuid']}, expected ${transfer.uuid}',
            'TransferController',
          );
          return;
        }

        switch (data['type']) {
          case null:
            Logger().warning('Received null type', 'TransferController');
            break;
          case 'cancel':
            // Notifying the transfer that it has been cancelled by the other side
            cancel(incoming: true);
            break;
          case 'error':
            // Notifying the transfer that an error occured on the other side
            _handleIncomingError(data);
        }
      } catch (e) {
        Logger().warning('Received invalid data', 'TransferController', error: e);
      }
    }, onDone: () => _handleDoneOrError(socket), onError: (e) => _handleDoneOrError(socket));
  }

  /// This function is called when an error is received on the incoming stream.
  /// This function cancels the transfer.
  void _handleIncomingError(Map<String, dynamic> data) {
    // Set the error to a default value if it is not provided.
    data['error'] ??= {
      'title': 'An error occured on the other side but no error was provided',
      'className': 'TransferController',
      'methodName': 'start',
      'stackTrace': StackTrace.current.toString(),
    };

    // Create the error object.
    CoreError error = CoreError.fromJson(data['error']);
    // Cancel the transfer.
    cancel(incoming: true, isError: true, error: error);
  }

  /// Cancels the transfer
  ///
  /// This function is used to cancel the transfer on both sides,
  /// it will send a cancel message to the other side and close the socket
  /// This function can be called from both sides, if it is called from the
  /// other side, then the [incoming] argument should be true
  /// The [isError] argument is true if there is an error that caused the transfer
  /// to be cancelled, if so, the [error] argument should be set to the error
  Future<void> cancel({bool incoming = false, bool isError = false, CoreError? error}) async {
    if (!transfer.ongoing) {
      Logger().warning('Transfer is not ongoing', 'TransferController');
      return;
    }

    Logger().info('Cancelling transfer ${transfer.uuid}', 'TransferController(${transfer.runtimeType})');
    // Cancel the transfer on current side
    transfer.dataHandler.cancel();

    // This code is used to send a cancel message to the controller socket
    // This is used to notify the other side that the transfer has been cancelled
    // This is used when the transfer is cancelled on this side
    // This will send the error if there is one, otherwise it will send a generic error
    if (incoming) {
      if (isError) {
        // Error cant be null if isError is true, we binded on the listener
        transfer.report(ErrorReport(error: error!));
        _controlSocket?.close();
      }
    } else {
      // If the transcer is cancelled in this side, we send a cancel message to the other side

      if (_controlSocket == null) {
        Logger().warning('Control socket is null', 'TransferController');
        return;
      }

      try {
        // Notifying the other side that the transfer has been cancelled
        _controlSocket?.write(base64.encode(utf8.encode(jsonEncode({
          'transferUuid': transfer.uuid,
          'type': isError ? 'error' : 'cancel',
          'error': error?.toJson(),
        }))));
        await _controlSocket?.flush();
      } catch (e, stackTrace) {
        Logger().warning('Failed to send cancel message', 'TransferController', error: e, stackTrace: stackTrace);
        _controlSocket?.close();
      }
    }
  }

  _handleDoneOrError(Socket socket) {
    if (transfer.ongoing) {
      Logger().warning('Control socket closed while transfer is ongoing', 'TransferController(${transfer.runtimeType})');
    }
  }
}
