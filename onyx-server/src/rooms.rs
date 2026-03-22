use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};
use tokio::time::{Duration, Instant};

use crate::persistence::Store;

const BROADCAST_CAPACITY: usize = 256;
const ROOM_GRACE_PERIOD: Duration = Duration::from_secs(60);

/// A message sent through the broadcast channel to connected clients.
/// Contains the raw wire-format bytes and the sender's ID (for skip-echo).
#[derive(Clone, Debug)]
pub struct BroadcastMsg {
    pub data: Vec<u8>,
    pub sender_id: u64,
}

/// A single document room. Holds a broadcast channel for relaying messages
/// and the latest known snapshot for the document.
pub struct Room {
    /// Broadcast sender -- clone a receiver per client.
    pub tx: broadcast::Sender<BroadcastMsg>,
    /// Number of currently connected clients.
    pub client_count: usize,
    /// Latest document snapshot (binary blob).
    pub snapshot: Option<Vec<u8>>,
    /// When the last client disconnected (used for grace-period cleanup).
    pub last_empty: Option<Instant>,
}

impl Room {
    fn new() -> Self {
        let (tx, _) = broadcast::channel(BROADCAST_CAPACITY);
        Room {
            tx,
            client_count: 0,
            snapshot: None,
            last_empty: None,
        }
    }
}

/// Manages all active document rooms.
pub struct RoomManager {
    rooms: RwLock<HashMap<String, Arc<RwLock<Room>>>>,
    store: Arc<Store>,
}

impl RoomManager {
    pub fn new(store: Arc<Store>) -> Self {
        RoomManager {
            rooms: RwLock::new(HashMap::new()),
            store,
        }
    }

    /// Join a room, creating it if necessary. Loads snapshot from SQLite on creation.
    /// Returns (room_arc, optional snapshot to send to the connecting client).
    pub async fn join(
        &self,
        doc_id: &str,
    ) -> (Arc<RwLock<Room>>, Option<Vec<u8>>) {
        // Fast path: room already exists.
        {
            let rooms = self.rooms.read().await;
            if let Some(room_arc) = rooms.get(doc_id) {
                let mut room = room_arc.write().await;
                room.client_count += 1;
                room.last_empty = None;
                let snapshot = room.snapshot.clone();
                return (room_arc.clone(), snapshot);
            }
        }

        // Slow path: create room, load from DB.
        let mut rooms = self.rooms.write().await;

        // Double-check after acquiring write lock.
        if let Some(room_arc) = rooms.get(doc_id) {
            let mut room = room_arc.write().await;
            room.client_count += 1;
            room.last_empty = None;
            let snapshot = room.snapshot.clone();
            return (room_arc.clone(), snapshot);
        }

        let mut room = Room::new();
        room.client_count = 1;

        // Load persisted snapshot.
        match self.store.load_snapshot(doc_id) {
            Ok(Some(data)) => {
                tracing::info!(doc_id, bytes = data.len(), "loaded snapshot from db");
                room.snapshot = Some(data.clone());
                let room_arc = Arc::new(RwLock::new(room));
                rooms.insert(doc_id.to_string(), room_arc.clone());
                return (room_arc, Some(data));
            }
            Ok(None) => {
                tracing::info!(doc_id, "no existing snapshot in db");
            }
            Err(e) => {
                tracing::error!(doc_id, error = %e, "failed to load snapshot");
            }
        }

        let room_arc = Arc::new(RwLock::new(room));
        rooms.insert(doc_id.to_string(), room_arc.clone());
        (room_arc, None)
    }

    /// A client left the room. If the room is now empty, mark it for cleanup.
    pub async fn leave(&self, doc_id: &str, room: &Arc<RwLock<Room>>) {
        let mut r = room.write().await;
        r.client_count = r.client_count.saturating_sub(1);
        if r.client_count == 0 {
            r.last_empty = Some(Instant::now());
            tracing::info!(doc_id, "room now empty, starting grace period");
        }
    }

    /// Update the in-memory snapshot for a room and persist to SQLite.
    pub async fn update_snapshot(&self, doc_id: &str, room: &Arc<RwLock<Room>>, data: Vec<u8>) {
        {
            let mut r = room.write().await;
            r.snapshot = Some(data.clone());
        }
        let store = self.store.clone();
        let doc_id = doc_id.to_string();
        // Persist in a blocking task so SQLite I/O doesn't stall the async runtime.
        tokio::task::spawn_blocking(move || {
            if let Err(e) = store.save_snapshot(&doc_id, &data) {
                tracing::error!(doc_id, error = %e, "failed to persist snapshot");
            }
        });
    }

    /// Background task: periodically sweep empty rooms past their grace period.
    pub async fn cleanup_loop(self: Arc<Self>) {
        let mut interval = tokio::time::interval(Duration::from_secs(15));
        loop {
            interval.tick().await;
            let mut rooms = self.rooms.write().await;
            let mut to_remove = Vec::new();

            for (doc_id, room_arc) in rooms.iter() {
                let room = room_arc.read().await;
                if room.client_count == 0 {
                    if let Some(last) = room.last_empty {
                        if last.elapsed() >= ROOM_GRACE_PERIOD {
                            tracing::info!(doc_id, "unloading room after grace period");
                            to_remove.push(doc_id.clone());
                        }
                    }
                }
            }

            for doc_id in to_remove {
                rooms.remove(&doc_id);
            }
        }
    }
}
