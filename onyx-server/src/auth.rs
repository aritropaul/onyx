use std::sync::Arc;

use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::SaltString;
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};

use crate::persistence::Store;

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
    pub exp: usize,
}

#[derive(Deserialize)]
pub struct RegisterRequest {
    pub email: String,
    pub password: String,
    pub display_name: String,
}

#[derive(Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    pub token: String,
    pub user_id: String,
    pub display_name: String,
}

#[derive(Serialize)]
pub struct MeResponse {
    pub id: String,
    pub email: String,
    pub display_name: String,
}

#[derive(Serialize)]
pub(crate) struct ErrorBody {
    error: String,
}

fn jwt_secret() -> Vec<u8> {
    std::env::var("ONYX_JWT_SECRET")
        .unwrap_or_else(|_| "onyx-dev-secret-do-not-use-in-prod".to_string())
        .into_bytes()
}

fn create_token(user_id: &str) -> Result<String, jsonwebtoken::errors::Error> {
    let exp = chrono_exp_24h();
    let claims = Claims {
        sub: user_id.to_string(),
        exp,
    };
    jsonwebtoken::encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(&jwt_secret()),
    )
}

pub fn validate_token(token: &str) -> Option<String> {
    let validation = Validation::default();
    let data = jsonwebtoken::decode::<Claims>(
        token,
        &DecodingKey::from_secret(&jwt_secret()),
        &validation,
    )
    .ok()?;
    Some(data.claims.sub)
}

fn chrono_exp_24h() -> usize {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    (now + 86400) as usize
}

fn hash_password(password: &str) -> Result<String, argon2::password_hash::Error> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let hash = argon2.hash_password(password.as_bytes(), &salt)?;
    Ok(hash.to_string())
}

fn verify_password(password: &str, hash: &str) -> bool {
    let parsed = match PasswordHash::new(hash) {
        Ok(h) => h,
        Err(_) => return false,
    };
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok()
}

fn error_response(status: StatusCode, msg: &str) -> (StatusCode, Json<ErrorBody>) {
    (status, Json(ErrorBody { error: msg.to_string() }))
}

pub async fn register(
    State(store): State<Arc<Store>>,
    Json(req): Json<RegisterRequest>,
) -> Result<Json<AuthResponse>, (StatusCode, Json<ErrorBody>)> {
    if req.email.is_empty() || req.password.is_empty() || req.display_name.is_empty() {
        return Err(error_response(StatusCode::BAD_REQUEST, "All fields are required"));
    }

    let password_hash =
        hash_password(&req.password).map_err(|_| error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to hash password"))?;

    let user_id = uuid::Uuid::new_v4().to_string();

    store
        .create_user(&user_id, &req.email, &password_hash, &req.display_name)
        .map_err(|e| {
            if e.to_string().contains("UNIQUE") {
                error_response(StatusCode::CONFLICT, "Email already registered")
            } else {
                tracing::error!(error = %e, "failed to create user");
                error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to create user")
            }
        })?;

    let token = create_token(&user_id)
        .map_err(|_| error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to create token"))?;

    Ok(Json(AuthResponse {
        token,
        user_id,
        display_name: req.display_name,
    }))
}

pub async fn login(
    State(store): State<Arc<Store>>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<AuthResponse>, (StatusCode, Json<ErrorBody>)> {
    let user = store
        .find_user_by_email(&req.email)
        .map_err(|_| error_response(StatusCode::INTERNAL_SERVER_ERROR, "Database error"))?
        .ok_or_else(|| error_response(StatusCode::UNAUTHORIZED, "Invalid email or password"))?;

    if !verify_password(&req.password, &user.password_hash) {
        return Err(error_response(StatusCode::UNAUTHORIZED, "Invalid email or password"));
    }

    let token = create_token(&user.id)
        .map_err(|_| error_response(StatusCode::INTERNAL_SERVER_ERROR, "Failed to create token"))?;

    Ok(Json(AuthResponse {
        token,
        user_id: user.id,
        display_name: user.display_name,
    }))
}

pub async fn me(
    State(store): State<Arc<Store>>,
    headers: HeaderMap,
) -> Result<Json<MeResponse>, (StatusCode, Json<ErrorBody>)> {
    let token = headers
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .ok_or_else(|| error_response(StatusCode::UNAUTHORIZED, "Missing authorization header"))?;

    let user_id = validate_token(token)
        .ok_or_else(|| error_response(StatusCode::UNAUTHORIZED, "Invalid or expired token"))?;

    let user = store
        .find_user_by_id(&user_id)
        .map_err(|_| error_response(StatusCode::INTERNAL_SERVER_ERROR, "Database error"))?
        .ok_or_else(|| error_response(StatusCode::NOT_FOUND, "User not found"))?;

    Ok(Json(MeResponse {
        id: user.id,
        email: user.email,
        display_name: user.display_name,
    }))
}
