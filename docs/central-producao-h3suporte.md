# Central de Ativação: o que falta em produção para o h3suporte funcionar

Para repassar ao time da Central. Situação conferida no servidor (CT 110 do Proxmox, `10.0.4.19`, pasta
`/root/centralkeys`) em 14/11/2026, 21h:

- Feito: código das contas implantado (API e web; `/api/assinante/painel` responde 401), **servidor-api publicado** em
  `/opt/h3suporte-api` (container `h3suporte-api-h3suporte-api-1`, rede `central_interna`) e **Caddy reiniciado** com a
  rota `/h3suporte`. Pelo domínio público: `/h3suporte/saude` → `{"ok":true}`, `/h3suporte/api/login-options` → `[]`,
  `POST /h3suporte/api/heartbeat` → `{}` (a Cloudflare não desafiou o POST; mantenha a regra da seção 3 por garantia).
- Falta: criar o **produto H3 Suporte** com contas e a **credencial `sva_`** (hoje só existem os produtos Micron) e o
  **SMTP** (seções 4 a 6). Com a credencial em `/opt/h3suporte-api/.env`:
  `cd /opt/h3suporte-api && docker compose -f docker-compose.prod.yml up -d`. Até lá o login do app responde
  "Login indisponível"; heartbeat e saúde funcionam.

Como fica:

```
App h3suporte ──https──► keys.h3info.com/h3suporte/* ──Cloudflare──► Caddy da Central ──► h3suporte-api:21114
                                                                                              │ rede interna
                                                                                              ▼
                                                                                   API da Central (api:3001)
```

## 1. Implantar o código das contas

Commits na `main` do repositório da Central (todos já enviados ao Gitea e ao GitHub):

- `fd2b38c` Contas do assinante: titular, equipe e login de pessoas pelo serviço
- `90c8853` Contas na ficha da ativação, titularidade e exportação LGPD
- `7ce8f8e` Venda direta na vitrine da Central com cobrança pelo Asaas
- `33fd3c3` Contas do assinante: correções da revisão contra a spec
- `47a8cb9` Contas do assinante: titular automático e códigos de recuperação do 2FA
- `d41ff31` Caddy: rota /h3suporte para o servidor-api do h3suporte
- `3c1dce5` Produto H3 Suporte já cadastrado e computadores = contas do plano

```bash
git pull && make deploy
```

O `make deploy` aplica, em ordem, as migrações pendentes (nenhuma apaga dados):

| Migração                                         | O que faz                                                                    |
| ------------------------------------------------ | ---------------------------------------------------------------------------- |
| `20261114120000_venda_direta`                     | Preço da Central por plano, tabela `venda_direta`; `parceiro_id` passa a aceitar vazio |
| `20261114200000_contas_servico`                   | 4 tabelas das contas e 3 colunas com padrão                                  |
| `20261114210000_contas_servico_rls`               | Parceiro só lê contas e computadores (troca de policies)                     |
| `20261114220000_titular_automatico_recuperacao`   | Tipo de token para códigos de recuperação e `venda_direta.email`             |
| `20261115120000_produto_h3suporte`                | Cria o produto H3 Suporte (se o slug `h3suporte` ainda não existir)          |

Só não use `migrate dev` em produção.

Conferir: `curl -s https://keys.h3info.com/api/assinante/painel` deve dar **401** (“Sessão do assinante expirada”), não 404.

## 2. Rota `/h3suporte` no Caddy

Já está em `ops/Caddyfile` (commit `d41ff31`), **antes** do bloco `handle` do painel web; o `make deploy` reinicia o Caddy
(a menos que `SEM_PROXY=1`). O bloco é este:

```caddy
	# Servidor de API do h3suporte (app de suporte remoto): /h3suporte/<rota> -> servidor-api em /<rota>
	handle_path /h3suporte/* {
		request_body {
			max_size 3MB
		}
		reverse_proxy h3suporte-api:21114 {
			header_up X-Forwarded-For {client_ip}
		}
	}
```

