import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/h3_home_layout.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

const _portal = 'https://keys.h3info.com/assinante';

/// Configurações da conta: dados do cliente, plano e uso em tempo real, ao lado do card da conta na barra lateral.
/// [saida] são as sessões de saída abertas neste computador (atualizadas pela tela inicial).
Future<void> abrirPainelConta(BuildContext context,
    {required RxList<String> saida, required bool compacto}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, __, ___) => Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.only(left: compacto ? 76 : 14, bottom: 14),
        child: Theme(
          data: H3Cores.tema(Theme.of(context).brightness),
          child: _PainelConta(saida: saida),
        ),
      ),
    ),
    transitionBuilder: (_, a, __, filho) =>
        FadeTransition(opacity: a, child: filho),
  );
}

class _PainelConta extends StatefulWidget {
  final RxList<String> saida;
  const _PainelConta({required this.saida});

  @override
  State<_PainelConta> createState() => _PainelContaState();
}

class _PainelContaState extends State<_PainelConta> {
  Map<String, dynamic>? _uso;
  bool _falhou = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _buscar();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _buscar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _buscar() async {
    try {
      final url = await bind.mainGetApiServer();
      final r = await http.get(Uri.parse('$url/api/conta/uso'),
          headers: getHttpHeaders());
      if (r.statusCode != 200) throw r.statusCode;
      final dados = jsonDecode(decode_http_response(r)) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _uso = dados;
          _falhou = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _falhou = true);
    }
  }

  Map<String, dynamic> get _assinatura =>
      ((_uso?['assinatura'] ?? UserModel.getLocalUserInfo()?['assinatura'])
              as Map?)
          ?.cast<String, dynamic>() ??
      {};

  String _data(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '—';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final u = gFFI.userModel;
    final info = UserModel.getLocalUserInfo() ?? {};
    final a = _assinatura;
    final estado = '${a['estado'] ?? ''}';
    final ativa = estado == 'ATIVA';
    final papel = info['papel'] == 'TITULAR' ? 'Titular' : 'Membro';
    final fim = a['fim_em'] ?? a['pago_ate'];
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 340,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height - 28),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: H3Cores.painel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: H3Cores.linha2),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 24)
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                    child: Text('Configurações da conta',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: H3Cores.texto))),
                InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child:
                        Icon(Icons.close, size: 18, color: H3Cores.apagado)),
              ]),
              const SizedBox(height: 14),
              Obx(() {
                final nome = u.displayNameOrUserName;
                return Row(children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: H3Cores.destaque,
                    child: Text(
                        nome.isEmpty ? '?' : nome.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                            fontSize: 18,
                            color: H3Cores.destaqueTinta,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nome,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: H3Cores.texto)),
                        Text(u.userName.value,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: H3Cores.apagado)),
                      ],
                    ),
                  ),
                  _selo(papel, H3Cores.info),
                ]);
              }),
              _titulo('Plano'),
              _linha('Plano', '${a['plano'] ?? '—'}'),
              _linha('Situação', ativa ? 'Ativa' : (estado.isEmpty ? '—' : estado),
                  cor: ativa ? H3Cores.ok : H3Cores.aviso),
              _linha('Válido até', fim == null ? 'Sem data de término' : _data(fim)),
              _titulo('Uso em tempo real'),
              _usoSessoes(),
              _barra(Icons.swap_horiz, 'Acessos remotos',
                  _uso?['acessos_em_uso'], a['limite_acessos']),
              _barra(Icons.devices_outlined, 'Computadores',
                  _uso?['dispositivos'], a['limite_dispositivos']),
              _barra(Icons.group_outlined, 'Contas da equipe', _uso?['contas'],
                  a['limite_contas']),
              if (_falhou)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Sem conexão com o servidor. Tentando de novo…',
                      style: TextStyle(fontSize: 11, color: H3Cores.aviso)),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(_portal),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Gerenciar assinatura no portal'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD64545),
                    foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await gFFI.userModel.logOut();
                },
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Sair da conta'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: H3Cores.apagado)),
      );

  Widget _selo(String t, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: cor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(t,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: cor)),
      );

  Widget _linha(String r, String v, {Color? cor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(r, style: TextStyle(fontSize: 13, color: H3Cores.apagado)),
          const Spacer(),
          Text(v,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cor ?? H3Cores.texto)),
        ]),
      );

  Widget _usoSessoes() => Obx(() {
        final saida = widget.saida.length;
        final entrada =
            gFFI.serverModel.clients.where((c) => !c.disconnected).length;
        return _linha('Sessões agora',
            '${saida + entrada}  ($saida saindo · $entrada entrando)');
      });

  Widget _barra(IconData icone, String rotulo, dynamic usado, dynamic limite) {
    final n = usado is int ? usado : null;
    final max = limite is int && limite > 0 ? limite : null;
    final cheio = n != null && max != null && n >= max;
    final cor = cheio ? H3Cores.aviso : H3Cores.destaque;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icone, size: 16, color: H3Cores.apagado),
          const SizedBox(width: 8),
          Text(rotulo, style: TextStyle(fontSize: 13, color: H3Cores.texto)),
          const Spacer(),
          Text(n == null ? '…' : (max == null ? '$n (sem limite)' : '$n de $max'),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cheio ? H3Cores.aviso : H3Cores.apagado)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: n == null ? null : (max == null ? (n > 0 ? 0.08 : 0) : (n / max).clamp(0.0, 1.0)),
            backgroundColor: H3Cores.linha,
            valueColor: AlwaysStoppedAnimation(cor),
          ),
        ),
      ]),
    );
  }
}
