# Como funciona o sistema de relatórios do H3 Suporte

Guia para reaplicar o mesmo desenho em outros sistemas. Tudo aqui foi lido do código deste repositório; onde algo é
decisão de desenho (e não comportamento existente) isso está dito.

> O H3 Suporte não tem um único módulo chamado "report". O que existe são **quatro peças** que, juntas, formam o
> sistema: (1) a aba **Relatórios** do app, (2) o painel **Conta** (uso do plano em tempo real), (3) a **auditoria**
> que o app envia ao servidor e (4) o **heartbeat/inventário** de dispositivos. Cada peça tem uma fonte de dados e uma
> regra de atualização diferentes, e é essa separação que vale copiar.

## Visão geral

```
 App (Flutter + Rust)                                   servidor-api (Node, SQLite)
 ─────────────────────                                  ───────────────────────────
 Aba "Relatórios"  ◄── modelos locais (sem rede)
 Painel "Conta"    ◄── GET /api/conta/uso  (a cada 5 s) ──  contas + assinatura + acessos em memória
 Rust: conexões    ──► POST /api/audit/{conn,file,alarm} ─►  tabela auditoria (dedup por nonce)
 Rust: heartbeat   ──► POST /api/heartbeat, /api/sysinfo ─►  tabela dispositivo (visto_em, nome, SO)
 Sessão remota     ──► POST /api/acessos/{abrir,fechar} ──►  limite de acessos simultâneos (memória)
```

Princípio central: **cada número mostrado vem da fonte mais próxima e mais barata que o responde**. O que o app já
sabe, ele mostra sem rede; o que depende de várias máquinas, o servidor calcula; o que é evidência (quem acessou o
quê), o app envia como evento e o servidor guarda.

---

## 1. Aba "Relatórios" (somente dados locais)

Arquivo: `flutter/lib/desktop/pages/h3_home_layout.dart`, seção `// ---------- Relatórios ----------`
(`_relatorios()`, `_indicadores()`, `_seguranca()`).

Dois blocos:

**Indicadores (cartões numéricos):**

| Indicador        | Fonte                                                                             |
|------------------|-----------------------------------------------------------------------------------|
| Sessões ativas   | `_sessoesSaida` (sessões abertas nas subjanelas) + `serverModel.clients` não desconectados (entrando) |
| Dispositivos     | `recentPeersModel.peers`; "online" = `p.online`; a barra é `online / total`        |
| Favoritos        | `favoritePeersModel.peers`                                                        |
| Na rede local    | `lanPeersModel.peers`                                                             |

**Segurança e acesso (blocos clicáveis):** lê a configuração local (2FA via `bind.mainHasValid2FaSync()`, método de
senha, modo de aprovação, gravação automática) e cada bloco leva à aba de configuração correspondente
(`DesktopSettingPage.switch2page(SettingsTabKey.safety)`). O relatório é, ao mesmo tempo, um atalho para corrigir.

Como as sessões abertas são descobertas: a janela principal pergunta a cada subjanela
(`DesktopMultiWindow.invokeMethod(w, kWindowEventGetRemoteList)`) quais IDs ela tem abertos, num timer, e só atualiza
a lista observável quando ela muda (`listEquals`) para não redesenhar à toa.

**Padrões a copiar**
- Os modelos já existentes do app são a fonte; a tela só combina. Nada de rota nova para o que o cliente já sabe.
- `Listenable.merge` + `Obx` para que o cartão reaja a qualquer das listas.
- `_grade()` distribui os cartões em colunas iguais (mínimo 210 px, 1 a 4 colunas) e linhas de mesma altura
  (`IntrinsicHeight`). Serve para qualquer painel de cartões.
- Cartão = ícone + rótulo + valor grande + nota + (opcional) barra de progresso. Ver `_indicador()`.

## 2. Painel "Conta" (uso do plano em tempo real)

Arquivo: `flutter/lib/desktop/pages/h3_conta_painel.dart`. Rota: `GET /api/conta/uso` em `servidor-api/src/app.js`.

