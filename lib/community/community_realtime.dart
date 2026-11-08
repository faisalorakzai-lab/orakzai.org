import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth/auth_api.dart';

class CommunityRealtime {
  CommunityRealtime(this._auth);

  final AuthApi _auth;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _conversationUpdates = StreamController<Map<String, dynamic>>.broadcast();
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  final _typing = StreamController<Map<String, dynamic>>.broadcast();
  final _presence = StreamController<Map<String, dynamic>>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  io.Socket? _socket;
  bool _refreshing = false;

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<Map<String, dynamic>> get conversationUpdates => _conversationUpdates.stream;
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;
  Stream<Map<String, dynamic>> get typingUpdates => _typing.stream;
  Stream<Map<String, dynamic>> get presenceUpdates => _presence.stream;
  Stream<bool> get connectionUpdates => _connection.stream;
  bool get isConnected => _socket?.connected ?? false;

  Future<void> connect() async {
    if (_socket?.connected == true) return;
    final token = await _auth.readAccessToken();
    if (token == null) return;
    final apiUri = Uri.parse(_auth.apiBaseUrl);
    final origin = apiUri.replace(path: '', query: null, fragment: null).toString();
    final socket = io.io(
      origin,
      <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'auth': {'token': token},
        'autoConnect': false,
        'reconnection': true,
        'reconnectionAttempts': 8,
        'reconnectionDelay': 800,
        'reconnectionDelayMax': 8000,
      },
    );
    _socket?.dispose();
    _socket = socket;
    socket.on('message:new', (dynamic data) {
      final map = _mapOrNull(data);
      if (map != null) _messages.add(map);
    });
    socket.on('conversation:updated', (dynamic data) {
      final map = _mapOrNull(data);
      if (map != null) _conversationUpdates.add(map);
    });
    socket.on('notification:new', (dynamic data) {
      final map = _mapOrNull(data);
      if (map != null) _notifications.add(map);
    });
    socket.on('typing:update', (dynamic data) {
      final map = _mapOrNull(data);
      if (map != null) _typing.add(map);
    });
    socket.on('presence:update', (dynamic data) {
      final map = _mapOrNull(data);
      if (map != null) _presence.add(map);
    });
    socket.onConnect((_) => _connection.add(true));
    socket.onDisconnect((_) => _connection.add(false));
    socket.onConnectError((dynamic error) {
      _connection.add(false);
      if (_refreshing || _socket != socket) return;
      final text = error?.toString() ?? '';
      if (!text.toLowerCase().contains('authentication')) return;
      _refreshing = true;
      unawaited(_refreshAndReconnect(socket));
    });
    socket.connect();
  }

  Future<void> _refreshAndReconnect(io.Socket failedSocket) async {
    try {
      await _auth.refreshSession();
      if (_socket != failedSocket) return;
      failedSocket.dispose();
      _socket = null;
      await connect();
    } catch (_) {
      failedSocket.disconnect();
    } finally {
      _refreshing = false;
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void joinConversation(String conversationId) {
    _socket?.emitWithAck('conversation:join', conversationId, ack: (_) {});
  }

  void leaveConversation(String conversationId) {
    _socket?.emitWithAck('conversation:leave', conversationId, ack: (_) {});
  }

  void typing(String conversationId, {required bool active}) {
    _socket?.emit(active ? 'typing:start' : 'typing:stop', conversationId);
  }

  void watchPresence(List<String> userIds) {
    if (userIds.isEmpty) return;
    _socket?.emitWithAck('presence:watch', {'userIds': userIds}, ack: (_) {});
  }

  void dispose() {
    disconnect();
    _messages.close();
    _conversationUpdates.close();
    _notifications.close();
    _typing.close();
    _presence.close();
    _connection.close();
  }

  Map<String, dynamic>? _mapOrNull(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}
