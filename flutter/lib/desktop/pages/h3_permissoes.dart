import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/h3_home_layout.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher.dart';

class _Perm {
  final IconData icone;
  final String titulo;
  final String descricao;
  final bool ok;
  final String acao;
  final VoidCallback? onAcao;
  const _Perm(this.icone, this.titulo, this.descricao, this.ok,
      {this.acao = 'Configurar', this.onAcao});
}

/// Todas as permissões de que o H3 Suporte precisa neste computador, lado a lado, com o estado de cada uma.
class H3Permissoes extends StatefulWidget {
  const H3Permissoes({super.key});

  @override
  State<H3Permissoes> createState() => _H3PermissoesState();
}

class _H3PermissoesState extends State<H3Permissoes> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _abrir(String painel) => launchUrl(
      Uri.parse('x-apple.systempreferences:com.apple.preference.security?$painel'));

  List<_Perm> _lista() {
    final r = <_Perm>[];
    if (isMacOS) {
      final saida = bind.isOutgoingOnly();
      if (!saida) {
        r.add(_Perm(
            Icons.screenshot_monitor_outlined,
            'Gravação de tela',
            'Permite mostrar a tela deste computador a quem se conecta.',
            bind.mainIsCanScreenRecording(prompt: false), onAcao: () {
          bind.mainIsCanScreenRecording(prompt: true);
          _abrir('Privacy_ScreenCapture');
        }));
        r.add(_Perm(
            Icons.accessibility_new_outlined,
            'Acessibilidade',
            'Permite controlar o mouse e o teclado durante o acesso remoto.',
            bind.mainIsProcessTrusted(prompt: false), onAcao: () {
          bind.mainIsProcessTrusted(prompt: true);
          _abrir('Privacy_Accessibility');
        }));
      }
      r.add(_Perm(
          Icons.keyboard_outlined,
          'Monitoramento de entrada',
          'Permite capturar o teclado e o mouse para repassá-los ao computador remoto.',
          bind.mainIsCanInputMonitoring(prompt: false), onAcao: () {
        bind.mainIsCanInputMonitoring(prompt: true);
        _abrir('Privacy_ListenEvent');
      }));
      if (!saida && bind.mainIsInstalled()) {
        r.add(_Perm(
            Icons.dns_outlined,
            'Serviço em segundo plano',
            'Mantém o acesso disponível mesmo com o app fechado e na tela de login.',
            bind.mainIsInstalledDaemon(prompt: false),
            acao: 'Instalar',
            onAcao: () => bind.mainIsInstalledDaemon(prompt: true)));
      }
    } else if (isWindows && !bind.isDisableInstallation()) {
      final instalado = bind.mainIsInstalled();
      r.add(_Perm(
          Icons.install_desktop_outlined,
          'Instalação no sistema',
          'Necessária para acessar janelas com permissão de administrador e iniciar com o Windows.',
          instalado,
          acao: 'Instalar',
          onAcao: () => bind.mainGotoInstall()));
      if (instalado) {
        r.add(_Perm(
            Icons.system_update_alt_outlined,
            'Versão instalada',
            'A instalação precisa estar na mesma versão do app aberto.',
            !bind.mainIsInstalledLowerVersion(),
            acao: 'Atualizar',
            onAcao: () => bind.mainUpdateMe()));
      }
    } else if (isLinux) {
      r.add(_Perm(
          Icons.desktop_windows_outlined,
          'Sessão X11',
          'O acesso remoto funciona melhor fora do Wayland.',
          !bind.mainCurrentIsWayland(),
          acao: ''));
      r.add(_Perm(Icons.security_outlined, 'SELinux',
          'Em modo restrito, pode bloquear o serviço.', !bind.isSelinuxEnforcing(),
          acao: ''));
    }
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista();
    final ok = lista.where((p) => p.ok).length;
    final tudo = ok == lista.length;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Permissões',
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w600, color: H3Cores.texto)),
      const SizedBox(height: 4),
      Text('O que o H3 Suporte precisa para funcionar neste computador.',
          style: TextStyle(fontSize: 13, color: H3Cores.apagado)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: H3Cores.painel2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: H3Cores.linha),
        ),
        child: Row(children: [
          Icon(tudo ? Icons.verified_user : Icons.gpp_maybe_outlined,
              size: 30, color: tudo ? H3Cores.ok : H3Cores.aviso),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  tudo
                      ? 'Tudo certo'
                      : '$ok de ${lista.length} permissões concedidas',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: H3Cores.texto)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    minHeight: 6,
                    value: lista.isEmpty ? 1 : ok / lista.length,
                    backgroundColor: H3Cores.linha,
                    valueColor: AlwaysStoppedAnimation(
                        tudo ? H3Cores.ok : H3Cores.aviso)),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      if (lista.isEmpty)
        Text('Nenhuma permissão é necessária neste sistema.',
            style: TextStyle(color: H3Cores.apagado))
      else
        LayoutBuilder(builder: (context, c) {
          const gap = 16.0;
          final cols = ((c.maxWidth + gap) / (270 + gap)).floor().clamp(1, 4);
          final linhas = <Widget>[];
          for (var i = 0; i < lista.length; i += cols) {
            final fatia = lista.skip(i).take(cols).toList();
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
                                ? _cartao(fatia[j])
                                : const SizedBox.shrink()),
                      ],
                    ]),
              ),
            ));
          }
          return Column(children: linhas);
        }),
    ]);
  }

  Widget _cartao(_Perm p) {
    final cor = p.ok ? H3Cores.ok : H3Cores.aviso;
    final temAcao = !p.ok && p.acao.isNotEmpty && p.onAcao != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [H3Cores.painel2, H3Cores.painel]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.ok ? H3Cores.linha : cor.withOpacity(0.45)),
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
                  colors: [cor.withOpacity(0.28), cor.withOpacity(0.08)]),
            ),
            child: Icon(p.icone, color: cor, size: 24),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: cor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(p.ok ? 'Concedida' : 'Pendente',
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: cor)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Text(p.titulo,
            style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: H3Cores.texto)),
        const SizedBox(height: 6),
        Text(p.descricao,
            style: TextStyle(fontSize: 12.5, height: 1.45, color: H3Cores.apagado)),
        const Spacer(),
        const SizedBox(height: 18),
        Divider(height: 1, color: H3Cores.linha),
        const SizedBox(height: 14),
        if (temAcao)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: p.onAcao,
            child: Container(
              height: 42,
              alignment: Alignment.center,
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
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(p.acao,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: H3Cores.destaqueTinta)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded,
                    size: 17, color: H3Cores.destaqueTinta),
              ]),
            ),
          )
        else
          SizedBox(
            height: 42,
            child: Row(children: [
              Icon(p.ok ? Icons.check_circle_outline : Icons.info_outline,
                  size: 18, color: p.ok ? H3Cores.ok : H3Cores.apagado),
              const SizedBox(width: 8),
              Text(p.ok ? 'Nenhuma ação necessária' : 'Ajuste nas configurações do sistema',
                  style: TextStyle(fontSize: 12.5, color: H3Cores.apagado)),
            ]),
          ),
      ]),
    );
  }
}