- O app consulta **a cada 5 s** (`Timer.periodic`) e cancela o timer no `dispose`.
- Resposta: `{ assinatura, acessos_em_uso, dispositivos, contas }`.
- A tela mostra cada contador contra o limite do plano (`limite_acessos`, `limite_dispositivos`, `limite_contas`) em
  barra de progresso; a barra muda de cor quando enche (`n >= max`).
- Falha de rede não apaga o que já estava na tela: mostra "Sem conexão com o servidor. Tentando de novo…" e continua
  tentando. Enquanto não há resposta, usa a assinatura guardada localmente (`UserModel.getLocalUserInfo()`).
- Como o servidor calcula cada número:
  - `acessos_em_uso`: conjunto de **alvos** (conta + computador acessado) com concessão ainda válida. Várias janelas
    da mesma conta no mesmo computador (controle, arquivos, terminal) contam como **um** acesso.
  - `dispositivos`: linhas da tabela `dispositivo` vinculadas à assinatura.
  - `contas`: membros ativos da equipe, vindos da Central.

## 3. Limite de acessos simultâneos (contador com validade)

Rotas `POST /api/acessos/abrir` e `/fechar`, função `abrirAcesso` em `servidor-api/src/app.js`.

- O app **abre** uma concessão ao iniciar a sessão remota e **renova** enquanto ela durar; o servidor guarda tudo em
  memória (`Map` por assinatura), sem banco.
- Cada concessão expira sozinha em `ACESSO_VALIDADE_MS` (150 s). Se o app fechar sem avisar, a vaga volta sozinha.
- Ao abrir, se o plano tem limite e todas as vagas estão ocupadas por **outros alvos**, responde `409` com mensagem
  em português pronta para exibir. Resposta de sucesso: `{ limite, em_uso }`.
- O mapa de acessos é limpo se passar de 50 000 assinaturas (proteção de memória).

**Quando copiar:** qualquer limite "N ao mesmo tempo" (sessões, impressões, exportações). Concessão com validade
é mais robusta que contador incrementado/decrementado, porque não vaza quando o cliente cai.

## 4. Auditoria (eventos que o app envia ao servidor)

Cliente: `src/server/connection.rs` (`post_conn_audit`, `post_file_audit`, `post_alarm_audit`, `post_audit_async`).
Servidor: `POST /api/audit/conn|file|alarm` em `servidor-api/src/app.js`; tabela `auditoria` em `banco.js`.

**Quem envia:** o computador **controlado** (quem recebe a conexão); a única exceção é a **nota** da sessão
(`send_note`, em `src/ui_session_interface.rs`), enviada por quem controla ao mesmo endereço `conn`. A URL vem de `get_audit_server`
(`{api-server}/api/audit/{tipo}`); sem servidor configurado, não envia nada.

**Três tipos de evento**

| Tipo    | Quando                                   | Campos principais                                                     |
|---------|------------------------------------------|-----------------------------------------------------------------------|
| `conn`  | conexão nova (`action: "new"`), fechamento (`"close"`) e nota | `id`, `uuid`, `conn_id`, `session_id`, `ip`, `action`, `nonce`        |
| `file`  | transferência de arquivo/impressão       | `peer_id`, `type`, `path`, `is_file`, `info` (IP, nome, `num`, até 10 maiores arquivos) |
| `alarm` | evento de segurança                      | `typ` (número do tipo), `info`, `conn_id`, `nonce`                     |

Tipos de alarme (`AlarmAuditType`): lista branca de IP/ID, mais de 30 tentativas, 6 tentativas em 1 minuto,
prefixo IPv6 excedido, backoff/concorrência de login no terminal, violação de escopo de sessão.

**Garantias que importam (e valem copiar):**

1. **Nonce único por registro** (`uuid` v4). O servidor grava com `INSERT OR IGNORE` sobre `nonce UNIQUE`, então um
   reenvio nunca duplica o registro.
2. **Reenvio com atraso crescente** (`post_audit_async`): até 3 tentativas, esperas de 10 s e 30 s, teto de 120 s
   no total. Repete em erro de rede, 5xx, 408 e 429; **não** repete 4xx determinísticos. Corpo de resposta não vazio
   também é tratado como falha (um proxy com página de manutenção responde 200 e não prova gravação).
