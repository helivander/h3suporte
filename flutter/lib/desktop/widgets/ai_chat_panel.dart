import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/h3_estilo.dart';
import '../../models/ai_agent_model.dart';
import '../../models/ai_models.dart';

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
      : model.provider == kAiProviderGemini
          ? model.geminiKey.isEmpty
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
    final t = H3Tokens.of(context);
    return Material(
      elevation: 8,
      color: t.painel,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: t.linha2)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _header(t),
          Divider(height: 1, color: t.linha),
          Expanded(child: _showSettings ? _settings(t) : _conversation(t)),
        ],
      ),
    );
  }

  Widget _headerButton(
          H3Tokens t, String tip, IconData icon, VoidCallback? onTap) =>
      Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Tooltip(
          message: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: t.painel,
                  border: Border.all(color: t.linha2),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon,
                  size: 16,
                  color: onTap == null ? t.apagado.withOpacity(0.4) : t.apagado),
            ),
          ),
        ),
      );

  Widget _header(H3Tokens t) {
    final subtitle = model.provider == kAiProviderChatGpt
        ? 'ChatGPT · ${model.chatGptModel}'
        : model.provider == kAiProviderGemini
            ? 'Gemini · ${model.geminiModel}'
            : 'Claude · ${model.model}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: t.destaque.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.smart_toy_outlined, size: 20, color: t.destaque),
        ),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(translate('AI assistant'),
              style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 15, color: t.texto)),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: t.apagado)),
        ])),
        Obx(() => _headerButton(
            t,
            translate('Clear'),
            Icons.delete_outline,
            model.status.value == AiAgentStatus.idle ? model.clear : null)),
        _headerButton(t, translate('Settings'), Icons.settings_outlined,
            () => setState(() => _showSettings = !_showSettings)),
        _headerButton(t, translate('Close'), Icons.close, model.hidePanel),
      ]),
    );
  }

  InputDecoration _inputDecoration(H3Tokens t,
      {String? labelText, String? hintText}) {
    OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c));
    return InputDecoration(
        labelText: labelText,
        hintText: hintText,
        isDense: true,
        filled: true,
        fillColor: t.fundo,
        labelStyle: TextStyle(color: t.apagado),
        hintStyle: TextStyle(color: t.apagado),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: border(t.linha2),
        focusedBorder: border(t.destaque),
        border: border(t.linha2));
  }

  Widget _providerSelector(H3Tokens t) {
    Widget item(String p, String label) {
      final on = _provider == p;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => setState(() => _provider = p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            decoration: BoxDecoration(
                color: on ? t.painel2 : Colors.transparent,
                border: Border.all(color: on ? t.linha2 : Colors.transparent),
                borderRadius: BorderRadius.circular(7)),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: on ? t.texto : t.apagado)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: t.fundo,
          border: Border.all(color: t.linha2),
          borderRadius: BorderRadius.circular(10)),
      child: IntrinsicHeight(
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              item(kAiProviderClaude, translate('Claude (API key)')),
              item(kAiProviderChatGpt,
                  translate('ChatGPT (sign in with your account)')),
            ]),
      ),
    );
  }

  Widget _notice(H3Tokens t, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: t.aviso.withOpacity(0.08),
            border: Border.all(color: t.aviso.withOpacity(0.45)),
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: t.aviso),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, height: 1.4, color: t.texto))),
        ]),
      );

  Widget _settings(H3Tokens t) {
    field(String label, TextEditingController c, {bool secret = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: c,
              obscureText: secret,
              decoration: _inputDecoration(t, labelText: translate(label))),
        );
    final hint = TextStyle(fontSize: 12, color: t.apagado);
    if (_provider == kAiProviderGemini) {
      return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
              'O provedor Gemini é configurado em Configurações > IA (chave da API e modelo).',
              style: hint));
    }
    return ListView(padding: const EdgeInsets.all(12), children: [
      _providerSelector(t),
      const SizedBox(height: 14),
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
                  style: TextStyle(fontSize: 12, color: t.perigo))),
        field('Model', _chatGptModel),
        Text(translate('ai-agent-chatgpt-plan-tip'), style: hint),
        const SizedBox(height: 12),
      ],
      _notice(t, translate('ai-agent-privacy-tip')),
      const SizedBox(height: 12),
      Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
              onPressed: _saveSettings, child: Text(translate('OK')))),
    ]);
  }

  Widget _conversation(H3Tokens t) {
    return Column(children: [
      Expanded(
          child: Obx(() => model.entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: _notice(t, translate('ai-agent-privacy-tip')))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: model.entries.length,
                  itemBuilder: (_, i) => _entry(t, model.entries[i])))),
      Obx(() => model.status.value == AiAgentStatus.awaitingApproval
          ? _approval(t)
          : const SizedBox.shrink()),
      Obx(() => model.status.value == AiAgentStatus.running
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(translate('IA no controle'),
                        style: TextStyle(fontSize: 12, color: t.apagado)),
                    const SizedBox(height: 6),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            minHeight: 6,
                            color: t.destaque,
                            backgroundColor: t.linha)),
                  ]))
          : const SizedBox.shrink()),
      Divider(height: 1, color: t.linha),
      Obx(() => Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              Expanded(
                  child: Text(translate('Confirm each action'),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.texto))),
              Switch(
                  value: model.confirmEach.value,
                  activeColor: t.destaqueTinta,
                  activeTrackColor: t.destaque,
                  inactiveTrackColor: t.linha2,
                  inactiveThumbColor: t.apagado,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) => model.confirmEach.value = v),
            ]),
          )),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
              child: TextField(
                  controller: _input,
                  focusNode: _inputNode,
                  minLines: 1,
                  maxLines: 5,
                  style: TextStyle(color: t.texto),
                  decoration: _inputDecoration(t,
                      hintText: translate(
                          'Describe the task for the remote computer')))),
          const SizedBox(width: 8),
          Obx(() => model.status.value == AiAgentStatus.idle
              ? _actionButton(Icons.send, translate('Send'), t.destaque,
                  t.destaqueTinta, _send)
              : _actionButton(Icons.stop, translate('Stop'), Colors.transparent,
                  t.perigo, model.stop,
                  border: t.perigo)),
        ]),
      ),
    ]);
  }

  Widget _actionButton(
          IconData icon, String tip, Color bg, Color fg, VoidCallback onTap,
          {Color? border}) =>
      Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: bg,
                border: border == null ? null : Border.all(color: border),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: fg),
          ),
        ),
      );

  Widget _approval(H3Tokens t) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: t.aviso.withOpacity(0.08),
          border: Border.all(color: t.aviso.withOpacity(0.55)),
          borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: t.aviso),
          const SizedBox(width: 8),
          Expanded(
              child: Text(translate('The AI wants to run these actions'),
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: t.aviso))),
        ]),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                for (final a in model.pendingActions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(a,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: t.texto)),
                  )
              ])),
        ),
        const SizedBox(height: 10),
        Row(children: [
          ElevatedButton(
              onPressed: () => model.approve(true),
              child: Text(translate('Accept'))),
          const SizedBox(width: 8),
          OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: t.texto,
                  side: BorderSide(color: t.linha2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: () => model.approve(false),
              child: Text(translate('Decline'))),
        ]),
      ]),
    );
  }

  Widget _entry(H3Tokens t, AiChatEntry e) {
    switch (e.kind) {
      case AiEntryKind.user:
      case AiEntryKind.assistant:
        final mine = e.kind == AiEntryKind.user;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
                color: mine ? t.destaque : t.fundo,
                border: mine ? null : Border.all(color: t.linha2),
                borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(14),
                    topRight: const Radius.circular(14),
                    bottomLeft: Radius.circular(mine ? 14 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 14))),
            child: SelectableText(e.text,
                style: TextStyle(
                    height: 1.4, color: mine ? t.destaqueTinta : t.texto)),
          ),
        );
      case AiEntryKind.action:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: t.painel2,
                border: Border.all(color: t.linha2),
                borderRadius: BorderRadius.circular(6)),
            child: Text(e.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'monospace', fontSize: 12, color: t.apagado)),
          ),
        );
      case AiEntryKind.info:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(e.text,
              style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: t.apagado)),
        );
      case AiEntryKind.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: SelectableText(e.text,
              style: TextStyle(fontSize: 12, color: t.perigo)),
        );
    }
  }
}
