import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/desktop/pages/h3_home_layout.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:get/get.dart';

class H3Erro implements Exception {
  final String mensagem;
  final int? status;
  H3Erro(this.mensagem, [this.status]);
  @override
  String toString() => mensagem;
}

class H3Dispositivo {
  final String id;
  final String nome;
  final String so;
  final bool online;
  H3Dispositivo(this.id, this.nome, this.so, this.online);

  String get idFormatado {
    final r = id.replaceAll(' ', '');
    if (RegExp(r'^\d{9,}$').hasMatch(r)) {
      final b = StringBuffer();
      for (var i = 0; i < r.length; i++) {
        if (i > 0 && i % 3 == 0) b.write(' ');
        b.write(r[i]);
      }
      return b.toString();
    }
    return id;
  }
}

/// "Meus dispositivos": ID e senha de acesso dos computadores da conta, no
/// servidor-api (`/api/dispositivos-conta`). A lista não traz a senha; ela é
/// pedida só ao conectar.
class H3Dispositivos {
  static Future<Map<String, dynamic>> _chamar(String caminho,
      {Map<String, dynamic>? corpo}) async {
    final api = await bind.mainGetApiServer();
    final headers = getHttpHeaders()..['Content-Type'] = 'application/json';
    final uri = Uri.parse('$api/api/dispositivos-conta$caminho');
    final resp = corpo == null
        ? await http.get(uri, headers: headers)
        : await http.post(uri, headers: headers, body: jsonEncode(corpo));
    Map<String, dynamic> json = {};
    try {
      final v = jsonDecode(decode_http_response(resp));
      if (v is Map<String, dynamic>) json = v;
    } catch (_) {}
    if (resp.statusCode >= 400) {
      throw H3Erro(
          json['error']?.toString() ?? 'Erro ${resp.statusCode} do servidor.',
          resp.statusCode);
    }
    return json;
  }

  static String get meuId =>
      gFFI.serverModel.serverId.text.replaceAll(' ', '');

  static Future<List<H3Dispositivo>> listar() async {
    final json = await _chamar('');
    final dados = json['data'];
    if (dados is! List) return [];
    return dados
        .whereType<Map>()
        .map((d) => H3Dispositivo(d['id']?.toString() ?? '',
            d['nome']?.toString() ?? '', d['so']?.toString() ?? '',
            d['online'] == true))
        .where((d) => d.id.isNotEmpty)
        .toList();
  }

  static Future<String> senha(String id) async {
    final json = await _chamar('/senha', corpo: {'id': id});
    final s = json['senha'];
    if (s is! String || s.isEmpty) throw H3Erro('A conta não devolveu a senha.');
    return s;
  }

  static Future<void> remover(String id) async {
    await _chamar('/remover', corpo: {'id': id});
  }

  static String _gerarSenha() {
    const maiusculas = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const minusculas = 'abcdefghijkmnopqrstuvwxyz';
    const digitos = '23456789';
    final r = Random.secure();
    String um(String s) => s[r.nextInt(s.length)];
    final chars = <String>[
      um(maiusculas),
      um(minusculas),
      um(digitos),
      for (var i = 0; i < 13; i++) um(maiusculas + minusculas + digitos),
    ]..shuffle(r);
    return chars.join();
  }

  /// Define uma nova senha permanente neste computador e a guarda na conta.
  /// A senha só vale com o método de verificação e a aprovação que aceitam
  /// senha, então eles são ajustados quando estavam só em "uso único"/"clique".
  static Future<void> registrarEste() async {
    final id = meuId;
    if (id.isEmpty) {
      throw H3Erro(
          'Este computador ainda não tem ID. Aguarde a conexão com o servidor.');
    }
    final senha = _gerarSenha();
    final ok = await bind.mainSetPermanentPasswordWithResult(password: senha);
    if (!ok) {
      throw H3Erro(
          'Não foi possível definir a senha permanente neste computador.');
    }
    final model = gFFI.serverModel;
    if (model.verificationMethod == kUseTemporaryPassword) {
      await model.setVerificationMethod(kUseBothPasswords);
    }
    if (model.approveMode == 'click') {
      await model.setApproveMode(defaultOptionApproveMode);
    }
    String nome = '';
    String so = '';
    try {
      final info = jsonDecode(bind.mainGetLoginDeviceInfo());
      nome = info['name']?.toString() ?? '';
      so = info['os']?.toString() ?? '';
    } catch (_) {}
    try {
      await _chamar('', corpo: {'id': id, 'nome': nome, 'so': so, 'senha': senha});
    } on H3Erro catch (e) {
      throw H3Erro(
          'A nova senha já vale neste computador, mas não foi guardada na conta: ${e.mensagem} Registre de novo.',
          e.status);
    }
  }
}

