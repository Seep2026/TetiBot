use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::Arc;

use thiserror::Error;
use tokio::process::{Child, Command};
use tokio::sync::Mutex;

use super::rpc_client::{RpcClient, RpcError};

#[derive(Debug, Error)]
pub enum RpcProcessError {
    #[error("deltachat-rpc-server was not found; set DELTA_CORE_DIR or DELTA_CHAT_RPC_SERVER")]
    BinaryNotFound,
    #[error("failed to create Delta Chat account directory: {0}")]
    AccountDirectory(#[source] std::io::Error),
    #[error("failed to start deltachat-rpc-server: {0}")]
    Spawn(#[source] std::io::Error),
    #[error(transparent)]
    Rpc(#[from] RpcError),
}

pub struct RpcProcess {
    client: RpcClient,
    _child: Arc<Mutex<Child>>,
}

impl RpcProcess {
    pub async fn spawn(accounts_dir: &Path) -> Result<Self, RpcProcessError> {
        std::fs::create_dir_all(accounts_dir).map_err(RpcProcessError::AccountDirectory)?;
        let binary = resolve_binary().ok_or(RpcProcessError::BinaryNotFound)?;
        let mut child = Command::new(binary)
            .env("DC_ACCOUNTS_PATH", accounts_dir)
            .env("RUST_LOG", "warn")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(RpcProcessError::Spawn)?;
        let stdin = child.stdin.take().ok_or_else(|| {
            RpcProcessError::Spawn(std::io::Error::other("RPC stdin unavailable"))
        })?;
        let stdout = child.stdout.take().ok_or_else(|| {
            RpcProcessError::Spawn(std::io::Error::other("RPC stdout unavailable"))
        })?;
        let client = RpcClient::new(stdin, stdout);
        let _: serde_json::Value = client
            .call("get_system_info", serde_json::json!([]))
            .await?;
        Ok(Self {
            client,
            _child: Arc::new(Mutex::new(child)),
        })
    }

    pub fn client(&self) -> RpcClient {
        self.client.clone()
    }
}

fn resolve_binary() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("DELTA_CHAT_RPC_SERVER") {
        let path = PathBuf::from(path);
        if path.is_file() {
            return Some(path);
        }
    }

    if let Some(core_dir) = std::env::var_os("DELTA_CORE_DIR") {
        let path = PathBuf::from(core_dir)
            .join("target")
            .join("release")
            .join("deltachat-rpc-server");
        if path.is_file() {
            return Some(path);
        }
    }

    let candidates = [PathBuf::from("../core/target/release/deltachat-rpc-server")];
    candidates
        .into_iter()
        .find(|path| path.is_file())
        .or_else(|| {
            std::env::var_os("PATH").and_then(|paths| {
                std::env::split_paths(&paths)
                    .map(|dir| dir.join("deltachat-rpc-server"))
                    .find(|path| path.is_file())
            })
        })
}
