import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'ai_chatgpt_utils.dart';
import 'platform_model.dart';

const _kOptClientId = 'ai-agent-chatgpt-client-id';
const _kOptHostId = 'ai-agent-chatgpt-host-id';
const _kOptTokens = 'ai-agent-chatgpt-tokens';
const _kPreferredPort = 1455;

class ChatGptLoginRequired implements Exception {
  @override
  String toString() => 'ChatGPT login required';
}

/// "Sign in with ChatGPT" with plan usage: OAuth 2.0 authorization code with
/// PKCE and a loopback redirect, as documented for local apps.
class ChatGptAuth {
  Future<void>? _refreshing;

  Map<String, dynamic> get _tokens {
    final raw = bind.mainGetLocalOption(key: _kOptTokens);
    if (raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> v) =>
      bind.mainSetLocalOption(key: _kOptTokens, value: v.isEmpty ? '' : jsonEncode(v));

  bool get isSignedIn => (_tokens['refresh_token'] ?? '').toString().isNotEmpty;

  String get email => (_tokens['email'] ?? '').toString();

  String? get _clientId {
    final v = bind.mainGetLocalOption(key: _kOptClientId);
    return v.isEmpty ? null : v;
  }

  Future<String> _hostId() async {
    var v = bind.mainGetLocalOption(key: _kOptHostId);
    if (v.isEmpty) {
      v = 'urn:uuid:${const Uuid().v4()}';
      await bind.mainSetLocalOption(key: _kOptHostId, value: v);
    }
    return v;
  }

  static String _random() {
    final r = Random.secure();
    return base64Url
        .encode(List<int>.generate(32, (_) => r.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<void> logout() => _saveTokens({});

  Future<void> login() async {
    final verifier = _random();
    final state = _random();
    final nonce = _random();
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, _kPreferredPort);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    final redirectUri = 'http://127.0.0.1:${server.port}/auth/callback';
    final savedClientId = _clientId;
    final Map<String, String> query;
    try {
      final url = chatGptAuthorizeUrl(
          clientId: savedClientId,
          hostId: await _hostId(),
          redirectUri: redirectUri,
          state: state,
          nonce: nonce,
          codeChallenge: chatGptPkceChallenge(verifier),
          loginHint: email);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not open the browser';
      }
      query = await _waitForCallback(server).timeout(const Duration(minutes: 10));
    } finally {
      await server.close(force: true);
    }
    if (query['state'] != state) throw 'Invalid login state';
    if (query['error'] != null) throw 'ChatGPT login: ${query['error']}';
    final code = query['code'];
    if (code == null || code.isEmpty) throw 'ChatGPT login returned no code';
    final returnedClientId = query['client_id'];
    if (savedClientId != null &&
        returnedClientId != null &&
        returnedClientId != savedClientId) {
      throw 'ChatGPT login returned a different client';
    }
    final clientId = savedClientId ?? returnedClientId;
    if (clientId == null || clientId.isEmpty) throw 'ChatGPT login returned no client id';

    final resp = await http.post(Uri.parse('$kChatGptAuthBase/oauth/token'), body: {
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirectUri,
      'resource': kChatGptResource,
    });
    final tok = _decode(resp);
    if (resp.statusCode != 200) {
      throw 'ChatGPT login: HTTP ${resp.statusCode} ${tok['error'] ?? ''}';
    }
    if (!(tok['scope'] ?? '').toString().contains(kChatGptPlanScope)) {
      throw 'ChatGPT plan usage was not granted';
    }
    final idToken = (tok['id_token'] ?? '').toString();
    final claims = decodeJwtPayload(idToken);
    if (claims['nonce'] != null && claims['nonce'] != nonce) {
      throw 'Invalid login nonce';
    }
    if (savedClientId == null) {
      await bind.mainSetLocalOption(key: _kOptClientId, value: clientId);
    }
    await _store(tok, email: (claims['email'] ?? '').toString());
  }

  Future<Map<String, String>> _waitForCallback(HttpServer server) async {
    await for (final req in server) {
      if (req.uri.path != '/auth/callback') {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        continue;
      }
      req.response.headers.contentType = ContentType.html;
      req.response.write(
          '<meta charset="utf-8"><p>H3 Suporte: login concluído. Pode fechar esta aba.</p>');
      await req.response.close();
      return req.uri.queryParameters;
    }
    throw 'Login cancelled';
  }

  Map<String, dynamic> _decode(http.Response resp) {
    try {
      final v = jsonDecode(utf8.decode(resp.bodyBytes));
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _store(Map<String, dynamic> tok, {String? email}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresIn = tok['expires_in'] is num ? (tok['expires_in'] as num).toInt() : 3600;
    final old = _tokens;
    await _saveTokens({
      'access_token': tok['access_token'],
      'refresh_token': tok['refresh_token'] ?? old['refresh_token'],
      'id_token': tok['id_token'] ?? old['id_token'],
      'scope': tok['scope'] ?? old['scope'],
      'expires_at': now + expiresIn,
      'earliest_refresh_at': tok['earliest_refresh_at'],
      'email': (email == null || email.isEmpty) ? old['email'] : email,
    });
  }

  /// A valid access token, refreshed when it is about to expire.
  /// Throws [ChatGptLoginRequired] when the user must sign in again.
  Future<String> accessToken({bool forceRefresh = false}) async {
    final t = _tokens;
    if ((t['refresh_token'] ?? '').toString().isEmpty) throw ChatGptLoginRequired();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresAt = t['expires_at'] is num ? (t['expires_at'] as num).toInt() : 0;
    final earliest =
        t['earliest_refresh_at'] is num ? (t['earliest_refresh_at'] as num).toInt() : 0;
    final due = now >= expiresAt - 60;
    if (due || (forceRefresh && now >= earliest)) {
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
      await _refreshing;
    }
    final token = (_tokens['access_token'] ?? '').toString();
    if (token.isEmpty) throw ChatGptLoginRequired();
    return token;
  }

  Future<void> _refresh() async {
    final clientId = _clientId;
    final refreshToken = (_tokens['refresh_token'] ?? '').toString();
    if (clientId == null || refreshToken.isEmpty) throw ChatGptLoginRequired();
    final resp = await http.post(Uri.parse('$kChatGptAuthBase/oauth/token'), body: {
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': refreshToken,
    });
    final tok = _decode(resp);
    if (resp.statusCode == 200) {
      await _store(tok);
      return;
    }
    final code = (tok['error'] ?? '').toString();
    if (kChatGptTerminalRefreshErrors.contains(code)) {
      await logout();
      throw ChatGptLoginRequired();
    }
    throw 'ChatGPT token refresh failed: HTTP ${resp.statusCode} $code';
  }
}
