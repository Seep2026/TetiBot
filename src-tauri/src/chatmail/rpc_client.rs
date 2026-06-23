use std::collections::HashMap;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};

use serde::de::DeserializeOwned;
use serde_json::{json, Value};
use thiserror::Error;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, ChildStdout};
use tokio::sync::{oneshot, Mutex};

#[derive(Debug, Error)]
pub enum RpcError {
    #[error("Delta Chat RPC process is unavailable")]
    Unavailable,
    #[error("Delta Chat RPC I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("Delta Chat RPC returned an invalid response: {0}")]
    InvalidResponse(String),
    #[error("Delta Chat RPC request failed: {0}")]
    Remote(String),
}

type PendingMap = Arc<Mutex<HashMap<u64, oneshot::Sender<Result<Value, RpcError>>>>>;

#[derive(Clone)]
pub struct RpcClient {
    stdin: Arc<Mutex<ChildStdin>>,
    pending: PendingMap,
    next_id: Arc<AtomicU64>,
}

impl RpcClient {
    pub fn new(stdin: ChildStdin, stdout: ChildStdout) -> Self {
        let pending = Arc::new(Mutex::new(HashMap::new()));
        Self::spawn_reader(stdout, Arc::clone(&pending));
        Self {
            stdin: Arc::new(Mutex::new(stdin)),
            pending,
            next_id: Arc::new(AtomicU64::new(1)),
        }
    }

    pub async fn call<T>(&self, method: &str, params: Value) -> Result<T, RpcError>
    where
        T: DeserializeOwned,
    {
        let value = self.call_value(method, params).await?;
        serde_json::from_value(value).map_err(|error| RpcError::InvalidResponse(error.to_string()))
    }

    pub async fn call_value(&self, method: &str, params: Value) -> Result<Value, RpcError> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let request = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        });
        let encoded = serde_json::to_vec(&request)
            .map_err(|error| RpcError::InvalidResponse(error.to_string()))?;
        let (sender, receiver) = oneshot::channel();
        self.pending.lock().await.insert(id, sender);

        let write_result = async {
            let mut stdin = self.stdin.lock().await;
            stdin.write_all(&encoded).await?;
            stdin.write_all(b"\n").await?;
            stdin.flush().await
        }
        .await;

        if let Err(error) = write_result {
            self.pending.lock().await.remove(&id);
            return Err(RpcError::Io(error));
        }

        receiver.await.map_err(|_| RpcError::Unavailable)?
    }

    fn spawn_reader(stdout: ChildStdout, pending: PendingMap) {
        tauri::async_runtime::spawn(async move {
            let mut lines = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                if let Ok(value) = serde_json::from_str::<Value>(&line) {
                    let id = value.get("id").and_then(Value::as_u64);
                    if let Some(id) = id {
                        if let Some(sender) = pending.lock().await.remove(&id) {
                            let result = if let Some(error) = value.get("error") {
                                Err(RpcError::Remote(public_error(error)))
                            } else {
                                Ok(value.get("result").cloned().unwrap_or(Value::Null))
                            };
                            let _ = sender.send(result);
                        }
                    }
                }
            }

            let mut pending = pending.lock().await;
            for (_, sender) in pending.drain() {
                let _ = sender.send(Err(RpcError::Unavailable));
            }
        });
    }
}

fn public_error(error: &Value) -> String {
    error
        .get("message")
        .and_then(Value::as_str)
        .unwrap_or("Delta Chat operation failed")
        .to_owned()
}
