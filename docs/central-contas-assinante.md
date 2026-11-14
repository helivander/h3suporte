# Implementar na Central: contas do assinante (login do h3suporte)

Status: **implementado na Central** (repositório `central de ativação`, `docs/contas-assinante.md`) e testado de ponta
a ponta com o [servidor-api/](../servidor-api/README.md) do h3suporte. Esta página ficou como a especificação original; o
que mudou na implementação:

- O titular nasce **só pela chave** (`/assinante/criar-conta`). A criação automática pelo e-mail do cadastro ficou de fora.
- Sem códigos de recuperação do 2FA: quem perde o celular pede ao titular para zerar.
- As sessões do portal ficam na mesma tabela das do serviço (`origem = PORTAL`, token `cp_…`, 12 h).
- O login do portal aceita entrar sem `?produto=` quando o e-mail tem conta em um único produto.
- Ainda não feitos: aba **Contas** na ficha da ativação (admin/parceiro), contas na exportação LGPD (a anonimização já
  apaga) e transferência de titularidade.

## Objetivo

A Central passa a ser a dona das **assinaturas e das contas** de um produto SVA. Quem assina (o
**titular**) cria as contas da própria equipe (os **membros**). O h3suporte não guarda senha: o
servidor de API dele pergunta à Central se o e-mail e a senha valem e se a assinatura está ativa.

```
App h3suporte ──/api/login──► servidor-api do h3suporte ──Bearer sva_…──► Central /api-servico/contas/*
                                                                              │
Navegador do titular ─────────────────────────────────────────────────────► Central /assinante (portal)
```

Fica fora do escopo: catálogo de endereços, grupos e dispositivos do RustDesk. Isso é do
servidor-api do h3suporte.

## Conceitos

| Termo             | No banco da Central                              | Observação                                                         |
| ----------------- | ------------------------------------------------ | ------------------------------------------------------------------ |
| Assinatura        | `Ativacao` existente                             | Estado (`ATIVA`, `SUSPENSA`, …), plano e término já existem         |
| Titular           | `ContaServico` com `papel = TITULAR`             | Um por assinatura; cria e gerencia os membros                       |
| Membro            | `ContaServico` com `papel = MEMBRO`              | Técnico; entra no app, não gerencia a equipe                        |
| Sessão do serviço | `SessaoContaServico`                             | Token `cs_…` entregue ao servidor do serviço, nunca ao navegador    |
| Dispositivo       | `DispositivoContaServico`                        | Computador em que alguma conta entrou; conta no limite do plano     |

O produto liga o recurso com um campo novo: `Produto.contasHabilitadas Boolean @default(false)`.
Só produtos com ele ligado aceitam as rotas abaixo e mostram o portal.

## Modelo de dados (Prisma)

