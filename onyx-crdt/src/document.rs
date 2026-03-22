use std::collections::HashMap;

use parking_lot::RwLock;
use yrs::types::ToJson;
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::{
    Array, ArrayPrelim, ArrayRef, Doc, GetString, Map, MapPrelim, MapRef, ReadTxn, Text,
    TextPrelim, TextRef, Transact, TransactionMut, Out, WriteTxn,
};

use crate::block::{BlockState, BlockType};
use crate::CrdtError;

/// Callback interface for observing document changes.
/// Implementations must be thread-safe (Send + Sync).
pub trait OnyxDocObserver: Send + Sync {
    fn on_blocks_changed(&self, block_ids: Vec<String>);
    fn on_text_changed(&self, block_id: String, text: String);
}

/// Extract a MapRef from a Out.
fn value_to_map(v: Out) -> Option<MapRef> {
    match v {
        Out::YMap(m) => Some(m),
        _ => None,
    }
}

/// Extract a TextRef from a Out.
fn value_to_text(v: Out) -> Option<TextRef> {
    match v {
        Out::YText(t) => Some(t),
        _ => None,
    }
}

/// Extract an ArrayRef from a Out.
fn value_to_array(v: Out) -> Option<ArrayRef> {
    match v {
        Out::YArray(a) => Some(a),
        _ => None,
    }
}

/// Extract a string from a Out::Any(Any::String(..)).
fn value_to_string(v: &Out) -> Option<String> {
    match v {
        Out::Any(yrs::Any::String(s)) => Some(s.to_string()),
        _ => None,
    }
}

/// The core CRDT document wrapping a Yrs Doc.
///
/// Internal Y structure:
/// - Y.Map "blocks": each entry is a Y.Map { "type": String, "content": Y.Text, "children": Y.Array, "indent": f64, "meta": Y.Map }
/// - Y.Array "block_order": root ordering of block IDs
pub struct OnyxDoc {
    doc: Doc,
    blocks: MapRef,
    block_order: ArrayRef,
    observer: RwLock<Option<Box<dyn OnyxDocObserver>>>,
}

// Safety: yrs::Doc, MapRef, and ArrayRef are all Send+Sync.
// RwLock provides thread-safe interior mutability for the observer.
unsafe impl Send for OnyxDoc {}
unsafe impl Sync for OnyxDoc {}

impl std::fmt::Debug for OnyxDoc {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OnyxDoc")
            .field("client_id", &self.doc.client_id())
            .finish()
    }
}

impl OnyxDoc {
    pub fn new() -> Self {
        let doc = Doc::new();
        let (blocks, block_order) = {
            let mut txn = doc.transact_mut();
            let blocks = txn.get_or_insert_map("blocks");
            let block_order = txn.get_or_insert_array("block_order");
            (blocks, block_order)
        };

        OnyxDoc {
            doc,
            blocks,
            block_order,
            observer: RwLock::new(None),
        }
    }

    pub fn create_from_update(update: Vec<u8>) -> Result<Self, CrdtError> {
        let doc = Doc::new();
        let (blocks, block_order) = {
            let mut txn = doc.transact_mut();
            let blocks = txn.get_or_insert_map("blocks");
            let block_order = txn.get_or_insert_array("block_order");

            let decoded =
                yrs::Update::decode_v1(&update).map_err(|_| CrdtError::DecodingError)?;
            txn.apply_update(decoded)
                .map_err(|_| CrdtError::TransactionFailed)?;
            (blocks, block_order)
        };

        Ok(OnyxDoc {
            doc,
            blocks,
            block_order,
            observer: RwLock::new(None),
        })
    }

