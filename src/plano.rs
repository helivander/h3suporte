//! Funções do aplicativo liberadas pelo plano da assinatura (Central de ativação).
//!
//! O servidor-api do H3 Suporte devolve no login e no `currentUser` o campo `funcoes`, guardado pelo app em
//! `user_info`. Regras:
//! * sem login (`user_info` vazio): as funções abaixo ficam bloqueadas, porque são do plano;
//! * logado e `funcoes` ausente ou `null`: o produto não separa por função, tudo liberado;
//! * logado e `funcoes` lista: só os códigos da lista.
//!
//! O controle remoto comum não depende do plano.

use hbb_common::{config::LocalConfig, rendezvous_proto::ConnType};

pub const TRANSFERENCIA_ARQUIVOS: &str = "transferencia_arquivos";
pub const TERMINAL: &str = "terminal";
pub const TUNEL: &str = "tunel";
pub const CAMERA: &str = "camera";

/// Código da função do plano exigida por um tipo de conexão de saída (None = não depende do plano).
pub fn funcao_da_conexao(conn_type: ConnType) -> Option<&'static str> {
    match conn_type {
        ConnType::FILE_TRANSFER => Some(TRANSFERENCIA_ARQUIVOS),
        ConnType::TERMINAL => Some(TERMINAL),
        ConnType::PORT_FORWARD | ConnType::RDP => Some(TUNEL),
        ConnType::VIEW_CAMERA => Some(CAMERA),
        _ => None,
    }
}

fn nome(funcao: &str) -> &str {
    match funcao {
        TRANSFERENCIA_ARQUIVOS => "Transferência de arquivos",
        TERMINAL => "Terminal remoto",
        TUNEL => "Túnel (TCP/RDP)",
        CAMERA => "Câmera remota",
        outra => outra,
    }
}

/// `user_info` guardado pelo app libera a função?
fn liberada_em(user_info: &str, funcao: &str) -> bool {
    if user_info.trim().is_empty() {
        return false;
    }
    let Ok(info) = serde_json::from_str::<serde_json::Value>(user_info) else {
        return false;
    };
    match info.get("funcoes") {
        None | Some(serde_json::Value::Null) => true,
        Some(serde_json::Value::Array(lista)) => lista.iter().any(|f| f.as_str() == Some(funcao)),
        Some(_) => false,
    }
}

/// Motivo para recusar a conexão, ou None se o plano libera.
pub fn bloqueio(conn_type: ConnType) -> Option<String> {
    let funcao = funcao_da_conexao(conn_type)?;
    let user_info = LocalConfig::get_option("user_info");
    if liberada_em(&user_info, funcao) {
        return None;
    }
    Some(if user_info.trim().is_empty() {
        format!("{}: entre com sua conta H3 Suporte para usar.", nome(funcao))
    } else {
        format!("{}: não incluída no plano da sua assinatura.", nome(funcao))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sem_login_bloqueia() {
        assert!(!liberada_em("", TERMINAL));
        assert!(!liberada_em("lixo", TERMINAL));
    }

    #[test]
    fn sem_funcoes_libera_tudo() {
        assert!(liberada_em(r#"{"name":"a@b.c"}"#, TERMINAL));
        assert!(liberada_em(r#"{"name":"a@b.c","funcoes":null}"#, TUNEL));
    }

    #[test]
    fn lista_libera_so_as_do_plano() {
        let info = r#"{"name":"a@b.c","funcoes":["terminal"]}"#;
        assert!(liberada_em(info, TERMINAL));
        assert!(!liberada_em(info, TRANSFERENCIA_ARQUIVOS));
        assert!(!liberada_em(r#"{"funcoes":[]}"#, CAMERA));
    }

    #[test]
    fn conexao_comum_nao_depende_do_plano() {
        assert_eq!(funcao_da_conexao(ConnType::DEFAULT_CONN), None);
        assert_eq!(funcao_da_conexao(ConnType::RDP), Some(TUNEL));
    }
}