```prisma
enum PapelContaServico {
  TITULAR
  MEMBRO
}

/// Conta de pessoa que usa um produto SVA por meio de uma assinatura (ativação).
model ContaServico {
  id              String            @id @default(uuid(7)) @db.Uuid
  parceiroId      String?           @map("parceiro_id") @db.Uuid   // copiado da ativação (RLS)
  produtoId       String            @map("produto_id") @db.Uuid
  ativacaoId      String            @map("ativacao_id") @db.Uuid
  ativacao        Ativacao          @relation(fields: [ativacaoId], references: [id])
  papel           PapelContaServico
  nome            String
  email           String            // minúsculas, sem espaços
  senhaHash       String?           @map("senha_hash")            // null até a pessoa definir a senha
  totpSegredo     String?           @map("totp_segredo")          // cifrado com a CHAVE_MESTRA
  ativo           Boolean           @default(true)
  bloqueadaAte    DateTime?         @map("bloqueada_ate")
  falhas          Int               @default(0)
  ultimoAcessoEm  DateTime?         @map("ultimo_acesso_em")
  criadoEm        DateTime          @default(now()) @map("criado_em")
  anonimizadoEm   DateTime?         @map("anonimizado_em")
  sessoes         SessaoContaServico[]
  dispositivos    DispositivoContaServico[]
  tokens          TokenContaServico[]

  @@unique([produtoId, email])        // um e-mail = uma conta por produto
  @@index([ativacaoId])
  @@map("conta_servico")
}

model SessaoContaServico {
  id            String       @id @default(uuid(7)) @db.Uuid
  parceiroId    String?      @map("parceiro_id") @db.Uuid
  contaId       String       @map("conta_id") @db.Uuid
  conta         ContaServico @relation(fields: [contaId], references: [id], onDelete: Cascade)
  tokenHash     String       @unique @map("token_hash")   // SHA-256 do cs_…
  dispositivoId String       @map("dispositivo_id")
  rotulo        String?
  criadoEm      DateTime     @default(now()) @map("criado_em")
  ultimoUsoEm   DateTime     @default(now()) @map("ultimo_uso_em")
  expiraEm      DateTime     @map("expira_em")
  revogadaEm    DateTime?    @map("revogada_em")

  @@index([contaId])
  @@map("sessao_conta_servico")
}

model DispositivoContaServico {
  id                String       @id @default(uuid(7)) @db.Uuid
  parceiroId        String?      @map("parceiro_id") @db.Uuid
  ativacaoId        String       @map("ativacao_id") @db.Uuid
  contaId           String       @map("conta_id") @db.Uuid
  conta             ContaServico @relation(fields: [contaId], references: [id], onDelete: Cascade)
  dispositivoId     String       @map("dispositivo_id")
  rotulo            String?
  primeiroAcessoEm  DateTime     @default(now()) @map("primeiro_acesso_em")
  ultimoAcessoEm    DateTime     @default(now()) @map("ultimo_acesso_em")

  @@unique([ativacaoId, dispositivoId])
  @@map("dispositivo_conta_servico")
}

enum FinalidadeTokenConta {
  DEFINIR_SENHA      // convite de membro, titular criado automaticamente, "esqueci a senha"
  DESAFIO_TOTP       // segundo passo do login pelo serviço
}

model TokenContaServico {
  id           String               @id @default(uuid(7)) @db.Uuid
  contaId      String               @map("conta_id") @db.Uuid
  conta        ContaServico         @relation(fields: [contaId], references: [id], onDelete: Cascade)
  finalidade   FinalidadeTokenConta
  tokenHash    String               @unique @map("token_hash")
  dispositivoId String?             @map("dispositivo_id")       // só DESAFIO_TOTP
  expiraEm     DateTime             @map("expira_em")
  usadoEm      DateTime?            @map("usado_em")
  criadoEm     DateTime             @default(now()) @map("criado_em")

  @@map("token_conta_servico")
}
```

No `Plano`: `limiteContas Int?` (null = sem limite). O limite de **dispositivos** segue a mesma conta
que o `/licenciamento/ativar` já faz para `LIMITE_INSTALACOES` (`Produto.limiteInstalacoes`, multiplicado
pela quantidade do item quando `permiteQuantidade`). Reaproveite a função que já calcula isso.

RLS: as quatro tabelas só para administrador e sistema, como `conexao_servico`. O parceiro dono da
ativação pode **ler** contas e dispositivos dela (nome, e-mail, papel, ativo, último acesso), nunca hashes.

## Senhas, segundo fator e tokens

- Senha: o mesmo `src/seguranca/senha.ts` (argon2) dos usuários do painel, mesmas regras de tamanho
  (12 a 128) e a mesma lista de senhas fracas, se houver.
- Bloqueio: 10 falhas seguidas bloqueiam a conta por 15 min (`bloqueadaAte`); acerto zera `falhas`.
- TOTP opcional por conta, com `otplib` como no painel. O titular pode exigir 2FA da equipe
  (`Ativacao` ganha `exigirTotpEquipe Boolean @default(false)`); nesse caso, conta sem 2FA entra no portal
  e é obrigada a configurar antes de qualquer outra coisa, e o login pelo serviço responde `TOTP_NAO_CONFIGURADO`.
