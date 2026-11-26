//! "Registrar" da sessão em andamento: o técnico define, pela conexão já autenticada, uma senha permanente no
//! computador que está acessando e a guarda em "Meus dispositivos" da conta dele (servidor-api). A senha é gerada
//! pelo app do técnico e não aparece no computador acessado.

use base::message_proto::*;
use std::{
    collections::HashMap,
    sync::{mpsc, Mutex},
    time::Duration,
};

const ESPERA: Duration = Duration::from_secs(20);

lazy_static::lazy_static! {
    static ref PENDENTES: Mutex<HashMap<u64, mpsc::Sender<String>>> = Default::default();
}

fn mensagem_pedido(senha: String) -> Message {
    let mut misc = Misc::new();
    misc.set_h3_register_device(H3RegisterDevice {
        password: senha,
        ..Default::default()
    });
    let mut msg = Message::new();
    msg.set_misc(misc);
    msg
}

#[cfg(not(target_os = "ios"))]
fn mensagem_resposta(erro: String) -> Message {
    let mut misc = Misc::new();
    misc.set_h3_register_device_result(H3RegisterDeviceResult {
        error: erro,
        ..Default::default()
    });
    let mut msg = Message::new();
    msg.set_misc(misc);
    msg
}

/// Lado do técnico: envia a senha ao computador da sessão e espera a resposta (bloqueia até [ESPERA]).
/// Devolve JSON `{erro, nome, so}`; `erro` vazio = senha definida lá.
pub fn registrar<T: crate::ui_session_interface::InvokeUiSession>(
    sessao: &crate::ui_session_interface::Session<T>,
    senha: String,
) -> String {
    use crate::client::{Data, Interface};
    let (id, nome, so) = {
        let lc = sessao.lc.read().unwrap();
        (lc.session_id, lc.info.hostname.clone(), lc.info.platform.clone())
    };
    let (tx, rx) = mpsc::channel();
    PENDENTES.lock().unwrap().insert(id, tx);
    sessao.send(Data::Message(mensagem_pedido(senha)));
    let erro = rx.recv_timeout(ESPERA).unwrap_or_else(|_| {
        "O computador acessado não respondeu. Atualize o H3 Suporte nele e tente de novo.".to_owned()
    });
    PENDENTES.lock().unwrap().remove(&id);
    serde_json::json!({ "erro": erro, "nome": nome, "so": so }).to_string()
}

/// Lado do técnico: resposta que chegou pela conexão.
pub fn responder(sessao: u64, r: H3RegisterDeviceResult) {
    if let Some(tx) = PENDENTES.lock().unwrap().remove(&sessao) {
        tx.send(r.error).ok();
    }
}

/// Lado do computador acessado: libera a senha permanente (se só a de uso único ou só o clique valiam) e a define.
#[cfg(not(target_os = "ios"))]
pub async fn definir_senha(pedido: H3RegisterDevice, permitido: bool) -> Message {
    if !permitido {
        return mensagem_resposta(
            "Para registrar, o acesso precisa ser de controle remoto com teclado e mouse liberados.".to_owned(),
        );
    }
    let erro = match definir(pedido.password).await {
        Ok(()) => {
            hbb_common::log::info!("h3: senha permanente definida pelo técnico conectado");
            String::new()
        }
        Err(e) => {
            hbb_common::log::warn!("h3: registro pelo técnico recusado: {e}");
            e
        }
    };
    mensagem_resposta(erro)
}

#[cfg(not(target_os = "ios"))]
async fn definir(senha: String) -> Result<(), String> {
    use crate::trusted_devices::config as seguro;
    use base::config::keys;
    use hbb_common::{
        config::Config,
        password_security::{approve_mode, permanent_enabled, ApproveMode},
    };

    if senha.chars().count() < 8 || senha.len() > 128 {
        return Err("Senha inválida.".to_owned());
    }
    if Config::is_disable_change_permanent_password() {
        return Err("Este computador não permite trocar a senha permanente.".to_owned());
    }
    if !permanent_enabled() || approve_mode() == ApproveMode::Click {
        let mut opcoes = Config::get_options();
        if !permanent_enabled() {
            opcoes.insert(
                keys::OPTION_VERIFICATION_METHOD.to_owned(),
                "use-both-passwords".to_owned(),
            );
        }
        if approve_mode() == ApproveMode::Click {
            opcoes.insert(keys::OPTION_APPROVE_MODE.to_owned(), "password-click".to_owned());
        }
        seguro::update_options(opcoes)
            .await
            .map_err(|e| format!("Não foi possível liberar a senha permanente: {e}"))?;
        if !permanent_enabled() || approve_mode() == ApproveMode::Click {
            return Err(
                "A configuração deste computador só aceita senha de uso único ou aprovação por clique.".to_owned(),
            );
        }
    }
    let afetado = seguro::changes_password(&senha);
    match seguro::update_auth(afetado, move || seguro::set_password(&senha)).await {
        Ok(true) => Ok(()),
        Ok(false) => Err("O computador acessado não aceitou a nova senha.".to_owned()),
        Err(e) => Err(format!("O computador acessado recusou a nova senha: {e}")),
    }
}
