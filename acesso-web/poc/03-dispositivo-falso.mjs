// Dispositivo e servidor de conexão FALSOS, para testar o acesso pelo navegador (portal da Central) sem um computador
// de verdade. Escreve o lado do dispositivo do protocolo (assinaturas, troca de chaves, login, vídeo) com as
// bibliotecas de referência (protobufjs com os .proto reais, tweetnacl, blakejs), independentes do cliente do navegador.
//
//   node 03-dispositivo-falso.mjs            # sobe em ws://localhost:21120 (/ws/id e /ws/relay)
//   abra http://localhost:21120/gerar        # o navegador gera o vídeo VP9 de teste e envia para cá (uma vez)
//
// Na Central (desenvolvimento): ACESSO_REMOTO_SERVIDOR=ws://localhost:21120 e ACESSO_REMOTO_CHAVE=<chave impressa>.
// O ID do dispositivo e a senha vêm de ID e SENHA (padrão 999000111 / teste-123). Eventos recebidos vão para o console.
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import protobuf from 'protobufjs';
import nacl from 'tweetnacl';
import { blake2b } from 'blakejs';
import { fileURLToPath } from 'node:url';
import { WebSocketServer } from 'ws';

const PORTA = Number(process.env.PORTA ?? 21120);
const ID = process.env.ID ?? '999000111';
const SENHA = process.env.SENHA ?? 'teste-123';
const QUADROS = fileURLToPath(new URL('./quadros-teste.json', import.meta.url));
const seed = (nome) => new Uint8Array(crypto.createHash('sha256').update(nome).digest());

const base = fileURLToPath(new URL('../../libs/', import.meta.url));
const R = await protobuf.load(base + 'hbb_common/protos/rendezvous.proto');
const M = await protobuf.load(base + 'base/protos/message.proto');
const RMsg = R.lookupType('hbb.RendezvousMessage');
const IdPk = R.lookupType('hbb.IdPk');
const Msg = M.lookupType('hbb.Message');

// Chaves fixas (derivadas do nome): a chave do servidor não muda entre execuções.
const servidor = nacl.sign.keyPair.fromSeed(seed('servidor-falso'));
const dispositivoAssina = nacl.sign.keyPair.fromSeed(seed('dispositivo-falso'));
const dispositivoBox = nacl.box.keyPair.fromSecretKey(seed('dispositivo-falso-box'));
const CHAVE_SERVIDOR = Buffer.from(servidor.publicKey).toString('base64');

const log = (...a) => console.log(new Date().toISOString().slice(11, 23), ...a);
const enc = (T, obj) => T.encode(T.fromObject(obj)).finish();
const sha = (...p) => { const h = crypto.createHash('sha256'); p.forEach((x) => h.update(x)); return h.digest(); };

let quadros = fs.existsSync(QUADROS) ? JSON.parse(fs.readFileSync(QUADROS, 'utf8')) : null;

// ---------------------------------------------------------------- HTTP: gerador do vídeo de teste
const PAGINA = `<!doctype html><meta charset="utf-8"><title>Gerar vídeo de teste</title>
<body style="font:16px system-ui;padding:2rem"><h1>Gerar vídeo VP9 de teste</h1><pre id="o">gerando…</pre>
<canvas id="c" width="1280" height="720" style="display:none"></canvas>
<script type="module">
const o = document.getElementById('o'), c = document.getElementById('c'), x = c.getContext('2d');
const W = 1280, H = 720, N = 60, saida = [];
const enc = new VideoEncoder({
  output: (chunk) => { const d = new Uint8Array(chunk.byteLength); chunk.copyTo(d); saida.push({ key: chunk.type === 'key', data: btoa(String.fromCharCode(...d)) }); },
  error: (e) => { o.textContent = 'erro: ' + e.message; },
});
enc.configure({ codec: 'vp09.00.10.08', width: W, height: H, bitrate: 2_000_000, framerate: 15, latencyMode: 'realtime' });
for (let i = 0; i < N; i++) {
  const g = x.createLinearGradient(0, 0, W, H); g.addColorStop(0, '#12263f'); g.addColorStop(1, '#1b6b5c');
  x.fillStyle = g; x.fillRect(0, 0, W, H);
  x.fillStyle = '#fff'; x.font = 'bold 56px system-ui'; x.fillText('Computador de teste (H3 Suporte)', 60, 120);
  x.font = '32px system-ui'; x.fillText('Quadro ' + String(i).padStart(2, '0') + ' de ' + N, 60, 180);
  x.fillStyle = '#f4b942'; x.fillRect(60 + (i * 18) % 1000, 300 + Math.sin(i / 6) * 80, 160, 160);
  x.fillStyle = '#ffffff22'; x.fillRect(0, H - 80, W, 80); x.fillStyle = '#fff'; x.font = '24px system-ui'; x.fillText('Mova o mouse, clique, digite e role aqui: o console do dispositivo falso mostra o que chegou.', 40, H - 30);
  const f = new VideoFrame(c, { timestamp: i * 66667 }); enc.encode(f, { keyFrame: i === 0 }); f.close();
}
await enc.flush();
const r = await fetch('/quadros', { method: 'POST', body: JSON.stringify(saida) });
o.textContent = saida.length + ' quadros enviados (' + Math.round(JSON.stringify(saida).length / 1024) + ' KB): ' + (await r.text());
</script>`;