- `h3suporte-api` é o container do servidor-api, que entra na rede `interna` do Compose da Central (nome Docker
  `central_interna`). Se o container não estiver no ar, só essa rota responde 502; o resto da Central não é afetado.
- 3 MB porque o app envia o catálogo de endereços inteiro de uma vez.
- Só para recarregar o Caddy sem deploy: `docker compose -p central -f docker-compose.prod.yml restart caddy`.

Conferir o nome da rede no servidor: `docker network ls | grep interna` deve mostrar `central_interna`. Se for outro,
informe para colocarmos em `REDE_CENTRAL` no `.env` do servidor-api.

## 3. Cloudflare

**Feito em 15/11/2026** na zona `h3info.com` (plano Free), as duas regras valendo só para `keys.h3info.com` com caminho
começando em `/h3suporte/` (o resto do domínio não muda):

- Regras de segurança → regra personalizada **"h3suporte: app sem desafio"**, primeira da lista, ação **Ignorar**:
  regras personalizadas restantes, Rate Limiting, regras gerenciadas, Verificação de integridade do navegador e Nível
  de segurança. Expressão:
  `(http.host eq "keys.h3info.com" and starts_with(http.request.uri.path, "/h3suporte/"))`
- Caching → Cache Rules → **"h3suporte: sem cache"**, mesma expressão, **Ignorar cache**.

**Desde 27/11/2026 o app usa `h3info.com`** (o gestor de assinaturas) no lugar de `keys.h3info.com`. As duas regras
precisam valer também para esse host; troque a expressão das duas por:
`(http.host in {"keys.h3info.com" "h3info.com"} and starts_with(http.request.uri.path, "/h3suporte/"))`

Ambas estão dentro da cota gratuita do plano Free (sem cobrança). Limitação: no plano Free o **Modo Bot Fight** (ligado
na zona) não pode ser pulado por regra. Hoje o app passa normalmente; se aparecerem desafios (respostas HTML ou 403 em
`/h3suporte/*`), as saídas são desligar o Bot Fight na zona (vale para todo o `h3info.com`) ou o plano Pro (Super Bot
Fight Mode pode ser pulado na mesma regra).

Conferir de fora (não pode vir HTML de desafio):

```bash
curl -s -X POST https://keys.h3info.com/h3suporte/api/heartbeat -d '{"id":"teste"}'   # deve responder {}
```

## 4. Produto h3suporte no painel (Admin → Produtos)

O produto **já nasce no deploy**: a migração `20261115120000_produto_h3suporte` (commit `3c1dce5`) cria o H3 Suporte
(slug `h3suporte`, **Publicado**, **Contas do assinante: Sim**, com descrição e instruções). O h3suporte não tem site para
"Conectar à Central"; o resto se faz no painel:

1. Criar os planos e, em cada um, o **Limite de contas por assinatura** (ex.: plano Equipe 5 → 5). O limite de
   **computadores** acompanha o de contas: um computador por técnico. Plano sem limite de contas usa o **Limite de
   instalações** do produto (vem 1; ajuste se for usar plano sem limite).
2. Termos de uso, preços (da Central e/ou dos parceiros) e liberação aos parceiros, como qualquer produto.
3. Revisar as instruções que aparecem na entrega da chave (já vêm preenchidas):
   > Crie a conta do responsável em https://keys.h3info.com/assinante/criar-conta com a sua chave. Você recebe um e-mail
   > para criar a senha. Depois convide sua equipe no portal do assinante e entre no H3 Suporte com o seu e-mail e senha.

   Na venda direta da Central e na habilitação pelo app, o titular é criado sozinho com o e-mail da compra e recebe o
   link para criar a senha; a chave serve só se esse e-mail não chegar (dá para corrigir o e-mail com a chave enquanto a
   senha não foi criada).

## 5. Credencial do servidor-api

