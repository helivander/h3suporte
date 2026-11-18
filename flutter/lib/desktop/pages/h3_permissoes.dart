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
        Wrap(
            spacing: 16,
            runSpacing: 16,
            children: lista.map(_cartao).toList()),
    ]);
  }

  Widget _cartao(_Perm p) {
    final cor = p.ok ? H3Cores.ok : H3Cores.aviso;
    return Container(
      width: 270,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [H3Cores.painel2, H3Cores.painel]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.ok ? H3Cores.linha : cor.withOpacity(0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: cor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(p.icone, color: cor, size: 24),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: cor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(p.ok ? Icons.check : Icons.priority_high, size: 13, color: cor),
              const SizedBox(width: 4),
              Text(p.ok ? 'Concedida' : 'Pendente',
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: cor)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text(p.titulo,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: H3Cores.texto)),
        const SizedBox(height: 6),
        Text(p.descricao,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: H3Cores.apagado)),
        if (!p.ok && p.acao.isNotEmpty && p.onAcao != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: p.onAcao,
              style: ElevatedButton.styleFrom(
                  backgroundColor: H3Cores.destaque,
                  foregroundColor: H3Cores.destaqueTinta,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text(p.acao,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}
