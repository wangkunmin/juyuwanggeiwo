use flutter_rust_bridge::frb;
pub use localsend::http::dto::{
    PrepareUploadRequestDto, PrepareUploadResponseDto, RegisterDto, RegisterResponseDto,
};
pub use localsend::http::dto_v2::ResumeInfoV2;
pub use localsend::model::discovery::DeviceType;
pub use localsend::model::discovery::ProtocolType;
pub use localsend::model::transfer::{FileDto, FileMetadata};
use std::collections::HashMap;

#[frb(mirror(RegisterDto))]
pub struct _RegisterDto {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub token: String,
    pub port: u16,
    pub protocol: ProtocolType,
    pub has_web_interface: bool,
}

#[frb(mirror(RegisterResponseDto))]
pub struct _RegisterResponseDto {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: Option<DeviceType>,
    pub token: String,
    pub has_web_interface: bool,
}

#[frb(mirror(DeviceType))]
pub enum _DeviceType {
    Mobile,
    Desktop,
    Web,
    Headless,
    Server,
}

#[frb(mirror(ProtocolType))]
pub enum _ProtocolType {
    Http,
    Https,
}

#[frb(mirror(FileDto))]
pub struct _FileDto {
    pub id: String,
    pub file_name: String,
    pub size: u64,
    pub file_type: String,
    pub sha256: Option<String>,
    pub preview: Option<String>,
    pub metadata: Option<FileMetadata>,
}

#[frb(mirror(FileMetadata))]
pub struct _FileMetadata {
    pub modified: Option<String>,
    pub accessed: Option<String>,
}

#[frb(mirror(PrepareUploadRequestDto))]
pub struct _PrepareUploadRequestDto {
    pub info: RegisterDto,
    pub files: HashMap<String, FileDto>,
}

#[frb(mirror(ResumeInfoV2))]
pub struct _ResumeInfoV2 {
    /// Number of bytes the receiver already holds for this file.
    pub offset: u64,
}

#[frb(mirror(PrepareUploadResponseDto))]
pub struct _PrepareUploadResponseDto {
    pub session_id: String,
    pub files: HashMap<String, String>,
    /// Per-file resume offsets; empty unless the receiver can continue a file.
    pub resume: HashMap<String, ResumeInfoV2>,
}