- Tokens `cs_…` (sessão), de definir senha e de desafio: 256 bits aleatórios, só o SHA-256 no banco.
- Sessão do serviço: expira com 30 dias **sem uso** (`ultimoUsoEm` renova em cada `validar`) e com
  90 dias no máximo desde a criação. Cai na hora quando: a conta é desativada ou excluída, a senha é trocada
  ou redefinida, o titular encerra a sessão ou remove o dispositivo, ou a assinatura sai de `ATIVA`.
- Link de definir senha: 48 h, uso único. Desafio TOTP: 5 min, uso único, preso ao `dispositivoId`.

## Como nasce o titular

Duas portas, para cobrir todos os canais de venda:

1. **Automática**: quando uma ativação de produto com `contasHabilitadas` vira `ATIVA` e a Central conhece
   um e-mail (cadastro da habilitação pelo app, pedido da venda direta), cria o titular com esse e-mail e o
   nome do cliente, sem senha, e manda o link de definir senha. Ponto de gancho: onde hoje já se grava o
   evento `ativacao.ativada`.
2. **Pela chave**: na página pública `/assinante/criar-conta`, a pessoa informa a **chave de licença**,
   nome, e-mail e senha. Se a chave é válida, a ativação é de produto com `contasHabilitadas`, está `ATIVA`
   e ainda não tem titular, cria o titular (e-mail confirmado por link antes do primeiro login). Mesmo
   limite anti-sondagem das chaves (`30 chaves inválidas em 10 min bloqueiam o IP`). Chave de ativação que
   já tem titular: mensagem genérica "Essa chave já tem uma conta. Entre com ela ou peça acesso ao titular."

Uma pessoa com o mesmo e-mail em duas assinaturas do mesmo produto não é suportado (`@@unique`): o
cadastro responde `409 EMAIL_EM_USO`. Fica como limite conhecido.

## Portal do assinante (web)

Rotas novas em `apps/web/app/assinante/`, com o mesmo kit de UI do painel e sessão em cookie HttpOnly
separada da sessão do painel (nome de cookie próprio, `SameSite=Strict`).

| Tela                                | Quem     | O que faz                                                                                                  |
| ----------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------- |
| `/assinante/entrar`                 | todos    | E-mail, senha e, se houver, código TOTP. Escolhe o produto pelo `?produto=<slug>` (o app manda o link)      |
| `/assinante/criar-conta`            | público  | Cria o titular pela chave (seção anterior)                                                                  |
| `/assinante/definir-senha?token=`   | público  | Define a senha pelo link (convite, criação automática, esqueci a senha). Confirma por clique, não ao abrir  |
| `/assinante/esqueci`                | público  | Pede o link de definir senha (resposta sempre igual, exista o e-mail ou não)                               |
| `/assinante` (início)               | todos    | Plano, estado da assinatura, término, uso: `contas x/limite`, `dispositivos y/limite`                       |
| `/assinante/equipe`                 | titular  | Lista, cria, desativa, reativa, reenvia convite, redefine senha (manda link), zera 2FA, remove conta        |
| `/assinante/dispositivos`           | titular  | Computadores por conta, último acesso; **remover** libera a vaga e encerra as sessões daquele computador    |
| `/assinante/conta`                  | todos    | Nome, senha, 2FA (com códigos de recuperação, como no painel), sessões abertas                             |

Regras da equipe:

- Criar membro: `{ nome, email }`. Respeita `Plano.limiteContas` (o titular conta). Manda o convite por e-mail.
- O titular não se desativa nem se remove. Transferir a titularidade: fora do escopo desta fase (o
  administrador da Central faz pela ficha da ativação).
- Assinatura `SUSPENSA`: o portal abre só para ver o estado e o aviso; equipe e dispositivos ficam só leitura.
  `CANCELADA`/`EXPIRADA`: o portal mostra o estado e nada mais.
- Tudo auditado: `conta_servico.criada|convidada|ativada|desativada|removida|senha_definida|totp_zerado`,
  `dispositivo_conta_servico.removido`, `sessao_conta_servico.encerrada`, com autor `assinante:<contaId>`.