**Automática desde o commit `733b5f8` da Central.** O `make deploy`/`make up` da Central garante a credencial `sva_` de
licenciamento do produto `h3suporte` e a guarda em `H3SUPORTE_CREDENCIAL` no `.env` da Central (reaproveita a de
`/opt/h3suporte-api/.env` na primeira vez; se não houver, cria outra direto no banco). Ninguém precisa copiar a credencial.

Situação em 14/11/2026: a credencial "Servidor h3suporte-api" foi criada no painel e colocada em `/opt/h3suporte-api/.env`;
o login pelo app já fala com a Central (e-mail inexistente responde "E-mail ou senha incorretos"). O próximo `make deploy`
leva essa mesma credencial para o `.env` da Central.

## 6. E-mail (obrigatório antes de vender)

Toda conta nasce sem senha e define a senha por um link enviado por e-mail: o titular (pela chave ou automático), o
convite da equipe e o “esqueci minha senha”. Sem SMTP configurado (Admin → E-mail), criar a conta pela chave e convidar
membro respondem `503` “A Central não consegue enviar e-mails agora”. Configure e teste o SMTP antes de liberar o produto.

## 7. O que mudou na Central e afeta o h3suporte

Contrato de `/api-servico/contas/*` igual; mudou o comportamento:

- **Códigos de recuperação do 2FA:** o `codigoTotp` do segundo passo aceita também um código no formato `ABCDE-FGHJK`
  (uso único). O servidor-api já repassa o `tfaCode` (até 32 caracteres), mas o campo do app
  (`Dialog2FaField` em `flutter/lib/common/widgets/dialog.dart`) só aceita 6 dígitos. Até mudar o app, quem perdeu o
  celular usa o código no portal do assinante (e reconfigura o 2FA em Minha conta) ou pede ao titular para zerar.
- **`CONTA_BLOQUEADA` só com a senha certa:** durante o bloqueio, senha errada responde `401 CREDENCIAIS_INVALIDAS`.
- **Limite por e-mail:** 5 tentativas de `entrar` em 10 min (antes 10); o 6º responde `429 MUITAS_TENTATIVAS`.
- **`validar` informa o motivo** também para sessão encerrada: `CONTA_DESATIVADA` e `DISPOSITIVO_REMOVIDO` passam a
  aparecer de fato.
- **Assinatura que sai de `ATIVA`** derruba as sessões abertas; com a reativação, cada pessoa entra de novo.
- **Conta sem senha** (convite ou titular que ainda não abriu o link) responde `CREDENCIAIS_INVALIDAS` no `entrar`.

## 8. Publicar o servidor-api

**Sobe junto com a Central** (`make up` e `make deploy`, ou só `make servicos`), pelo `ops/servicos.sh` do repositório da
Central: constrói a imagem direto deste repositório no GitHub (`master`, pasta `servidor-api`; outra fonte em
`H3SUPORTE_FONTE`), sobe o container `h3suporte-api` no projeto `central` (rede interna, volume `h3suporte-api_dados`) e
remove o container do deploy separado antigo, se existir. Desligar: `H3SUPORTE=0` no `.env` da Central. Detalhes e mudança
de servidor: `docs/operacao.md` da Central, seção "Serviços de produtos no mesmo servidor".

Para publicar uma versão nova do servidor-api: commit e push no `master` deste repositório e `make deploy` (ou
`make servicos`) no servidor da Central. O `servidor-api/publicar.sh` (cópia por SSH, projeto separado) fica só como
alternativa; não use os dois juntos.

## 9. Verificação final

```bash
curl -s https://keys.h3info.com/h3suporte/saude              # {"ok":true}
curl -s https://keys.h3info.com/h3suporte/api/login-options  # []
```

Depois: criar uma conta de titular de teste com uma chave real em `/assinante/criar-conta`, abrir o link do e-mail e
criar a senha, entrar no app h3suporte (build novo, que já aponta para `https://keys.h3info.com/h3suporte`) e conferir em
Admin → Ativações → a ativação → **Contas do assinante** se o computador aparece.
