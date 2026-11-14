import 'dart:convert';
import 'dart:math';

const kAiMaxLongEdge = 1280;

/// Size of the screenshot sent to the model: long edge capped, never upscaled.
Point<int> aiScaledSize(int width, int height,
    {int maxLongEdge = kAiMaxLongEdge}) {
  final longEdge = max(width, height);
  if (longEdge <= maxLongEdge) return Point(width, height);
  final k = maxLongEdge / longEdge;
  return Point(max(1, (width * k).round()), max(1, (height * k).round()));
}

/// Maps a point in the sent screenshot to remote desktop coordinates.
Point<int> aiToRemotePoint(
  num x,
  num y, {
  required int sentWidth,
  required int sentHeight,
  required double left,
  required double top,
  required double width,
  required double height,
}) {
  final cx = x.clamp(0, sentWidth - 1);
  final cy = y.clamp(0, sentHeight - 1);
  return Point((left + cx * width / sentWidth).floor(),
      (top + cy * height / sentHeight).floor());
}

class AiKeyCombo {
  final String name;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool command;
  const AiKeyCombo(this.name,
      {this.ctrl = false,
      this.alt = false,
      this.shift = false,
      this.command = false});
}

const _modifierTokens = {
  'ctrl': 'ctrl',
  'control': 'ctrl',
  'control_l': 'ctrl',
  'control_r': 'ctrl',
  'alt': 'alt',
  'alt_l': 'alt',
  'alt_r': 'alt',
  'option': 'alt',
  'shift': 'shift',
  'shift_l': 'shift',
  'shift_r': 'shift',
  'super': 'command',
  'super_l': 'command',
  'super_r': 'command',
  'cmd': 'command',
  'command': 'command',
  'win': 'command',
  'windows': 'command',
  'meta': 'command',
};

const _modifierKeyNames = {
  'ctrl': 'VK_CONTROL',
  'alt': 'VK_MENU',
  'shift': 'VK_SHIFT',
  'command': 'Meta',
};

const _namedKeys = {
  'return': 'VK_RETURN',
  'enter': 'VK_RETURN',
  'kp_enter': 'VK_RETURN',
  'tab': 'VK_TAB',
  'escape': 'VK_ESCAPE',
  'esc': 'VK_ESCAPE',
  'backspace': 'VK_BACK',
  'delete': 'VK_DELETE',
  'del': 'VK_DELETE',
  'space': 'VK_SPACE',
  'up': 'VK_UP',
  'down': 'VK_DOWN',
  'left': 'VK_LEFT',
  'right': 'VK_RIGHT',
  'home': 'VK_HOME',
  'end': 'VK_END',
  'page_up': 'VK_PRIOR',
  'pageup': 'VK_PRIOR',
  'prior': 'VK_PRIOR',
  'page_down': 'VK_NEXT',
  'pagedown': 'VK_NEXT',
  'next': 'VK_NEXT',
  'insert': 'VK_INSERT',
  'print': 'VK_SNAPSHOT',
  'printscreen': 'VK_SNAPSHOT',
  'pause': 'VK_PAUSE',
  'caps_lock': 'VK_CAPITAL',
  'menu': 'Apps',
  'minus': '-',
  'plus': '+',
  'equal': '=',
  'comma': ',',
  'period': '.',
  'slash': '/',
  'backslash': '\\',
  'semicolon': ';',
  'apostrophe': '\'',
  'grave': '`',
  'bracketleft': '[',
  'bracketright': ']',
};

List<String> _splitCombo(String text) {
  final tokens = text.split('+');
  // "ctrl++" and "+" mean the plus key itself.
  if (tokens.length >= 2 && tokens.last.isEmpty) {
    tokens.removeLast();
    tokens[tokens.length - 1] = '+';
  }
  return tokens.map((t) => t.trim()).toList();
}

String? _keyName(String token) {
  final lower = token.toLowerCase();
  final named = _namedKeys[lower];
  if (named != null) return named;
  if (RegExp(r'^f([1-9]|1[0-2])$').hasMatch(lower)) {
    return 'VK_${lower.toUpperCase()}';
  }
  if (token.runes.length != 1) return null;
  if (RegExp(r'^[a-z0-9]$').hasMatch(lower)) return 'VK_${lower.toUpperCase()}';
  return token;
}

/// Parses an xdotool-style key or combo ("Return", "ctrl+s", "alt+Tab") into
/// a key name understood by `sessionInputKey` plus modifier flags.
/// Returns null when the key is unknown.
AiKeyCombo? parseAiKeyCombo(String text) {
  final tokens = _splitCombo(text);
  if (tokens.isEmpty || tokens.any((t) => t.isEmpty)) return null;
  final mods = <String>{};
  for (final t in tokens.sublist(0, tokens.length - 1)) {
    final m = _modifierTokens[t.toLowerCase()];
    if (m == null) return null;
    mods.add(m);
  }
  final last = tokens.last;
  final lastMod = _modifierTokens[last.toLowerCase()];
  String? name;
  if (lastMod != null) {
    name = _modifierKeyNames[lastMod];
    mods.remove(lastMod);
  } else {
    name = _keyName(last);
  }
  if (name == null) return null;
  if (name == 'VK_DELETE' &&
      mods.length == 2 &&
      mods.contains('ctrl') &&
      mods.contains('alt')) {
    return const AiKeyCombo('CTRL_ALT_DEL');
  }
  return AiKeyCombo(name,
      ctrl: mods.contains('ctrl'),
      alt: mods.contains('alt'),
      shift: mods.contains('shift'),
      command: mods.contains('command'));
}

/// Parses the modifier-only string of click and scroll actions ("ctrl+shift").
/// Unknown tokens are ignored.
AiKeyCombo parseAiModifiers(String? text) {
  final mods = <String>{};
  for (final t in (text ?? '').split('+')) {
    final m = _modifierTokens[t.trim().toLowerCase()];
    if (m != null) mods.add(m);
  }
  return AiKeyCombo('',
      ctrl: mods.contains('ctrl'),
      alt: mods.contains('alt'),
      shift: mods.contains('shift'),
      command: mods.contains('command'));
}

/// Actions that only observe or wait; they never need operator approval.
bool aiIsPassiveAction(String name) =>
    name == 'screenshot' || name == 'zoom' || name == 'wait';

String describeAiAction(String name, Map<String, dynamic> input) =>
    input.isEmpty ? name : '$name ${jsonEncode(input)}';
