import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/widgets/h3_estilo.dart';
import '../../models/file_model.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';

const _kPastasSalvas = 'h3-pastas-salvas';

/// Gerenciador de arquivos de painel único: só a máquina remota é navegada;
/// o computador do técnico é escolhido pelos seletores nativos.
class H3ArquivosView extends StatefulWidget {
  final FFI ffi;
  final String peerId;
  const H3ArquivosView({Key? key, required this.ffi, required this.peerId})
      : super(key: key);

  @override
  State<H3ArquivosView> createState() => _H3ArquivosViewState();
}

class _H3ArquivosViewState extends State<H3ArquivosView> {
  final _filtro = TextEditingController();
  final _caminho = TextEditingController();
  final _filtroFoco = FocusNode();
  final _listaFoco = FocusNode();
  final _avancar = <String>[];
  var _editandoCaminho = false;
  var _detalhes = true;
  var _transferencias = false;
  var _qtdTarefas = 0;
  var _unidades = <String>[];
  var _unidadesPedidas = false;
  var _salvas = <String>[];
  Entry? _ancora;
  Entry? _ultimoClique;
  var _ultimoCliqueMs = 0;
  late final Worker _aoMudarPasta;
  late final Worker _aoMudarTarefas;

  FileModel get _model => widget.ffi.fileModel;
  FileController get _remoto => _model.remoteController;
  JobController get _jobs => _model.jobController;
  SelectedItems get _sel => _remoto.selectedItems;
  bool get _windows => _remoto.options.value.isWindows;
  String get _pasta => _remoto.directory.value.path;
  H3Tokens get _t => H3Tokens.of(context);

  @override
  void initState() {
    super.initState();
    _salvas = _lerSalvas();
    _aoMudarPasta = ever(_remoto.directory, (_) {
      if (_pasta.isNotEmpty) _carregarUnidades();
      if (mounted) setState(() {});
    });
    _aoMudarTarefas = ever(_jobs.jobTable, (List<JobProgress> jobs) {
      if (jobs.length > _qtdTarefas && mounted) {
        setState(() => _transferencias = true);
      }
      _qtdTarefas = jobs.length;
    });
  }

  @override
  void dispose() {
    _aoMudarPasta.dispose();
    _aoMudarTarefas.dispose();
    _filtro.dispose();
    _caminho.dispose();
    _filtroFoco.dispose();
    _listaFoco.dispose();
    super.dispose();
  }

  List<String> _lerSalvas() {
    try {
      final v = bind.mainGetLocalOption(key: _kPastasSalvas);
      if (v.isEmpty) return [];
      return (jsonDecode(v) as List).map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('Pastas salvas inválidas: $e');
      return [];
    }
  }

  Future<void> _gravarSalvas(List<String> salvas) async {
    setState(() => _salvas = salvas);
    await bind.mainSetLocalOption(
        key: _kPastasSalvas, value: jsonEncode(salvas));
  }

  Future<void> _carregarUnidades() async {
    if (_unidadesPedidas || !_windows) return;
    _unidadesPedidas = true;
    try {
      final fd = await _model.fileFetcher.fetchDirectory('/', false, false);
      if (!mounted) return;
      setState(() => _unidades = fd.entries.map((e) => e.name).toList());
    } catch (e) {
      debugPrint('Falha ao listar unidades: $e');
      _unidadesPedidas = false;
    }
  }

  void _limparSelecao() {
    _sel.clear();
    _ancora = null;
  }

  Future<void> _abrir(String path) async {
    _limparSelecao();
    _filtro.clear();
    _avancar.clear();
    await _remoto.openDirectory(path);
  }

  void _voltar() {
    if (_remoto.history.isEmpty) return;
    _limparSelecao();
    _avancar.add(_pasta);
    _remoto.goBack();
  }

  Future<void> _seguir() async {
    if (_avancar.isEmpty) return;
    _limparSelecao();
    await _remoto.openDirectory(_avancar.removeLast());
  }

  void _subir() {
    _limparSelecao();
    _avancar.clear();
    _remoto.goToParentDirectory();
  }

  List<Entry> _visiveis() {
    final busca = _filtro.text.trim().toLowerCase();
    final todos = _remoto.directory.value.entries;
    if (busca.isEmpty) return todos;
    return todos.where((e) => e.name.toLowerCase().contains(busca)).toList();
  }

