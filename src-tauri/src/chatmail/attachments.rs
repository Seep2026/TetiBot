use std::{
    collections::HashMap,
    path::{Component, Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::SystemTime,
};

use serde::Serialize;
use thiserror::Error;
use tokio::sync::Mutex;

const MAX_ATTACHMENT_BYTES: u64 = 25 * 1024 * 1024;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AttachmentGrant {
    pub token: String,
    pub name: String,
    pub size: u64,
}

#[derive(Debug, Clone)]
pub(crate) struct GrantedAttachment {
    pub path: PathBuf,
    pub name: String,
}

struct StoredGrant {
    file: GrantedAttachment,
    size: u64,
    modified: Option<SystemTime>,
}

#[derive(Default)]
pub struct AttachmentGrantStore {
    next_id: AtomicU64,
    grants: Mutex<HashMap<String, StoredGrant>>,
}

#[derive(Debug, Error)]
pub enum AttachmentError {
    #[error("attachment authorization expired; choose the file again")]
    InvalidGrant,
    #[error("attachment is too large (maximum 25 MB)")]
    TooLarge,
    #[error("sensitive local files cannot be attached")]
    SensitivePath,
    #[error("failed to inspect attachment: {0}")]
    Io(#[from] std::io::Error),
}

impl AttachmentGrantStore {
    pub async fn pick_file(&self) -> Result<Option<AttachmentGrant>, AttachmentError> {
        let Some(handle) = rfd::AsyncFileDialog::new().pick_file().await else {
            return Ok(None);
        };
        let path = handle.path().canonicalize()?;
        ensure_allowed(&path)?;
        let metadata = std::fs::metadata(&path)?;
        if !metadata.is_file() {
            return Err(AttachmentError::InvalidGrant);
        }
        if metadata.len() > MAX_ATTACHMENT_BYTES {
            return Err(AttachmentError::TooLarge);
        }
        let name = path
            .file_name()
            .and_then(|value| value.to_str())
            .ok_or(AttachmentError::InvalidGrant)?
            .to_owned();
        let token = format!(
            "attachment-{}",
            self.next_id.fetch_add(1, Ordering::Relaxed)
        );
        self.grants.lock().await.insert(
            token.clone(),
            StoredGrant {
                file: GrantedAttachment {
                    path,
                    name: name.clone(),
                },
                size: metadata.len(),
                modified: metadata.modified().ok(),
            },
        );
        Ok(Some(AttachmentGrant {
            token,
            name,
            size: metadata.len(),
        }))
    }

    pub(crate) async fn consume(&self, token: &str) -> Result<GrantedAttachment, AttachmentError> {
        let grant = self
            .grants
            .lock()
            .await
            .remove(token)
            .ok_or(AttachmentError::InvalidGrant)?;
        let metadata = std::fs::metadata(&grant.file.path)?;
        if metadata.len() != grant.size || metadata.modified().ok() != grant.modified {
            return Err(AttachmentError::InvalidGrant);
        }
        ensure_allowed(&grant.file.path)?;
        Ok(grant.file)
    }
}

fn ensure_allowed(path: &Path) -> Result<(), AttachmentError> {
    let forbidden = [
        ".ssh",
        "keychains",
        "cookies",
        "login data",
        "id_rsa",
        "id_ed25519",
    ];
    let blocked = path
        .components()
        .filter_map(|part| match part {
            Component::Normal(value) => value.to_str(),
            _ => None,
        })
        .any(|part| forbidden.iter().any(|name| part.eq_ignore_ascii_case(name)));
    if blocked {
        Err(AttachmentError::SensitivePath)
    } else {
        Ok(())
    }
}
