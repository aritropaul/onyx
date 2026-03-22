/// Binary protocol message types matching the Swift SyncClient.
///
/// Wire format: [1 byte type][payload bytes]
///
/// - SyncStep1 (0x00): Server sends on connect (empty payload). Client responds with full state.
/// - SyncStep2 (0x01): Full document snapshot exchange.
/// - Update   (0x02): Incremental document change, broadcast to other clients.
/// - Awareness(0x03): Cursor/presence JSON, broadcast to other clients.

pub const SYNC_STEP1: u8 = 0x00;
pub const SYNC_STEP2: u8 = 0x01;
pub const UPDATE: u8 = 0x02;
pub const AWARENESS: u8 = 0x03;

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub enum Message {
    SyncStep1 { payload: Vec<u8> },
    SyncStep2 { payload: Vec<u8> },
    Update { payload: Vec<u8> },
    Awareness { payload: Vec<u8> },
}

#[allow(dead_code)]
impl Message {
    /// Parse a raw binary frame into a typed Message.
    pub fn parse(data: &[u8]) -> Option<Message> {
        if data.is_empty() {
            return None;
        }

        let msg_type = data[0];
        let payload = data[1..].to_vec();

        match msg_type {
            SYNC_STEP1 => Some(Message::SyncStep1 { payload }),
            SYNC_STEP2 => Some(Message::SyncStep2 { payload }),
            UPDATE => Some(Message::Update { payload }),
            AWARENESS => Some(Message::Awareness { payload }),
            _ => {
                tracing::warn!(msg_type, "unknown message type");
                None
            }
        }
    }

    /// Encode a Message back into the binary wire format.
    pub fn encode(&self) -> Vec<u8> {
        match self {
            Message::SyncStep1 { payload } => {
                let mut buf = Vec::with_capacity(1 + payload.len());
                buf.push(SYNC_STEP1);
                buf.extend_from_slice(payload);
                buf
            }
            Message::SyncStep2 { payload } => {
                let mut buf = Vec::with_capacity(1 + payload.len());
                buf.push(SYNC_STEP2);
                buf.extend_from_slice(payload);
                buf
            }
            Message::Update { payload } => {
                let mut buf = Vec::with_capacity(1 + payload.len());
                buf.push(UPDATE);
                buf.extend_from_slice(payload);
                buf
            }
            Message::Awareness { payload } => {
                let mut buf = Vec::with_capacity(1 + payload.len());
                buf.push(AWARENESS);
                buf.extend_from_slice(payload);
                buf
            }
        }
    }

    /// Build a SyncStep1 message (server -> client on connect).
    pub fn sync_step1() -> Vec<u8> {
        vec![SYNC_STEP1]
    }

    /// Build a SyncStep2 message wrapping a full snapshot.
    pub fn sync_step2(snapshot: &[u8]) -> Vec<u8> {
        let mut buf = Vec::with_capacity(1 + snapshot.len());
        buf.push(SYNC_STEP2);
        buf.extend_from_slice(snapshot);
        buf
    }
}