  void _clicar(Entry e, List<Entry> lista) {
    _listaFoco.requestFocus();
    final agora = DateTime.now().millisecondsSinceEpoch;
    final duplo = _ultimoClique?.path == e.path &&
        agora - _ultimoCliqueMs < bind.getDoubleClickTime();
    _ultimoClique = e;
    _ultimoCliqueMs = agora;
    if (duplo && (e.isDirectory || e.isDrive)) {
      _abrir(e.path);
      return;
    }
    final teclado = HardwareKeyboard.instance;
    if (teclado.isShiftPressed && _ancora != null) {
      final a = lista.indexWhere((x) => x.path == _ancora!.path);
      final b = lista.indexOf(e);
      if (a >= 0) {
        _sel.clear();
        for (final x in lista.sublist(a < b ? a : b, (a < b ? b : a) + 1)) {
          _sel.add(x);
        }
      }
    } else if (teclado.isControlPressed || teclado.isMetaPressed) {
      _alternar(e);
    } else {
      _sel.clear();
      _sel.add(e);
      _ancora = e;
    }
    // Unidades não entram na seleção, mas ainda precisam aparecer no detalhe.
    setState(() {});
  }

  void _alternar(Entry e) {
    _sel.items.contains(e) ? _sel.remove(e) : _sel.add(e);
    _ancora = e;
  }

  void _enviar(List<Entry> entradas) {
    if (entradas.isEmpty || _pasta.isEmpty || _pasta == '/') return;
    final itens = SelectedItems(isLocal: true);
    for (final e in entradas) {
      itens.add(e);
    }
    _model.localController.sendFiles(itens, _remoto.directoryData());
  }

  Entry? _entradaLocal(String path) {
    try {
      final pasta = FileSystemEntity.isDirectorySync(path);
      return Entry()
        ..path = path
        ..name = path.split(Platform.pathSeparator).last
        ..entryType = pasta ? 0 : 4
        ..size = pasta ? 0 : File(path).lengthSync();
    } on FileSystemException catch (e) {
      showToast(e.message);
      return null;
    }
  }

  void _enviarCaminhos(Iterable<String> caminhos) =>
      _enviar(caminhos.map(_entradaLocal).whereType<Entry>().toList());

