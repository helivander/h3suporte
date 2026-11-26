import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/shared_state.dart';
import '../../common/widgets/h3_estilo.dart';
import '../../common/widgets/toolbar.dart';
import '../../consts.dart';
import '../../models/chat_model.dart';
import '../../models/h3_comandos_rapidos.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';

/// Anunciado pelo agente que sabe travar teclado e mouse separadamente.
const kH3TravaSeparada = 'h3_input_lock';

/// Menu lateral com as ações da sessão. Reaproveita `toolbarControls` para
/// que as regras de permissão sejam as mesmas do menu da barra.
class H3PainelSessao extends StatelessWidget {
  final String id;
  final FFI ffi;
  const H3PainelSessao({Key? key, required this.id, required this.ffi})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() => ffi.h3PainelAberto.value
        ? Consumer<FfiModel>(
            builder: (context, _, __) => Obx(() {
                  // Reconstrói quando o modo privacidade muda.
                  PrivacyModeState.find(id).value;
                  return _painel(context);
                }))
        : const SizedBox.shrink());
  }

  Widget _painel(BuildContext context) {
    final t = H3Tokens.of(context);
    final m = ffi.ffiModel;
    final pi = m.pi;
    final podeControlar = m.keyboard && !m.viewOnly;
    final controles = {
      for (final c in toolbarControls(context, id, ffi))
        if (c.actionId != null && c.onPressed != null)
          c.actionId!: c.onPressed!
    };
    final blocos = <Widget>[];
    void bloco(IconData icone, String rotulo, VoidCallback? acao,
        {bool ativo = false}) {
      if (acao != null) blocos.add(_bloco(t, icone, rotulo, acao, ativo));
    }

    void rodar(H3Comando c) =>
        executarComandoRapido(ffi.sessionId, c, pi.platform);

    bloco(Icons.keyboard, 'Ctrl+Alt+Del',
        controles[kShortcutActionSendCtrlAltDel]);
    bloco(Icons.lock, 'Bloquear sessão', controles[kShortcutActionInsertLock]);
    bloco(Icons.refresh, 'Atualizar', controles[kShortcutActionRefresh]);
    bloco(
        Icons.photo_camera, 'Captura', controles[kShortcutActionScreenshot]);
    bloco(Icons.chat_bubble, 'Mensagem', () {
      ffi.chatModel
          .changeCurrentKey(MessageKey(ffi.id, ChatModel.clientModeID));
      ffi.chatModel.toggleChatOverlay();
    });
    if (podeControlar &&
        (pi.platform == kPeerPlatformWindows ||
            pi.platform == kPeerPlatformMacOS)) {
      bloco(Icons.public, 'Abrir site', () => _abrirSite(rodar));
    }
    if (podeControlar && pi.platform == kPeerPlatformWindows) {
      bloco(Icons.monitor_heart, 'Tarefas',
          () => rodar(const H3Comando.executar('Tarefas', 'taskmgr')));
      bloco(Icons.terminal, 'PowerShell',
          () => rodar(const H3Comando.executar('PowerShell', 'powershell')));
    }
    bloco(Icons.content_paste_go, 'Digitar cópia',
        controles[kShortcutActionSendClipboardKeystrokes]);
    if (m.permissions['recording'] != false || ffi.recordingModel.start) {
      blocos.add(ChangeNotifierProvider.value(
        value: ffi.recordingModel,
        child: Consumer<RecordingModel>(
            builder: (_, r, __) => _bloco(t, Icons.videocam,
                r.start ? 'Parar gravação' : 'Gravar sessão', r.toggle,
                r.start)),
      ));
    }
    bloco(Icons.restart_alt, 'Reiniciar PC',
        controles[kShortcutActionRestartRemote]);

    final privacidade =
        toolbarPrivacyMode(PrivacyModeState.find(id), context, id, ffi);
    final travas = _travas(t);

    return Material(
      color: t.painel,
      elevation: 12,
      shape: Border(left: BorderSide(color: t.linha)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Expanded(
              child: Text(pi.hostname,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: t.texto, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: translate('Close'),
              icon: Icon(Icons.close, color: t.apagado, size: 20),
              onPressed: () => ffi.h3PainelAberto.value = false,
            ),
          ]),
        ),
        Divider(height: 1, color: t.linha),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(14), children: [
            if (privacidade.isNotEmpty) ...[
              _titulo(t, 'Sessão'),
              for (final p in privacidade)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: t.destaque,
                  title: DefaultTextStyle.merge(
                      style: TextStyle(color: t.texto, fontSize: 13),
                      child: p.child),
                  value: p.value,
                  onChanged: p.onChanged,
                ),
            ],
            _titulo(t, 'Controle remoto'),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth < 260 ? 2 : 3;
              return GridView.count(
                crossAxisCount: cols,
                childAspectRatio: 1.15,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: blocos,
              );
            }),
            ...travas,
            _titulo(t, 'Arquivos'),
            _item(
                t,
                Icons.folder_open,
                'Arquivos da máquina',
                'Enviar, baixar e organizar arquivos da máquina',
                () => connect(context, id,
                    isFileTransfer: true,
                    connToken:
                        bind.sessionGetConnToken(sessionId: ffi.sessionId))),
            _titulo(t, 'Conexão'),
            _item(
                t,
                Icons.sync,
                'Reiniciar conexão',
                'Reconecta a sessão de tela',
                () => ffi.ffiModel
                    .reconnect(ffi.dialogManager, ffi.sessionId, false)),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _travas(H3Tokens t) {
    final m = ffi.ffiModel;
    if (m.pi.platform != kPeerPlatformWindows ||
        !m.keyboard ||
        m.viewOnly ||
        m.permissions['block_input'] == false) {
      return const [];
    }
    Widget chave(IconData icone, String titulo, String detalhe, RxBool estado,
            String ligar, String desligar) =>
        Obx(() => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: t.destaque,
              secondary: Icon(icone, color: t.destaque),
              title:
                  Text(titulo, style: TextStyle(color: t.texto, fontSize: 13)),
              subtitle: Text(detalhe,
                  style: TextStyle(color: t.apagado, fontSize: 11)),
              value: estado.value,
              onChanged: (v) {
                bind.sessionToggleOption(
                    sessionId: ffi.sessionId, value: v ? ligar : desligar);
                estado.value = v;
              },
            ));

    final separado = m.pi.platformAdditions[kH3TravaSeparada] == true;
    return [
      const SizedBox(height: 6),
      if (separado) ...[
        chave(
            Icons.keyboard,
            'Travar teclado do usuário',
            'Você continua digitando normalmente',
            ffi.h3TravaTeclado,
            'block-keyboard',
            'unblock-keyboard'),
        chave(
            Icons.mouse,
            'Travar mouse do usuário',
            'Inclui touchpad; você continua controlando',
            ffi.h3TravaMouse,
            'block-mouse',
            'unblock-mouse'),
      ] else
        chave(
            Icons.block,
            'Travar teclado e mouse',
            'Atualize o agente da máquina para travar separadamente',
            BlockInputState.find(id),
            'block-input',
            'unblock-input'),
    ];
  }

  void _abrirSite(void Function(H3Comando) rodar) {
    final url = TextEditingController(text: 'https://');
    String? erro;
    ffi.dialogManager.show((setState, close, context) {
      submit() {
        final uri = Uri.tryParse(url.text.trim());
        if (uri == null ||
            !(uri.isScheme('http') || uri.isScheme('https')) ||
            uri.host.isEmpty) {
          setState(() => erro = 'Informe um endereço http(s) válido');
          return;
        }
        close();
        // `uri.toString()` codifica espaços e quebras de linha antes de
        // o texto ser digitado na máquina remota.
        rodar(H3Comando.executar('Abrir site', uri.toString()));
      }

      return CustomAlertDialog(
        title: const Text('Abrir site na máquina'),
        content: TextField(
          controller: url,
          autofocus: true,
          decoration: InputDecoration(errorText: erro),
        ),
        actions: [
          dialogButton('Cancel', onPressed: close, isOutline: true),
          dialogButton('OK', onPressed: submit),
        ],
        onSubmit: submit,
        onCancel: close,
      );
    });
  }

  Widget _titulo(H3Tokens t, String texto) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(texto.toUpperCase(),
            style: TextStyle(
                color: t.apagado,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      );

  Widget _bloco(H3Tokens t, IconData icone, String rotulo, VoidCallback acao,
          bool ativo) =>
      Material(
        color: ativo ? t.linha2 : t.painel2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: t.linha)),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: acao,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icone, color: t.destaque, size: 22),
                  const SizedBox(height: 6),
                  Text(rotulo,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.texto,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ]),
          ),
        ),
      );

  Widget _item(H3Tokens t, IconData icone, String titulo, String detalhe,
          VoidCallback acao) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: t.painel2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.linha)),
          child: Icon(icone, color: t.destaque, size: 18),
        ),
        title: Text(titulo,
            style: TextStyle(
                color: t.texto, fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle:
            Text(detalhe, style: TextStyle(color: t.apagado, fontSize: 11)),
        onTap: acao,
      );
}
