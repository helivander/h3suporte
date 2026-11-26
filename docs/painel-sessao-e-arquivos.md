# Menu lateral da sessão, arquivos da máquina e travas de entrada

## Menu lateral (desktop)

Botão "Menu lateral" na barra da sessão (`flutter/lib/desktop/widgets/h3_painel_sessao.dart`). As ações vêm de
`toolbarControls`, então seguem as mesmas permissões do menu da barra; o que a sessão não permite não aparece.

## Arquivos da máquina (desktop)

`flutter/lib/desktop/widgets/h3_arquivos.dart`: navega só a máquina remota; enviar e baixar usam os seletores do
sistema. Web e celular continuam com as telas antigas.

O protocolo do RustDesk não oferece, por isso a tela não mostra: copiar/mover dentro da máquina remota, espaço
livre dos discos, prévia de conteúdo, SHA-256 e busca em subpastas. As transferências param se a janela for
fechada.

## Travar teclado e mouse (só máquina Windows)

`src/platform/windows/h3_trava.rs` instala ganchos de baixo nível que descartam apenas a entrada física; o controle
remoto é injetado e continua passando. Campos `block_keyboard` e `block_mouse` em `OptionMessage`.

- O agente precisa ser desta versão: ele anuncia `h3_input_lock`. Agente antigo mostra uma única chave que trava
  teclado e mouse juntos (`BlockInput`).
- A trava é solta quando a conexão que travou encerra ou quando a permissão é retirada.
- Limites do Windows: Ctrl+Alt+Del físico e a tela segura do UAC não são bloqueados.
- Pendente: teste numa máquina Windows real.
