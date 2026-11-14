# servidor-api do h3suporte

Servidor de API que o app h3suporte usa para login, catálogo de endereços e grupo. Ele fala o formato
do cliente RustDesk (`/api/login`, `/api/currentUser`, `/api/ab`…) e delega **contas, senhas e
assinaturas à Central de Ativação** pelas rotas `/api-servico/contas/*`
([especificação](../docs/central-contas-assinante.md)).

```
App h3suporte ──https──► suporte-api.h3info.com (este servidor) ──Bearer sva_…──► Central (keys.h3info.com)
```

Node 24, sem dependências externas (`node:http`, `node:sqlite`, `node:test`).

## O que fica onde

| Dado                                     | Onde                         |
| ---------------------------------------- | ---------------------------- |
| Conta, senha, 2FA, equipe, assinatura    | Central de Ativação          |
| Sessão (só o hash do token `cs_…`)       | aqui, cache da validação     |
| Catálogo de endereços de cada conta      | aqui (SQLite)                |
| Computadores (ID, nome, sistema, versão) | aqui, apaga 90 dias sem uso  |
| Auditoria de conexões e arquivos         | aqui, apaga em 180 dias      |

## Rotas atendidas

| Rota                                                    | Comportamento                                                                                   |
| ------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `POST /api/login`                                       | E-mail e senha (ou desafio + código 2FA) → Central `entrar`; devolve `access_token` = `cs_…`    |
| `POST /api/currentUser`                                 | Dados da conta; revalida na Central a cada `REVALIDAR_SEG`                                      |
| `POST /api/logout`                                      | Encerra a sessão aqui e na Central                                                              |
| `GET/POST /api/ab`                                      | Catálogo de endereços por conta (modo legado do cliente)                                        |
| `POST /api/ab/personal` e demais `/api/ab/*`            | `404`: o cliente entra no modo legado                                                           |
| `GET /api/users`, `GET /api/peers`                      | Aba Grupo: contas da equipe e os computadores em que elas entraram                              |
| `GET /api/device-group/accessible`                      | Lista vazia                                                                                     |
| `POST /api/heartbeat`, `/api/sysinfo`, `/api/sysinfo_ver` | Registro de computadores                                                                      |
| `POST /api/audit/{conn,file,alarm}`                     | Guarda a auditoria (64 KB por registro, 120/min por IP)                                         |
| `GET /api/login-options`                                | `[]` (sem login por Google/Microsoft)                                                           |
| `GET /saude`                                            | `{"ok":true}`                                                                                   |

Sessões: se a Central responder que a sessão não vale mais (conta desativada, assinatura suspensa), o
próximo pedido dá `401` e o app volta para a tela de login. Com a Central fora do ar, a sessão continua
valendo por `TOLERANCIA_HORAS` desde a última validação; depois disso responde `503` (o app mostra o erro
e não apaga o login).

## Rodar

```bash
cp .env.example .env   # preencha CENTRAL_URL e CENTRAL_CREDENCIAL
docker build -t h3suporte-api .
docker run -d --name h3suporte-api --restart unless-stopped --env-file .env \
  -p 127.0.0.1:21114:21114 -v h3suporte-api-dados:/app/dados h3suporte-api
```

Na frente, um proxy reverso com TLS para `https://suporte-api.h3info.com` → `127.0.0.1:21114`
(com `CONFIAR_PROXY=1`). O app usa esse endereço quando nenhum servidor de API foi configurado
(`src/common.rs`, `get_api_server_`). Para trocar o domínio, mude essa linha ou configure
`api-server` no app.

Sem Docker: `node src/main.js` com as variáveis do `.env` no ambiente.

Backup: o arquivo `dados/h3suporte.db` (SQLite em WAL). Copie com `sqlite3 h3suporte.db ".backup copia.db"`.

## Testes

```bash
npm test
```

Os testes sobem uma Central simulada com o contrato da especificação e cobrem login, 2FA, catálogo,
suspensão da assinatura, Central fora do ar, grupo e as rotas de registro.

## Limites conhecidos

- Catálogo de endereços compartilhado entre a equipe (modo novo do cliente, `/api/ab/personal` e
  `/api/ab/shared/*`) não está implementado; cada conta tem o próprio catálogo.
- Grupos de dispositivos, gravação de sessão (`/api/record`) e estratégias remotas não são suportados.
- Limites de tentativa ficam em memória: com mais de uma instância, cada uma conta separado (a Central
  também limita).
