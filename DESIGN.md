# DESIGN.md — H3 Suporte

Sistema de design oficial do **H3 Suporte** (cliente Desktop, Mobile e referência de paridade para o acesso Web em `centralkeys`).

---

## 1. Direção Visual e Modo de Superfície

- **Modo predominante:** *Operate* (ferramenta de suporte remoto e administração de TI). Clareza, escaneabilidade, previsibilidade e densidade controlada superam ornamentação.
- **Identidade cromática:** Verde-água técnico sobre superfícies escuras profundas (modo escuro padrão) e cinza-gelo limpo (modo claro).

---

## 2. Tokens de Cor (`H3Tokens`)

| Token | Escuro (Dark) | Claro (Light) | Uso principal |
| --- | --- | --- | --- |
| `fundo` | `#070D10` | `#E9EFF1` | Fundo base da janela e área externa |
| `painel` | `#0E171B` | `#FFFFFF` | Superfície principal de conteúdo e cartões |
| `painel2` | `#132026` | `#F4F8F9` | Superfície elevada, inputs, itens em hover |
| `linha` | `#1D2D33` | `#DCE5E8` | Bordas sutis e divisores padrão |
| `linha2` | `#26393F` | `#C9D6DA` | Bordas de destaque / hover / foco secundário |
| `texto` | `#E6F1F2` | `#13262B` | Texto primário e títulos |
| `apagado` | `#8AA1A6` | `#587177` | Rótulos secundários, metadados, placeholders |
| `destaque` | `#1FD1C1` | `#087F76` | Ação primária, foco, item ativo (contraste >= 4.5:1 com `destaqueTinta`) |
| `destaqueTinta` | `#04201D` | `#FFFFFF` | Texto/ícone sobre `destaque` |
| `ok` | `#3DDC84` | `#1C9A58` | Online, concedido, sucesso |
| `aviso` | `#F0B544` | `#B5730F` | Atenção, pendência, limite próximo |
| `info` | `#4F8CFF` | `#2D6BDB` | Informação neutra, sessão ativa |
| `perigo` | `#FF5D6C` | `#C6283A` | Erro, desconexão, remoção, saída |
| `perigoTinta` | `#FFFFFF` | `#FFFFFF` | Texto/ícone sobre fundo `perigo` |

---

## 3. Tipografia

- **Títulos e KPIs:** `Space Grotesk` (pesos `600`, `700`).
- **UI, corpo e botões:** `Inter` (pesos `400`, `500`, `600`, `700`; tamanho mínimo prático `12px` para metadados, `13–14px` para corpo).
- **IDs de acesso e dados técnicos:** Fonte monoespaçada (`JetBrains Mono` / `Roboto Mono`) com `tabular-nums` (`FontFeature.tabularFigures()`), agrupando IDs em blocos de 3 dígitos.

---

## 4. Escala Geométrica e Espaçamento

- **Espaçamento base (múltiplos de 4):** `4`, `8`, `12`, `16`, `20`, `24`, `32`.
- **Raios de borda:**
  - `rXs = 6px` (badges, chips compactos)
  - `rSm = 8px` (botões padrão, inputs, itens de menu)
  - `rMd = 12px` (cartões internos, botões de destaque)
  - `rLg = 16px` (cartões principais, modais)
  - `rFull = 999px` (pílulas de status e indicadores)
- **Alvos de clique:** mínimo `36x36px` (preferencial `40x40px`) para botões de ícone em desktop.

---

## 5. Estados, Acessibilidade e Movimento

- **Hover e Focus:** Todos os controles interativos devem responder a `hover` (fundo `painel2` / borda `linha2`) e exibir anel/borda de foco visível (`destaque`, `1.5px`) na navegação por teclado.
- **Carregamento e Erro:** Listas remotas (`Meus dispositivos`, `Conta`) devem exibir indicador de carregamento inicial e ação explícita *Tentar novamente* em caso de falha.
- **Transições:** `150–200ms` com `Curves.easeOutCubic` em trocas de aba e abertura de painéis.
