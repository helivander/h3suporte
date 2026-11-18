// Passo 2: sessão completa com um dispositivo por WebSocket (sem navegador ainda).
//   punch hole -> relay -> troca de chaves com o dispositivo -> login com senha -> primeiros quadros de vídeo
// Uso: SENHA='...' node 02-sessao.mjs <id-do-dispositivo>
// A senha vem só do ambiente: nunca grave em arquivo nem no git.
import crypto from 'node:crypto';
import protobuf from 'protobufjs';
import nacl from 'tweetnacl';
import { blake2b } from 'blakejs';
import WebSocket from 'ws';

const HOST = process.env.HOST ?? 'hbbsserver.h3info.com';
const CHAVE_SERVIDOR = process.env.CHAVE ?? 'ZCsYXRdFGM3S59i637iReSPtYe+UG4mKAwaqQAqRwJk=';
const id = process.argv[2];
const senha = process.env.SENHA ?? '';
if (!id || !senha) { console.error('uso: SENHA=... node 02-sessao.mjs <id>'); process.exit(1); }

const base = new URL('../../libs/', import.meta.url).pathname;
const R = (await protobuf.load(base + 'hbb_common/protos/rendezvous.proto'));
const M = (await protobuf.load(base + 'base/protos/message.proto'));
const RMsg = R.lookupType('hbb.RendezvousMessage');
const Msg = M.lookupType('hbb.Message');
const IdPk = R.lookupType('hbb.IdPk');
const log = (...a) => console.log(new Date().toISOString().slice(11, 23), ...a);

// ---------- transporte WebSocket com fila de mensagens ----------
function abrir(url) {
  return new Promise((ok, falha) => {
    const ws = new WebSocket(url);
    ws.binaryType = 'nodebuffer';
    const fila = []; let espera = null;
    ws.on('message', (d) => { espera ? (espera(d), espera = null) : fila.push(d); });
    ws.on('close', () => { if (espera) espera(null); });
    ws.on('open', () => ok({
      enviar: (b) => ws.send(b),
      receber: (ms = 10000) => new Promise((res, rej) => {
        if (fila.length) return res(fila.shift());
        const t = setTimeout(() => { espera = null; rej(new Error('tempo esgotado')); }, ms);
        espera = (d) => { clearTimeout(t); d ? res(d) : rej(new Error('conexão fechada')); };
      }),
      fechar: () => ws.close(),
    }));
    ws.on('error', falha);
  });
}
const rz_enviar = (c, obj) => c.enviar(RMsg.encode(RMsg.create(obj)).finish());
const rz_receber = async (c, ms) => RMsg.toObject(RMsg.decode(await c.receber(ms)), { enums: String, bytes: Buffer, defaults: false });

// ---------- 1. punch hole: onde está o dispositivo ----------
const rend = await abrir(`ws://${HOST}:21118`);
rz_enviar(rend, { punchHoleRequest: { id, natType: 1, licenceKey: CHAVE_SERVIDOR, connType: 0, version: '1.5.3', forceRelay: true } });
const ph = (await rz_receber(rend)).punchHoleResponse;
rend.fechar();
if (!ph?.pk?.length) { log('dispositivo não encontrado ou offline:', JSON.stringify(ph)); process.exit(2); }
const servidorRelay = ph.relayServer || `${HOST}:21117`;
log('1. dispositivo encontrado; relay:', servidorRelay);

// ---------- 2. pede o relay ----------
const uuid = crypto.randomUUID();
const rend2 = await abrir(`ws://${HOST}:21118`);
rz_enviar(rend2, { requestRelay: { id, uuid, relayServer: servidorRelay, secure: true } });
const rr = (await rz_receber(rend2)).relayResponse;
rend2.fechar();
if (rr?.refuseReason) { log('relay recusado:', rr.refuseReason); process.exit(3); }
log('2. relay aceito');
const relay = await abrir(`ws://${HOST}:21119`);
rz_enviar(relay, { requestRelay: { licenceKey: CHAVE_SERVIDOR, id, uuid, connType: 0 } });
log('   conectado ao relay');

// ---------- 3. troca de chaves com o dispositivo ----------
const rsPk = Buffer.from(CHAVE_SERVIDOR, 'base64');
const abertoRs = nacl.sign.open(ph.pk, rsPk);
if (!abertoRs) { log('assinatura do servidor inválida'); process.exit(4); }
const idpk = IdPk.decode(abertoRs);
if (idpk.id !== id) { log('ID da assinatura diferente'); process.exit(4); }
const signPk = idpk.pk;

