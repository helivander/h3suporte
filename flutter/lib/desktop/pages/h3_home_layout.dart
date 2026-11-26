import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/h3_estilo.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/pages/h3_meus_dispositivos.dart';
import 'package:flutter_hbb/desktop/pages/h3_permissoes.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Paleta da tela inicial e das Configurações (verde-água), nos temas escuro e claro.
class H3Cores {
  static bool escuro = true;
  static Color _c(int e, int c) => Color(escuro ? e : c);

  static Color get fundo => _c(0xFF070D10, 0xFFE9EFF1);
  static Color get painel => _c(0xFF0E171B, 0xFFFFFFFF);
  static Color get painel2 => _c(0xFF132026, 0xFFF4F8F9);
  static Color get linha => _c(0xFF1D2D33, 0xFFDCE5E8);
  static Color get linha2 => _c(0xFF26393F, 0xFFC9D6DA);
  static Color get texto => _c(0xFFE6F1F2, 0xFF13262B);
  static Color get apagado => _c(0xFF8AA1A6, 0xFF587177);
  static Color get destaque => _c(0xFF1FD1C1, 0xFF087F76);
  static Color get destaqueTinta => _c(0xFF04201D, 0xFFFFFFFF);
  static Color get ok => _c(0xFF3DDC84, 0xFF1C9A58);
  static Color get aviso => _c(0xFFF0B544, 0xFFB5730F);
  static Color get info => _c(0xFF4F8CFF, 0xFF2D6BDB);
  static Color get perigo => _c(0xFFFF5D6C, 0xFFC6283A);
  static Color get perigoTinta => const Color(0xFFFFFFFF);

  /// Tema verde-água; [brilho] vem do tema escolhido nas Configurações (Claro/Escuro/Sistema).
  static ThemeData tema(Brightness brilho) {
    escuro = brilho == Brightness.dark;
    final base = escuro ? MyTheme.darkTheme : MyTheme.lightTheme;
    return base.copyWith(
      scaffoldBackgroundColor: painel,
      cardColor: painel2,
      hoverColor: painel2,
      dividerColor: linha,
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        backgroundColor: destaque,
        foregroundColor: destaqueTinta,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      )),
      colorScheme: base.colorScheme.copyWith(
        primary: destaque,
        secondary: destaque,
        background: fundo,
      ),
      extensions: [
        ...base.extensions.values.where((e) => e is! H3Tokens),
        escuro ? H3Tokens.dark : H3Tokens.light,
      ],
    );
  }
}

/// Tela inicial do app de acesso (não usada no build `-cliente`, que é
/// incoming-only): menu lateral com Visão geral, Meus dispositivos e Relatórios.
/// Aba de Configurações aberta dentro da tela inicial (sem criar aba nova); null = fechada.
final h3ConfigAberta = Rxn<SettingsTabKey>();

/// Aba selecionada dentro das Configurações; a barra do topo mostra o título fixo de algumas.
final h3ConfigAbaAtual = Rxn<SettingsTabKey>();

class H3HomeLayout extends StatefulWidget {
  /// ID, senha e aviso de senha predefinida deste computador.
  final Widget deviceBoard;

  /// Avisos de instalação, atualização e permissões (vazio quando não há nada pendente).
  final Widget Function() helpCards;

  const H3HomeLayout(
      {Key? key, required this.deviceBoard, required this.helpCards})
      : super(key: key);

  @override
  State<H3HomeLayout> createState() => _H3HomeLayoutState();
}

