pub mod awareness;
pub mod block;
pub mod document;
pub mod sync;

pub use awareness::AwarenessState;
pub use block::{BlockState, BlockType};
pub use document::{OnyxDoc, OnyxDocObserver};
pub use sync::{SyncMessage, SyncMessageType};

/// UniFFI-compatible error type for CRDT operations.
#[derive(Debug, thiserror::Error)]
pub enum CrdtError {
    #[error("Block not found")]
    BlockNotFound,
    #[error("Transaction failed")]
    TransactionFailed,
    #[error("Encoding error")]
    EncodingError,
    #[error("Decoding error")]
    DecodingError,
    #[error("Invalid operation")]
    InvalidOperation,
}

uniffi::include_scaffolding!("onyx_crdt");
