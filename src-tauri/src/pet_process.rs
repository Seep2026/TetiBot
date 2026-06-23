use std::{
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum DesktopPetError {
    #[error("usagi was not found; build engine/usagi or set USAGI_BIN")]
    BinaryNotFound,
    #[error("Teti's usagi project was not found; set TETI_PET_PROJECT")]
    ProjectNotFound,
    #[error("failed to start the usagi desktop pet: {0}")]
    Spawn(#[from] std::io::Error),
}

pub struct DesktopPetProcess {
    child: Arc<Mutex<Child>>,
}

pub struct PetStatusBridge {
    signal_path: PathBuf,
    nonce: AtomicU64,
}

#[derive(Debug, Serialize)]
struct PetStatusSignal<'a> {
    command: &'static str,
    nonce: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pet_status: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    hat_id: Option<&'a str>,
}

impl DesktopPetProcess {
    pub fn spawn(app: AppHandle) -> Result<Self, DesktopPetError> {
        let binary = resolve_usagi_binary().ok_or(DesktopPetError::BinaryNotFound)?;
        let project = resolve_pet_project().ok_or(DesktopPetError::ProjectNotFound)?;
        let child = Command::new(binary)
            .arg("run")
            .arg(project)
            .env("USAGI_ACCESSORY_APP", "1")
            .env("TETI_PARENT_PID", std::process::id().to_string())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()?;
        let child = Arc::new(Mutex::new(child));
        monitor_pet_exit(app, Arc::clone(&child));
        Ok(Self { child })
    }
}

impl PetStatusBridge {
    pub fn new(signal_path: PathBuf) -> Self {
        Self {
            signal_path,
            nonce: AtomicU64::new(1),
        }
    }

    pub fn write_status(&self, status: &str) -> std::io::Result<()> {
        if let Some(parent) = self.signal_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let signal = PetStatusSignal {
            command: "pet_status",
            nonce: self.nonce.fetch_add(1, Ordering::Relaxed),
            pet_status: Some(status),
            hat_id: None,
        };
        let json = serde_json::to_vec(&signal).map_err(std::io::Error::other)?;
        std::fs::write(&self.signal_path, json)
    }

    pub fn write_hat(&self, hat_id: &str) -> std::io::Result<()> {
        if let Some(parent) = self.signal_path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let signal = PetStatusSignal {
            command: "set_hat",
            nonce: self.nonce.fetch_add(1, Ordering::Relaxed),
            pet_status: None,
            hat_id: Some(hat_id),
        };
        let json = serde_json::to_vec(&signal).map_err(std::io::Error::other)?;
        std::fs::write(&self.signal_path, json)
    }
}

impl Drop for DesktopPetProcess {
    fn drop(&mut self) {
        self.terminate();
    }
}

impl DesktopPetProcess {
    pub fn terminate(&self) {
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

#[derive(Debug, Deserialize)]
struct PetBridgeSignal {
    command: String,
    nonce: u64,
}

pub fn watch_bridge(app: AppHandle, signal_path: PathBuf) {
    tauri::async_runtime::spawn(async move {
        let mut last_nonce = read_signal(&signal_path).map(|signal| signal.nonce);
        loop {
            if let Some(signal) = read_signal(&signal_path) {
                if Some(signal.nonce) != last_nonce {
                    last_nonce = Some(signal.nonce);
                    match signal.command.as_str() {
                        "open_mail" => {
                            if let Some(window) = app.get_webview_window("mail") {
                                let _ = window.show();
                                let _ = window.unminimize();
                                let _ = window.set_focus();
                            }
                        }
                        "quit_teti" => {
                            app.exit(0);
                            break;
                        }
                        _ => {}
                    }
                }
            }
            tokio::time::sleep(Duration::from_millis(200)).await;
        }
    });
}

fn monitor_pet_exit(app: AppHandle, child: Arc<Mutex<Child>>) {
    tauri::async_runtime::spawn(async move {
        loop {
            let exited = child
                .lock()
                .ok()
                .and_then(|mut child| child.try_wait().ok().flatten())
                .is_some();
            if exited {
                app.exit(0);
                break;
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
    });
}

fn read_signal(path: &Path) -> Option<PetBridgeSignal> {
    let bytes = std::fs::read(path).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn resolve_usagi_binary() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("USAGI_BIN") {
        let path = PathBuf::from(path);
        if path.is_file() {
            return Some(path);
        }
    }
    let source_root = Path::new(env!("CARGO_MANIFEST_DIR")).parent()?;
    [
        PathBuf::from("engine/usagi/target/release/usagi"),
        source_root.join("engine/usagi/target/release/usagi"),
    ]
    .into_iter()
    .find(|path| path.is_file())
    .or_else(|| find_on_path("usagi"))
}

fn resolve_pet_project() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("TETI_PET_PROJECT") {
        let path = PathBuf::from(path);
        if path.join("main.lua").is_file() {
            return Some(path);
        }
    }
    let source_root = Path::new(env!("CARGO_MANIFEST_DIR")).parent()?;
    [
        PathBuf::from("pet-runtime/lua"),
        source_root.join("pet-runtime/lua"),
    ]
    .into_iter()
    .find(|path| path.join("main.lua").is_file())
}

fn find_on_path(binary: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .map(|dir| dir.join(binary))
            .find(|path| path.is_file())
    })
}
