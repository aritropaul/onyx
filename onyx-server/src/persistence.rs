use rusqlite::{Connection, params};
use std::path::Path;
use std::sync::Mutex;

pub struct UserRow {
    pub id: String,
    pub email: String,
    pub password_hash: String,
    pub display_name: String,
}

/// SQLite-backed document snapshot storage.
pub struct Store {
    conn: Mutex<Connection>,
}

impl Store {
    /// Open (or create) the database at the given path and run migrations.
    pub fn open<P: AsRef<Path>>(path: P) -> Result<Self, rusqlite::Error> {
        let conn = Connection::open(path)?;

        conn.execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA synchronous=NORMAL;
             PRAGMA busy_timeout=5000;"
        )?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS documents (
                doc_id     TEXT PRIMARY KEY,
                snapshot   BLOB NOT NULL,
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            )",
            [],
        )?;

        conn.execute(
            "CREATE TABLE IF NOT EXISTS users (
                id            TEXT PRIMARY KEY,
                email         TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                display_name  TEXT NOT NULL,
                created_at    TEXT NOT NULL DEFAULT (datetime('now'))
            )",
            [],
        )?;

        Ok(Store { conn: Mutex::new(conn) })
    }

    // MARK: - Users

    pub fn create_user(
        &self,
        id: &str,
        email: &str,
        password_hash: &str,
        display_name: &str,
    ) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO users (id, email, password_hash, display_name) VALUES (?1, ?2, ?3, ?4)",
            params![id, email, password_hash, display_name],
        )?;
        Ok(())
    }

    pub fn find_user_by_email(&self, email: &str) -> Result<Option<UserRow>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, email, password_hash, display_name FROM users WHERE email = ?1",
        )?;
        let result = stmt.query_row(params![email], |row| {
            Ok(UserRow {
                id: row.get(0)?,
                email: row.get(1)?,
                password_hash: row.get(2)?,
                display_name: row.get(3)?,
            })
        });
        match result {
            Ok(user) => Ok(Some(user)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    pub fn find_user_by_id(&self, id: &str) -> Result<Option<UserRow>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, email, password_hash, display_name FROM users WHERE id = ?1",
        )?;
        let result = stmt.query_row(params![id], |row| {
            Ok(UserRow {
                id: row.get(0)?,
                email: row.get(1)?,
                password_hash: row.get(2)?,
                display_name: row.get(3)?,
            })
        });
        match result {
            Ok(user) => Ok(Some(user)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Load the latest snapshot for a document. Returns None if not found.
    pub fn load_snapshot(&self, doc_id: &str) -> Result<Option<Vec<u8>>, rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT snapshot FROM documents WHERE doc_id = ?1"
        )?;

        let result = stmt.query_row(params![doc_id], |row| {
            row.get::<_, Vec<u8>>(0)
        });

        match result {
            Ok(data) => Ok(Some(data)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// Upsert a document snapshot.
    pub fn save_snapshot(&self, doc_id: &str, snapshot: &[u8]) -> Result<(), rusqlite::Error> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO documents (doc_id, snapshot, updated_at)
             VALUES (?1, ?2, datetime('now'))
             ON CONFLICT(doc_id) DO UPDATE SET
                snapshot = excluded.snapshot,
                updated_at = excluded.updated_at",
            params![doc_id, snapshot],
        )?;
        Ok(())
    }
}
