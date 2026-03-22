use yrs::updates::decoder::Decode;
use yrs::{ReadTxn, Transact};

/// Sync message type for the CRDT sync protocol.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncMessageType {
    SyncStep1,
    SyncStep2,
    Update,
}

/// A sync message containing a type and binary payload.
///
/// This wraps the y-sync protocol messages into a simple struct
/// that can cross the UniFFI boundary.
///
/// - SyncStep1: payload is an encoded StateVector
/// - SyncStep2: payload is an encoded Update (diff)
/// - Update: payload is an encoded Update
#[derive(Debug, Clone)]
pub struct SyncMessage {
    pub msg_type: SyncMessageType,
    pub data: Vec<u8>,
}

impl SyncMessage {
    /// Create a SyncStep1 message from an encoded state vector.
    pub fn sync_step1(state_vector: Vec<u8>) -> Self {
        SyncMessage {
            msg_type: SyncMessageType::SyncStep1,
            data: state_vector,
        }
    }

    /// Create a SyncStep2 message from an encoded update.
    pub fn sync_step2(update: Vec<u8>) -> Self {
        SyncMessage {
            msg_type: SyncMessageType::SyncStep2,
            data: update,
        }
    }

    /// Create an Update message from an encoded update.
    pub fn update(update: Vec<u8>) -> Self {
        SyncMessage {
            msg_type: SyncMessageType::Update,
            data: update,
        }
    }

    /// Encode the sync message into a tagged binary format for wire transmission.
    ///
    /// Format: [tag: u8][data...]
    /// Tags: 0 = SyncStep1, 1 = SyncStep2, 2 = Update
    pub fn to_bytes(&self) -> Vec<u8> {
        let tag: u8 = match self.msg_type {
            SyncMessageType::SyncStep1 => 0,
            SyncMessageType::SyncStep2 => 1,
            SyncMessageType::Update => 2,
        };
        let mut buf = Vec::with_capacity(1 + self.data.len());
        buf.push(tag);
        buf.extend_from_slice(&self.data);
        buf
    }

    /// Decode a sync message from the tagged binary format.
    pub fn from_bytes(data: &[u8]) -> Result<Self, crate::CrdtError> {
        if data.is_empty() {
            return Err(crate::CrdtError::DecodingError);
        }
        let tag = data[0];
        let payload = data[1..].to_vec();
        let msg_type = match tag {
            0 => SyncMessageType::SyncStep1,
            1 => SyncMessageType::SyncStep2,
            2 => SyncMessageType::Update,
            _ => return Err(crate::CrdtError::DecodingError),
        };
        Ok(SyncMessage {
            msg_type,
            data: payload,
        })
    }

    /// Process a SyncStep1 message against a document, producing a SyncStep2 response.
    ///
    /// Takes the remote state vector (from SyncStep1) and encodes the diff.
    pub fn handle_sync_step1(
        remote_sv_bytes: &[u8],
        doc: &yrs::Doc,
    ) -> Result<SyncMessage, crate::CrdtError> {
        let sv = yrs::StateVector::decode_v1(remote_sv_bytes)
            .map_err(|_| crate::CrdtError::DecodingError)?;
        let txn = doc.transact();
        let update = txn.encode_state_as_update_v1(&sv);
        Ok(SyncMessage::sync_step2(update))
    }

    /// Process a SyncStep2 or Update message by applying it to a document.
    pub fn handle_sync_step2_or_update(
        update_bytes: &[u8],
        doc: &yrs::Doc,
    ) -> Result<(), crate::CrdtError> {
        let mut txn = doc.transact_mut();
        let update = yrs::Update::decode_v1(update_bytes)
            .map_err(|_| crate::CrdtError::DecodingError)?;
        txn.apply_update(update)
            .map_err(|_| crate::CrdtError::TransactionFailed)?;
        Ok(())
    }
}
