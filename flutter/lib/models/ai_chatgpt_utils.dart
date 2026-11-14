import 'dart:convert';

import 'package:crypto/crypto.dart';

const kChatGptAuthBase = 'https://auth.openai.com/api/accounts';
const kChatGptResource = 'https://api.openai.com/v1';
const kChatGptScope =
    'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct';
const kChatGptPlanScope = 'chatgpt.tokens.use.direct';
const kChatGptAppName = 'H3 Suporte';

/// Refresh errors after which the stored tokens can no longer be used.
const kChatGptTerminalRefreshErrors = {
  'invalid_grant',
  'invalid_refresh_token',
  'token_expired',
  'refresh_token_expired',
  'refresh_token_invalidated',
  'refresh_token_reused',
};

String chatGptPkceChallenge(String verifier) =>
    base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

Uri chatGptAuthorizeUrl({
  required String? clientId,
  required String hostId,
  required String redirectUri,
  required String state,
  required String nonce,
  required String codeChallenge,
  String? loginHint,
}) {
  final params = <String, String>{
    'client_id': clientId ?? 'dynamic_agent_client',
    if (clientId == null) 'agent_name_hint': kChatGptAppName,
    'ext_agent_host_id': hostId,
    'response_type': 'code',
    'redirect_uri': redirectUri,
    'scope': kChatGptScope,
    'resource': kChatGptResource,
    'state': state,
    'nonce': nonce,
    'code_challenge_method': 'S256',
    'code_challenge': codeChallenge,
    if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
  };
  return Uri.parse('$kChatGptAuthBase/authorize')
      .replace(queryParameters: params);
}

/// Payload of a JWT, without verifying its signature. Only for display data.
Map<String, dynamic> decodeJwtPayload(String jwt) {
  final parts = jwt.split('.');
  if (parts.length < 2) return {};
  try {
    final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final v = jsonDecode(json);
    return v is Map<String, dynamic> ? v : {};
  } catch (_) {
    return {};
  }
}

class ChatGptStreamError implements Exception {
  final String code;
  final String message;
  ChatGptStreamError(this.code, this.message);
  @override
  String toString() => message.isEmpty ? code : '$code: $message';
}

/// Returns the `response` object of the `response.completed` event of a
/// Responses API server-sent event stream, or throws [ChatGptStreamError].
Map<String, dynamic> parseChatGptStream(String body) {
  for (final line in const LineSplitter().convert(body)) {
    if (!line.startsWith('data: ')) continue;
    final dynamic ev;
    try {
      ev = jsonDecode(line.substring(6));
    } catch (_) {
      continue;
    }
    if (ev is! Map) continue;
    final type = ev['type'];
    if (type == 'response.completed' && ev['response'] is Map) {
      return Map<String, dynamic>.from(ev['response']);
    }
    if (type == 'response.failed' || type == 'response.incomplete') {
      final r = ev['response'] is Map ? ev['response'] as Map : const {};
      final err = r['error'] is Map ? r['error'] as Map : const {};
      final reason = r['incomplete_details'] is Map
          ? (r['incomplete_details'] as Map)['reason']
          : null;
      throw ChatGptStreamError(
          (err['code'] ?? reason ?? type).toString(), (err['message'] ?? '').toString());
    }
    if (type == 'error') {
      final err = ev['error'] is Map ? ev['error'] as Map : ev;
      throw ChatGptStreamError(
          (err['code'] ?? 'error').toString(), (err['message'] ?? '').toString());
    }
  }
  throw ChatGptStreamError('stream_incomplete', '');
}

/// Error code of a failed Responses API HTTP reply: `{"error": {"code"}}` or
/// `{"detail": "..."}`.
String chatGptErrorCode(String body) {
  try {
    final v = jsonDecode(body);
    if (v is Map) {
      if (v['error'] is Map && v['error']['code'] != null) {
        return v['error']['code'].toString();
      }
      if (v['detail'] != null) return v['detail'].toString();
      if (v['error'] is String) return v['error'];
    }
  } catch (_) {}
  return body.length > 200 ? body.substring(0, 200) : body;
}

Map<String, dynamic> _fn(String name, String description,
        Map<String, dynamic> properties, List<String> required) =>
    {
      'type': 'function',
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
        'additionalProperties': false,
      },
      'strict': false,
    };

const _point = {
  'type': 'array',
  'items': {'type': 'integer'},
  'description': '[x, y] in pixels of the latest screenshot',
};
const _mods = {
  'type': 'string',
  'description': 'Optional modifier keys held during the action, e.g. "ctrl" or "ctrl+shift"',
};

/// Computer actions offered to ChatGPT models as plain functions, because the
/// built-in computer tool is not available with ChatGPT plan usage. Names and
/// arguments match the Claude computer toolset so one executor serves both.
final List<Map<String, dynamic>> kChatGptComputerTools = [
  _fn('screenshot', 'Capture the current remote screen.', {}, []),
  _fn('zoom', 'Capture a region of the remote screen at higher detail.', {
    'region': {
      'type': 'array',
      'items': {'type': 'integer'},
      'description': '[x0, y0, x1, y1] in pixels of the latest full screenshot',
    },
  }, ['region']),
  _fn('left_click', 'Left click.', {'coordinate': _point, 'text': _mods}, ['coordinate']),
  _fn('right_click', 'Right click.', {'coordinate': _point, 'text': _mods}, ['coordinate']),
  _fn('double_click', 'Double left click.', {'coordinate': _point, 'text': _mods}, ['coordinate']),
  _fn('mouse_move', 'Move the mouse pointer.', {'coordinate': _point}, ['coordinate']),
  _fn('left_click_drag', 'Drag with the left button held.', {
    'start_coordinate': _point,
    'coordinate': _point,
  }, ['start_coordinate', 'coordinate']),
  _fn('scroll', 'Scroll the mouse wheel.', {
    'coordinate': _point,
    'scroll_direction': {
      'type': 'string',
      'enum': ['up', 'down', 'left', 'right'],
    },
    'scroll_amount': {'type': 'integer', 'description': 'Wheel clicks, 1-30'},
  }, ['coordinate', 'scroll_direction', 'scroll_amount']),
  _fn('type', 'Type text on the remote keyboard.', {
    'text': {'type': 'string'},
  }, ['text']),
  _fn('key', 'Press a key or combination, xdotool style: "Return", "ctrl+s", "alt+Tab".', {
    'text': {'type': 'string'},
    'repeat': {'type': 'integer', 'description': 'Times to press, 1-100'},
  }, ['text']),
  _fn('wait', 'Wait before the next action.', {
    'duration': {'type': 'number', 'description': 'Seconds, up to 10'},
  }, ['duration']),
];