3. **Ordem preservada:** os envios de `conn` passam por uma fila sequencial (`tx_post_seq`), então "new" chega
   antes de "close".
4. **Não bloqueia a conexão:** `tokio::spawn`; falha só vira log.
5. **Limite no servidor:** `limiteAuditoria` = 120 requisições por minuto por IP (`429` acima disso).
6. **Retenção:** `banco.limpar` roda na partida e a cada 6 h e apaga auditoria com mais de **180 dias**.
7. **Entrada limitada:** o servidor guarda o corpo como JSON em `dados` e limita tamanho (`lerJson`) e campos
   (`texto(valor, 64)`).

**Lacuna atual (decisão a tomar ao copiar):** hoje a auditoria só **grava**. Não há rota que liste ou resuma esses
registros, nem tela que os mostre. Para virar relatório de fato, falta uma rota autenticada por assinatura (ex.:
`GET /api/relatorios/sessoes?de=&ate=`) e um índice em `(tipo, criado_em)`; a tabela hoje só tem o índice do `id`.

## 5. Heartbeat e inventário de dispositivos

Cliente: `src/hbbs_http/sync.rs`. Servidor: `POST /api/heartbeat`, `POST /api/sysinfo`, `POST /api/sysinfo_ver`.

- O app manda **heartbeat** periódico. O servidor só grava `visto_em` no máximo uma vez por 60 s por dispositivo
  (`VISTO_INTERVALO_MS`), com um cache em memória (`vistos`) para não ir ao banco a cada batida.
- **Sysinfo** (nome da máquina, SO, versão, UUID) só é reenviado quando muda: o servidor devolve a versão
  (`sysinfo_ver`) e o app compara um hash antes de subir de novo. Mudança de usuário do SO também força reenvio.
- "Online" na UI vem de `visto_em` recente. Dispositivos sem vínculo e sem sinal por 90 dias são apagados.
- O heartbeat é desligado quando o endereço do servidor é público não confiável (`is_public`) ou o serviço está
  parado.

## 6. Receita para aplicar em outro sistema

1. **Classifique cada número** pela fonte: já está no cliente (cartão local), depende do conjunto de máquinas
   (calculado no servidor, rota `/uso`) ou é evidência (evento de auditoria).
2. **Cartões:** copie `_grade` + `_indicador`. Reaja por `Listenable.merge`/`Obx`, não por `setState` global.
3. **Tempo real leve:** `GET` que devolve contadores já agregados + `Timer.periodic` de poucos segundos, com falha
   silenciosa e texto "tentando de novo". Nunca esvazie a tela quando a rede cai.
4. **Limites simultâneos:** concessão com validade (renovada pelo cliente), em memória; `409` com mensagem pronta.
5. **Auditoria confiável:** nonce por evento, `INSERT OR IGNORE`, fila sequencial, reenvio com atraso e teto de tempo,
   limite por IP, retenção definida. Decida desde o início como o evento será **lido** (índices e rota de consulta).
6. **Inventário:** heartbeat barato + dado pesado só quando muda (hash/versão).
7. **Privacidade:** o servidor não deve guardar mais do que mostra. Aqui os nomes de arquivo são truncados em 10 e os
   campos de texto têm tamanho máximo.

## 7. Onde está cada coisa

| O quê                                  | Arquivo                                                         |
|----------------------------------------|-----------------------------------------------------------------|
| Aba Relatórios                          | `flutter/lib/desktop/pages/h3_home_layout.dart`                 |
| Painel Conta                            | `flutter/lib/desktop/pages/h3_conta_painel.dart`                |
| Envio de auditoria (Rust)               | `src/server/connection.rs`                                      |
| Heartbeat e sysinfo (Rust)              | `src/hbbs_http/sync.rs`                                         |
| Rotas e limites do servidor             | `servidor-api/src/app.js`                                       |
| Tabelas e retenção                      | `servidor-api/src/banco.js`                                     |
| Documentação das rotas                  | `servidor-api/README.md`                                        |
