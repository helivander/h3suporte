import 'package:flutter_hbb/common.dart' show SessionID;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/ai_agent_utils.dart';
import 'package:flutter_hbb/models/platform_model.dart';

enum H3TipoComando { executar, teclas, ctrlAltDel, bloquear }

/// Um atalho do menu "Comandos rápidos". `executar` abre o diálogo Executar (Windows) ou o Spotlight (macOS) e digita
/// [valor]; `teclas` envia a combinação [valor] (ex.: "ctrl+shift+esc").
class H3Comando {
  final String titulo;
  final H3TipoComando tipo;
  final String valor;
  final bool admin;
  final String? confirmar;

  const H3Comando(this.titulo, this.tipo,
      {this.valor = '', this.admin = false, this.confirmar});

  const H3Comando.executar(String titulo, String comando,
      {bool admin = false, String? confirmar})
      : this(titulo, H3TipoComando.executar,
            valor: comando, admin: admin, confirmar: confirmar);

  const H3Comando.teclas(String titulo, String combinacao)
      : this(titulo, H3TipoComando.teclas, valor: combinacao);
}

class H3GrupoComandos {
  final String titulo;
  final List<H3Comando> comandos;
  const H3GrupoComandos(this.titulo, this.comandos);
}

const _terminalAdmin = 'Como administrador (pede UAC)';