No painel do administrador e do parceiro, a ficha da ativação ganha a aba **Contas** (lista, desativar,
reenviar convite, trocar o titular só para administrador).

## API para o serviço (`/api-servico/contas/*`)

Autenticação: `Authorization: Bearer sva_…` com a credencial de **licenciamento** do produto (a mesma de
`/licenciamento`). Produto sem `contasHabilitadas` → `404`. Erros no padrão da Central:
`{ statusCode, message, codigo }`.

O servidor do serviço fala com a Central em nome de muitos usuários, então o `req.ip` é sempre o dele.
Para os limites, a Central aceita o cabeçalho **`X-Cliente-Ip`** (só nestas rotas e só com credencial
`sva_` válida) e usa `X-Cliente-Ip` + e-mail nas chaves de limite; sem o cabeçalho, usa o IP da conexão.

### `POST /api-servico/contas/entrar`

```json
{ "email": "ana@empresa.com.br", "senha": "…", "dispositivoId": "a1b2…", "rotulo": "NOTE-ANA" }
```

ou, no segundo passo do 2FA:

```json
{ "desafio": "…", "codigoTotp": "123456", "dispositivoId": "a1b2…", "rotulo": "NOTE-ANA" }
```

`codigoTotp` aceita também um código de recuperação. `dispositivoId` segue a regra de sempre
(8 a 128 de `[A-Za-z0-9_.:-]`), `rotulo` até 80 caracteres.

Ordem das verificações: limites → credenciais → conta ativa e não bloqueada → 2FA → assinatura `ATIVA` →
dispositivo (já conhecido, ou cabe no limite) → cria a sessão e registra/atualiza o dispositivo.

| Resposta | `codigo`                  | Quando                                                                                       |
| -------- | ------------------------- | -------------------------------------------------------------------------------------------- |
| `200`    | —                         | Entrou (corpo abaixo)                                                                        |
| `401`    | `CREDENCIAIS_INVALIDAS`   | E-mail inexistente, senha errada, conta sem senha definida, desafio inválido/expirado — sempre a mesma mensagem |
| `401`    | `TOTP_NECESSARIO`         | Senha certa e a conta tem 2FA. Corpo traz `desafio` (5 min). Nada de sessão ainda             |
| `401`    | `TOTP_INVALIDO`           | Código errado no segundo passo (o desafio continua valendo até 5 tentativas)                 |
| `403`    | `TOTP_NAO_CONFIGURADO`    | A assinatura exige 2FA e a conta não configurou                                              |
| `403`    | `CONTA_DESATIVADA`        | Conta desativada pelo titular                                                                |
| `403`    | `CONTA_BLOQUEADA`         | Bloqueio por falhas (traz `ate`)                                                             |
| `403`    | `ASSINATURA_INATIVA`      | Ativação fora de `ATIVA` (traz `estado`)                                                     |
| `409`    | `LIMITE_DISPOSITIVOS`     | Computador novo e o limite do plano já está cheio                                            |
| `429`    | `MUITAS_TENTATIVAS`       | 10 por minuto por IP do cliente; 5 por 10 min por e-mail                                     |

Corpo do `200`:

```json
{
  "sessao": { "token": "cs_…", "expiraEm": "2026-12-14T12:00:00.000Z" },
  "conta": { "id": "uuid", "email": "ana@empresa.com.br", "nome": "Ana Souza", "papel": "MEMBRO" },
  "assinatura": {
    "id": "uuid-da-ativacao",
    "estado": "ATIVA",
    "plano": { "id": "uuid", "nome": "Equipe 5" },
    "limiteContas": 5,
    "limiteDispositivos": 10,
    "fimEm": null
  },
  "portalUrl": "https://keys.h3info.com/assinante/entrar?produto=h3suporte"
}
```

`TOTP_NECESSARIO` traz `{ statusCode: 401, message, codigo, desafio: "…" }`.

### `POST /api-servico/contas/validar`

`{ "sessao": "cs_…" }` → sempre `200`:

