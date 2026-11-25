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

/// Dados da conta, plano e uso em tempo real, exibidos em Configurações > Conta.
class ContaConteudo extends StatefulWidget {
  /// Abre a aba de configurações locais do computador.
  final VoidCallback onConfigLocal;

  /// Chamado após sair da conta (ex.: fechar modal na Web).
  final VoidCallback? onLogout;
  const ContaConteudo({super.key, required this.onConfigLocal, this.onLogout});

  @override
  State<ContaConteudo> createState() => _ContaConteudoState();
}

class _ContaConteudoState extends State<ContaConteudo> {
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
    BoxDecoration caixa() => BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [H3Cores.painel2, H3Cores.painel]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: H3Cores.linha),
        );
    Widget secao(String titulo, IconData icone, List<Widget> filhos) =>
        Container(
          padding: const EdgeInsets.all(20),
          decoration: caixa(),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            H3Cores.destaque.withOpacity(0.28),
                            H3Cores.destaque.withOpacity(0.08)
                          ]),
                    ),
                    child: Icon(icone, size: 18, color: H3Cores.destaque),
                  ),
                  Text(titulo,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: H3Cores.texto)),
                ]),
                const SizedBox(height: 10),
                Divider(height: 1, color: H3Cores.linha),
                const SizedBox(height: 8),
                ...filhos,
              ]),
        );

    final perfil = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [H3Cores.destaque.withOpacity(0.16), H3Cores.painel]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: H3Cores.linha2),
      ),
      child: Obx(() {
        final nome = u.displayNameOrUserName;
        return Row(children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: H3Cores.destaque,
            child: Text(
                nome.isEmpty ? '?' : nome.substring(0, 1).toUpperCase(),
                style: TextStyle(
                    fontSize: 26,
                    color: H3Cores.destaqueTinta,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nome,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: H3Cores.texto)),
              const SizedBox(height: 2),
              Text('@${u.userName.value}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: H3Cores.apagado)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _selo(papel, H3Cores.info),
                _selo(ativa ? 'Assinatura ativa' : (estado.isEmpty ? 'Sem plano' : estado),
                    ativa ? H3Cores.ok : H3Cores.aviso),
              ]),
            ]),
          ),
        ]);
      }),
    );

    final plano = secao('Plano', Icons.workspace_premium_outlined, [
      _linha('Plano', '${a['plano'] ?? '—'}'),
      _linha('Situação', ativa ? 'Ativa' : (estado.isEmpty ? '—' : estado),
          cor: ativa ? H3Cores.ok : H3Cores.aviso),
      _linha('Válido até', fim == null ? 'Sem data de término' : _data(fim)),
    ]);
    final uso = secao('Uso em tempo real', Icons.speed_outlined, [
      _barra(Icons.swap_horiz, 'Acessos remotos', _uso?['acessos_em_uso'],
          a['limite_acessos']),
      _barra(Icons.devices_outlined, 'Computadores', _uso?['dispositivos'],
          a['limite_dispositivos']),
      _barra(Icons.group_outlined, 'Contas da equipe', _uso?['contas'],
          a['limite_contas']),
      if (_falhou)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(
              child: Text('Sem conexão com o servidor.',
                  style: TextStyle(fontSize: 11, color: H3Cores.aviso)),
            ),
            TextButton(
              onPressed: _buscar,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Tentar novamente',
                  style: TextStyle(fontSize: 11, color: H3Cores.destaque)),
            ),
          ]),
        ),
    ]);

    return LayoutBuilder(builder: (context, c) {
      final largo = c.maxWidth >= 720;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        perfil,
        const SizedBox(height: 16),
        if (largo)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: plano),
              const SizedBox(width: 16),
              Expanded(child: uso),
            ]),
          )
        else ...[plano, const SizedBox(height: 16), uso],
        const SizedBox(height: 16),
        _botaoPrincipal(
            Icons.workspace_premium_outlined,
            'Gerenciar assinatura no portal',
            'Plano, pagamentos e equipe',
            () => launchUrl(Uri.parse(_portal),
                mode: LaunchMode.externalApplication)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _botaoSecundario(Icons.tune,
                  'Configurações deste computador', widget.onConfigLocal)),
          const SizedBox(width: 12),
          Expanded(
              child: _botaoSecundario(Icons.logout, 'Sair da conta', () async {
            await gFFI.userModel.logOut();
            widget.onLogout?.call();
          }, cor: H3Cores.perigo)),
        ]),
      ]);
    });
  }

  Widget _botaoPrincipal(
          IconData icone, String titulo, String sub, VoidCallback onTap) =>
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(colors: [
              H3Cores.destaque,
              H3Cores.destaque.withOpacity(0.75)
            ]),
          ),
          child: Row(children: [
            Icon(icone, size: 22, color: H3Cores.destaqueTinta),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: H3Cores.destaqueTinta)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: H3Cores.destaqueTinta.withOpacity(0.8))),
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 18, color: H3Cores.destaqueTinta),
          ]),
        ),
      );

  Widget _botaoSecundario(IconData icone, String rotulo, VoidCallback onTap,
      {Color? cor}) {
    final c = cor ?? H3Cores.texto;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: H3Cores.painel2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor?.withOpacity(0.5) ?? H3Cores.linha2),
        ),
        child: Row(children: [
          Icon(icone, size: 18, color: c),
          const SizedBox(width: 12),
          Expanded(
              child: Text(rotulo,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: c))),
          Icon(Icons.chevron_right, size: 18, color: H3Cores.apagado),
        ]),
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