    /// Create a new block and return its ID.
    pub fn create_block(
        &self,
        block_type: BlockType,
        after_block_id: Option<String>,
    ) -> Result<String, CrdtError> {
        let block_id = uuid::Uuid::new_v4().to_string();
        let type_str = block_type.to_string();

        let mut txn = self.doc.transact_mut();

        // Create the block as a nested map
        let block_prelim = MapPrelim::from([
            ("type", yrs::Any::String(type_str.into())),
            ("indent", yrs::Any::Number(0.0)),
        ]);

        // Insert block into blocks map -- returns MapRef
        let block_ref: MapRef = self.blocks.insert(&mut txn, block_id.as_str(), block_prelim);

        // Insert nested CRDT types into the block
        block_ref.insert(&mut txn, "content", TextPrelim::new(""));
        let empty_children: [yrs::Any; 0] = [];
        block_ref.insert(&mut txn, "children", ArrayPrelim::from(empty_children));
        let empty_meta: [(&str, yrs::Any); 0] = [];
        block_ref.insert(&mut txn, "meta", MapPrelim::from(empty_meta));

        // Insert block_id into block_order at the right position
        self.insert_into_order(&mut txn, &block_id, after_block_id.as_deref());

        drop(txn);

        // Notify observer
        self.notify_blocks_changed(&[block_id.clone()]);

        Ok(block_id)
    }

    /// Delete a block by its ID.
    pub fn delete_block(&self, block_id: String) -> Result<(), CrdtError> {
        let mut txn = self.doc.transact_mut();

        // Remove from blocks map
        self.blocks.remove(&mut txn, &block_id);

        // Remove from block_order array
        self.remove_from_order(&mut txn, &block_id);

        drop(txn);

        self.notify_blocks_changed(&[block_id]);

        Ok(())
    }

    /// Move a block to a new position.
    pub fn move_block(
        &self,
        block_id: String,
        after_block_id: Option<String>,
    ) -> Result<(), CrdtError> {
        let mut txn = self.doc.transact_mut();

        // Find and remove the block from its current position
        let removed = self.remove_from_order(&mut txn, &block_id);
        if !removed {
            return Err(CrdtError::BlockNotFound);
        }

        // Insert at the new position
        self.insert_into_order(&mut txn, &block_id, after_block_id.as_deref());

        drop(txn);

        self.notify_blocks_changed(&[block_id]);

        Ok(())
    }

    /// Set the type of an existing block.
    pub fn set_block_type(
        &self,
        block_id: String,
        block_type: BlockType,
    ) -> Result<(), CrdtError> {
        let mut txn = self.doc.transact_mut();

        let block = self
            .blocks
            .get(&txn, &block_id)
            .and_then(value_to_map)
            .ok_or(CrdtError::BlockNotFound)?;

        block.insert(
            &mut txn,
            "type",
            yrs::Any::String(block_type.to_string().into()),
        );

        drop(txn);

        self.notify_blocks_changed(&[block_id]);

        Ok(())
    }

    /// Get the state of a single block.
    pub fn get_block_state(&self, block_id: String) -> Option<BlockState> {
        let txn = self.doc.transact();
        let block_val = self.blocks.get(&txn, &block_id)?;
        let block = value_to_map(block_val)?;
        Some(self.read_block_state(&txn, &block_id, &block))
    }

    /// Get all blocks as BlockState values, in order.
    pub fn get_all_blocks(&self) -> Vec<BlockState> {
        let txn = self.doc.transact();
        let order = self.read_block_order_vec(&txn);
        let mut result = Vec::with_capacity(order.len());
        for id in &order {
            if let Some(block_val) = self.blocks.get(&txn, id.as_str()) {
                if let Some(block) = value_to_map(block_val) {
                    result.push(self.read_block_state(&txn, id, &block));
                }
            }
        }
        result
    }

    /// Get the ordered list of block IDs.
    pub fn get_block_order(&self) -> Vec<String> {
        let txn = self.doc.transact();
        self.read_block_order_vec(&txn)
    }

    /// Insert text into a block at a given offset.
    pub fn insert_text(
        &self,
        block_id: String,
        offset: u32,
        text: String,
    ) -> Result<(), CrdtError> {
        let mut txn = self.doc.transact_mut();
        let content = self
            .get_block_content_ref(&txn, &block_id)
            .ok_or(CrdtError::BlockNotFound)?;

        content.insert(&mut txn, offset, &text);

        let new_text = content.get_string(&txn);
        drop(txn);
        self.notify_text_changed(&block_id, &new_text);

        Ok(())
    }

