use std::path::PathBuf;

use chrono::Utc;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

use crate::chatmail::relay_config::CHATMAIL_DOMAIN;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PetProfile {
    pub pet_id: String,
    pub nickname: String,
    pub chatmail_domain: String,
    pub dc_account_id: u32,
    pub addr: String,
    pub created_at: String,
}

impl PetProfile {
    pub fn draft(nickname: String, dc_account_id: u32) -> Self {
        Self {
            pet_id: Uuid::new_v4().to_string(),
            nickname,
            chatmail_domain: CHATMAIL_DOMAIN.to_owned(),
            dc_account_id,
            addr: String::new(),
            created_at: Utc::now().to_rfc3339(),
        }
    }
}

pub struct PetProfileStore {
    path: PathBuf,
}

#[derive(Debug, Error)]
pub enum PetProfileError {
    #[error("failed to access the local Teti profile: {0}")]
    Io(#[from] std::io::Error),
    #[error("the local Teti profile is invalid: {0}")]
    Json(#[from] serde_json::Error),
}

impl PetProfileStore {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }

    pub fn load(&self) -> Result<Option<PetProfile>, PetProfileError> {
        if !self.path.is_file() {
            return Ok(None);
        }
        Ok(Some(serde_json::from_slice(&std::fs::read(&self.path)?)?))
    }

    pub fn save(&self, profile: &PetProfile) -> Result<(), PetProfileError> {
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&self.path, serde_json::to_vec_pretty(profile)?)?;
        Ok(())
    }

    pub fn delete(&self) -> Result<(), PetProfileError> {
        match std::fs::remove_file(&self.path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.into()),
        }
    }
}

#[derive(Debug, Error, PartialEq)]
pub enum NicknameError {
    #[error("请输入 Teti 昵称")]
    Required,
    #[error("昵称最长为 10 个英文字符或 5 个汉字")]
    TooLong,
    #[error("昵称不能包含换行或控制字符")]
    InvalidCharacter,
}

pub fn validate_nickname(input: &str) -> Result<String, NicknameError> {
    let nickname = input.trim();
    if nickname.is_empty() {
        return Err(NicknameError::Required);
    }
    if nickname.chars().any(char::is_control) {
        return Err(NicknameError::InvalidCharacter);
    }
    if nickname_units(nickname) > 10 {
        return Err(NicknameError::TooLong);
    }
    Ok(nickname.to_owned())
}

fn nickname_units(value: &str) -> usize {
    value
        .chars()
        .map(|ch| {
            if ('\u{3400}'..='\u{9fff}').contains(&ch) {
                2
            } else {
                1
            }
        })
        .sum()
}

#[cfg(test)]
mod tests {
    use super::{validate_nickname, NicknameError};

    #[test]
    fn validates_unicode_characters_instead_of_bytes() {
        assert_eq!(validate_nickname("  MintTeti10  ").unwrap(), "MintTeti10");
        assert_eq!(validate_nickname("一二三四五").unwrap(), "一二三四五");
        assert_eq!(
            validate_nickname("一二三四五六"),
            Err(NicknameError::TooLong)
        );
        assert_eq!(
            validate_nickname("薄荷Teti123"),
            Err(NicknameError::TooLong)
        );
    }

    #[test]
    fn rejects_empty_and_control_characters() {
        assert_eq!(validate_nickname("  "), Err(NicknameError::Required));
        assert_eq!(
            validate_nickname("Mint\nTeti"),
            Err(NicknameError::InvalidCharacter)
        );
    }
}
