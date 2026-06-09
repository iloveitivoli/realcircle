// 真人圈 API 客户端 — 对接与 Web 端完全相同的后端 REST 接口
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int status;
  final String code; // 后端错误码(可被本地化),如 AI_BLOCKED
  ApiException(this.status, this.code);
  @override
  String toString() => code;
}

class Api {
  // 真机/模拟器请改为你的服务器地址:
  //   Android 模拟器访问宿主机: http://10.0.2.2:3000
  //   iOS 模拟器: http://localhost:3000
  //   生产: https://your-domain.com
  static String baseUrl = const String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static String? _token;
  static Map<String, dynamic>? me;

  static Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString('token');
  }

  static Future<void> _setToken(String? t) async {
    _token = t;
    final sp = await SharedPreferences.getInstance();
    if (t == null) {
      await sp.remove('token');
    } else {
      await sp.setString('token', t);
    }
  }

  static bool get loggedIn => _token != null;
  static String? get token => _token; // 供实时层(WebSocket)鉴权

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<dynamic> _req(String method, String path,
      [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final req = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final streamed = await req.send().timeout(const Duration(seconds: 15));
    final res = await http.Response.fromStream(streamed);
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, (data['error'] ?? 'HTTP ${res.statusCode}').toString());
    }
    return data;
  }

  // ---- 账号(多国区号 dial + 短信验证码 code) ----
  static Future<Map<String, dynamic>> register(String phone, String pwd, String nick,
      {String dial = '86', String? code}) async {
    final d = await _req('POST', '/api/register',
        {'dial': dial, 'phone': phone, 'password': pwd, 'nickname': nick, if (code != null) 'code': code});
    await _setToken(d['token']);
    me = d['user'];
    return d;
  }

  static Future<Map<String, dynamic>> login(String phone, String pwd, {String dial = '86'}) async {
    final d = await _req('POST', '/api/login', {'dial': dial, 'phone': phone, 'password': pwd});
    await _setToken(d['token']);
    me = d['user'];
    return d;
  }

  // 发送短信验证码;mock+开发模式会回显 devCode 便于自测
  static Future<String?> sendSms(String dial, String phone) async {
    final d = await _req('POST', '/api/sms/send', {'dial': dial, 'phone': phone});
    return d['devCode'] as String?;
  }

  static Future<void> logout() async {
    try { await _req('POST', '/api/logout'); } catch (_) {}
    await _setToken(null);
    me = null;
  }

  static Future<Map<String, dynamic>> fetchMe() async {
    final d = await _req('GET', '/api/me');
    me = d['user'];
    return d;
  }

  static Future<void> updateMe({String? nickname, String? bio}) async {
    final d = await _req('POST', '/api/me', {
      if (nickname != null) 'nickname': nickname,
      if (bio != null) 'bio': bio,
    });
    me = d['user'];
  }

  // ---- 活体验证(provider 抽象;仅上传特征/会话,绝不上传原图)----
  // mock:传 faceSample。生产 SDK(FaceTec/iProov)把会话结果经 providerData 透传给后端校验:
  //   FaceTec → {'sessionId':..., 'faceScan':...};iProov → {'token':...}
  static Future<Map<String, dynamic>> liveness(String faceSample, {Map<String, dynamic>? providerData}) async {
    final d = await _req('POST', '/api/liveness', {
      'faceSample': faceSample,
      ...?providerData,
    });
    me = d['user'];
    return d;
  }

  // ---- 内容 ----
  static Future<List> posts({String? kind, String? scope}) async {
    final q = <String>[];
    if (kind != null) q.add('kind=$kind');
    if (scope != null) q.add('scope=$scope');
    final qs = q.isEmpty ? '' : '?' + q.join('&');
    final d = await _req('GET', '/api/posts$qs');
    return d['posts'] as List;
  }

  static Future<List> stories() async => (await _req('GET', '/api/stories'))['stories'] as List;

  static Future<void> createPost(String text,
          {String kind = 'text', bool direct = true, bool story = false, String? media, String? mediaType}) =>
      _req('POST', '/api/posts', {
        'text': text, 'kind': kind, 'direct': direct, 'story': story,
        if (media != null) 'media': media, if (mediaType != null) 'mediaType': mediaType,
      });

  // 二进制流式上传图片/视频,返回 {url, type}
  static Future<Map<String, dynamic>> uploadMedia(List<int> bytes, String contentType) async {
    final res = await http.put(Uri.parse('$baseUrl/api/upload'),
        headers: {'Content-Type': contentType, if (_token != null) 'Authorization': 'Bearer $_token'},
        body: bytes).timeout(const Duration(seconds: 60));
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : {};
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, (data['error'] ?? 'HTTP ${res.statusCode}').toString());
    }
    return Map<String, dynamic>.from(data);
  }

  static String mediaUrl(String path) => path.startsWith('http') ? path : '$baseUrl$path';

  static Future<Map> like(String id) async => await _req('POST', '/api/posts/$id/like');
  static Future<Map> report(String id) async => await _req('POST', '/api/posts/$id/report');
  static Future<void> deletePost(String id) => _req('DELETE', '/api/posts/$id');

  static Future<List> comments(String pid) async => (await _req('GET', '/api/posts/$pid/comments'))['comments'] as List;
  static Future<void> addComment(String pid, String text) => _req('POST', '/api/posts/$pid/comments', {'text': text});

  // ---- 社交 ----
  static Future<Map> follow(String uid) async => await _req('POST', '/api/users/$uid/follow');
  static Future<Map<String, dynamic>> user(String uid) async =>
      Map<String, dynamic>.from(await _req('GET', '/api/users/$uid'));
  static Future<List> searchUsers(String q) async =>
      (await _req('GET', '/api/users?q=${Uri.encodeComponent(q)}'))['users'] as List;

  // ---- 通知 ----
  static Future<Map<String, dynamic>> notifications() async =>
      Map<String, dynamic>.from(await _req('GET', '/api/notifications'));
  static Future<void> readNotifications() => _req('POST', '/api/notifications/read');

  // ---- 私信 ----
  static Future<List> conversations() async => (await _req('GET', '/api/conversations'))['conversations'] as List;
  static Future<Map<String, dynamic>> messages(String withId) async =>
      Map<String, dynamic>.from(await _req('GET', '/api/messages?with=$withId'));
  static Future<void> sendMessage(String to, String text) => _req('POST', '/api/messages', {'to': to, 'text': text});

  // ---- 活动 ----
  static Future<List> events() async => (await _req('GET', '/api/events'))['events'] as List;
  static Future<Map> joinEvent(String id) async => await _req('POST', '/api/events/$id/join');
  static Future<void> createEvent(String title, String time, String fee, int cap) =>
      _req('POST', '/api/events', {'title': title, 'time': time, 'fee': fee, 'cap': cap});
}