    /// Delete text from a block.
    pub fn delete_text(
        &self,
        block_id: String,
        offset: u32,
        length: u32,
    ) -> Result<(), CrdtError> {
        let mut txn = self.doc.transact_mut();
        let content = self
            .get_block_content_ref(&txn, &block_id)
            .ok_or(CrdtError::BlockNotFound)?;

        content.remove_range(&mut txn, offset, length);

        let new_text = content.get_string(&txn);
        drop(txn);
        self.notify_text_changed(&block_id, &new_text);

        Ok(())
    }

    /// Replace text in a block.
    pub fn replace_text(
        &self,
        block_id: String,
        offset: u32,
        length: u32,
        text: String,
    ) -> Result<(), CrdtError> {
        let mut txn = self.doc.transact_mut();
        let content = self
            .get_block_content_ref(&txn, &block_id)
            .ok_or(CrdtError::BlockNotFound)?;

        content.remove_range(&mut txn, offset, length);
        content.insert(&mut txn, offset, &text);

        let new_text = content.get_string(&txn);
        drop(txn);
        self.notify_text_changed(&block_id, &new_text);

        Ok(())
    }

    /// Get the text content of a block.
    pub fn get_text(&self, block_id: String) -> Option<String> {
        let txn = self.doc.transact();
        let content = self.get_block_content_ref(&txn, &block_id)?;
        Some(content.get_string(&txn))
    }

    /// Encode the document's state vector.
    pub fn encode_state_vector(&self) -> Vec<u8> {
        let txn = self.doc.transact();
        txn.state_vector().encode_v1()
    }

    /// Encode the full document state as an update.
    pub fn encode_state_as_update(&self) -> Vec<u8> {
        let txn = self.doc.transact();
        txn.encode_state_as_update_v1(&yrs::StateVector::default())
    }

    /// Apply a remote update to this document.
    pub fn apply_update(&self, update: Vec<u8>) -> Result<(), CrdtError> {
        let mut txn = self.doc.transact_mut();
        let decoded =
            yrs::Update::decode_v1(&update).map_err(|_| CrdtError::DecodingError)?;
        txn.apply_update(decoded)
            .map_err(|_| CrdtError::TransactionFailed)?;
        Ok(())
    }

    /// Encode the diff between a remote state vector and this document.
    pub fn encode_diff(&self, state_vector: Vec<u8>) -> Result<Vec<u8>, CrdtError> {
        let txn = self.doc.transact();
        let sv = yrs::StateVector::decode_v1(&state_vector)
            .map_err(|_| CrdtError::DecodingError)?;
        Ok(txn.encode_state_as_update_v1(&sv))
    }

    /// Register an observer for document changes.
    pub fn observe(&self, observer: Box<dyn OnyxDocObserver>) {
        let mut obs = self.observer.write();
        *obs = Some(observer);
    }

    /// Remove the current observer.
    pub fn unobserve(&self) {
        let mut obs = self.observer.write();
        *obs = None;
    }

    /// Get the client ID of this document.
    pub fn get_client_id(&self) -> u64 {
        self.doc.client_id()
    }

    // --- Private helpers ---

    /// Read a block's content TextRef.
    fn get_block_content_ref<T: ReadTxn>(&self, txn: &T, block_id: &str) -> Option<TextRef> {
        let block_val = self.blocks.get(txn, block_id)?;
        let block_map = value_to_map(block_val)?;
        let content_val = block_map.get(txn, "content")?;
        value_to_text(content_val)
    }

    /// Read block order as a Vec<String>.
    fn read_block_order_vec<T: ReadTxn>(&self, txn: &T) -> Vec<String> {
        let len = self.block_order.len(txn);
        let mut result = Vec::with_capacity(len as usize);
        for i in 0..len {
            if let Some(val) = self.block_order.get(txn, i) {
                if let Some(s) = value_to_string(&val) {
                    result.push(s);
                }
            }
        }
        result
    }

