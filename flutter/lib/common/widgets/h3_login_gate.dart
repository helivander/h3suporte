import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
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
      if (mounted && !_logado) await loginDialog();
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
      final cores = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: cores.surface,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: cores.primary),
                  const SizedBox(height: 16),
                  const Text('H3 Suporte',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    'Entre com sua conta H3 Suporte para usar o sistema. '
                    'É preciso ter uma assinatura ativa.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => loginDialog(),
                    child: const Text('Entrar'),
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
