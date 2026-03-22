mod auth;
mod persistence;
mod protocol;
mod rooms;
mod ws;

use std::sync::Arc;

use axum::Router;
use axum::routing::{get, post};
use tower_http::cors::CorsLayer;
use tracing_subscriber::EnvFilter;

use persistence::Store;
use rooms::RoomManager;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("onyx_server=info,tower_http=info")),
        )
        .init();

    let db_path = std::env::var("ONYX_DB_PATH").unwrap_or_else(|_| "onyx.db".to_string());
    let store = Arc::new(
        Store::open(&db_path).expect("failed to open database"),
    );
    tracing::info!(path = db_path, "database opened");

    let manager = Arc::new(RoomManager::new(store.clone()));

    {
        let mgr = manager.clone();
        tokio::spawn(async move {
            mgr.cleanup_loop().await;
        });
    }

    let auth_routes = Router::new()
        .route("/auth/register", post(auth::register))
        .route("/auth/login", post(auth::login))
        .route("/auth/me", get(auth::me))
        .with_state(store);

    let ws_routes = Router::new()
        .route("/docs/{doc_id}", get(ws::ws_handler))
        .with_state(manager);

    let app = Router::new()
        .merge(ws_routes)
        .merge(auth_routes)
        .route("/health", get(health))
        .layer(CorsLayer::permissive());

    let bind = std::env::var("ONYX_BIND").unwrap_or_else(|_| "0.0.0.0:3000".to_string());
    let listener = tokio::net::TcpListener::bind(&bind)
        .await
        .expect("failed to bind");
    tracing::info!(address = bind, "onyx-server listening");

    axum::serve(listener, app).await.expect("server error");
}

async fn health() -> &'static str {
    "ok"
}
