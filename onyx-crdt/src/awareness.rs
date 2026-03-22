/// Represents the awareness/presence state of a connected client.
#[derive(Debug, Clone)]
pub struct AwarenessState {
    pub client_id: u64,
    pub user_name: String,
    pub color: String,
    pub cursor_block_id: Option<String>,
    pub cursor_offset: Option<u32>,
}

impl AwarenessState {
    pub fn new(client_id: u64, user_name: String, color: String) -> Self {
        AwarenessState {
            client_id,
            user_name,
            color,
            cursor_block_id: None,
            cursor_offset: None,
        }
    }

    pub fn with_cursor(mut self, block_id: String, offset: u32) -> Self {
        self.cursor_block_id = Some(block_id);
        self.cursor_offset = Some(offset);
        self
    }

    /// Encode to JSON for transmission.
    pub fn to_json(&self) -> String {
        serde_json::to_string(&self.to_json_value()).unwrap_or_default()
    }

    /// Convert to a serde_json::Value for serialization.
    fn to_json_value(&self) -> serde_json::Value {
        let mut map = serde_json::Map::new();
        map.insert("client_id".to_string(), serde_json::json!(self.client_id));
        map.insert("user_name".to_string(), serde_json::json!(self.user_name));
        map.insert("color".to_string(), serde_json::json!(self.color));
        if let Some(ref block_id) = self.cursor_block_id {
            map.insert("cursor_block_id".to_string(), serde_json::json!(block_id));
        }
        if let Some(offset) = self.cursor_offset {
            map.insert("cursor_offset".to_string(), serde_json::json!(offset));
        }
        serde_json::Value::Object(map)
    }

    /// Parse from JSON string.
    pub fn from_json(json: &str) -> Option<Self> {
        let v: serde_json::Value = serde_json::from_str(json).ok()?;
        let obj = v.as_object()?;
        Some(AwarenessState {
            client_id: obj.get("client_id")?.as_u64()?,
            user_name: obj.get("user_name")?.as_str()?.to_string(),
            color: obj.get("color")?.as_str()?.to_string(),
            cursor_block_id: obj
                .get("cursor_block_id")
                .and_then(|v| v.as_str().map(|s| s.to_string())),
            cursor_offset: obj
                .get("cursor_offset")
                .and_then(|v| v.as_u64().map(|n| n as u32)),
        })
    }
}