class _H3HomeLayoutState extends State<H3HomeLayout> {
  final _aba = 0.obs;
  final _sessoesSaida = <String>[].obs;
  final _registrando = <String>{}.obs;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
        const Duration(seconds: 2), (_) => _atualizarSessoesSaida());
    _atualizarSessoesSaida();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// IDs das sessões abertas nas janelas de acesso remoto e de câmera.
  Future<void> _atualizarSessoesSaida() async {
    final ids = <String>[];
    try {
      for (final w in await rustDeskWinManager.getAllSubWindowIds()) {
        try {
          final r = await DesktopMultiWindow.invokeMethod(
              w, kWindowEventGetRemoteList, null);
          if (r is String && r.isNotEmpty) ids.addAll(r.split(','));
        } catch (_) {
          // Janelas de outros tipos não respondem a essa chamada.
        }
      }
    } catch (_) {}
    if (!listEquals(ids, _sessoesSaida.toList())) {
      _sessoesSaida.assignAll(ids);
    }
  }

  bool _ehAviso(Widget w) => w is Stack || w is Column;

  ThemeData _tema(BuildContext context) =>
      H3Cores.tema(Theme.of(context).brightness);

  @override
  Widget build(BuildContext context) {
    final tema = _tema(context);
    return Theme(
      key: ValueKey(H3Cores.escuro),
      data: tema,
      child: ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Container(
          color: H3Cores.fundo,
          child: Obx(() => h3ConfigAberta.value != null
              ? _configuracoes(h3ConfigAberta.value!)
              : _inicio()),
        ),
      ),
    );
  }

  Widget _configuracoes(SettingsTabKey aba) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Row(children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => h3ConfigAberta.value = null,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  H3Cores.destaque.withOpacity(0.20),
                  H3Cores.destaque.withOpacity(0.06)
                ]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: H3Cores.destaque.withOpacity(0.55)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: H3Cores.destaque),
                  child: Icon(Icons.arrow_back_rounded,
                      size: 18, color: H3Cores.destaqueTinta),
                ),
                const SizedBox(width: 12),
                Text('Voltar ao sistema',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: H3Cores.texto)),
              ]),
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Obx(() {
              final t = {
                SettingsTabKey.general: [
                  'Geral',
                  'Idioma, tema, serviço e preferências do aplicativo.'
                ],
                SettingsTabKey.safety: [
                  'Segurança',
                  'Controle quem pode acessar este computador e como.'
                ],
                SettingsTabKey.network: [
                  'Rede',
                  'Servidor, proxy e opções de conexão.'
                ],
                SettingsTabKey.display: [
                  'Exibição',
                  'Qualidade de imagem, codec e comportamento das sessões.'
                ],
                SettingsTabKey.account: [
                  'Conta',
                  'Seus dados, plano e uso em tempo real.'
                ],
                SettingsTabKey.printer: [
                  'Impressora',
                  'Impressão a partir do computador remoto.'
                ],
                SettingsTabKey.ia: [
                  'IA',
                  'Provedor, modelo e comportamento do assistente.'
                ],
                SettingsTabKey.about: [
                  'Sobre',
                  'Informações da versão instalada neste computador.'
                ],
              }[h3ConfigAbaAtual.value];
              if (t == null) return const SizedBox.shrink();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t[0],
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: H3Cores.texto)),
                    Text(t[1],
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: H3Cores.apagado)),
                  ]);
            }),
          ),
          Tooltip(
            message: 'Fechar',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => h3ConfigAberta.value = null,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: H3Cores.painel2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: H3Cores.linha2),
                ),
                child: Icon(Icons.close_rounded, size: 20, color: H3Cores.texto),
              ),
            ),
          ),
        ]),
      ),
      Expanded(
          child: DesktopSettingPage(
              key: const ValueKey('h3-config'), initialTabkey: aba)),
    ]);
  }

  Widget _inicio() {
    return Builder(builder: (context) {
      return LayoutBuilder(builder: (context, c) {
            final compacto = c.maxWidth < 900;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _menu(compacto),
                Expanded(
                  child: Obx(() {
                    final aba = _aba.value;
                    final Widget pagina;
                    switch (aba) {
                      case 1:
                        pagina = const H3MeusDispositivosPage();
                        break;
                      case 2:
                        pagina = _relatorios();
                        break;
                      case 3:
                        pagina = _permissoes();
                        break;
                      case 0:
                      default:
                        pagina = _visaoGeral();
                        break;
                    }
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 165),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animacao) => FadeTransition(
                        opacity: animacao,
                        child: child,
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(aba),
                        child: pagina,
                      ),
                    );
                  }),
                ),
              ],
            );
          });
    });
  }

  Widget _menu(bool compacto) {
    Widget item(IconData icone, String rotulo, VoidCallback onTap,
        {int? aba, bool selo = false}) {
      return Obx(() {
        final selecionada = _aba.value;
        final ativo = aba != null && selecionada == aba;
        // O aviso de atualização tem lugar próprio no menu (acima da conta).
        final pendente = selo &&
            stateGlobal.updateUrl.value.isEmpty &&
            _ehAviso(widget.helpCards());
        final ponto = Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: H3Cores.aviso),
        );
        final botao = _MenuLateralItem(
          icone: icone,
          rotulo: rotulo,
          compacto: compacto,
          ativo: ativo,
          pendente: pendente,
          ponto: ponto,
          onTap: onTap,
        );
        return compacto ? Tooltip(message: rotulo, child: botao) : botao;
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
      child: Container(
      width: compacto ? 68 : 220,
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [H3Cores.painel2, H3Cores.painel]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: H3Cores.linha),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _marca(compacto),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  item(Icons.home_outlined, 'Visão geral', () => _aba.value = 0,
                      aba: 0),
                  const SizedBox(height: 2),
                  item(Icons.devices_outlined, 'Meus dispositivos',
                      () => _aba.value = 1,
                      aba: 1),
                  const SizedBox(height: 2),
                  item(Icons.insights_outlined, 'Relatórios',
                      () => _aba.value = 2,
                      aba: 2),
                  const SizedBox(height: 2),
                  item(Icons.verified_user_outlined, 'Permissões',
                      () => _aba.value = 3,
                      aba: 3, selo: true),
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: H3Cores.linha)),
                  item(Icons.settings_outlined, 'Configurações',
                      () => DesktopTabPage.onAddSetting()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _atualizacao(compacto),
          _conta(compacto),
        ],
      ),
      ),
    );
  }

  Widget _marca(bool compacto) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 18),
      child: Column(
        children: [
          loadIcon(compacto ? 38 : 64),
          if (!compacto) ...[
            const SizedBox(height: 10),
            Text('H3 Suporte',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: H3Cores.texto)),
          ],
        ],
      ),
    );
  }

  /// Nova versão disponível: fica no menu, acima do cartão da conta.
  Widget _atualizacao(bool compacto) {
    return Obx(() {
      final url = stateGlobal.updateUrl.value;
      if (url.isEmpty) return const SizedBox.shrink();
      final instalar = (isWindows || isMacOS) && bind.mainIsInstalled();
      final versao = bind.mainGetNewVersion();
      void abrir() {
        if (instalar) {
          handleUpdate(url);
        } else {
          launchUrl(Uri.parse(url));
        }
      }

      final icone = Icon(Icons.system_update_alt_rounded,
          size: 18, color: H3Cores.destaqueTinta);
      if (compacto) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Tooltip(
            message: 'Nova versão $versao: ${instalar ? 'atualizar' : 'baixar'}',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: abrir,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: H3Cores.destaque,
                      borderRadius: BorderRadius.circular(10)),
                  child: icone,
                ),
              ),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: abrir,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                H3Cores.destaque.withOpacity(0.22),
                H3Cores.destaque.withOpacity(0.06)
              ]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: H3Cores.destaque.withOpacity(0.55)),
            ),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: H3Cores.destaque,
                    borderRadius: BorderRadius.circular(9)),
                child: icone,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Atualização disponível',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: H3Cores.texto)),
                    Text(
                        '${versao.isEmpty ? 'Nova versão' : 'Versão $versao'} · ${instalar ? 'Atualizar' : 'Baixar'}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: H3Cores.destaque)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _conta(bool compacto) {
    return Obx(() {
      final logado = gFFI.userModel.isLogin;
      final nome = gFFI.userModel.displayNameOrUserName;
      final avatar = CircleAvatar(
        radius: 16,
        backgroundColor: logado ? H3Cores.destaque : H3Cores.linha2,
        child: logado
            ? Text(nome.isEmpty ? '?' : nome.substring(0, 1).toUpperCase(),
                style: TextStyle(
                    color: H3Cores.destaqueTinta,
                    fontWeight: FontWeight.bold))
            : Icon(Icons.person_outline,
                size: 18, color: H3Cores.apagado),
      );
      final entrar = () async {
        if (logado) {
          DesktopSettingPage.switch2page(SettingsTabKey.account);
        } else {
          await loginDialog();
        }
      };
      if (compacto) {
        return Tooltip(
            message: logado ? nome : 'Entrar',
            child: InkWell(
                customBorder: const CircleBorder(),
                onTap: entrar,
                child: Center(child: avatar)));
      }
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: entrar,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: H3Cores.painel2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: H3Cores.linha2),
          ),
          child: Row(children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Conta H3 Suporte',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: H3Cores.apagado)),
                  Text(logado ? nome : 'Entrar',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: logado ? H3Cores.texto : H3Cores.destaque)),
                  if (logado)
                    Obx(() {
                      final n = _sessoesSaida.length +
                          gFFI.serverModel.clients
                              .where((c) => !c.disconnected)
                              .length;
                      return Text(
                          n == 0
                              ? 'Nenhuma sessão agora'
                              : '$n ${n == 1 ? 'sessão' : 'sessões'} agora',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: n == 0 ? H3Cores.apagado : H3Cores.ok));
                    }),
                ],
              ),
            ),
          ]),
        ),
      );
    });
  }

  Widget _cartao(
      {String? titulo,
      String? subtitulo,
      Widget? acao,
      IconData? icone,
      required Widget filho,
      bool expandir = false,
      EdgeInsets padding = const EdgeInsets.all(18)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [H3Cores.painel2, H3Cores.painel]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: H3Cores.linha),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandir ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (titulo != null)
          Row(children: [
            if (icone != null) ...[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        H3Cores.destaque.withOpacity(0.28),
                        H3Cores.destaque.withOpacity(0.08)
                      ]),
                ),
                child: Icon(icone, size: 20, color: H3Cores.destaque),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: H3Cores.texto)),
                  if (subtitulo != null)
                    Text(subtitulo,
                        style: TextStyle(
                            fontSize: 12.5, color: H3Cores.apagado)),
                ],
              ),
            ),
            if (acao != null) acao,
          ]),
          if (titulo != null) const SizedBox(height: 12),
          expandir ? Expanded(child: filho) : filho,
        ],
      ),
    );
  }

  // ---------- Visão geral ----------

  Widget _visaoGeral() {
    final mostrarEstePc = !bind.isOutgoingOnly();
    final conexoes = _cartao(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      expandir: true,
      filho: const H3Estilo(child: ConnectionPage(h3: true)),
    );
    final esteComputador = _cartao(
      titulo: 'Este computador',
      subtitulo: 'Passe o ID e a senha para quem vai acessar.',
      filho: widget.deviceBoard,
    );
    return LayoutBuilder(builder: (context, c) {
      final largo = c.maxWidth >= 780;
      final larguraDireita = (c.maxWidth * 0.35).clamp(330.0, 440.0);
      final alturaConexoesCompacta = (c.maxHeight * 0.58).clamp(420.0, 620.0);
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: largo
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: conexoes),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: larguraDireita,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (mostrarEstePc) ...[
                                esteComputador,
                                const SizedBox(height: 16),
                              ],
                              _sessaoAtual(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (mostrarEstePc) ...[
                          esteComputador,
                          const SizedBox(height: 16),
                        ],
                        _sessaoAtual(),
                        const SizedBox(height: 16),
                        SizedBox(height: alturaConexoesCompacta, child: conexoes),
                      ],
                    ),
                  ),
          ),
        ),
      );
    });
  }

  Peer? _peer(String id) {
    for (final p in gFFI.recentPeersModel.peers) {
      if (p.id == id) return p;
    }
    return null;
  }

  Widget _sessaoAtual() {
    return Consumer<ServerModel>(builder: (context, model, _) {
      final entrada = model.clients.where((c) => !c.disconnected).toList();
      return Obx(() {
        final saida = _sessoesSaida.toList();
        final linhas = <Widget>[
          for (final id in saida)
            _linhaSessao(
              icone: Icons.north_east,
              cor: H3Cores.destaque,
              titulo: _nomePeer(id),
              detalhe: 'Você está acessando · $id',
              acao: Row(mainAxisSize: MainAxisSize.min, children: [
                if (gFFI.userModel.userName.value.isNotEmpty)
                  _registrando.contains(id)
                      ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : Tooltip(
                          message:
                              'Guardar este computador em Meus dispositivos',
                          child: TextButton(
                            onPressed: () => _registrarRemoto(id),
                            child: Text('Registrar',
                                style: TextStyle(color: H3Cores.texto)),
                          ),
                        ),
                TextButton(
                  onPressed: () => connect(context, id),
                  child: Text('Abrir',
                      style: TextStyle(color: H3Cores.destaque)),
                ),
              ]),
            ),
          for (final c in entrada)
            _linhaSessao(
              icone: Icons.south_west,
              cor: H3Cores.aviso,
              titulo: c.name.isEmpty ? c.peerId : c.name,
              detalhe: '${_tipoEntrada(c)} neste computador · ${c.peerId}',
            ),
        ];
        final ativo = linhas.isNotEmpty;
        return _cartao(
          titulo: 'Sessão em andamento',
          icone: Icons.sensors,
          subtitulo: ativo
              ? '${linhas.length} ${linhas.length == 1 ? 'acesso ativo' : 'acessos ativos'}'
              : 'Nenhum acesso remoto ativo',
          acao: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ativo ? H3Cores.ok : H3Cores.linha2,
              boxShadow: ativo
                  ? [BoxShadow(color: H3Cores.ok.withOpacity(0.6), blurRadius: 8)]
                  : null,
            ),
          ),
          filho: ativo
              ? Column(mainAxisSize: MainAxisSize.min, children: linhas)
              : Container(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                  decoration: BoxDecoration(
                    color: H3Cores.fundo,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: H3Cores.linha),
                  ),
                  child: Row(children: [
                    Icon(Icons.wifi_tethering_off,
                        size: 22, color: H3Cores.apagado),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          'Quando alguém acessar este computador, ou você acessar outro, a sessão aparece aqui.',
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: H3Cores.apagado)),
                    ),
                  ]),
                ),
        );
      });
    });
  }

  /// Sessão (da janela de acesso remoto) aberta para [id].
  Future<SessionID?> _sessaoDe(String id) async {
    for (final w in await rustDeskWinManager.getAllSubWindowIds()) {
      try {
        final r = await DesktopMultiWindow.invokeMethod(
            w, kWindowEventGetSessionIdList, null);
        if (r is! String) continue;
        for (final par in r.split(';')) {
          final p = par.split(',');
          if (p.length == 2 && p[0] == id) return SessionID(p[1]);
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _registrarRemoto(String id) async {
    final nome = _nomePeer(id);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: H3Cores.painel2,
        title: Text('Registrar $nome em Meus dispositivos?'),
        content: const Text(
            'O computador acessado recebe uma nova senha permanente, gerada aqui. A senha permanente que ele tinha '
            'deixa de valer. A nova senha não aparece nele: fica guardada, cifrada, só na sua conta H3 Suporte, '
            'para você acessá-lo de novo com um clique em Meus dispositivos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Registrar',
                  style: TextStyle(color: H3Cores.destaque))),
        ],
      ),
    );
    if (confirmou != true) return;
    _registrando.add(id);
    try {
      final sessao = await _sessaoDe(id);
      if (sessao == null) throw H3Erro('A sessão foi encerrada.');
      await H3Dispositivos.registrarRemoto(id, sessao);
      showToast('$nome registrado em Meus dispositivos.');
    } on H3Erro catch (e) {
      showToast(e.mensagem, timeout: const Duration(seconds: 6));
    } catch (e) {
      showToast('Não foi possível registrar: $e',
          timeout: const Duration(seconds: 6));
    } finally {
      _registrando.remove(id);
    }
  }

  String _nomePeer(String id) {
    final p = _peer(id);
    if (p == null) return id;
    if (p.alias.isNotEmpty) return p.alias;
    if (p.hostname.isNotEmpty) return p.hostname;
    return id;
  }

  String _tipoEntrada(Client c) {
    if (c.isFileTransfer) return 'Transferência de arquivos';
    if (c.isTerminal) return 'Terminal';
    if (c.isViewCamera) return 'Câmera';
    if (c.portForward.isNotEmpty) return 'Túnel';
    return 'Acesso remoto';
  }

  Widget _linhaSessao(
      {required IconData icone,
      required Color cor,
      required String titulo,
      required String detalhe,
      Widget? acao}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: H3Cores.fundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: H3Cores.linha2),
      ),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: cor.withOpacity(0.14),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icone, size: 18, color: cor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: H3Cores.texto)),
              Text(detalhe,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11.5, color: H3Cores.apagado)),
            ],
          ),
        ),
        if (acao != null) acao,
      ]),
    );
  }

  // ---------- Permissões ----------

  Widget _permissoes() => const H3Permissoes();

  // ---------- Relatórios ----------

  Widget _titulo(String t, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: H3Cores.texto)),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(fontSize: 13, color: H3Cores.apagado)),
        ],
      );

  /// Distribui [itens] em colunas iguais e linhas de mesma altura.
  Widget _grade(List<Widget> itens, {double minimo = 230}) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 16.0;
      var cols = ((c.maxWidth + gap) / (minimo + gap)).floor().clamp(1, 4);
      if (itens.length == 4 && cols == 3) cols = 2;
      cols = cols.clamp(1, itens.length.clamp(1, 4));
      final linhas = <Widget>[];
      for (var i = 0; i < itens.length; i += cols) {
        final fatia = itens.skip(i).take(cols).toList();
        linhas.add(Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) const SizedBox(width: gap),
                Expanded(
                    child: j < fatia.length ? fatia[j] : const SizedBox.shrink()),
              ],
            ]),
          ),
        ));
      }
      return Column(children: linhas);
    });
  }

  Widget _relatorios() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titulo('Relatórios', 'Resumo das suas sessões, dispositivos e da segurança deste computador.'),
              const SizedBox(height: 18),
              _indicadores(),
              const SizedBox(height: 26),
              _titulo('Segurança e acesso', 'Como este computador aceita conexões. Toque para ajustar.'),
              const SizedBox(height: 14),
              _seguranca(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _indicadores() {
    final listas = Listenable.merge([
      gFFI.recentPeersModel,
      gFFI.favoritePeersModel,
      gFFI.lanPeersModel,
      gFFI.serverModel,
    ]);
    return AnimatedBuilder(
      animation: listas,
      builder: (context, _) => Obx(() {
        final recentes = gFFI.recentPeersModel.peers;
        final online = recentes.where((p) => p.online).length;
        final entrada =
            gFFI.serverModel.clients.where((c) => !c.disconnected).length;
        final saida = _sessoesSaida.length;
        return _grade([
          _indicador(Icons.layers_outlined, H3Cores.info, 'Sessões ativas',
              '${saida + entrada}', '$saida saindo · $entrada entrando'),
          _indicador(Icons.desktop_windows_outlined, H3Cores.destaque,
              'Dispositivos', '${recentes.length}', '$online online · recentes',
              progresso: recentes.isEmpty ? 0 : online / recentes.length),
          _indicador(Icons.star_outline, H3Cores.aviso, 'Favoritos',
              '${gFFI.favoritePeersModel.peers.length}', 'marcados por você'),
          _indicador(Icons.lan_outlined, H3Cores.ok, 'Na rede local',
              '${gFFI.lanPeersModel.peers.length}', 'encontrados na rede'),
        ], minimo: 210);
      }),
    );
  }

  Widget _indicador(IconData icone, Color cor, String rotulo, String valor,
      String nota,
      {double? progresso}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [H3Cores.painel2, H3Cores.painel]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: H3Cores.linha),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cor.withOpacity(0.28), cor.withOpacity(0.08)]),
            ),
            child: Icon(icone, color: cor, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(rotulo,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: H3Cores.apagado)),
          ),
        ]),
        const SizedBox(height: 14),
        Text(valor,
            style: TextStyle(
                fontSize: 34,
                height: 1,
                fontWeight: FontWeight.w700,
                color: H3Cores.texto)),
        const SizedBox(height: 8),
        Text(nota, style: TextStyle(fontSize: 12, color: H3Cores.apagado)),
        const Spacer(),
        if (progresso != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                minHeight: 5,
                value: progresso,
                backgroundColor: H3Cores.linha,
                valueColor: AlwaysStoppedAnimation(cor)),
          ),
        ],
      ]),
    );
  }

  Widget _seguranca() {
    return Consumer<ServerModel>(builder: (context, model, _) {
      final senha = {
            kUseTemporaryPassword: 'Senha de uso único',
            kUsePermanentPassword: 'Senha permanente',
          }[model.verificationMethod] ??
          'Uso único e permanente';
      final aprovacao = model.approveMode == 'password'
          ? 'Só por senha'
          : model.approveMode == 'click'
              ? 'Só por clique'
              : 'Senha ou clique';
      final doisFatores = bind.mainHasValid2FaSync();
      final gravar = mainGetBoolOptionSync(kOptionAllowAutoRecordIncoming);
      return _grade([
        _tileSeguranca(Icons.lock_outline, 'Autenticação em 2 etapas',
            doisFatores ? 'Ativada' : 'Desativada', doisFatores),
        _tileSeguranca(Icons.key_outlined, 'Senha aceita', senha, true),
        _tileSeguranca(Icons.how_to_reg_outlined, 'Aprovar conexões', aprovacao,
            model.approveMode != ''),
        _tileSeguranca(Icons.videocam_outlined, 'Gravar sessões de entrada',
            gravar ? 'Ativada' : 'Desativada', gravar),
      ], minimo: 210);
    });
  }

  Widget _tileSeguranca(
      IconData icone, String titulo, String valor, bool ligado) {
    final cor = ligado ? H3Cores.ok : H3Cores.apagado;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => DesktopSettingPage.switch2page(SettingsTabKey.safety),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: H3Cores.painel2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: H3Cores.linha),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icone, size: 22, color: H3Cores.apagado),
            const Spacer(),
            Icon(Icons.chevron_right, size: 20, color: H3Cores.apagado),
          ]),
          const SizedBox(height: 14),
          Text(titulo,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: H3Cores.texto)),
          const Spacer(),
          const SizedBox(height: 10),
          Row(children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(valor,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: cor)),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _MenuLateralItem extends StatefulWidget {
  final IconData icone;
  final String rotulo;
  final bool compacto;
  final bool ativo;
  final bool pendente;
  final Widget ponto;
  final VoidCallback onTap;

  const _MenuLateralItem({
    required this.icone,
    required this.rotulo,
    required this.compacto,
    required this.ativo,
    required this.pendente,
    required this.ponto,
    required this.onTap,
  });

  @override
  State<_MenuLateralItem> createState() => _MenuLateralItemState();
}

