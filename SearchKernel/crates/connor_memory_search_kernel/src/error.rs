use std::fmt::{Display, Formatter};

pub type KernelResult<T> = Result<T, KernelError>;

#[derive(Debug)]
pub struct KernelError {
    message: String,
}

impl KernelError {
    pub fn new(message: impl Into<String>) -> Self {
        Self { message: message.into() }
    }
}

impl Display for KernelError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for KernelError {}

impl From<anyhow::Error> for KernelError {
    fn from(value: anyhow::Error) -> Self {
        Self::new(value.to_string())
    }
}

impl From<serde_json::Error> for KernelError {
    fn from(value: serde_json::Error) -> Self {
        Self::new(value.to_string())
    }
}
