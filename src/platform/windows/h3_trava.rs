//! Trava só o teclado ou só o mouse físicos. `BlockInput` trava os dois juntos,
//! por isso aqui são usados ganchos de baixo nível que descartam apenas a
//! entrada não injetada: o controle remoto (`SendInput`) continua passando.

use hbb_common::{bail, log, ResultType};
use std::{
    io,
    ptr::null_mut,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Mutex,
    },
};
use winapi::{
    ctypes::c_int,
    shared::minwindef::{LPARAM, LRESULT, WPARAM},
    um::{libloaderapi::GetModuleHandleW, processthreadsapi::GetCurrentThreadId, winuser::*},
};

static TECLADO: AtomicBool = AtomicBool::new(false);
static MOUSE: AtomicBool = AtomicBool::new(false);
// Id da thread dos ganchos; zero quando não há ganchos instalados.
static THREAD: Mutex<u32> = Mutex::new(0);

unsafe extern "system" fn gancho_teclado(code: c_int, w: WPARAM, l: LPARAM) -> LRESULT {
    if code >= 0 && TECLADO.load(Ordering::SeqCst) {
        let k = &*(l as *const KBDLLHOOKSTRUCT);
        if k.flags & LLKHF_INJECTED == 0 {
            return 1;
        }
    }
    CallNextHookEx(null_mut(), code, w, l)
}

unsafe extern "system" fn gancho_mouse(code: c_int, w: WPARAM, l: LPARAM) -> LRESULT {
    if code >= 0 && MOUSE.load(Ordering::SeqCst) {
        let m = &*(l as *const MSLLHOOKSTRUCT);
        if m.flags & LLMHF_INJECTED == 0 {
            return 1;
        }
    }
    CallNextHookEx(null_mut(), code, w, l)
}

pub fn travar_teclado(travar: bool) -> ResultType<()> {
    TECLADO.store(travar, Ordering::SeqCst);
    ajustar_ganchos()
}

pub fn travar_mouse(travar: bool) -> ResultType<()> {
    MOUSE.store(travar, Ordering::SeqCst);
    ajustar_ganchos()
}

fn ajustar_ganchos() -> ResultType<()> {
    let mut thread = THREAD.lock().unwrap();
    let precisa = TECLADO.load(Ordering::SeqCst) || MOUSE.load(Ordering::SeqCst);
    if precisa && *thread == 0 {
        *thread = instalar()?;
    } else if !precisa && *thread != 0 {
        if unsafe { PostThreadMessageW(*thread, WM_QUIT, 0, 0) } == 0 {
            bail!("PostThreadMessageW: {}", io::Error::last_os_error());
        }
        *thread = 0;
    }
    Ok(())
}

// Ganchos de baixo nível exigem uma thread própria com laço de mensagens.
fn instalar() -> ResultType<u32> {
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || unsafe {
        let modulo = GetModuleHandleW(null_mut());
        let teclado = SetWindowsHookExW(WH_KEYBOARD_LL, Some(gancho_teclado), modulo, 0);
        let mouse = SetWindowsHookExW(WH_MOUSE_LL, Some(gancho_mouse), modulo, 0);
        let resultado = if teclado.is_null() || mouse.is_null() {
            Err(io::Error::last_os_error().to_string())
        } else {
            Ok(GetCurrentThreadId())
        };
        let instalado = resultado.is_ok();
        let mut msg: MSG = std::mem::zeroed();
        // Cria a fila de mensagens antes de publicar o id da thread.
        PeekMessageW(&mut msg, null_mut(), 0, 0, PM_NOREMOVE);
        if tx.send(resultado).is_ok() && instalado {
            while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {}
        }
        for gancho in [teclado, mouse] {
            if !gancho.is_null() && UnhookWindowsHookEx(gancho) == 0 {
                log::error!("UnhookWindowsHookEx: {}", io::Error::last_os_error());
            }
        }
    });
    match rx.recv()? {
        Ok(id) => Ok(id),
        Err(e) => {
            TECLADO.store(false, Ordering::SeqCst);
            MOUSE.store(false, Ordering::SeqCst);
            bail!("SetWindowsHookExW: {}", e)
        }
    }
}
