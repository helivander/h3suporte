import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/ai_agent_utils.dart';
import 'package:flutter_hbb/models/h3_comandos_rapidos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows oferece os comandos essenciais de TI', () {
    final titulos = comandosRapidosPara(kPeerPlatformWindows)
        .expand((g) => g.comandos)
        .map((c) => c.titulo)
        .toList();
    for (final t in [
      'Ctrl + Alt + Del',
      'Gerenciador de Tarefas',
      'Painel de Controle',
      'PowerShell',
      'Terminal do Windows',
      'Gerenciador de Dispositivos',
      'Editor do Registro',
    ]) {
      expect(titulos, contains(t));
    }
  });

  test(
      'toda combinação de teclas dos comandos é válida e nenhuma lista repete título',
      () {
    for (final p in [
      kPeerPlatformWindows,
      kPeerPlatformMacOS,
      kPeerPlatformLinux
    ]) {
      final todos = comandosRapidosPara(p).expand((g) => g.comandos).toList();
      expect(todos.map((c) => c.titulo).toSet().length, todos.length);
      for (final c in todos.where((c) => c.tipo == H3TipoComando.teclas)) {
        expect(parseAiKeyCombo(c.valor), isNotNull, reason: c.valor);
      }
    }
  });

  test('comando abre Win+R, digita e confirma; admin usa Ctrl+Shift+Enter', () {
    final normal = passosDe(
        const H3Comando.executar('x', 'taskmgr'), kPeerPlatformWindows);
    expect(normal.map((p) => p.$1 ?? p.$2), ['win+r', 'taskmgr', 'Return']);
    final admin = passosDe(const H3Comando.executar('x', 'cmd', admin: true),
        kPeerPlatformWindows);
    expect(admin.last.$1, 'ctrl+shift+Return');
    final mac =
        passosDe(const H3Comando.executar('x', 'Terminal'), kPeerPlatformMacOS);
    expect(mac.first.$1, 'command+space');
  });

  test(
      'ações de energia pedem confirmação e plataformas sem lista ficam sem menu',
      () {
    final grupoEnergia = comandosRapidosPara(kPeerPlatformWindows)
        .firstWhere((g) => g.titulo.startsWith('Energia'));
    final energia = grupoEnergia.comandos.where((c) =>
        c.valor.startsWith('shutdown /s') ||
        c.valor.startsWith('shutdown /r') ||
        c.valor == 'logoff');
    expect(energia.every((c) => c.confirmar != null && c.confirmar!.isNotEmpty),
        isTrue);
    final cancelar = grupoEnergia.comandos
        .firstWhere((c) => c.valor == 'shutdown /a');
    expect(cancelar.confirmar, isNull);
    expect(comandosRapidosPara(kPeerPlatformAndroid), isEmpty);
    expect(comandosRapidosPara(''), isEmpty);
    expect(comandosRapidosPara('desconhecido'), isEmpty);
  });

  test('macOS e Linux oferecem atalhos essenciais e valores não vazios', () {
    final macTitulos = comandosRapidosPara(kPeerPlatformMacOS)
        .expand((g) => g.comandos)
        .map((c) => c.titulo)
        .toList();
    expect(macTitulos,
        containsAll(['Bloquear tela', 'Terminal', 'Monitor de Atividade', 'Finder']));

    final linuxTitulos = comandosRapidosPara(kPeerPlatformLinux)
        .expand((g) => g.comandos)
        .map((c) => c.titulo)
        .toList();
    expect(linuxTitulos,
        containsAll(['Ctrl + Alt + Del', 'Bloquear tela', 'Abrir Terminal (Ctrl + Alt + T)']));

    for (final p in [
      kPeerPlatformWindows,
      kPeerPlatformMacOS,
      kPeerPlatformLinux,
    ]) {
      final todos = comandosRapidosPara(p).expand((g) => g.comandos);
      for (final c in todos) {
        if (c.tipo == H3TipoComando.executar || c.tipo == H3TipoComando.teclas) {
          expect(c.valor, isNotEmpty, reason: c.titulo);
        }
      }
    }
  });

  test('passosDe respeita pausas de abertura e digitação por plataforma', () {
    final win = passosDe(
        const H3Comando.executar('x', 'notepad'), kPeerPlatformWindows);
    expect(win, [('win+r', null, 800), (null, 'notepad', 250), ('Return', null, 0)]);

    final mac =
        passosDe(const H3Comando.executar('x', 'Finder'), kPeerPlatformMacOS);
    expect(mac, [('command+space', null, 700), (null, 'Finder', 250), ('Return', null, 0)]);
  });
}
