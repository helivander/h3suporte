import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/h3_home_layout.dart';
import 'package:flutter_hbb/models/ai_agent_model.dart';
import 'package:flutter_hbb/models/ai_chatgpt_auth.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// Configuração do assistente de IA em Configurações > IA. A sessão remota só usa o chat.
class IaConfig extends StatefulWidget {
  const IaConfig({super.key});

  @override
  State<IaConfig> createState() => _IaConfigState();
}

class _IaConfigState extends State<IaConfig> {
  final _auth = ChatGptAuth();
  String _get(String k) => bind.mainGetLocalOption(key: k);

  late final _apiKey = TextEditingController(text: _get(kAiOptionApiKey));
  late final _modelo = TextEditingController(
      text: _get(kAiOptionModel).isEmpty ? kAiDefaultModel : _get(kAiOptionModel));
  late final _url = TextEditingController(
      text: _get(kAiOptionBaseUrl).isEmpty
          ? kAiDefaultBaseUrl
          : _get(kAiOptionBaseUrl));
  late final _modeloGpt = TextEditingController(
      text: _get(kAiOptionChatGptModel).isEmpty
          ? kAiDefaultChatGptModel
          : _get(kAiOptionChatGptModel));
  late String _provedor = _get(kAiOptionProvider) == kAiProviderChatGpt
      ? kAiProviderChatGpt
      : kAiProviderClaude;
  late bool _abrirAuto = _get(kAiOptionAutoOpen) != 'N';
  late bool _confirmar = _get(kAiOptionConfirmEach) != 'N';
  bool _entrando = false;
  bool _salvo = false;
  String _erro = '';

  @override
  void dispose() {
    _apiKey.dispose();
    _modelo.dispose();
    _url.dispose();
    _modeloGpt.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    Future<void> s(String k, String v) =>
        bind.mainSetLocalOption(key: k, value: v.trim());
    await s(kAiOptionProvider, _provedor);
    await s(kAiOptionApiKey, _apiKey.text);
    await s(kAiOptionModel, _modelo.text);
    await s(kAiOptionBaseUrl, _url.text);
    await s(kAiOptionChatGptModel, _modeloGpt.text);
    await s(kAiOptionAutoOpen, _abrirAuto ? 'Y' : 'N');
    await s(kAiOptionConfirmEach, _confirmar ? 'Y' : 'N');
    if (mounted) setState(() => _salvo = true);
  }

  Future<void> _entrar() async {
    setState(() {
      _entrando = true;
      _erro = '';
    });
    try {
      await _auth.login();
    } catch (e) {
      _erro = e.toString();
    }
    if (mounted) setState(() => _entrando = false);
  }

  InputDecoration _dec(String rotulo) {
    OutlineInputBorder b(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c));
    return InputDecoration(
        labelText: rotulo,
        isDense: true,
        filled: true,
        fillColor: H3Cores.fundo,
        labelStyle: TextStyle(color: H3Cores.apagado),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: b(H3Cores.linha2),
        focusedBorder: b(H3Cores.destaque));
  }

  Widget _campo(String rotulo, TextEditingController c, {bool segredo = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: c,
            obscureText: segredo,
            style: TextStyle(color: H3Cores.texto),
            onChanged: (_) => setState(() => _salvo = false),
            decoration: _dec(rotulo)),
      );

  Widget _opcao(String p, String rotulo) {
    final on = _provedor == p;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          _provedor = p;
          _salvo = false;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? H3Cores.destaque.withOpacity(0.15) : H3Cores.painel2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? H3Cores.destaque : H3Cores.linha2),
          ),
          child: Text(rotulo,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: on ? H3Cores.destaque : H3Cores.texto)),
        ),
      ),
    );
  }

  Widget _chave(String titulo, String sub, bool v, ValueChanged<bool> f) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: H3Cores.texto)),
              Text(sub, style: TextStyle(fontSize: 11.5, color: H3Cores.apagado)),
            ]),
          ),
          Switch(
              value: v,
              activeColor: Colors.white,
              activeTrackColor: H3Cores.destaque,
              inactiveTrackColor: H3Cores.linha2,
              inactiveThumbColor: Colors.white,
              onChanged: (x) => setState(() {
                    f(x);
                    _salvo = false;
                  })),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final apagado = TextStyle(fontSize: 12, color: H3Cores.apagado);
    return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: H3Cores.painel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: H3Cores.linha2),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Assistente de IA',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: H3Cores.texto)),
          const SizedBox(height: 4),
          Text(
              'Configure aqui uma vez. Ao conectar a um computador, o chat da IA já abre pronto para uso.',
              style: apagado),
          const SizedBox(height: 16),
          Row(children: [
            _opcao(kAiProviderClaude, 'Claude (chave da API)'),
            const SizedBox(width: 10),
            _opcao(kAiProviderChatGpt, 'ChatGPT (sua conta)'),
          ]),
          const SizedBox(height: 16),
          if (_provedor == kAiProviderClaude) ...[
            _campo('Chave da API', _apiKey, segredo: true),
            _campo('Modelo', _modelo),
            _campo('Endereço da API', _url),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(
                    child: Text(
                        _auth.isSignedIn
                            ? 'Conectado: ${_auth.email}'
                            : 'Não conectado',
                        style: TextStyle(
                            fontSize: 13,
                            color: _auth.isSignedIn ? H3Cores.ok : H3Cores.apagado))),
                if (_entrando)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else if (_auth.isSignedIn)
                  TextButton(
                      onPressed: () async {
                        await _auth.logout();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Desconectar'))
                else
                  ElevatedButton(
                      onPressed: _entrar,
                      child: const Text('Entrar com o ChatGPT')),
              ]),
            ),
            if (_erro.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SelectableText(_erro,
                      style: TextStyle(fontSize: 12, color: H3Cores.aviso))),
            _campo('Modelo', _modeloGpt),
          ],
          Divider(color: H3Cores.linha),
          const SizedBox(height: 8),
          _chave('Abrir o chat ao conectar',
              'O chat da IA aparece sozinho em toda sessão remota.', _abrirAuto,
              (v) => _abrirAuto = v),
          _chave('Confirmar cada ação',
              'A IA espera sua aprovação antes de mexer no computador remoto.',
              _confirmar, (v) => _confirmar = v),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: H3Cores.aviso.withOpacity(0.08),
                border: Border.all(color: H3Cores.aviso.withOpacity(0.45)),
                borderRadius: BorderRadius.circular(12)),
            child: Text(translate('ai-agent-privacy-tip'),
                style: TextStyle(fontSize: 12, height: 1.4, color: H3Cores.texto)),
          ),
          const SizedBox(height: 16),
          Row(children: [
            if (_salvo)
              Text('Salvo', style: TextStyle(fontSize: 12, color: H3Cores.ok)),
            const Spacer(),
            ElevatedButton(onPressed: _salvar, child: const Text('Salvar')),
          ]),
        ]),
      ),
    ]);
  }
}
