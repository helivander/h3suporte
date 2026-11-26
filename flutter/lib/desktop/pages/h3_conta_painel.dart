import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/h3_estilo.dart';
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
    final t = H3Tokens.of(context);
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
              colors: [t.painel2, t.painel]),
          borderRadius: BorderRadius.circular(H3Raios.lg),
          border: Border.all(color: t.linha),
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
                      borderRadius: BorderRadius.circular(H3Raios.sm),
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            t.destaque.withOpacity(0.28),
                            t.destaque.withOpacity(0.08)
                          ]),
                    ),
                    child: Icon(icone, size: 18, color: t.destaque),
                  ),
                  Text(titulo,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.texto)),
                ]),
                const SizedBox(height: 10),
                Divider(height: 1, color: t.linha),
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
            colors: [t.destaque.withOpacity(0.16), t.painel]),
        borderRadius: BorderRadius.circular(H3Raios.lg),
        border: Border.all(color: t.linha2),
      ),
      child: Obx(() {
        final nome = u.displayNameOrUserName;
        return Row(children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: t.destaque,
            child: Text(
                nome.isEmpty ? '?' : nome.substring(0, 1).toUpperCase(),
                style: TextStyle(
                    fontSize: 26,
                    color: t.destaqueTinta,
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
                      color: t.texto)),
              const SizedBox(height: 2),
              Text('@${u.userName.value}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: t.apagado)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _selo(papel, t.info),
                _selo(ativa ? 'Assinatura ativa' : (estado.isEmpty ? 'Sem plano' : estado),
                    ativa ? t.ok : t.aviso),
              ]),
            ]),
          ),
        ]);
      }),
    );

    final plano = secao('Plano', Icons.workspace_premium_outlined, [
      _linha(t, 'Plano', '${a['plano'] ?? '—'}'),
      _linha(t, 'Situação', ativa ? 'Ativa' : (estado.isEmpty ? '—' : estado),
          cor: ativa ? t.ok : t.aviso),
      _linha(t, 'Válido até', fim == null ? 'Sem data de término' : _data(fim)),
    ]);
    final uso = secao('Uso em tempo real', Icons.speed_outlined, [
      _barra(t, Icons.swap_horiz, 'Acessos remotos', _uso?['acessos_em_uso'],
          a['limite_acessos']),
      _barra(t, Icons.devices_outlined, 'Computadores', _uso?['dispositivos'],
          a['limite_dispositivos']),
      _barra(t, Icons.group_outlined, 'Contas da equipe', _uso?['contas'],
          a['limite_contas']),
      if (_falhou)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Expanded(
              child: Text('Sem conexão com o servidor.',
                  style: TextStyle(fontSize: 11, color: t.aviso)),
            ),
            TextButton(
              onPressed: _buscar,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Tentar novamente',
                  style: TextStyle(fontSize: 11, color: t.destaque)),
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
            t,
            Icons.workspace_premium_outlined,
            'Gerenciar assinatura no portal',
            'Plano, pagamentos e equipe',
            () => launchUrl(Uri.parse(_portal),
                mode: LaunchMode.externalApplication)),
        const SizedBox(height: 12),
        if (largo)
          IntrinsicHeight(
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                      child: _botaoSecundario(t, Icons.tune,
                          'Configurações deste computador', widget.onConfigLocal)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _botaoSecundario(t, Icons.logout, 'Sair da conta',
                          () async {
                    await gFFI.userModel.logOut();
                    widget.onLogout?.call();
                  }, cor: t.perigo)),
                ]),
          )
        else ...[
          _botaoSecundario(t, Icons.tune, 'Configurações deste computador',
              widget.onConfigLocal),
          const SizedBox(height: 10),
          _botaoSecundario(t, Icons.logout, 'Sair da conta', () async {
            await gFFI.userModel.logOut();
            widget.onLogout?.call();
          }, cor: t.perigo),
        ],
      ]);
    });
  }

  Widget _botaoPrincipal(H3Tokens t, IconData icone, String titulo, String sub,
          VoidCallback onTap) =>
      InkWell(
        borderRadius: BorderRadius.circular(H3Raios.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(H3Raios.md),
            gradient: LinearGradient(
                colors: [t.destaque, t.destaque.withOpacity(0.75)]),
          ),
          child: Row(children: [
            Icon(icone, size: 22, color: t.destaqueTinta),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.destaqueTinta)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: t.destaqueTinta.withOpacity(0.8))),
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 18, color: t.destaqueTinta),
          ]),
        ),
      );

  Widget _botaoSecundario(
      H3Tokens t, IconData icone, String rotulo, VoidCallback onTap,
      {Color? cor}) {
    final c = cor ?? t.texto;
    return InkWell(
      borderRadius: BorderRadius.circular(H3Raios.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: t.painel2,
          borderRadius: BorderRadius.circular(H3Raios.md),
          border: Border.all(color: cor?.withOpacity(0.5) ?? t.linha2),
        ),
        child: Row(children: [
          Icon(icone, size: 18, color: c),
          const SizedBox(width: 12),
          Expanded(
              child: Text(rotulo,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: c))),
          Icon(Icons.chevron_right, size: 18, color: t.apagado),
        ]),
      ),
    );
  }

  Widget _selo(String t, Color cor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: cor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(H3Raios.full)),
        child: Text(t,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: cor)),
      );

  Widget _linha(H3Tokens t, String r, String v, {Color? cor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
              child: Text(r,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: t.apagado))),
          const SizedBox(width: 8),
          Flexible(
              child: Text(v,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cor ?? t.texto))),
        ]),
      );

  Widget _barra(
      H3Tokens t, IconData icone, String rotulo, dynamic usado, dynamic limite) {
    final n = usado is int ? usado : null;
    final max = limite is int && limite > 0 ? limite : null;
    final cheio = n != null && max != null && n >= max;
    final cor = cheio ? t.aviso : t.destaque;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icone, size: 16, color: t.apagado),
          const SizedBox(width: 8),
          Expanded(
              child: Text(rotulo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: t.texto))),
          const SizedBox(width: 8),
          Flexible(
              child: Text(
                  n == null
                      ? '…'
                      : (max == null ? '$n (sem limite)' : '$n de $max'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cheio ? t.aviso : t.apagado))),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(H3Raios.xs),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: n == null ? null : (max == null ? (n > 0 ? 0.08 : 0) : (n / max).clamp(0.0, 1.0)),
            backgroundColor: t.linha,
            valueColor: AlwaysStoppedAnimation(cor),
          ),
        ),
      ]),
    );
  }
}