const m1 = Msg.decode(await relay.receber());
if (!m1.signedId) { log('esperava SignedId, veio:', Object.keys(Msg.toObject(m1))); process.exit(5); }
const abertoPeer = nacl.sign.open(m1.signedId.id, signPk);
if (!abertoPeer) { log('assinatura do dispositivo inválida'); process.exit(5); }
const peerIdPk = IdPk.decode(abertoPeer);
if (peerIdPk.id !== id) { log('ID do dispositivo diferente'); process.exit(5); }
const advertised = peerIdPk.kxVersion ?? 0;
const picked = Math.min(advertised, 1);
log('3. dispositivo verificado; kx anunciado', advertised, 'escolhido', picked);

const meu = nacl.box.keyPair();
const chaveSim = nacl.randomBytes(32);
const selada = nacl.box(chaveSim, new Uint8Array(24), peerIdPk.pk, meu.secretKey);
relay.enviar(Msg.encode(Msg.create({ publicKey: { asymmetricValue: meu.publicKey, symmetricValue: selada, kxVersion: picked } })).finish());

function subchave(direcao) {
  const u32 = (n) => { const b = Buffer.alloc(4); b.writeUInt32LE(n); return b; };
  const entrada = Buffer.concat([Buffer.from('rdkx-spl'), Buffer.from([direcao]), u32(advertised), u32(picked), Buffer.from(meu.publicKey), Buffer.from(peerIdPk.pk)]);
  return Buffer.from(blake2b(entrada, chaveSim, 32));
}
const kEnv = picked >= 1 ? subchave(1) : chaveSim;
const kRec = picked >= 1 ? subchave(2) : chaveSim;
let nEnv = 0, nRec = 0;
const nonce = (n) => { const b = Buffer.alloc(24); b.writeBigUInt64LE(BigInt(n)); return b; };
const cifrar = (buf) => Buffer.from(nacl.secretbox(buf, nonce(++nEnv), kEnv));
const decifrar = (buf) => { const r = nacl.secretbox.open(buf, nonce(++nRec), kRec); if (!r) throw new Error('falha ao decifrar'); return Buffer.from(r); };
const enviarMsg = (obj) => relay.enviar(cifrar(Msg.encode(Msg.create(obj)).finish()));
let ultimoBruto = null;
const receberMsg = async (ms) => { ultimoBruto = decifrar(await relay.receber(ms)); return Msg.decode(ultimoBruto); };
const nome = (m) => Object.keys(Msg.toObject(m, { oneofs: true }))[0];

// ---------- 4. login ----------
const m2 = await receberMsg();
if (!m2.hash) { log('esperava Hash, veio:', nome(m2)); process.exit(6); }
const sha = (...p) => { const h = crypto.createHash('sha256'); p.forEach((x) => h.update(x)); return h.digest(); };
const senhaHash = sha(sha(senha, m2.hash.salt), m2.hash.challenge);
log('4. recebi o desafio de senha; enviando login');
enviarMsg({
  loginRequest: {
    username: id, password: senhaHash, myId: 'web' + crypto.randomBytes(3).toString('hex'), myName: 'Acesso Web (teste)',
    option: { imageQuality: 3, supportedDecoding: { abilityVp9: 1, abilityVp8: 1, abilityH264: 1, abilityAv1: 1, prefer: 0 } },
    videoAckRequired: false, sessionId: Number(crypto.randomBytes(6).readUIntBE(0, 6)), version: '1.5.3', myPlatform: 'Web',
  },
});

// ---------- 5. respostas e vídeo ----------
let quadros = 0; const t0 = Date.now();
while (Date.now() - t0 < 15000) {
  let m;
  try { m = await receberMsg(5000); } catch (e) { log('fim:', e.message); break; }
  const tipo = nome(m);
  if (tipo === 'loginResponse') {
    const lr = Msg.toObject(m.loginResponse, { enums: String, bytes: String });
    const erro = m.loginResponse.error;
    log('5. loginResponse:', erro ? `ERRO "${erro}"` : `ok, ${lr.peerInfo?.hostname} (${lr.peerInfo?.platform}), ${lr.peerInfo?.displays?.length} tela(s)`);
    if (erro) break;
  } else if (tipo === 'videoFrame') {
    const vf = m.videoFrame; const cod = ['vp9s', 'h264s', 'h265s', 'vp8s', 'av1s', 'rgb', 'yuv'].find((k) => vf[k]);
    const f = vf[cod]?.frames ?? [];
    quadros += f.length;
    if (quadros <= 3 || quadros % 30 === 0) log(`   vídeo ${cod}: ${f.length} quadro(s), ${f[0]?.data?.length} bytes, key=${f[0]?.key} (total ${quadros})`);
    if (quadros >= 60) break;
  } else {
    log('   msg:', tipo, tipo === 'misc' ? JSON.stringify(Msg.toObject(m.misc, { enums: String, bytes: String })).slice(0, 200) : '');
  }
}
log('resultado: quadros de vídeo recebidos =', quadros);
relay.fechar();
process.exit(quadros > 0 ? 0 : 7);