    /// Read a BlockState from a block MapRef.
    fn read_block_state<T: ReadTxn>(
        &self,
        txn: &T,
        block_id: &str,
        block: &MapRef,
    ) -> BlockState {
        // Read type
        let type_str = block
            .get(txn, "type")
            .and_then(|v| value_to_string(&v))
            .unwrap_or_else(|| "paragraph".to_string());

        // Read text content
        let text = block
            .get(txn, "content")
            .and_then(value_to_text)
            .map(|t| t.get_string(txn))
            .unwrap_or_default();

        // Read children
        let children = block
            .get(txn, "children")
            .and_then(value_to_array)
            .map(|arr| {
                let len = arr.len(txn);
                let mut result = Vec::with_capacity(len as usize);
                for i in 0..len {
                    if let Some(val) = arr.get(txn, i) {
                        if let Some(s) = value_to_string(&val) {
                            result.push(s);
                        }
                    }
                }
                result
            })
            .unwrap_or_default();

        // Read indent level
        let indent_level = block
            .get(txn, "indent")
            .and_then(|v| match v {
                Out::Any(yrs::Any::Number(n)) => Some(n as u32),
                _ => None,
            })
            .unwrap_or(0);

        // Read meta map
        let meta = block
            .get(txn, "meta")
            .and_then(value_to_map)
            .map(|m| {
                let json = m.to_json(txn);
                let mut result = HashMap::new();
                if let yrs::Any::Map(map) = json {
                    for (k, v) in map.iter() {
                        if let yrs::Any::String(s) = v {
                            result.insert(k.to_string(), s.to_string());
                        }
                    }
                }
                result
            })
            .unwrap_or_default();

        BlockState {
            id: block_id.to_string(),
            block_type: BlockType::from_str(&type_str),
            text,
            children,
            indent_level,
            meta,
        }
    }

    /// Insert a block_id into the block_order array at the right position.
    fn insert_into_order(
        &self,
        txn: &mut TransactionMut,
        block_id: &str,
        after_block_id: Option<&str>,
    ) {
        match after_block_id {
            Some(after_id) => {
                let len = self.block_order.len(txn);
                let mut found_index = None;
                for i in 0..len {
                    if let Some(val) = self.block_order.get(txn, i) {
                        if let Some(s) = value_to_string(&val) {
                            if s == after_id {
                                found_index = Some(i);
                                break;
                            }
                        }
                    }
                }
                match found_index {
                    Some(idx) => {
                        self.block_order.insert(
                            txn,
                            idx + 1,
                            yrs::Any::String(block_id.into()),
                        );
                    }
                    None => {
                        self.block_order.push_back(
                            txn,
                            yrs::Any::String(block_id.into()),
                        );
                    }
                }
            }
            None => {
                self.block_order.push_back(
                    txn,
                    yrs::Any::String(block_id.into()),
                );
            }
        }
    }

    /// Remove a block_id from the block_order array. Returns true if found and removed.
    fn remove_from_order(
        &self,
        txn: &mut TransactionMut,
        block_id: &str,
    ) -> bool {
        let len = self.block_order.len(txn);
        for i in 0..len {
            if let Some(val) = self.block_order.get(txn, i) {
                if let Some(s) = value_to_string(&val) {
                    if s == block_id {
                        self.block_order.remove(txn, i);
                        return true;
                    }
                }
            }
        }
        false
    }

    fn notify_blocks_changed(&self, block_ids: &[String]) {
        let obs = self.observer.read();
        if let Some(ref observer) = *obs {
            observer.on_blocks_changed(block_ids.to_vec());
        }
    }

    fn notify_text_changed(&self, block_id: &str, text: &str) {
        let obs = self.observer.read();
        if let Some(ref observer) = *obs {
            observer.on_text_changed(block_id.to_string(), text.to_string());
        }
    }
}