const http_ = http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/gerar') { res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); return res.end(PAGINA); }
  if (req.method === 'POST' && req.url === '/quadros') {
    let corpo = ''; for await (const p of req) corpo += p;
    fs.writeFileSync(QUADROS, corpo); quadros = JSON.parse(corpo);
    log('vídeo de teste recebido:', quadros.length, 'quadros');
    res.writeHead(200); return res.end('ok, salvo em quadros-teste.json');
  }
  res.writeHead(404); res.end();
});

// ---------------------------------------------------------------- /ws/id (rendezvous) e /ws/relay (dispositivo)
const wss = new WebSocketServer({ noServer: true });
http_.on('upgrade', (req, socket, head) => {
  if (req.url !== '/ws/id' && req.url !== '/ws/relay') return socket.destroy();
  wss.handleUpgrade(req, socket, head, (ws) => (req.url === '/ws/id' ? rendezvous(ws) : relay(ws)));
});

function rendezvous(ws) {
  ws.on('message', (d) => {
    const m = RMsg.toObject(RMsg.decode(d), { defaults: false, longs: Number });
    if (m.punchHoleRequest) {
      const q = m.punchHoleRequest;
      log('rendezvous: punch_hole_request id', q.id, 'forceRelay', q.forceRelay);
      let resp;
      if (q.licenceKey !== CHAVE_SERVIDOR) resp = { failure: 3 };
      else if (q.id !== ID) resp = { failure: 0 };
      else {
        const idpk = enc(IdPk, { id: ID, pk: Buffer.from(dispositivoAssina.publicKey) });
        resp = { pk: Buffer.from(nacl.sign(idpk, servidor.secretKey)), relayServer: `localhost:${PORTA}` };
      }
      ws.send(enc(RMsg, { punchHoleResponse: resp }));
    } else if (m.requestRelay) {
      log('rendezvous: request_relay uuid', m.requestRelay.uuid);
      ws.send(enc(RMsg, { relayResponse: { uuid: m.requestRelay.uuid, relayServer: `localhost:${PORTA}` } }));
    }
  });
}

