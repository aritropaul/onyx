use std::collections::HashMap;
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BlockType {
    Paragraph,
    Heading1,
    Heading2,
    Heading3,
    BulletList,
    NumberedList,
    Code,
    Quote,
    Divider,
}

impl fmt::Display for BlockType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BlockType::Paragraph => write!(f, "paragraph"),
            BlockType::Heading1 => write!(f, "heading1"),
            BlockType::Heading2 => write!(f, "heading2"),
            BlockType::Heading3 => write!(f, "heading3"),
            BlockType::BulletList => write!(f, "bullet_list"),
            BlockType::NumberedList => write!(f, "numbered_list"),
            BlockType::Code => write!(f, "code"),
            BlockType::Quote => write!(f, "quote"),
            BlockType::Divider => write!(f, "divider"),
        }
    }
}

impl BlockType {
    pub fn from_str(s: &str) -> Self {
        match s {
            "heading1" => BlockType::Heading1,
            "heading2" => BlockType::Heading2,
            "heading3" => BlockType::Heading3,
            "bullet_list" => BlockType::BulletList,
            "numbered_list" => BlockType::NumberedList,
            "code" => BlockType::Code,
            "quote" => BlockType::Quote,
            "divider" => BlockType::Divider,
            _ => BlockType::Paragraph,
        }
    }
}

#[derive(Debug, Clone)]
pub struct BlockState {
    pub id: String,
    pub block_type: BlockType,
    pub text: String,
    pub children: Vec<String>,
    pub indent_level: u32,
    pub meta: HashMap<String, String>,
}
