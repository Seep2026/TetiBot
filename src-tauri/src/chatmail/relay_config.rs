pub const CHATMAIL_DOMAIN: &str = "mail.seep.im";
pub const CHATMAIL_QR: &str = "DCACCOUNT:mail.seep.im";
pub const CHATMAIL_QR_TYPE: &str = "DCACCOUNT";

#[cfg(test)]
mod tests {
    use super::{CHATMAIL_DOMAIN, CHATMAIL_QR};

    #[test]
    fn relay_is_fixed_for_the_mvp() {
        assert_eq!(CHATMAIL_DOMAIN, "mail.seep.im");
        assert_eq!(CHATMAIL_QR, "DCACCOUNT:mail.seep.im");
    }
}