  Future<void> _enviarArquivos() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null) return;
    _enviarCaminhos(r.paths.whereType<String>());
  }

  Future<void> _enviarPasta() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    _enviarCaminhos([dir]);
  }

  Future<void> _baixar() async {
    if (!SelectedItems.valid(_sel.items)) return;
    final destino = await FilePicker.platform.getDirectoryPath();
    if (destino == null) return;
    final local = DirectoryData(FileDirectory()..path = destino,
        DirectoryOptions(isWindows: isWindows));
    await _remoto.sendFiles(_sel, local);
  }

  Future<void> _apagar() async {
    if (!SelectedItems.valid(_sel.items)) return;
    await _remoto.removeAction(_sel);
    _limparSelecao();
  }

  void _renomear() {
    if (_sel.items.length == 1) _remoto.renameAction(_sel.items.first, false);
  }

  void _novaPasta() {
    if (_pasta.isEmpty || _pasta == '/') return;
    final nome = TextEditingController();
    String? erro;
    widget.ffi.dialogManager.show((setState, close, context) {
      submit() {
        final v = nome.text.trim();
        if (v.isEmpty) return;
        if (!PathUtil.validName(v, _windows)) {
          setState(() => erro = translate('Invalid folder name'));
          return;
        }
        _remoto.createDir(PathUtil.join(_pasta, v, _windows));
        close();
      }

      return CustomAlertDialog(
        title: const Text('Nova pasta'),
        content: TextField(
          controller: nome,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Nome', errorText: erro),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _t.fundo,
      padding: const EdgeInsets.all(12),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _filtroFoco.requestFocus,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _filtroFoco.requestFocus,
        },
        child: Column(children: [
          _barraSuperior(),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 220, child: _cartao(_lateral())),
                  const SizedBox(width: 10),
                  Expanded(child: _cartao(_centro())),
                  if (_detalhes && MediaQuery.of(context).size.width > 900) ...[
                    const SizedBox(width: 10),
                    SizedBox(width: 280, child: _cartao(Obx(_painelDetalhe))),
                  ],
                ]),
          ),
          const SizedBox(height: 10),
          _cartao(_barraTransferencias()),
        ]),
      ),
    );
  }

  Widget _cartao(Widget child) => Material(
        color: _t.painel,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _t.linha)),
        child: child,
      );

  Widget _icone(IconData icone, String dica, VoidCallback? onPressed,
          {bool ativo = false}) =>
      IconButton(
        tooltip: dica,
        icon: Icon(icone, size: 20),
        color: ativo ? _t.destaque : _t.texto,
        disabledColor: _t.apagado.withOpacity(0.4),
        onPressed: onPressed,
      );

  Widget _barraSuperior() {
    return Row(children: [
      _cartao(Row(children: [
        _icone(Icons.arrow_back, 'Voltar', _voltar),
        _icone(Icons.arrow_forward, 'Avançar',
            _avancar.isEmpty ? null : _seguir),
        _icone(Icons.arrow_upward, 'Pasta acima', _subir),
      ])),
      const SizedBox(width: 8),
      Expanded(flex: 3, child: _cartao(SizedBox(height: 40, child: _trilha()))),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: SizedBox(
          height: 40,
          child: TextField(
            controller: _filtro,
            focusNode: _filtroFoco,
            onChanged: (_) => setState(_limparSelecao),
            style: TextStyle(color: _t.texto, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Filtrar nesta pasta…',
              prefixIcon: Icon(Icons.search, size: 18, color: _t.apagado),
              contentPadding: EdgeInsets.zero,
              filled: true,
              fillColor: _t.painel,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
      _icone(
          _remoto.options.value.showHidden
              ? Icons.visibility
              : Icons.visibility_off,
          'Mostrar arquivos ocultos', () {
        _remoto.toggleShowHidden();
        setState(() {});
      }, ativo: _remoto.options.value.showHidden),
      _icone(Icons.refresh, 'Atualizar', _remoto.refresh),
      _icone(Icons.view_sidebar, 'Painel de detalhes',
          () => setState(() => _detalhes = !_detalhes),
          ativo: _detalhes),
    ]);
  }

  Widget _trilha() {
    if (_editandoCaminho) {
      return Focus(
        onFocusChange: (foco) {
          if (!foco) setState(() => _editandoCaminho = false);
        },
        child: TextField(
          controller: _caminho,
          autofocus: true,
          style: TextStyle(color: _t.texto, fontSize: 13),
          decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 12)),
          onSubmitted: (v) {
            setState(() => _editandoCaminho = false);
            if (v.trim().isNotEmpty) _abrir(v.trim());
          },
        ),
      );
    }
    final partes = _pasta.isEmpty || _pasta == '/'
        ? <String>[]
        : PathUtil.split(_pasta, _windows);
    var acumulado = '';
    final trilha = <Widget>[
      TextButton.icon(
        icon: Icon(Icons.folder, size: 16, color: _t.aviso),
        label: Text(widget.ffi.ffiModel.pi.hostname),
        onPressed: () => _abrir('/'),
      ),
    ];
    for (final p in partes) {
      acumulado =
          acumulado.isEmpty ? p : PathUtil.join(acumulado, p, _windows);
      final destino = acumulado;
      final rotulo = p.replaceAll('\\', '');
      if (rotulo.isEmpty || p == '/') continue;
      trilha.add(Icon(Icons.chevron_right, size: 14, color: _t.apagado));
      trilha.add(TextButton(
          onPressed: () => _abrir(destino), child: Text(rotulo)));
    }
    return InkWell(
      onTap: () => setState(() {
        _caminho.text = _pasta;
        _editandoCaminho = true;
      }),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(children: trilha),
      ),
    );
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Text(texto.toUpperCase(),
            style: TextStyle(
                color: _t.apagado,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      );

  Widget _atalho(IconData icone, String rotulo, String path,
      {Widget? trailing}) {
    final ativo = _pasta.isNotEmpty &&
        _pasta.toLowerCase().replaceAll(RegExp(r'[\\/]+$'), '') ==
            path.toLowerCase().replaceAll(RegExp(r'[\\/]+$'), '');
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: ativo,
      selectedTileColor: _t.painel2,
      leading: Icon(icone, size: 18, color: _t.destaque),
      minLeadingWidth: 18,
      title: Text(rotulo,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _t.texto, fontSize: 13)),
      trailing: trailing,
      onTap: () => _abrir(path),
    );
  }

  Widget _lateral() {
    final pi = widget.ffi.ffiModel.pi;
    final home = _remoto.options.value.home;
    String sob(String nome) => PathUtil.join(home, nome, _windows);
    return ListView(padding: const EdgeInsets.only(bottom: 12), children: [
      ListTile(
        leading: Icon(Icons.desktop_windows, color: _t.destaque),
        title: Text(pi.hostname,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _t.texto, fontWeight: FontWeight.w700)),
        subtitle: Text('${pi.username} conectado',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _t.ok, fontSize: 12)),
      ),
      Divider(height: 1, color: _t.linha),
      Row(children: [
        Expanded(child: _titulo('Pastas salvas')),
        TextButton(
          onPressed:
              _pasta.isEmpty || _pasta == '/' || _salvas.contains(_pasta)
                  ? null
                  : () => _gravarSalvas([..._salvas, _pasta]),
          child: const Text('Salvar esta', style: TextStyle(fontSize: 12)),
        ),
      ]),
      for (final s in _salvas)
        _atalho(Icons.bookmark, s, s,
            trailing: InkWell(
              onTap: () =>
                  _gravarSalvas(_salvas.where((x) => x != s).toList()),
              child: Icon(Icons.close, size: 14, color: _t.apagado),
            )),
      if (home.isNotEmpty) ...[
        _titulo('Usuário logado'),
        _atalho(Icons.desktop_windows_outlined, 'Área de Trabalho',
            sob('Desktop')),
        _atalho(Icons.description_outlined, 'Documentos', sob('Documents')),
        _atalho(Icons.download_outlined, 'Downloads', sob('Downloads')),
        _atalho(Icons.image_outlined, 'Imagens', sob('Pictures')),
        _atalho(Icons.person_outline, 'Pasta do usuário', home),
      ],
      _titulo('Este computador'),
      if (_windows)
        for (final u in _unidades)
          _atalho(Icons.storage, 'Disco ($u)', '$u\\')
      else
        _atalho(Icons.storage, 'Raiz (/)', '/'),
      if (_windows && home.isNotEmpty) ...[
        _titulo('Atalhos do técnico'),
        _atalho(Icons.auto_delete_outlined, 'Temporários do usuário',
            sob(r'AppData\Local\Temp')),
        _atalho(Icons.delete_sweep_outlined, 'Temporários do Windows',
            r'C:\Windows\Temp'),
        _atalho(Icons.apps, 'Arquivos de Programas', r'C:\Program Files'),
      ],
    ]);
  }

  Widget _acao(IconData icone, String rotulo, VoidCallback? onPressed) =>
      OutlinedButton.icon(
        icon: Icon(icone, size: 16),
        label: Text(rotulo),
        style: OutlinedButton.styleFrom(
            foregroundColor: _t.texto,
            side: BorderSide(color: _t.linha2),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8))),
        onPressed: onPressed,
      );

  Widget _barraAcoes() => Padding(
        padding: const EdgeInsets.all(10),
        child: Obx(() {
          final tem = SelectedItems.valid(_sel.items);
          final um = tem && _sel.items.length == 1;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            PopupMenuButton<bool>(
              tooltip: 'Enviar para esta pasta',
              onSelected: (pasta) =>
                  pasta ? _enviarPasta() : _enviarArquivos(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('Arquivos…')),
                PopupMenuItem(value: true, child: Text('Pasta…')),
              ],
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: _t.destaque,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.upload, size: 16, color: _t.destaqueTinta),
                  const SizedBox(width: 6),
                  Text('Enviar',
                      style: TextStyle(
                          color: _t.destaqueTinta,
                          fontWeight: FontWeight.w600)),
                  Icon(Icons.arrow_drop_down,
                      size: 18, color: _t.destaqueTinta),
                ]),
              ),
            ),
            _acao(Icons.create_new_folder_outlined, 'Nova pasta', _novaPasta),
            _acao(Icons.download, 'Baixar', tem ? _baixar : null),
            _acao(Icons.edit_outlined, 'Renomear', um ? _renomear : null),
            _acao(Icons.delete_outline, 'Apagar', tem ? _apagar : null),
            _acao(
                Icons.copy,
                'Copiar caminho',
                tem
                    ? () {
                        Clipboard.setData(ClipboardData(
                            text: _sel.items.map((e) => e.path).join('\n')));
                        showToast(translate('Copied'));
                      }
                    : null),
          ]);
        }),
      );

  Widget _cabecalho(String rotulo, SortBy ordem, {int? flex, double? largura}) {
    final ativo = _remoto.sortBy.value == ordem;
    final w = InkWell(
      onTap: () {
        _remoto.changeSortStyle(ordem,
            ascending: ativo ? !_remoto.sortAscending : true);
        setState(() {});
      },
      child: Row(children: [
        Text(rotulo,
            style: TextStyle(
                color: _t.apagado, fontSize: 12, fontWeight: FontWeight.w600)),
        if (ativo)
          Icon(
              _remoto.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: _t.apagado),
      ]),
    );
    return largura == null
        ? Expanded(flex: flex ?? 1, child: w)
        : SizedBox(width: largura, child: w);
  }

  String _data(Entry e) => e.isDrive || e.modifiedTime == 0
      ? '—'
      : e.lastModified().toString().substring(0, 16);

  String _tipo(Entry e) {
    if (e.isDrive) return 'Unidade';
    if (e.isDirectory) return 'Pasta';
    final ponto = e.name.lastIndexOf('.');
    return ponto > 0
        ? 'Arquivo ${e.name.substring(ponto + 1).toUpperCase()}'
        : 'Arquivo';
  }

  IconData _iconeDe(Entry e) => e.isDrive
      ? Icons.storage
      : e.isDirectory
          ? Icons.folder
          : Icons.insert_drive_file_outlined;

  Widget _centro() {
    final lista = _visiveis();
    return DropTarget(
      onDragDone: (d) => _enviarCaminhos(d.files.map((f) => f.path)),
      child: Column(children: [
        _barraAcoes(),
        Divider(height: 1, color: _t.linha),
        SizedBox(
          height: 34,
          child: Row(children: [
            SizedBox(
              width: 44,
              child: Obx(() => Checkbox(
                    value: lista.isNotEmpty && _sel.items.length == lista.length,
                    onChanged: (v) {
                      _sel.clear();
                      if (v == true) {
                        for (final e in lista) {
                          _sel.add(e);
                        }
                      }
                    },
                  )),
            ),
            _cabecalho('Nome', SortBy.name, flex: 3),
            _cabecalho('Modificado', SortBy.modified, largura: 130),
            _cabecalho('Tipo', SortBy.type, largura: 110),
            _cabecalho('Tamanho', SortBy.size, largura: 90),
          ]),
        ),
        Divider(height: 1, color: _t.linha),
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (_sel.items.length == 1 && _sel.items.first.isDirectory) {
                  _abrir(_sel.items.first.path);
                }
              },
              const SingleActivator(LogicalKeyboardKey.backspace): _voltar,
              const SingleActivator(LogicalKeyboardKey.f2): _renomear,
              const SingleActivator(LogicalKeyboardKey.delete): _apagar,
              const SingleActivator(LogicalKeyboardKey.keyA, control: true):
                  () => _sel.selectAll(lista.where((e) => !e.isDrive).toList()),
              const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () =>
                  _sel.selectAll(lista.where((e) => !e.isDrive).toList()),
            },
            child: Focus(
              focusNode: _listaFoco,
              autofocus: true,
              child: lista.isEmpty
                  ? Center(
                      child: Text(
                          _pasta.isEmpty
                              ? translate('Connecting...')
                              : 'Nada para mostrar',
                          style: TextStyle(color: _t.apagado)))
                  : ListView.builder(
                      itemCount: lista.length,
                      itemExtent: 36,
                      itemBuilder: (_, i) => _linha(lista[i], lista),
                    ),
            ),
          ),
        ),
        Divider(height: 1, color: _t.linha),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Obx(() => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    '${lista.length} itens'
                    '${_sel.items.isEmpty ? '' : ' · ${_sel.items.length} selecionado(s)'}',
                    style: TextStyle(color: _t.apagado, fontSize: 12)),
              )),
        ),
      ]),
    );
  }

  Widget _linha(Entry e, List<Entry> lista) {
    final apagado = TextStyle(color: _t.apagado, fontSize: 12);
    return Obx(() {
      final marcado = _sel.items.contains(e);
      return InkWell(
        onTap: () => _clicar(e, lista),
        child: Container(
          color: marcado ? _t.painel2 : null,
          child: Row(children: [
            SizedBox(
              width: 44,
              child: e.isDrive
                  ? null
                  : Checkbox(
                      value: marcado,
                      onChanged: (_) {
                        _alternar(e);
                        setState(() {});
                      }),
            ),
            Expanded(
              flex: 3,
              child: Row(children: [
                Icon(_iconeDe(e),
                    size: 18, color: e.isFile ? _t.apagado : _t.aviso),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _t.texto, fontSize: 13)),
                ),
              ]),
            ),
            SizedBox(width: 130, child: Text(_data(e), style: apagado)),
            SizedBox(
                width: 110,
                child: Text(_tipo(e),
                    overflow: TextOverflow.ellipsis, style: apagado)),
            SizedBox(
                width: 90,
                child: Text(
                    e.isFile ? readableFileSize(e.size.toDouble()) : '—',
                    style: apagado)),
          ]),
        ),
      );
    });
  }

  Widget _painelDetalhe() {
    final apagado = TextStyle(color: _t.apagado, fontSize: 12);
    if (_sel.items.length != 1) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 40),
        Icon(Icons.touch_app, size: 36, color: _t.apagado),
        const SizedBox(height: 10),
        Text(
            _sel.items.isEmpty
                ? 'Selecione um item'
                : '${_sel.items.length} itens selecionados',
            textAlign: TextAlign.center,
            style: TextStyle(color: _t.texto, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Dois cliques abrem a pasta.',
            textAlign: TextAlign.center, style: apagado),
        const SizedBox(height: 18),
        for (final a in const [
          'Enter  abrir',
          'Backspace  voltar',
          'F2  renomear',
          'Del  apagar',
          'Ctrl+A  todos',
          'Ctrl+F  filtrar',
        ])
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(a, textAlign: TextAlign.center, style: apagado)),
      ]);
    }
    final e = _sel.items.first;
    Widget campo(String rotulo, String valor) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: apagado),
            SelectableText(valor,
                style: TextStyle(color: _t.texto, fontSize: 13)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Icon(_iconeDe(e), size: 48, color: e.isFile ? _t.apagado : _t.aviso),
      const SizedBox(height: 10),
      SelectableText(e.name,
          textAlign: TextAlign.center,
          style: TextStyle(color: _t.texto, fontWeight: FontWeight.w700)),
      campo('Tipo', _tipo(e)),
      if (e.isFile) campo('Tamanho', readableFileSize(e.size.toDouble())),
      campo('Modificado', _data(e)),
      campo('Caminho', e.path),
    ]);
  }

  Widget _barraTransferencias() {
    return Obx(() {
      final jobs = _jobs.jobTable;
      final ativos = jobs.where((j) => j.state == JobState.inProgress).length;
      final resumo = jobs.isEmpty
          ? 'Nenhuma ainda — arraste arquivos para a lista para enviar'
          : '${jobs.length} no total · $ativos em andamento';
      return Column(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: () => setState(() => _transferencias = !_transferencias),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(Icons.swap_vert, size: 18, color: _t.destaque),
              const SizedBox(width: 8),
              Text('Transferências',
                  style: TextStyle(
                      color: _t.texto, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(resumo,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _t.apagado, fontSize: 12))),
              Icon(_transferencias ? Icons.expand_more : Icons.expand_less,
                  color: _t.apagado),
            ]),
          ),
        ),
        if (_transferencias && jobs.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 170),
            child: ListView(
                shrinkWrap: true,
                children: [for (final j in jobs.toList()) _tarefa(j)]),
          ),
      ]);
    });
  }

  Widget _tarefa(JobProgress j) {
    return ListTile(
      dense: true,
      leading: Icon(
          j.type != JobType.transfer
              ? Icons.delete_outline
              : j.isRemoteToLocal
                  ? Icons.download
                  : Icons.upload,
          size: 18,
          color: j.state == JobState.error ? _t.perigo : _t.destaque),
      title: Text(j.jobName,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _t.texto, fontSize: 12)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(j.getStatus(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _t.apagado, fontSize: 11)),
        if (j.type == JobType.transfer && j.state == JobState.inProgress)
          LinearProgressIndicator(
              value: j.percent.clamp(0.0, 1.0).toDouble(),
              color: _t.destaque,
              backgroundColor: _t.linha),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (j.state == JobState.paused)
          _icone(Icons.play_arrow, 'Retomar', () => _jobs.resumeJob(j.id)),
        _icone(Icons.close, 'Remover', () {
          _jobs.jobTable.remove(j);
          _jobs.cancelJob(j.id);
        }),
      ]),
    );
  }
}
