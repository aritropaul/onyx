use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use axum::extract::ws::{WebSocket, Message as WsMessage};
use axum::extract::{Path, Query, State, WebSocketUpgrade};
use axum::response::IntoResponse;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::sync::broadcast;

use crate::auth;
use crate::protocol;
use crate::rooms::{BroadcastMsg, RoomManager};

/// Global client ID counter.
static NEXT_CLIENT_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Deserialize, Default)]
pub struct WsQuery {
    pub token: Option<String>,
}

/// Axum handler: extract doc_id from path and upgrade to WebSocket.
pub async fn ws_handler(
    Path(doc_id): Path<String>,
    Query(query): Query<WsQuery>,
    ws: WebSocketUpgrade,
    State(manager): State<Arc<RoomManager>>,
) -> impl IntoResponse {
    let client_id = NEXT_CLIENT_ID.fetch_add(1, Ordering::Relaxed);

    let user_id = query.token.as_deref().and_then(auth::validate_token);
    if let Some(ref uid) = user_id {
        tracing::info!(doc_id, client_id, user_id = %uid, "authenticated websocket upgrade");
    } else {
        tracing::info!(doc_id, client_id, "anonymous websocket upgrade");
    }

    ws.on_upgrade(move |socket| handle_socket(socket, doc_id, client_id, manager, user_id))
}

/// Handle a single WebSocket connection for a given document room.
async fn handle_socket(
    socket: WebSocket,
    doc_id: String,
    client_id: u64,
    manager: Arc<RoomManager>,
    _user_id: Option<String>,
) {
    tracing::info!(client_id, doc_id, "client connected");

    // Join the room and get the current snapshot (if any).
    let (room, snapshot) = manager.join(&doc_id).await;

    // Subscribe to broadcasts from other clients.
    let mut rx = {
        let r = room.read().await;
        r.tx.subscribe()
    };

    let (mut ws_tx, mut ws_rx) = socket.split();

    // Send SyncStep1 to the newly connected client.
    let sync1 = protocol::Message::sync_step1();
    if ws_tx.send(WsMessage::Binary(sync1.into())).await.is_err() {
        tracing::warn!(client_id, doc_id, "failed to send SyncStep1");
        manager.leave(&doc_id, &room).await;
        return;
    }

    // If we have a persisted snapshot, send it as SyncStep2 immediately after.
    if let Some(snap) = snapshot {
        let sync2 = protocol::Message::sync_step2(&snap);
        if ws_tx.send(WsMessage::Binary(sync2.into())).await.is_err() {
            tracing::warn!(client_id, doc_id, "failed to send snapshot");
            manager.leave(&doc_id, &room).await;
            return;
        }
        tracing::info!(client_id, doc_id, "sent persisted snapshot to client");
    }

    // Spawn a task that forwards broadcast messages to this client's WebSocket.
    let forward_doc_id = doc_id.clone();
    let forward_handle = tokio::spawn(async move {
        loop {
            match rx.recv().await {
                Ok(msg) => {
                    // Don't echo back to the sender.
                    if msg.sender_id == client_id {
                        continue;
                    }
                    if ws_tx.send(WsMessage::Binary(msg.data.into())).await.is_err() {
                        tracing::debug!(
                            client_id,
                            doc_id = forward_doc_id,
                            "forward send failed, client gone"
                        );
                        break;
                    }
                }
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    tracing::warn!(
                        client_id,
                        doc_id = forward_doc_id,
                        lagged = n,
                        "client lagged behind broadcast"
                    );
                    // Continue -- some messages were lost but we keep going.
                }
                Err(broadcast::error::RecvError::Closed) => {
                    break;
                }
            }
        }
    });

    // Read messages from the client.
    while let Some(result) = ws_rx.next().await {
        let raw = match result {
            Ok(WsMessage::Binary(data)) => data.to_vec(),
            Ok(WsMessage::Text(text)) => text.as_bytes().to_vec(),
            Ok(WsMessage::Close(_)) => break,
            Ok(WsMessage::Ping(_)) | Ok(WsMessage::Pong(_)) => continue,
            Err(e) => {
                tracing::debug!(client_id, doc_id, error = %e, "ws read error");
                break;
            }
        };

        if raw.is_empty() {
            continue;
        }

        let msg_type = raw[0];
        let payload = &raw[1..];

        match msg_type {
            protocol::SYNC_STEP1 => {
                // Client sent SyncStep1 -- respond with current snapshot if available.
                let r = room.read().await;
                if let Some(snap) = &r.snapshot {
                    let encoded = protocol::Message::sync_step2(snap);
                    let _ = r.tx.send(BroadcastMsg {
                        data: encoded,
                        sender_id: 0, // sender_id=0 means "server", won't be filtered
                    });
                }
            }
            protocol::SYNC_STEP2 => {
                // Client responding with full state. Store and broadcast.
                tracing::debug!(client_id, doc_id, bytes = payload.len(), "received SyncStep2");
                manager.update_snapshot(&doc_id, &room, payload.to_vec()).await;

                let encoded = protocol::Message::sync_step2(payload);
                let r = room.read().await;
                let _ = r.tx.send(BroadcastMsg {
                    data: encoded,
                    sender_id: client_id,
                });
            }
            protocol::UPDATE => {
                // Incremental update: broadcast to others and persist.
                tracing::debug!(client_id, doc_id, bytes = payload.len(), "received Update");
                manager.update_snapshot(&doc_id, &room, payload.to_vec()).await;

                let r = room.read().await;
                let _ = r.tx.send(BroadcastMsg {
                    data: raw,
                    sender_id: client_id,
                });
            }
            protocol::AWARENESS => {
                // Broadcast awareness to all other clients (no persistence).
                let r = room.read().await;
                let _ = r.tx.send(BroadcastMsg {
                    data: raw,
                    sender_id: client_id,
                });
            }
            other => {
                tracing::warn!(client_id, doc_id, msg_type = other, "unknown message type");
            }
        }
    }

    // Client disconnected.
    forward_handle.abort();
    manager.leave(&doc_id, &room).await;
    tracing::info!(client_id, doc_id, "client disconnected");
}