class _MenuLateralItemState extends State<_MenuLateralItem> {
  bool _hover = false;
  bool _foco = false;

  @override
  Widget build(BuildContext context) {
    final ativo = widget.ativo;
    final realce = _hover || _foco;
    final corBorda = _foco
        ? H3Cores.destaque.withOpacity(0.65)
        : ativo
            ? H3Cores.destaque.withOpacity(0.24)
            : (_hover ? H3Cores.linha2 : Colors.transparent);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(H3Raios.md),
        hoverColor: H3Cores.destaque.withOpacity(0.08),
        focusColor: H3Cores.destaque.withOpacity(0.14),
        splashColor: H3Cores.destaque.withOpacity(0.12),
        highlightColor: H3Cores.destaque.withOpacity(0.06),
        onHover: (v) => setState(() => _hover = v),
        onFocusChange: (v) => setState(() => _foco = v),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
              horizontal: widget.compacto ? 0 : H3Raios.md, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(H3Raios.md),
            border: Border.all(color: corBorda),
            gradient: ativo
                ? LinearGradient(colors: [
                    H3Cores.destaque.withOpacity(_hover ? 0.28 : 0.22),
                    H3Cores.destaque.withOpacity(_hover ? 0.10 : 0.06),
                  ])
                : null,
            color: !ativo && realce
                ? H3Cores.destaque.withOpacity(_foco ? 0.10 : 0.06)
                : null,
          ),
          child: Row(
            mainAxisAlignment: widget.compacto
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Stack(clipBehavior: Clip.none, children: [
                Icon(widget.icone,
                    size: 20,
                    color: ativo
                        ? H3Cores.destaque
                        : (realce ? H3Cores.texto : H3Cores.apagado)),
                if (widget.pendente && widget.compacto)
                  Positioned(right: -2, top: -2, child: widget.ponto),
              ]),
              if (!widget.compacto) ...[
                const SizedBox(width: H3Raios.md),
                Expanded(
                  child: Text(widget.rotulo,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
                          color: (ativo || realce)
                              ? H3Cores.texto
                              : H3Cores.apagado)),
                ),
                if (widget.pendente) widget.ponto,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