function relay(ws) {
  let estado = 'pedido'; let kEnv, kRec, nEnv = 0, nRec = 0; let anunciada = 1;
  const nonce = (n) => { const b = Buffer.alloc(24); b.writeBigUInt64LE(BigInt(n)); return b; };
  const enviar = (obj) => ws.send(Buffer.from(nacl.secretbox(enc(Msg, obj), nonce(++nEnv), kEnv)));
  const desafio = { salt: 'sal-de-teste', challenge: crypto.randomBytes(8).toString('hex') };
  let timer = null; let indice = 0; let forcarChave = false; let tela = 0;

  const parar = () => { if (timer) clearInterval(timer); timer = null; };
  ws.on('close', () => { parar(); log('dispositivo: conexão encerrada'); });

  function iniciarVideo() {
    if (!quadros) { log('AVISO: sem vídeo de teste. Abra http://localhost:' + PORTA + '/gerar no navegador.'); return; }
    parar(); indice = 0;
    timer = setInterval(() => {
      if (forcarChave) { indice = 0; forcarChave = false; }
      const q = quadros[indice % quadros.length];
      enviar({ videoFrame: { vp9s: { frames: [{ data: Buffer.from(q.data, 'base64'), key: q.key, pts: Date.now() % 1_000_000 }] }, display: tela } });
      indice++;
      if (indice >= quadros.length) indice = 0; // recomeça num quadro-chave (o primeiro)
    }, 66);
  }

  ws.on('message', (d) => {
    try {
      if (estado === 'pedido') {
        const m = RMsg.toObject(RMsg.decode(d), { defaults: false });
        if (!m.requestRelay) return;
        log('relay: request_relay id', m.requestRelay.id);
        const idpk = enc(IdPk, { id: ID, pk: Buffer.from(dispositivoBox.publicKey), kxVersion: anunciada });
        ws.send(enc(Msg, { signedId: { id: Buffer.from(nacl.sign(idpk, dispositivoAssina.secretKey)) } }));
        estado = 'chaves';
        return;
      }
      if (estado === 'chaves') {
        const m = Msg.toObject(Msg.decode(d), { defaults: false });
        const pk = m.publicKey; const picked = pk.kxVersion ?? 0;
        const sim = nacl.box.open(new Uint8Array(pk.symmetricValue), new Uint8Array(24), new Uint8Array(pk.asymmetricValue), dispositivoBox.secretKey);
        if (!sim) { log('ERRO: não consegui abrir a chave simétrica'); return ws.close(); }
        const sub = (dir) => {
          const u32 = (n) => { const b = Buffer.alloc(4); b.writeUInt32LE(n); return b; };
          return Buffer.from(blake2b(Buffer.concat([Buffer.from('rdkx-spl'), Buffer.from([dir]), u32(anunciada), u32(picked), Buffer.from(pk.asymmetricValue), Buffer.from(dispositivoBox.publicKey)]), sim, 32));
        };
        kRec = picked >= 1 ? sub(1) : Buffer.from(sim); kEnv = picked >= 1 ? sub(2) : Buffer.from(sim);
        log('relay: chaves trocadas (kx', picked + ')');
        enviar({ hash: desafio });
        estado = 'login';
        return;
      }
      const aberto = nacl.secretbox.open(new Uint8Array(d), nonce(++nRec), kRec);
      if (!aberto) { log('ERRO: falha ao decifrar mensagem do navegador'); return ws.close(); }
      const m = Msg.toObject(Msg.decode(aberto), { defaults: false, longs: Number, enums: String });
      if (m.loginRequest) {
        const q = m.loginRequest;
        const esperado = sha(sha(SENHA, desafio.salt), desafio.challenge);
        const ok = Buffer.from(q.password).equals(esperado);
        log('login de', q.myName, '/', q.myId, '→', ok ? 'senha ok' : 'SENHA ERRADA', '| decodifica:', JSON.stringify(q.option?.supportedDecoding), '| opções:', JSON.stringify({ ...q.option, supportedDecoding: undefined }));
        if (!ok) return enviar({ loginResponse: { error: 'Wrong Password' } });
        enviar({ loginResponse: { peerInfo: { username: 'teste', hostname: 'PC-DE-TESTE', platform: 'Windows', displays: [{ x: 0, y: 0, width: 1280, height: 720, name: 'Tela 1', online: true, cursorEmbedded: true }, { x: 1280, y: 0, width: 1280, height: 720, name: 'Tela 2', online: true, cursorEmbedded: true }], currentDisplay: 0, sasEnabled: true, version: '1.5.3' } } });
        iniciarVideo();
        setInterval(() => enviar({ testDelay: { time: Date.now(), fromClient: false } }), 3000).unref();
      } else if (m.mouseEvent) {
        const tipo = ['mover', 'descer', 'subir', 'roda'][m.mouseEvent.mask & 7]; const botao = m.mouseEvent.mask >> 3;
        if (tipo !== 'mover') log('mouse', tipo, 'botão', botao, 'x', m.mouseEvent.x, 'y', m.mouseEvent.y, 'mod', m.mouseEvent.modifiers ?? []);
        else if ((indice % 10) === 0) log('mouse mover', m.mouseEvent.x, m.mouseEvent.y);
      } else if (m.keyEvent) {
        log('tecla', JSON.stringify(m.keyEvent));
      } else if (m.misc?.refreshVideo) { log('misc: refresh_video'); forcarChave = true; }
      else if (m.misc?.switchDisplay) { tela = m.misc.switchDisplay.display ?? 0; log('misc: trocar para a tela', tela); }
      else if (m.misc?.option) log('misc: opção', JSON.stringify(m.misc.option));
      else if (m.testDelay) log('test_delay devolvido (', Date.now() - m.testDelay.time, 'ms )');
      else log('mensagem', Object.keys(m).join(','));
    } catch (e) { log('ERRO no relay:', e.message); }
  });
}

http_.listen(PORTA, () => {
  log(`dispositivo falso em ws://localhost:${PORTA}/ws/id e /ws/relay`);
  log('ID do dispositivo:', ID, '| senha:', SENHA);
  log('ACESSO_REMOTO_SERVIDOR=ws://localhost:' + PORTA);
  log('ACESSO_REMOTO_CHAVE=' + CHAVE_SERVIDOR);
  if (!quadros) log('Falta o vídeo de teste: abra http://localhost:' + PORTA + '/gerar no navegador (uma vez).');
});