const _windows = <H3GrupoComandos>[
  H3GrupoComandos('Atalhos do sistema', [
    H3Comando('Ctrl + Alt + Del', H3TipoComando.ctrlAltDel),
    H3Comando('Bloquear tela', H3TipoComando.bloquear),
    H3Comando.executar('Gerenciador de Tarefas', 'taskmgr'),
    H3Comando.teclas('Menu Iniciar (tecla Windows)', 'win'),
    H3Comando.teclas('Menu Win + X (ferramentas)', 'win+x'),
    H3Comando.teclas('Mostrar a área de trabalho (Win + D)', 'win+d'),
    H3Comando.teclas('Alternar janelas (Alt + Tab)', 'alt+Tab'),
    H3Comando.teclas('Fechar janela (Alt + F4)', 'alt+f4'),
    H3Comando.teclas('Captura de tela (Print Screen)', 'PrintScreen'),
  ]),
  H3GrupoComandos('Terminais', [
    H3Comando.executar('Terminal do Windows', 'wt'),
    H3Comando.executar('PowerShell', 'powershell'),
    H3Comando.executar('Prompt de Comando (CMD)', 'cmd'),
    H3Comando.executar('PowerShell — $_terminalAdmin', 'powershell',
        admin: true),
    H3Comando.executar('Prompt de Comando — $_terminalAdmin', 'cmd',
        admin: true),
  ]),
  H3GrupoComandos('Painéis e configurações', [
    H3Comando.executar('Painel de Controle', 'control'),
    H3Comando.executar('Configurações do Windows', 'ms-settings:'),
    H3Comando.executar('Windows Update', 'ms-settings:windowsupdate'),
    H3Comando.executar('Programas e Recursos (desinstalar)', 'appwiz.cpl'),
    H3Comando.executar('Propriedades do Sistema', 'sysdm.cpl'),
    H3Comando.executar('Conexões de Rede', 'ncpa.cpl'),
    H3Comando.executar('Firewall do Windows', 'firewall.cpl'),
    H3Comando.executar('Opções de Energia', 'powercfg.cpl'),
    H3Comando.executar('Vídeo e Resolução', 'ms-settings:display'),
    H3Comando.executar('Som', 'mmsys.cpl'),
    H3Comando.executar('Impressoras e Scanners', 'ms-settings:printers'),
    H3Comando.executar('Data e Hora', 'timedate.cpl'),
    H3Comando.executar('Contas de Usuário', 'netplwiz'),
    H3Comando.executar('Credenciais (Gerenciador)', 'control keymgr.dll'),
  ]),
  H3GrupoComandos('Gerenciamento', [
    H3Comando.executar('Gerenciamento do Computador', 'compmgmt.msc'),
    H3Comando.executar('Gerenciador de Dispositivos', 'devmgmt.msc'),
    H3Comando.executar('Gerenciamento de Disco', 'diskmgmt.msc'),
    H3Comando.executar('Serviços', 'services.msc'),
    H3Comando.executar('Visualizador de Eventos', 'eventvwr.msc'),
    H3Comando.executar('Agendador de Tarefas', 'taskschd.msc'),
    H3Comando.executar('Usuários e Grupos Locais', 'lusrmgr.msc'),
    H3Comando.executar('Pastas Compartilhadas', 'fsmgmt.msc'),
    H3Comando.executar('Política de Segurança Local', 'secpol.msc'),
    H3Comando.executar('Política de Grupo Local', 'gpedit.msc'),
    H3Comando.executar('Editor do Registro', 'regedit'),
    H3Comando.executar('Configuração do Sistema (msconfig)', 'msconfig'),
  ]),
  H3GrupoComandos('Diagnóstico', [
    H3Comando.executar('Monitor de Recursos', 'resmon'),
    H3Comando.executar('Monitor de Desempenho', 'perfmon'),
    H3Comando.executar('Informações do Sistema', 'msinfo32'),
    H3Comando.executar('Diagnóstico do DirectX', 'dxdiag'),
    H3Comando.executar('Limpeza de Disco', 'cleanmgr'),
    H3Comando.executar('Verificador de Memória', 'mdsched'),
    H3Comando.executar('Ver IP e rede (ipconfig /all)', 'cmd /k ipconfig /all'),
    H3Comando.executar('Testar conexão (ping 8.8.8.8)', 'cmd /k ping 8.8.8.8'),
    H3Comando.executar('Renovar IP (release / renew)',
        'cmd /k ipconfig /release && ipconfig /renew'),
    H3Comando.executar('Limpar cache DNS', 'cmd /k ipconfig /flushdns'),
    H3Comando.executar('Conexões ativas (netstat)', 'cmd /k netstat -ano'),
    H3Comando.executar('Dados do computador (systeminfo)', 'cmd /k systeminfo'),
    H3Comando.executar(
        'Atualizar políticas (gpupdate)', 'cmd /k gpupdate /force'),
    H3Comando.executar(
        'Verificar arquivos do sistema (sfc) — admin', 'cmd /k sfc /scannow',
        admin: true),
    H3Comando.executar('Reparar imagem do Windows (DISM) — admin',
        'cmd /k DISM /Online /Cleanup-Image /RestoreHealth',
        admin: true),
  ]),
  H3GrupoComandos('Arquivos e acesso', [
    H3Comando.executar('Explorador de Arquivos', 'explorer'),
    H3Comando.executar('Bloco de Notas', 'notepad'),
    H3Comando.executar('Pasta Temp do usuário', 'explorer %TEMP%'),
    H3Comando.executar(
        'Pasta Arquivos de Programas', 'explorer %ProgramFiles%'),
    H3Comando.executar('Área de Trabalho Remota (mstsc)', 'mstsc'),
    H3Comando.executar('Assistência Remota', 'msra'),
  ]),
  H3GrupoComandos('Energia (pede confirmação)', [
    H3Comando.executar('Encerrar sessão (logoff)', 'logoff',
        confirmar: 'Encerrar a sessão do usuário no computador remoto?'),
    H3Comando.executar('Reiniciar agora', 'shutdown /r /t 0',
        confirmar: 'Reiniciar o computador remoto agora?'),
    H3Comando.executar(
        'Reiniciar no modo de recuperação', 'shutdown /r /o /t 0',
        confirmar:
            'Reiniciar o computador remoto no modo de recuperação (opções avançadas)?'),
    H3Comando.executar('Desligar agora', 'shutdown /s /t 0',
        confirmar:
            'Desligar o computador remoto? Depois de desligado não será possível reconectar daqui.'),
    H3Comando.executar('Cancelar desligamento agendado', 'shutdown /a'),
  ]),
];