- válida: `{ "valida": true, "conta": {…}, "assinatura": {…} }` (mesmo formato do `entrar`), e renova
  `ultimoUsoEm` da sessão, da conta e do dispositivo (no máximo uma escrita por minuto por sessão);
- inválida: `{ "valida": false, "motivo": "SESSAO_INVALIDA" | "CONTA_DESATIVADA" | "ASSINATURA_INATIVA" | "DISPOSITIVO_REMOVIDO" }`.

O serviço chama no máximo a cada poucos minutos por sessão. Limite: 600/min por credencial.

### `POST /api-servico/contas/sair`

`{ "sessao": "cs_…" }` → `204`, idempotente. Revoga a sessão. Não remove o dispositivo.

### `POST /api-servico/contas/equipe`

`{ "sessao": "cs_…" }` → `200 { "contas": [ { "id", "email", "nome", "papel", "ativo" } ] }` com todas as
contas da mesma assinatura (ativas e desativadas), ou `401 SESSAO_INVALIDA`. Token no corpo, não na URL.

## Webhooks (opcional nesta fase)

Não é obrigatório: o serviço descobre mudanças pelo `validar`. Se for barato, emitir para o parceiro os
eventos `conta_servico.criada|desativada` junto da fila de webhooks que já existe.

## LGPD

`ContaServico` entra na exportação e na anonimização do titular dos dados (nome e e-mail apagados,
`anonimizadoEm` preenchido, sessões e dispositivos removidos). Nada de senha, token ou código em log,
auditoria ou webhook. O `rotulo` do dispositivo é o nome do computador: tratar como dado pessoal.

## OpenAPI e documentação

- Esquemas Zod novos em `packages/contratos` (`esquemaContaEntrar`, `esquemaContaSessao`), para o OpenAPI
  gerado incluir as rotas.
- Atualizar `docs/integracao-sva.md` (seção nova "Contas do assinante") e `implantacao/INTEGRACAO-SISTEMAS.md`
  (2.14), e criar `docs/contas-assinante.md` com as decisões.

## Critérios de aceite (testes da API com Postgres e Redis reais)

1. Entrar com e-mail e senha certos em assinatura `ATIVA` devolve `cs_…` e registra o dispositivo.
2. Senha errada, e-mail inexistente e conta sem senha dão a **mesma** resposta `401 CREDENCIAIS_INVALIDAS`.
3. Conta com 2FA: primeiro passo dá `TOTP_NECESSARIO` com `desafio`; segundo passo com o código certo entra;
   desafio reutilizado ou de outro `dispositivoId` dá `CREDENCIAIS_INVALIDAS`.
4. Suspender a ativação (admin ou reconsulta) faz o `validar` responder `ASSINATURA_INATIVA` e o `entrar` dar `403`.
5. Titular desativa um membro: `validar` da sessão dele vira `CONTA_DESATIVADA`.
6. Limite: com `limiteDispositivos` cheio, computador novo dá `409`; computador já conhecido entra; remover um
   dispositivo libera a vaga e invalida as sessões dele (`DISPOSITIVO_REMOVIDO`).
7. Criar membro além de `limiteContas` é recusado no portal e na API do portal.
8. Credencial `sva_` de outro produto não enxerga contas deste (`401 SESSAO_INVALIDA` / `CREDENCIAIS_INVALIDAS`).
9. Credencial financeira dá `403`, como hoje.
10. Criar titular pela chave: chave válida cria; segunda tentativa na mesma ativação é recusada; chave inválida
    conta no bloqueio anti-sondagem.
11. Trocar a senha encerra as sessões do serviço daquela conta.
12. Teste e2e (Playwright) do portal: entrar como titular, criar membro, desativar, remover dispositivo.

## Configuração do produto h3suporte na Central

1. Cadastrar o produto `h3suporte` (ou conectar pelo "Conectar à Central"), ligar **contas habilitadas** e
   definir `limiteInstalacoes` e, em cada plano, `limiteContas`.
2. Criar a credencial de **licenciamento** `sva_…` e colocá-la no `.env` do servidor-api do h3suporte
   (`CENTRAL_CREDENCIAL`). Ela nunca vai para o app.
