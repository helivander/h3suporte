import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/h3_home_layout.dart';
import 'package:flutter_hbb/models/ai_agent_model.dart';
import 'package:flutter_hbb/models/ai_chatgpt_auth.dart';
import 'package:flutter_hbb/models/ai_models.dart';
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
  late final _chaveGemini = TextEditingController(text: _get(kAiOptionGeminiKey));
  late final _modeloGemini = TextEditingController(
      text: _get(kAiOptionGeminiModel).isEmpty
          ? kAiDefaultGeminiModel
          : _get(kAiOptionGeminiModel));
  final _listas = <String, List<String>>{};
  final _outro = <String, bool>{};
  bool _carregandoModelos = false;
  String _erroModelos = '';
  late String _provedor = {
    kAiProviderChatGpt,
    kAiProviderGemini
  }.contains(_get(kAiOptionProvider))
      ? _get(kAiOptionProvider)
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
    _chaveGemini.dispose();
    _modeloGemini.dispose();
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
    await s(kAiOptionGeminiKey, _chaveGemini.text);
    await s(kAiOptionGeminiModel, _modeloGemini.text);
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

  TextEditingController _ctrlModelo(String p) => p == kAiProviderGemini
      ? _modeloGemini
      : p == kAiProviderChatGpt
          ? _modeloGpt
          : _modelo;

  Future<void> _carregarModelos(String p) async {
    setState(() {
      _carregandoModelos = true;
      _erroModelos = '';
    });
    try {
      final chave = p == kAiProviderGemini ? _chaveGemini.text : _apiKey.text;
      _listas[p] = await fetchAiModels(p, apiKey: chave, baseUrl: _url.text);
    } catch (e) {
      _erroModelos = e.toString();
    }
    if (mounted) setState(() => _carregandoModelos = false);
  }

  Widget _seletorModelo(String p) {
    final c = _ctrlModelo(p);
    final itens = <String>{
      if (c.text.isNotEmpty) c.text,
      ...(_listas[p] ?? kAiSuggestedModels[p] ?? const []),
    }.toList();
    final outro = _outro[p] == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: outro ? '__outro__' : (itens.contains(c.text) ? c.text : null),
            isExpanded: true,
            dropdownColor: H3Cores.painel2,
            style: TextStyle(color: H3Cores.texto, fontSize: 14),
            decoration: _dec('Modelo'),
            items: [
              for (final m in itens) DropdownMenuItem(value: m, child: Text(m)),
              const DropdownMenuItem(
                  value: '__outro__', child: Text('Outro (digitar)…')),
            ],
            onChanged: (v) => setState(() {
              _salvo = false;
              if (v == '__outro__') {
                _outro[p] = true;
              } else if (v != null) {
                _outro[p] = false;
                c.text = v;
              }
            }),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: 'Atualizar lista de modelos',
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _carregandoModelos ? null : () => _carregarModelos(p),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: H3Cores.painel2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: H3Cores.linha2),
              ),
              child: _carregandoModelos
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.refresh, size: 20, color: H3Cores.destaque),
            ),
          ),
        ),
      ]),
      if (outro) ...[
        const SizedBox(height: 12),
        TextField(
            controller: c,
            style: TextStyle(color: H3Cores.texto),
            onChanged: (_) => setState(() => _salvo = false),
            decoration: _dec('Nome do modelo')),
      ],
      if (_erroModelos.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_erroModelos,
              style: TextStyle(fontSize: 12, color: H3Cores.aviso)),
        ),
      const SizedBox(height: 12),
    ]);
  }

  Widget _opcao(String p, IconData icone, String rotulo, String sub) {
    final on = _provedor == p;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        _provedor = p;
        _salvo = false;
      }),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: on
              ? LinearGradient(colors: [
                  H3Cores.destaque.withOpacity(0.18),
                  H3Cores.destaque.withOpacity(0.05)
                ])
              : null,
          color: on ? null : H3Cores.painel2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: on ? H3Cores.destaque : H3Cores.linha2, width: on ? 1.5 : 1),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: (on ? H3Cores.destaque : H3Cores.apagado).withOpacity(0.15),
            ),
            child: Icon(icone,
                size: 21, color: on ? H3Cores.destaque : H3Cores.apagado),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rotulo,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: H3Cores.texto)),
              const SizedBox(height: 2),
              Text(sub,
                  style: TextStyle(fontSize: 11.5, color: H3Cores.apagado)),
            ]),
          ),
          Icon(on ? Icons.check_circle : Icons.circle_outlined,
              size: 20, color: on ? H3Cores.destaque : H3Cores.linha2),
        ]),
      ),
    );
  }

  Widget _secao(String titulo, String sub, Widget filho) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [H3Cores.painel2, H3Cores.painel]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: H3Cores.linha),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(titulo,
              style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: H3Cores.texto)),
          const SizedBox(height: 3),
          Text(sub, style: TextStyle(fontSize: 12.5, color: H3Cores.apagado)),
          const SizedBox(height: 16),
          filho,
        ]),
      );

  Widget _chave(IconData icone, String titulo, String sub, bool v,
          ValueChanged<bool> f) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: H3Cores.fundo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: H3Cores.linha),
        ),
        child: Row(children: [
          Icon(icone, size: 20, color: H3Cores.apagado),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: TextStyle(
                      fontSize: 13.5,
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
    final claude = _provedor == kAiProviderClaude;
    final gemini = _provedor == kAiProviderGemini;
    final pronto = claude
        ? _apiKey.text.trim().isNotEmpty
        : gemini
            ? _chaveGemini.text.trim().isNotEmpty
            : _auth.isSignedIn;
    final cor = pronto ? H3Cores.ok : H3Cores.aviso;
    return ListView(padding: const EdgeInsets.fromLTRB(15, 6, 15, 20), children: [
      Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withOpacity(0.45)),
        ),
        child: Row(children: [
          Icon(pronto ? Icons.smart_toy : Icons.smart_toy_outlined,
              size: 26, color: cor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pronto ? 'Assistente pronto' : 'Configuração pendente',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: H3Cores.texto)),
              Text(
                  pronto
                      ? 'O chat abrirá automaticamente nas sessões remotas.'
                      : claude
                          ? 'Informe a chave da API do Claude para ativar o assistente.'
                          : gemini
                              ? 'Informe a chave da API do Gemini para ativar o assistente.'
                              : 'Entre com a sua conta do ChatGPT para ativar o assistente.',
                  style: TextStyle(fontSize: 12.5, color: H3Cores.apagado)),
            ]),
          ),
        ]),
      ),
      _secao(
          'Provedor',
          'Escolha qual serviço de IA vai controlar o computador remoto.',
          LayoutBuilder(builder: (context, c) {
            final cartoes = [
              _opcao(kAiProviderClaude, Icons.key_outlined, 'Claude',
                  'Chave da API Anthropic'),
              _opcao(kAiProviderGemini, Icons.auto_awesome_outlined, 'Gemini',
                  'Chave da API Google'),
              _opcao(kAiProviderChatGpt, Icons.chat_outlined, 'ChatGPT',
                  'Entrar com a sua conta'),
            ];
            if (c.maxWidth >= 720) {
              return Row(children: [
                for (var i = 0; i < cartoes.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cartoes[i]),
                ]
              ]);
            }
            return Column(children: [
              for (var i = 0; i < cartoes.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cartoes[i],
              ]
            ]);
          })),
      _secao(
          'Conexão',
          claude
              ? 'Dados de acesso à API do Claude.'
              : gemini
                  ? 'Dados de acesso à API do Google Gemini.'
                  : 'Sua conta do ChatGPT autoriza o uso do plano.',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (claude) ...[
              _campo('Chave da API', _apiKey, segredo: true),
              _seletorModelo(kAiProviderClaude),
              _campo('Endereço da API', _url),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: H3Cores.info.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: H3Cores.info.withOpacity(0.4)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, size: 18, color: H3Cores.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'Entrar com a conta Claude (assinatura Pro/Max) não está disponível: a Anthropic só permite esse login no Claude Code e no claude.ai, e proíbe em aplicativos de terceiros. Use uma chave de API do console.anthropic.com.',
                        style: TextStyle(
                            fontSize: 12, height: 1.4, color: H3Cores.texto)),
                  ),
                ]),
              ),
            ] else if (gemini) ...[
              _campo('Chave da API', _chaveGemini, segredo: true),
              _seletorModelo(kAiProviderGemini),
            ] else ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: H3Cores.fundo,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: H3Cores.linha),
                ),
                child: Row(children: [
                  Icon(_auth.isSignedIn ? Icons.verified_user : Icons.person_outline,
                      size: 22, color: _auth.isSignedIn ? H3Cores.ok : H3Cores.apagado),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(
                          _auth.isSignedIn
                              ? 'Conectado: ${_auth.email}'
                              : 'Não conectado',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: H3Cores.texto))),
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
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _entrar,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(colors: [
                            H3Cores.destaque,
                            H3Cores.destaque.withOpacity(0.78)
                          ]),
                        ),
                        child: Text('Entrar com o ChatGPT',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: H3Cores.destaqueTinta)),
                      ),
                    ),
                ]),
              ),
              if (_erro.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SelectableText(_erro,
                        style: TextStyle(fontSize: 12, color: H3Cores.aviso))),
              _seletorModelo(kAiProviderChatGpt),
            ],
          ])),
      _secao(
          'Comportamento',
          'Como o assistente age durante a sessão remota.',
          Column(children: [
            _chave(
                Icons.open_in_browser,
                'Abrir o chat ao conectar',
                'O chat da IA aparece sozinho em toda sessão remota.',
                _abrirAuto,
                (v) => _abrirAuto = v),
            _chave(
                Icons.fact_check_outlined,
                'Confirmar cada ação',
                'A IA espera sua aprovação antes de mexer no computador remoto.',
                _confirmar,
                (v) => _confirmar = v),
          ])),
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: H3Cores.aviso.withOpacity(0.08),
            border: Border.all(color: H3Cores.aviso.withOpacity(0.45)),
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: H3Cores.aviso),
          const SizedBox(width: 10),
          Expanded(
            child: Text(translate('ai-agent-privacy-tip'),
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: H3Cores.texto)),
          ),
        ]),
      ),
      Row(children: [
        if (_salvo)
          Row(children: [
            Icon(Icons.check_circle, size: 16, color: H3Cores.ok),
            const SizedBox(width: 6),
            Text('Salvo', style: TextStyle(fontSize: 12.5, color: H3Cores.ok)),
          ]),
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _salvar,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: [
                H3Cores.destaque,
                H3Cores.destaque.withOpacity(0.78)
              ]),
              boxShadow: [
                BoxShadow(
                    color: H3Cores.destaque.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Text('Salvar',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: H3Cores.destaqueTinta)),
          ),
        ),
      ]),
    ]);
  }
}