class H3MeusDispositivosPage extends StatefulWidget {
  const H3MeusDispositivosPage({Key? key}) : super(key: key);

  @override
  State<H3MeusDispositivosPage> createState() => _H3MeusDispositivosPageState();
}

class _H3MeusDispositivosPageState extends State<H3MeusDispositivosPage> {
  List<H3Dispositivo> _lista = [];
  bool _carregando = false;
  bool _carregouUmaVez = false;
  bool _registrando = false;
  String _erro = '';
  Timer? _timer;
  Worker? _login;

  bool get _logado => gFFI.userModel.userName.value.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _carregar());
    _login = ever(gFFI.userModel.userName, (_) => _carregar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _login?.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (!_logado) {
      if (mounted) setState(() => _lista = []);
      return;
    }
    if (_carregando) return;
    if (!_carregouUmaVez && mounted) setState(() => _carregando = true);
    _carregando = true;
    try {
      final lista = await H3Dispositivos.listar();
      if (mounted) {
        setState(() {
          _lista = lista;
          _erro = '';
        });
      }
    } on H3Erro catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível falar com o servidor.');
    } finally {
      _carregando = false;
      if (!_carregouUmaVez && mounted) {
        setState(() => _carregouUmaVez = true);
      } else {
        _carregouUmaVez = true;
      }
    }
  }

  bool get _esteRegistrado =>
      _lista.any((d) => d.id == H3Dispositivos.meuId);

  Future<void> _registrar() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: H3Cores.painel2,
        title: Text(_esteRegistrado
            ? 'Gerar nova senha e atualizar a conta?'
            : 'Registrar este computador na sua conta?'),
        content: const Text(
            'Será criada uma nova senha permanente para este computador. A senha permanente atual deixa de valer. '
            'A nova senha fica guardada, cifrada, na sua conta H3 Suporte: quem entrar na conta em outro app poderá '
            'acessar este computador sem digitar a senha.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Registrar',
                  style: TextStyle(color: H3Cores.destaque))),
        ],
      ),
    );
    if (confirmou != true) return;
    setState(() => _registrando = true);
    try {
      await H3Dispositivos.registrarEste();
      showToast('Computador registrado na sua conta.');
    } on H3Erro catch (e) {
      showToast(e.mensagem, timeout: const Duration(seconds: 6));
    } catch (e) {
      showToast('Não foi possível registrar: $e',
          timeout: const Duration(seconds: 6));
    } finally {
      if (mounted) setState(() => _registrando = false);
      await _carregar();
    }
  }

  Future<void> _conectar(H3Dispositivo d, {bool arquivos = false}) async {
    try {
      final senha = await H3Dispositivos.senha(d.id);
      if (!mounted) return;
      await connect(context, d.id, password: senha, isFileTransfer: arquivos);
    } on H3Erro catch (e) {
      showToast(e.mensagem, timeout: const Duration(seconds: 5));
    } catch (e) {
      showToast('Não foi possível conectar: $e');
    }
  }

  Future<void> _remover(H3Dispositivo d) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: H3Cores.painel2,
        title: Text('Remover ${d.nome.isEmpty ? d.idFormatado : d.nome}?'),
        content: const Text(
            'O ID e a senha deixam de ficar guardados na conta. O computador continua com a senha que tem; '
            'para acessá-lo de novo por aqui, registre-o outra vez.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Remover',
                  style: TextStyle(color: H3Cores.perigo))),
        ],
      ),
    );
    if (confirmou != true) return;
    try {
      await H3Dispositivos.remover(d.id);
    } on H3Erro catch (e) {
      showToast(e.mensagem);
    }
    await _carregar();
  }

  IconData _icone(String so) {
    final s = so.toLowerCase();
    if (s.contains('mac')) return Icons.laptop_mac;
    if (s.contains('android')) return Icons.phone_android;
    if (s.contains('linux')) return Icons.computer;
    return Icons.desktop_windows_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final logado = _logado;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Meus dispositivos',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: H3Cores.texto)),
          const SizedBox(height: 4),
          Text('Computadores registrados na sua conta, prontos para conectar com um clique.',
              style: TextStyle(fontSize: 13, color: H3Cores.apagado)),
          const SizedBox(height: 18),
          _cartaoEste(logado),
          const SizedBox(height: 16),
          _cartaoLista(logado),
        ],
      );
    });
  }

  BoxDecoration get _caixa => BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [H3Cores.painel2, H3Cores.painel]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: H3Cores.linha),
      );

  Widget _cartaoEste(bool logado) {
    final registrado = _esteRegistrado;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _caixa,
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: H3Cores.destaque.withOpacity(0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.cloud_done_outlined,
              color: H3Cores.destaque, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Este computador',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: H3Cores.texto)),
              Text(
                !logado
                    ? 'Entre na sua conta H3 Suporte para guardar o ID e a senha deste computador nela.'
                    : registrado
                        ? 'Registrado na sua conta. Qualquer app logado nela consegue acessá-lo.'
                        : 'Não registrado. Registre para acessá-lo de outro app, sem digitar a senha.',
                style:
                    TextStyle(fontSize: 12.5, color: H3Cores.apagado),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (!logado)
          _botaoH3(Icons.login, 'Entrar', () => loginDialog())
        else
          _botaoH3(
              registrado ? Icons.refresh : Icons.cloud_upload_outlined,
              _registrando
                  ? 'Registrando…'
                  : registrado
                      ? 'Gerar nova senha'
                      : 'Registrar na conta',
              _registrando ? null : _registrar,
              primario: !registrado,
              carregando: _registrando),
      ]),
    );
  }

  Widget _botaoH3(IconData icone, String rotulo, VoidCallback? onTap,
      {bool primario = true, bool carregando = false}) {
    final fg = primario ? H3Cores.destaqueTinta : H3Cores.texto;
    return Opacity(
      opacity: onTap == null && !carregando ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: primario
                ? LinearGradient(colors: [
                    H3Cores.destaque,
                    H3Cores.destaque.withOpacity(0.78)
                  ])
                : null,
            color: primario ? null : H3Cores.painel2,
            border: primario ? null : Border.all(color: H3Cores.linha2),
            boxShadow: primario
                ? [
                    BoxShadow(
                        color: H3Cores.destaque.withOpacity(0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            carregando
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                : Icon(icone, size: 18, color: fg),
            const SizedBox(width: 10),
            Text(rotulo,
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700, color: fg)),
          ]),
        ),
      ),
    );
  }

  Widget _cartaoLista(bool logado) {
    final meu = H3Dispositivos.meuId;
    Widget corpo;
    if (!logado) {
      corpo = _vazio('Entre na sua conta para ver os dispositivos registrados.');
    } else if (_carregando && !_carregouUmaVez) {
      corpo = Container(
        padding: const EdgeInsets.all(28),
        decoration: _caixa,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: H3Cores.destaque),
            ),
            const SizedBox(width: 12),
            Text('Carregando dispositivos...',
                style: TextStyle(fontSize: 13, color: H3Cores.apagado)),
          ],
        ),
      );
    } else if (_erro.isNotEmpty) {
      corpo = _vazio(_erro, tentarNovamente: _carregar);
    } else if (_lista.isEmpty) {
      corpo = _vazio(
          'Nenhum dispositivo registrado ainda. Abra o H3 Suporte no computador que quer acessar, entre na mesma conta e escolha Registrar na conta.');
    } else {
      corpo = LayoutBuilder(builder: (context, c) {
        const gap = 16.0;
        final cols = ((c.maxWidth + gap) / (300 + gap)).floor().clamp(1, 4);
        final linhas = <Widget>[];
        for (var i = 0; i < _lista.length; i += cols) {
          final fatia = _lista.skip(i).take(cols).toList();
          linhas.add(Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < cols; j++) ...[
                      if (j > 0) const SizedBox(width: gap),
                      Expanded(
                          child: j < fatia.length
                              ? _cartaoDispositivo(fatia[j], meu)
                              : const SizedBox.shrink()),
                    ],
                  ]),
            ),
          ));
        }
        return Column(children: linhas);
      });
    }
    final online = _lista.where((d) => d.online).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('Dispositivos da conta',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: H3Cores.texto)),
        ),
        if (logado && _lista.isNotEmpty) ...[
          _chip('${_lista.length} registrados', H3Cores.apagado),
          const SizedBox(width: 8),
          _chip('$online online', H3Cores.ok),
        ],
      ]),
      const SizedBox(height: 14),
      corpo,
    ]);
  }

  Widget _chip(String t, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: cor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(t,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: cor)),
      );

  Widget _cartaoDispositivo(dynamic d, String? meu) {
    final eu = d.id == meu;
    Widget quadro(IconData i, String dica, VoidCallback f) => Tooltip(
          message: dica,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: f,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: H3Cores.painel2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: H3Cores.linha2),
              ),
              child: Icon(i, size: 19, color: H3Cores.apagado),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [H3Cores.painel2, H3Cores.painel]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: H3Cores.linha),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    H3Cores.destaque.withOpacity(0.28),
                    H3Cores.destaque.withOpacity(0.08)
                  ]),
            ),
            child: Icon(_icone(d.so), color: H3Cores.destaque, size: 24),
          ),
          const Spacer(),
          _pilula(d.online),
        ]),
        const SizedBox(height: 14),
        Text(d.nome.isEmpty ? d.idFormatado : d.nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: H3Cores.texto)),
        const SizedBox(height: 3),
        Row(children: [
          Text(d.idFormatado,
              style: TextStyle(
                  fontSize: 12.5,
                  color: H3Cores.apagado,
                  fontFamily: 'monospace')),
          if (eu) ...[
            const SizedBox(width: 8),
            Text('· este computador',
                style: TextStyle(fontSize: 12, color: H3Cores.destaque)),
          ],
        ]),
        const Spacer(),
        const SizedBox(height: 16),
        Divider(height: 1, color: H3Cores.linha),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _conectar(d),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(colors: [
                    H3Cores.destaque,
                    H3Cores.destaque.withOpacity(0.78)
                  ]),
                  boxShadow: [
                    BoxShadow(
                        color: H3Cores.destaque.withOpacity(0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bolt, size: 18, color: H3Cores.destaqueTinta),
                  const SizedBox(width: 6),
                  Text('Conectar',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: H3Cores.destaqueTinta)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          quadro(Icons.folder_outlined, 'Transferir arquivos',
              () => _conectar(d, arquivos: true)),
          const SizedBox(width: 8),
          quadro(Icons.delete_outline, 'Remover da conta', () => _remover(d)),
        ]),
      ]),
    );
  }

  Widget _vazio(String msg, {VoidCallback? tentarNovamente}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: H3Cores.linha2),
          color: H3Cores.fundo,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: H3Cores.apagado)),
            if (tentarNovamente != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: tentarNovamente,
                icon: Icon(Icons.refresh, size: 16, color: H3Cores.destaque),
                label: Text('Tentar novamente',
                    style: TextStyle(color: H3Cores.destaque)),
              ),
            ],
          ],
        ),
      );

  Widget _pilula(bool online) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: (online ? H3Cores.ok : H3Cores.apagado).withOpacity(0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? H3Cores.ok : H3Cores.apagado),
          ),
          const SizedBox(width: 5),
          Text(online ? 'Online' : 'Offline',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: online ? H3Cores.ok : H3Cores.apagado)),
        ]),
      );
}
