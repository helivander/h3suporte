import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/h3_estilo.dart';
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
            const SizedBox(height: H3Raios.md),
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

  Widget _acao(IconData icone, String dica, VoidCallback onTap) =>
      _AcaoBotao(icone: icone, dica: dica, onTap: onTap);

  Widget _bloco({
    required String rotulo,
    required IconData icone,
    required String valor,
    required double tamanho,
    double espaco = 1.5,
    required List<Widget> acoes,
  }) {
    return LayoutBuilder(builder: (context, c) {
      final quebrarAcoes = c.maxWidth < 320 && acoes.length > 1;
      return Container(
        padding: const EdgeInsets.fromLTRB(
            H3Raios.md + 2, H3Raios.md, H3Raios.sm, H3Raios.md),
        decoration: BoxDecoration(
          color: H3Cores.painel2,
          borderRadius: BorderRadius.circular(H3Raios.md),
          border: Border.all(color: H3Cores.linha),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: H3Cores.destaque.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(H3Raios.sm),
                ),
                child: Icon(icone, size: 20, color: H3Cores.destaque),
              ),
              const SizedBox(width: H3Raios.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rotulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: H3Cores.apagado)),
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
              if (!quebrarAcoes) ...acoes,
            ]),
            if (quebrarAcoes) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: acoes,
              ),
            ],
          ],
        ),
      );
    });
  }
}

class _AcaoBotao extends StatefulWidget {
  final IconData icone;
  final String dica;
  final VoidCallback onTap;

  const _AcaoBotao({
    required this.icone,
    required this.dica,
    required this.onTap,
  });

  @override
  State<_AcaoBotao> createState() => _AcaoBotaoState();
}

class _AcaoBotaoState extends State<_AcaoBotao> {
  bool _hover = false;
  bool _foco = false;

  @override
  Widget build(BuildContext context) {
    final ativo = _hover || _foco;
    return Tooltip(
      message: widget.dica,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(H3Raios.sm),
          hoverColor: H3Cores.destaque.withOpacity(0.12),
          focusColor: H3Cores.destaque.withOpacity(0.18),
          splashColor: H3Cores.destaque.withOpacity(0.16),
          highlightColor: H3Cores.destaque.withOpacity(0.08),
          onHover: (v) => setState(() => _hover = v),
          onFocusChange: (v) => setState(() => _foco = v),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(H3Raios.sm),
              border: Border.all(
                color: _foco
                    ? H3Cores.destaque.withOpacity(0.55)
                    : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icone,
              size: 18,
              color: ativo ? H3Cores.destaque : H3Cores.apagado,
            ),
          ),
        ),
      ),
    );
  }
}
