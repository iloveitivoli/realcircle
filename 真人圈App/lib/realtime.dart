// 真人圈 RealCircle — 实时推送层(WebSocket)
// 与后端 /ws 建立长连接,接收 message / notify 事件并广播给各页面。
// 断线自动重连;轮询仍保留为降级兜底,二者叠加保证消息不丢。
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'api.dart';

class Realtime {
  Realtime._();
  static final Realtime instance = Realtime._();

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _reconnect;
  int _retry = 0;
  bool _wantOpen = false;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  /// 解码后的事件流:{ type: 'message'|'notify'|'connected', ... }
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool get connected => _ch != null;

  void connect() {
    _wantOpen = true;
    if (_ch != null) return;            // 已连接/连接中
    final token = Api.token;
    if (token == null) return;
    // http(s)://host:port → ws(s)://host:port/ws;token 经子协议传递(避免出现在 URL 日志里)
    final wsUrl = '${Api.baseUrl.replaceFirst('http', 'ws')}/ws';
    try {
      _ch = WebSocketChannel.connect(Uri.parse(wsUrl), protocols: [token]);
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    _sub = _ch!.stream.listen(
      (data) {
        _retry = 0;
        try {
          final obj = jsonDecode(data as String);
          if (obj is Map<String, dynamic>) _events.add(obj);
        } catch (_) {/* 忽略非 JSON 帧 */}
      },
      onError: (_) => _onClose(),
      onDone: _onClose,
      cancelOnError: true,
    );
  }

  void _onClose() {
    _sub?.cancel();
    _sub = null;
    _ch = null;
    if (_wantOpen && Api.loggedIn) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    _retry = (_retry + 1).clamp(1, 6);
    _reconnect = Timer(Duration(milliseconds: 800 * _retry), () {
      if (_wantOpen && Api.loggedIn) connect();
    });
  }

  void disconnect() {
    _wantOpen = false;
    _reconnect?.cancel();
    _sub?.cancel();
    _sub = null;
    final c = _ch;
    _ch = null;
    try {
      c?.sink.close(ws_status.normalClosure);
    } catch (_) {}
  }
}
