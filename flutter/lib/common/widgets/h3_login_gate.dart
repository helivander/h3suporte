import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/h3_estilo.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:get/get.dart';

/// Trava o app na tela de login: o resto do sistema só aparece depois de entrar
/// numa conta H3 Suporte com assinatura ativa (o servidor-api só devolve sessão nesse caso).
/// O cliente (build só de recepção) não pede login: só recebe conexões.
class H3LoginGate extends StatefulWidget {
  final Widget child;
  const H3LoginGate({Key? key, required this.child}) : super(key: key);

  @override
  State<H3LoginGate> createState() => _H3LoginGateState();
}

class _H3LoginGateState extends State<H3LoginGate> {
  Worker? _worker;
  bool _dialogoAberto = false;

  bool get _logado =>
      gFFI.userModel.isLogin || UserModel.getLocalUserInfo() != null;

  /// O agente só funciona instalado: no Windows pelo instalador, no Mac em Aplicativos e com o serviço.
  /// O cliente (só recepção) roda sem instalar.
  bool get _precisaInstalar {
    if (!isDesktop || bind.isIncomingOnly() || bind.isDisableInstallation()) {
      return false;
    }
    if (isWindows) return !bind.mainIsInstalled();
    if (isMacOS) {
      return !bind.mainIsInstalled() ||
          !bind.mainIsInstalledDaemon(prompt: false);
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _worker = ever(gFFI.userModel.userName, (_) => _pedirLogin());
    _pedirLogin();
  }

  void _pedirLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted ||
          bind.isDisableAccount() ||
          bind.isIncomingOnly() ||
          _precisaInstalar ||
          _logado ||
          _dialogoAberto) {
        return;
      }
      _dialogoAberto = true;
      try {
        await loginDialog();
      } finally {
        _dialogoAberto = false;
      }
    });
  }

  /// Sem conta ou sem querer entrar agora: fecha o app (o login volta a ser pedido ao abrir de novo).
  void _fecharApp() {
    if (isDesktop) exit(0);
    SystemNavigator.pop();
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      gFFI.userModel.userName.value;
      if (!_precisaInstalar &&
          (bind.isDisableAccount() || bind.isIncomingOnly() || _logado)) {
        return widget.child;
      }
      final t = H3Tokens.of(context);
      final instalar = _precisaInstalar;
      final foraDeAplicativos = instalar && isMacOS && !bind.mainIsInstalled();
      final String texto;
      final String botao;
      final VoidCallback acao;
      if (!instalar) {
        texto = 'Entre com sua conta H3 Suporte para usar o sistema. '
            'É preciso ter uma assinatura ativa.';
        botao = 'Entrar';
        acao = () => loginDialog();
      } else if (isWindows) {
        texto = 'O H3 Suporte precisa ser instalado neste computador para ser usado.';
        botao = 'Instalar';
        acao = () => bind.mainGotoInstall();
      } else if (foraDeAplicativos) {
        texto = 'Arraste o H3 Suporte para a pasta Aplicativos e abra-o por lá para usar.';
        botao = 'Verificar de novo';
        acao = () => setState(() {});
      } else {
        texto = 'Instale o serviço do H3 Suporte para usar o sistema. '
            'Depois de instalar, clique em Verificar de novo.';
        botao = 'Instalar o serviço';
        acao = () => bind.mainIsInstalledDaemon(prompt: true);
      }
      final verificar = instalar && isMacOS && !foraDeAplicativos;
      return Scaffold(
        backgroundColor: t.fundo,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: t.painel,
                borderRadius: BorderRadius.circular(H3Raios.lg),
                border: Border.all(color: t.linha),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/icon.png', width: 56, height: 56),
                  const SizedBox(height: 16),
                  Text('H3 Suporte',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: t.texto)),
                  const SizedBox(height: 8),
                  Text(
                    texto,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.45, color: t.apagado),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.destaque,
                        foregroundColor: t.destaqueTinta,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(H3Raios.sm),
                        ),
                      ),
                      onPressed: acao,
                      child: Text(botao,
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (verificar) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.texto,
                          side: BorderSide(color: t.linha),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(H3Raios.sm),
                          ),
                        ),
                        onPressed: () => setState(() {}),
                        child: const Text('Verificar de novo'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: t.texto,
                        side: BorderSide(color: t.linha),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(H3Raios.sm),
                        ),
                      ),
                      onPressed: _fecharApp,
                      child: const Text('Fechar o H3 Suporte'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
