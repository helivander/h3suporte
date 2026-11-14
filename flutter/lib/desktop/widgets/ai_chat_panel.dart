import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../models/ai_agent_model.dart';

class AiChatPanel extends StatefulWidget {
  final AiAgentModel model;
  const AiChatPanel({Key? key, required this.model}) : super(key: key);

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _inputNode;
  late final StreamSubscription _entriesSub;
  late bool _showSettings;

  late final _apiKey = TextEditingController(text: widget.model.apiKey);
  late final _modelName = TextEditingController(text: widget.model.model);
  late final _baseUrl = TextEditingController(text: widget.model.baseUrl);
  late final _chatGptModel =
      TextEditingController(text: widget.model.chatGptModel);
  late String _provider = widget.model.provider;
  bool _signingIn = false;
  String _loginError = '';

  AiAgentModel get model => widget.model;

  @override
  void initState() {
    super.initState();
    _showSettings = _needsSetup;
    _inputNode = FocusNode(onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        _send();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    });
    _entriesSub = model.entries.listen((_) => _scrollToEnd());
    if (!_showSettings) _inputNode.requestFocus();
  }

  @override
  void dispose() {
    _entriesSub.cancel();
    _input.dispose();
    _scroll.dispose();
    _inputNode.dispose();
    _apiKey.dispose();
    _modelName.dispose();
    _baseUrl.dispose();
    _chatGptModel.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    model.send(text);
  }

  bool get _needsSetup => model.provider == kAiProviderChatGpt
      ? !model.chatGpt.isSignedIn
      : model.apiKey.isEmpty;

  Future<void> _saveSettings() async {
    await model.saveSettings(
        apiKey: _apiKey.text,
        model: _modelName.text,
        baseUrl: _baseUrl.text,
        provider: _provider,
        chatGptModel: _chatGptModel.text);
    if (mounted) setState(() => _showSettings = _needsSetup);
  }

  Future<void> _chatGptLogin() async {
    setState(() {
      _signingIn = true;
      _loginError = '';
    });
    try {
      await model.chatGpt.login();
    } catch (e) {
      _loginError = e.toString();
    }
    if (mounted) setState(() => _signingIn = false);
  }

  Future<void> _chatGptLogout() async {
    await model.chatGpt.logout();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: MyTheme.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(child: _showSettings ? _settings() : _conversation()),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Row(children: [
        const Icon(Icons.smart_toy_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text(translate('AI assistant'),
                style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
            tooltip: translate('Settings'),
            iconSize: 18,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => setState(() => _showSettings = !_showSettings)),
        Obx(() => IconButton(
            tooltip: translate('Clear'),
            iconSize: 18,
            icon: const Icon(Icons.delete_outline),
            onPressed:
                model.status.value == AiAgentStatus.idle ? model.clear : null)),
        IconButton(
            tooltip: translate('Close'),
            iconSize: 18,
            icon: const Icon(Icons.close),
            onPressed: model.hidePanel),
      ]),
    );
  }

  Widget _settings() {
    field(String label, TextEditingController c, {bool secret = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: c,
              obscureText: secret,
              decoration: InputDecoration(
                  labelText: translate(label),
                  isDense: true,
                  border: const OutlineInputBorder())),
        );
    final hint = TextStyle(fontSize: 12, color: Theme.of(context).hintColor);
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final p in [kAiProviderClaude, kAiProviderChatGpt])
        RadioListTile<String>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: p,
            groupValue: _provider,
            title: Text(translate(p == kAiProviderChatGpt
                ? 'ChatGPT (sign in with your account)'
                : 'Claude (API key)')),
            onChanged: (v) => setState(() => _provider = v ?? _provider)),
      const SizedBox(height: 8),
      if (_provider == kAiProviderClaude) ...[
        field('API key', _apiKey, secret: true),
        field('Model', _modelName),
        field('API address', _baseUrl),
      ] else ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(
                child: Text(
                    model.chatGpt.isSignedIn
                        ? '${translate('Signed in')}: ${model.chatGpt.email}'
                        : translate('Not signed in'),
                    style: hint)),
            if (_signingIn)
              const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (model.chatGpt.isSignedIn)
              TextButton(
                  onPressed: _chatGptLogout, child: Text(translate('Logout')))
            else
              ElevatedButton(
                  onPressed: _chatGptLogin,
                  child: Text(translate('Sign in with ChatGPT'))),
          ]),
        ),
        if (_loginError.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SelectableText(_loginError,
                  style: const TextStyle(fontSize: 12, color: Colors.red))),
        field('Model', _chatGptModel),
        Text(translate('ai-agent-chatgpt-plan-tip'), style: hint),
        const SizedBox(height: 12),
      ],
      Text(translate('ai-agent-privacy-tip'),
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      const SizedBox(height: 12),
      Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
              onPressed: _saveSettings, child: Text(translate('OK')))),
    ]);
  }

  Widget _conversation() {
    return Column(children: [
      Expanded(
          child: Obx(() => model.entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(translate('ai-agent-privacy-tip'),
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).hintColor)))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(8),
                  itemCount: model.entries.length,
                  itemBuilder: (_, i) => _entry(model.entries[i])))),
      Obx(() => model.status.value == AiAgentStatus.awaitingApproval
          ? _approval()
          : const SizedBox.shrink()),
      const Divider(height: 1),
      Obx(() => CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Text(translate('Confirm each action')),
          value: model.confirmEach.value,
          onChanged: (v) => model.confirmEach.value = v ?? true)),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
              child: TextField(
                  controller: _input,
                  focusNode: _inputNode,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                      hintText: translate(
                          'Describe the task for the remote computer'),
                      isDense: true,
                      border: const OutlineInputBorder()))),
          Obx(() => model.status.value == AiAgentStatus.idle
              ? IconButton(
                  tooltip: translate('Send'),
                  icon: const Icon(Icons.send),
                  color: MyTheme.accent,
                  onPressed: _send)
              : IconButton(
                  tooltip: translate('Stop'),
                  icon: const Icon(Icons.stop_circle_outlined),
                  color: Colors.red,
                  onPressed: model.stop)),
        ]),
      ),
    ]);
  }

  Widget _approval() {
    return Container(
      width: double.infinity,
      color: MyTheme.accent.withOpacity(0.08),
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(translate('The AI wants to run these actions'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                for (final a in model.pendingActions)
                  Text(a,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12))
              ])),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
              onPressed: () => model.approve(false),
              child: Text(translate('Decline'))),
          const SizedBox(width: 8),
          ElevatedButton(
              onPressed: () => model.approve(true),
              child: Text(translate('Accept'))),
        ]),
      ]),
    );
  }

  Widget _entry(AiChatEntry e) {
    final theme = Theme.of(context);
    switch (e.kind) {
      case AiEntryKind.user:
      case AiEntryKind.assistant:
        final mine = e.kind == AiEntryKind.user;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
                color: mine ? MyTheme.accent : theme.cardColor,
                borderRadius: BorderRadius.circular(8)),
            child: SelectableText(e.text,
                style: TextStyle(color: mine ? Colors.white : null)),
          ),
        );
      case AiEntryKind.action:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text('› ${e.text}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: theme.hintColor)),
        );
      case AiEntryKind.info:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(e.text,
              style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: theme.hintColor)),
        );
      case AiEntryKind.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: SelectableText(e.text,
              style: const TextStyle(fontSize: 12, color: Colors.red)),
        );
    }
  }
}