const _macos = <H3GrupoComandos>[
  H3GrupoComandos('Atalhos do sistema', [
    H3Comando('Bloquear tela', H3TipoComando.bloquear),
    H3Comando.teclas(
        'Forçar encerrar aplicativos (⌥⌘Esc)', 'alt+command+Escape'),
    H3Comando.teclas('Spotlight (⌘ Espaço)', 'command+space'),
    H3Comando.teclas('Alternar aplicativos (⌘ Tab)', 'command+Tab'),
    H3Comando.teclas('Captura de tela (⇧⌘3)', 'shift+command+3'),
  ]),
  H3GrupoComandos('Aplicativos', [
    H3Comando.executar('Terminal', 'Terminal'),
    H3Comando.executar('Monitor de Atividade', 'Activity Monitor'),
    H3Comando.executar('Ajustes do Sistema', 'System Settings'),
    H3Comando.executar('Utilitário de Disco', 'Disk Utility'),
    H3Comando.executar('Console (logs)', 'Console'),
    H3Comando.executar('Informações do Sistema', 'System Information'),
    H3Comando.executar('Finder', 'Finder'),
    H3Comando.executar('Acesso às Chaves', 'Keychain Access'),
  ]),
];

const _linux = <H3GrupoComandos>[
  H3GrupoComandos('Atalhos do sistema', [
    H3Comando('Ctrl + Alt + Del', H3TipoComando.ctrlAltDel),
    H3Comando('Bloquear tela', H3TipoComando.bloquear),
    H3Comando.teclas('Abrir Terminal (Ctrl + Alt + T)', 'ctrl+alt+t'),
    H3Comando.teclas('Alternar janelas (Alt + Tab)', 'alt+Tab'),
    H3Comando.teclas('Fechar janela (Alt + F4)', 'alt+f4'),
    H3Comando.teclas('Captura de tela (Print Screen)', 'PrintScreen'),
  ]),
];

/// Comandos oferecidos para o sistema do computador remoto; vazio quando não há.
List<H3GrupoComandos> comandosRapidosPara(String plataforma) {
  if (plataforma == kPeerPlatformWindows) return _windows;
  if (plataforma == kPeerPlatformMacOS) return _macos;
  if (plataforma == kPeerPlatformLinux) return _linux;
  return const [];
}

/// Teclas, na ordem e com a pausa de cada passo, que realizam [c] no sistema [plataforma].
/// Cada passo é `(tecla, texto, esperaDepoisMs)`: ou envia a combinação `tecla` ou digita `texto`.
List<(String?, String?, int)> passosDe(H3Comando c, String plataforma) {
  final executa = plataforma == kPeerPlatformMacOS ? 'command+space' : 'win+r';
  final abre = plataforma == kPeerPlatformMacOS ? 700 : 800;
  return [
    (executa, null, abre),
    (null, c.valor, 250),
    (c.admin ? 'ctrl+shift+Return' : 'Return', null, 0),
  ];
}

final _executando = <SessionID>{};

/// Executa [c] na sessão remota. A lista de passos garante pausas entre as teclas para o sistema remoto acompanhar.
Future<void> executarComandoRapido(
    SessionID sessionId, H3Comando c, String plataforma) async {
  if (_executando.contains(sessionId)) return;
  _executando.add(sessionId);
  try {
    switch (c.tipo) {
      case H3TipoComando.ctrlAltDel:
        await bind.sessionCtrlAltDel(sessionId: sessionId);
      case H3TipoComando.bloquear:
        await bind.sessionLockScreen(sessionId: sessionId);
      case H3TipoComando.teclas:
        await _tecla(sessionId, c.valor);
      case H3TipoComando.executar:
        for (final (tecla, texto, espera) in passosDe(c, plataforma)) {
          if (tecla != null) await _tecla(sessionId, tecla);
          if (texto != null) {
            await bind.sessionInputString(sessionId: sessionId, value: texto);
          }
          if (espera > 0) await Future.delayed(Duration(milliseconds: espera));
        }
    }
  } finally {
    _executando.remove(sessionId);
  }
}

Future<void> _tecla(SessionID sessionId, String combinacao) async {
  final k = parseAiKeyCombo(combinacao);
  if (k == null) return;
  await bind.sessionInputKey(
      sessionId: sessionId,
      name: k.name,
      down: false,
      press: true,
      alt: k.alt,
      ctrl: k.ctrl,
      shift: k.shift,
      command: k.command);
}
