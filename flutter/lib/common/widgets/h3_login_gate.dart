import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/h3_estilo.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:get/get.dart';

/// Trava o app na tela de login: o resto do sistema só aparece depois de entrar
/// numa conta H3 Suporte com assinatura ativa (o servidor-api só devolve sessão nesse caso).
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

  @override
  void initState() {
    super.initState();
    _worker = ever(gFFI.userModel.userName, (_) => _pedirLogin());
    _pedirLogin();
  }

  void _pedirLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || bind.isDisableAccount() || _logado || _dialogoAberto) {
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

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      gFFI.userModel.userName.value;
      if (bind.isDisableAccount() || _logado) return widget.child;
      final t = H3Tokens.of(context);
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
                    'Entre com sua conta H3 Suporte para usar o sistema. '
                    'É preciso ter uma assinatura ativa.',
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
                      onPressed: () => loginDialog(),
                      child: const Text('Entrar',
                          style: TextStyle(fontWeight: FontWeight.w600)),
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
