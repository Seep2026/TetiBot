use std::sync::OnceLock;

use regex::Regex;
use serde::Serialize;

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ParseInviteResult {
    pub kind: String,
    pub display_name: Option<String>,
    pub address: Option<String>,
    pub invite_link: Option<String>,
    pub pet_name: Option<String>,
    pub pet_type: Option<String>,
    pub raw_text: String,
}

pub fn parse(text: &str) -> ParseInviteResult {
    let raw_text = text.trim().to_owned();
    let is_teti = raw_text.lines().any(|line| line.trim() == "TETI_INVITE_V1");
    let invite_link = invite_regex()
        .find(&raw_text)
        .map(|value| trim_tail(value.as_str()));
    let address = email_regex()
        .find(&raw_text)
        .map(|value| trim_tail(value.as_str()));
    let field = |name: &str| {
        raw_text.lines().find_map(|line| {
            let (key, value) = line.split_once('=')?;
            (key.trim() == name)
                .then(|| value.trim().to_owned())
                .filter(|value| !value.is_empty())
        })
    };
    let kind = if is_teti {
        "teti_invite"
    } else if invite_link.is_some() {
        "delta_invite_link"
    } else if address.is_some() {
        "email_address"
    } else {
        "unknown"
    };
    ParseInviteResult {
        kind: kind.to_owned(),
        display_name: field("display_name"),
        address,
        invite_link,
        pet_name: field("pet_name"),
        pet_type: field("pet_type"),
        raw_text,
    }
}

fn invite_regex() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r#"(?i)https://i\.delta\.chat/[^\s<>"']+"#).unwrap())
}

fn email_regex() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"(?i)[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+").unwrap())
}

fn trim_tail(value: &str) -> String {
    value
        .trim_end_matches(['.', ',', ';', ':', ')', ']', '}', '。', '，'])
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::parse;

    #[test]
    fn extracts_invites_from_plain_text() {
        let result = parse("联系 Alice <alice@example.com>，邀请：https://i.delta.chat/abc123。");
        assert_eq!(result.kind, "delta_invite_link");
        assert_eq!(result.address.as_deref(), Some("alice@example.com"));
        assert_eq!(
            result.invite_link.as_deref(),
            Some("https://i.delta.chat/abc123")
        );
    }

    #[test]
    fn parses_teti_enhancement() {
        let result = parse("TETI_INVITE_V1\npet_name=Mint\npet_type=teti-track\ndelta_invite=https://i.delta.chat/x");
        assert_eq!(result.kind, "teti_invite");
        assert_eq!(result.pet_name.as_deref(), Some("Mint"));
    }
}
