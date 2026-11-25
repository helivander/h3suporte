import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/h3_home_layout.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:provider/provider.dart';

/// ID e senha de uso único deste computador, no tema H3 da tela inicial.
class H3EsteComputador extends StatelessWidget {
  const H3EsteComputador({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final model = gFFI.serverModel;
    return ChangeNotifierProvider.value(
      value: model,
      child: Consumer<ServerModel>(builder: (context, model, _) {
        final mostrarSenha = model.approveMode != 'click' &&
            model.verificationMethod != kUsePermanentPassword;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: model.serverId,
              builder: (_, id, __) => _bloco(
                rotulo: 'ID de acesso',
                icone: Icons.fingerprint,
                valor: _agrupar(id.text),
                tamanho: 21,
                acoes: [
                  _acao(Icons.copy_outlined, 'Copiar ID', () => _copiar(id.text)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: model.serverPasswd,
              builder: (_, senha, __) => _bloco(
                rotulo: 'Senha de uso único',
                icone: Icons.key_outlined,
                valor: mostrarSenha ? senha.text : 'Aprovação por clique',
                tamanho: mostrarSenha ? 20 : 14,
                espaco: mostrarSenha ? 2 : 0,
                acoes: [
                  if (mostrarSenha) ...[
                    _acao(Icons.copy_outlined, 'Copiar senha',
                        () => _copiar(senha.text)),
                    _acao(Icons.refresh, 'Gerar nova senha',
                        () => bind.mainUpdateTemporaryPassword()),
                  ],
                  if (!bind.isDisableSettings())
                    _acao(Icons.edit_outlined, 'Alterar senha',
                        () => DesktopSettingPage.switch2page(
                            SettingsTabKey.safety)),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  static String _agrupar(String id) {
    final limpo = id.replaceAll(' ', '');
    if (limpo.length < 7) return id;
    final b = StringBuffer();
    for (var i = 0; i < limpo.length; i++) {
      if (i > 0 && i % 3 == 0) b.write(' ');
      b.write(limpo[i]);
    }
    return b.toString();
  }

  static void _copiar(String texto) {
    Clipboard.setData(ClipboardData(text: texto.replaceAll(' ', '')));
    showToast(translate('Copied'));
  }

  Widget _acao(IconData icone, String dica, VoidCallback onTap) => Tooltip(
        message: dica,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: H3Cores.painel2,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icone, size: 18, color: H3Cores.apagado),
          ),
        ),
      );

  Widget _bloco({
    required String rotulo,
    required IconData icone,
    required String valor,
    required double tamanho,
    double espaco = 1.5,
    required List<Widget> acoes,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: H3Cores.painel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: H3Cores.linha),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: H3Cores.destaque.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icone, size: 20, color: H3Cores.destaque),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo,
                  style: TextStyle(fontSize: 11.5, color: H3Cores.apagado)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(valor,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                        fontSize: tamanho,
                        letterSpacing: espaco,
                        fontWeight: FontWeight.w600,
                        color: H3Cores.texto)),
              ),
            ],
          ),
        ),
        ...acoes,
      ]),
    );
  }
}
