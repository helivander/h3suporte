# Acesso remoto pelo navegador

Objetivo: o assinante, logado no portal da Central, controlar um dos seus dispositivos **sem instalar nada**.

**Estado (18/11/2026):** o cliente de produção já existe no portal da Central (repositório `centralkeys`,
`apps/web/lib/remoto/` e `apps/web/components/central/VisorRemoto.tsx`; documentação em `docs/acesso-remoto.md` de lá):
vídeo VP9 por WebCodecs, mouse, teclado, Ctrl+Alt+Del, envio de texto, troca de tela e qualidade. O que sobrou nesta
pasta são as provas de conceito em Node e o dispositivo falso para testes.

## O que a prova de conceito já validou (17/11/2026)

Contra o servidor de produção `hbbsserver.h3info.com`, por WebSocket (`ws://…:21118` e `ws://…:21119`):

1. **Rendezvous** (`poc/01-rendezvous.mjs`): o hbbs responde ao `PunchHoleRequest` com a chave assinada do dispositivo
   e o relay. Exige a chave pública do servidor em `licence_key`, senão responde `LICENSE_MISMATCH`.
2. **Relay**: `RequestRelay` no hbbs (21118) e de novo no hbbr (21119).
3. **Troca de chaves com o dispositivo** (`poc/02-sessao.mjs`): verifica a assinatura do servidor e a do dispositivo,
   envia a chave simétrica selada (`crypto_box`), deriva as chaves por direção (BLAKE2b, `kx_version` 1) e passa a
   cifrar cada mensagem com `secretbox` e nonce por contador.
4. **Login por senha**: `sha256(sha256(senha + salt) + challenge)`; o dispositivo aceitou e devolveu `PeerInfo`
   (nome, plataforma, telas).
5. **Vídeo**: chegaram quadros de vídeo, além de cursor e áudio.

## O que falta para funcionar em produção

- **`wss://`**: uma página `https://` não abre `ws://`. Resolvido no centralkeys: o Caddy da Central expõe
  `/ws/id` e `/ws/relay` no domínio dela (que já passa pela Cloudflare) e leva ao hbbs (`10.0.4.6:21118`) e ao hbbr
  (`:21119`); veja `docs/acesso-remoto.md` de lá. Com isso, as portas 21118 e 21119 abertas no UniFi só para os testes
  podem ser fechadas. O host `hbbsserver.h3info.com` é só DNS (sem Cloudflare nem certificado do nome) e não serve.
- Validar com um dispositivo real e com a senha de um computador de verdade (os testes automáticos e o dispositivo falso
  cobrem o protocolo, mas só o aplicativo real prova o comportamento de teclado e de tela do Windows/macOS/Linux).

## Como rodar

```bash
cd acesso-web/poc && npm install
node 01-rendezvous.mjs <id>                 # o dispositivo está online?
SENHA='…' node 02-sessao.mjs <id>           # sessão completa; a senha vem só do ambiente
node 03-dispositivo-falso.mjs               # servidor de conexão + dispositivo falsos (ws://localhost:21120)
```

`03-dispositivo-falso.mjs` serve para testar o portal da Central sem um computador de verdade: imprime a chave
pública e o ID/senha de teste, gera o vídeo VP9 (abra `http://localhost:21120/gerar` uma vez) e escreve no console o
que chega de mouse e teclado. A senha de **uso único** do app muda depois do primeiro login: para repetir o teste real
use uma senha permanente de teste. Nunca grave a senha em arquivo.
