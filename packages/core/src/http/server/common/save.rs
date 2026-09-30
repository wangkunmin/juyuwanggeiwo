use crate::crypto;
use bytes::Bytes;
use http_body_util::BodyExt;
use hyper::body::Incoming;
use hyper::Request;
use std::future::Future;
use std::path::PathBuf;
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
use tokio::sync::{mpsc, oneshot};

/// Channel capacity for file upload chunks (provides backpressure).
const UPLOAD_CHANNEL_CAPACITY: usize = 16;

/// Size of the write buffer that coalesces incoming body chunks (typically one
/// TLS record, ~16 KiB) into larger file writes.
const WRITE_BUFFER_SIZE: usize = 512 * 1024;

/// Size of the buffer used when re-reading an existing prefix to seed the
/// checksum of a resumed transfer.
const PREFIX_READ_BUFFER_SIZE: usize = 64 * 1024;

/// Where the content of an uploaded file should go, decided by the application.
#[derive(Debug)]
pub enum FileUploadTarget {
    /// The application consumes the binary chunks itself.
    ///
    /// The server forwards chunks into `binary_tx` and closes it at end of file.
    /// The application should compare the number of received bytes with `file.size`
    /// and report the result on the sender side of `result_rx` which determines
    /// the HTTP response (200 on `Ok`, 500 on `Err` or when the sender is dropped).
    ///
    /// Note: the checksum is only verified after the application reported its
    /// result, so a checksum mismatch is not observable by the application here
    /// (unlike [FileUploadTarget::Path] and [FileUploadTarget::Fd]).
    ///
    /// Resuming is not supported for this target: the application would have to
    /// know about the existing prefix itself.
    Stream {
        /// Channel the server sends the binary chunks of the file into.
        binary_tx: mpsc::Sender<Bytes>,

        /// Channel on which the application reports whether the file was
        /// processed successfully.
        result_rx: oneshot::Receiver<Result<(), String>>,
    },

    /// The server writes the file to this path and reports the outcome on
    /// `result_tx`.
    ///
    /// With `offset == 0` the file is created or truncated. With `offset > 0`
    /// the existing file must be at least `offset` bytes long: the server keeps
    /// its content, continues writing at `offset` and still verifies the
    /// checksum over the whole file.
    ///
    /// Timestamps provided in the sender's file metadata are applied to the
    /// written file, so the application does not need to set them itself.
    Path {
        /// The path to write the file to.
        path: PathBuf,

        /// Channel on which the server reports the outcome of the transfer.
        result_tx: oneshot::Sender<SaveOutcome>,

        /// Optional channel on which the server reports the number of bytes
        /// written so far (including a resumed prefix). Events are dropped when
        /// the channel is full; the final value is always delivered.
        progress_tx: Option<mpsc::Sender<u64>>,

        /// Byte offset to continue writing at. `0` starts a new file.
        offset: u64,
    },

    /// The server writes the file to this raw file descriptor (Android only)
    /// and reports the outcome on `result_tx`.
    ///
    /// Timestamps provided in the sender's file metadata are applied through
    /// the descriptor, which also covers SAF documents that have no path.
    /// Resuming requires the descriptor to be seekable; if it is not, the
    /// transfer fails and the application should retry from `offset = 0`.
    #[cfg(target_os = "android")]
    Fd {
        /// The raw file descriptor to write the file to.
        /// Ownership is transferred; the descriptor is closed after writing.
        fd: std::os::fd::RawFd,

        /// Channel on which the server reports the outcome of the transfer.
        result_tx: oneshot::Sender<SaveOutcome>,

        /// Optional channel on which the server reports the number of bytes
        /// written so far (including a resumed prefix). Events are dropped when
        /// the channel is full; the final value is always delivered.
        progress_tx: Option<mpsc::Sender<u64>>,

        /// Byte offset to continue writing at. `0` starts a new file.
        offset: u64,
    },
}

/// The sender-provided timestamps of an uploaded file, applied to the written
/// file for [FileUploadTarget::Path] and [FileUploadTarget::Fd].
#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct FileTimestamps {
    pub modified: Option<std::time::SystemTime>,
    pub accessed: Option<std::time::SystemTime>,
}

impl FileTimestamps {
    fn is_empty(&self) -> bool {
        self.modified.is_none() && self.accessed.is_none()
    }
}

/// Outcome of receiving an uploaded file.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SaveResult {
    /// The file has been received and, if a checksum was given, it matched.
    Success,

    /// The body could not be read or the target failed to process it.
    Failed,

    /// The received bytes do not match the expected SHA-256 checksum.
    HashMismatch,
}

/// Result of one upload attempt, including how much data reached the disk.
///
/// `written` includes a resumed prefix, so an application that keeps a partial
/// file can store it as the next resume offset. It is the number of bytes that
/// were flushed to the target when the attempt ended (also on failure).
#[derive(Debug, Clone, Copy)]
pub struct SaveOutcome {
    /// How the attempt ended.
    pub result: SaveResult,
    /// Bytes stored on disk when the attempt ended (includes a resumed prefix).
    pub written: u64,
}

impl SaveOutcome {
    fn failed(written: u64) -> Self {
        Self {
            result: SaveResult::Failed,
            written,
        }
    }
}

/// What the file writer task observed.
#[derive(Debug)]
struct WriteOutcome {
    written: u64,
    error: Option<String>,
    hash_mismatch: bool,
}

/// Forwards the body of `req` to `target`.
///
/// `offset` is the byte position to continue at; it must be `0` unless the
/// caller verified that the target already holds a matching prefix (see
/// `/upload` for the validation rules).
pub(crate) async fn save_req_to_target(
    req: Request<Incoming>,
    target: FileUploadTarget,
    file_size: u64,
    offset: u64,
    expected_sha256: Option<&str>,
    timestamps: FileTimestamps,
) -> SaveOutcome {
    // A stream target is consumed by the application itself, which would have to
    // know about the existing prefix. Refuse instead of storing a wrong file.
    if offset > 0 && matches!(&target, FileUploadTarget::Stream { .. }) {
        tracing::warn!("Resume is not supported for stream upload targets");
        return SaveOutcome::failed(0);
    }

    match target {
        FileUploadTarget::Stream {
            binary_tx,
            result_rx,
        } => save_to_stream(req, binary_tx, result_rx, file_size, expected_sha256).await,
        FileUploadTarget::Path {
            path,
            result_tx,
            progress_tx,
            offset: target_offset,
        } => {
            save_to_file(
                req,
                result_tx,
                progress_tx,
                file_size,
                offset,
                expected_sha256,
                timestamps,
                async move {
                    open_for_write(&path, target_offset)
                        .await
                        .map_err(|e| format!("Failed to open {}: {e}", path.display()))
                },
                target_offset,
            )
            .await
        }
        #[cfg(target_os = "android")]
        FileUploadTarget::Fd {
            fd,
            result_tx,
            progress_tx,
            offset: target_offset,
        } => {
            save_to_file(
                req,
                result_tx,
                progress_tx,
                file_size,
                offset,
                expected_sha256,
                timestamps,
                async move {
                    use std::os::fd::FromRawFd;

                    // SAFETY: the descriptor is owned by this transfer; wrapping it in
                    // a File transfers that ownership so it is closed once writing finishes.
                    let std_file = unsafe { std::fs::File::from_raw_fd(fd) };
                    Ok(tokio::fs::File::from_std(std_file))
                },
                target_offset,
            )
            .await
        }
    }
}

/// Opens `path` for writing: truncating for a fresh file, keeping the existing
/// content when a prefix is resumed.
async fn open_for_write(path: &std::path::Path, offset: u64) -> std::io::Result<tokio::fs::File> {
    if offset == 0 {
        tokio::fs::File::create(path).await
    } else {
        tokio::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(path)
            .await
    }
}

/// Streams the request body to an application-provided sink.
///
/// The checksum is verified here because the application only sees the chunks.
async fn save_to_stream(
    req: Request<Incoming>,
    binary_tx: mpsc::Sender<Bytes>,
    result_rx: oneshot::Receiver<Result<(), String>>,
    file_size: u64,
    expected_sha256: Option<&str>,
) -> SaveOutcome {
    use sha2::{Digest, Sha256};

    let mut hasher = expected_sha256.map(|_| Sha256::new());
    let mut forwarded: u64 = 0;
    let mut stream_error = false;

    let mut body = req.into_body();
    while let Some(frame) = body.frame().await {
        match frame {
            Ok(frame) => {
                let Ok(data) = frame.into_data() else {
                    continue; // ignore non-data frames (e.g. trailers)
                };
                if data.is_empty() {
                    continue;
                }
                if let Some(hasher) = &mut hasher {
                    hasher.update(&data);
                }
                forwarded += data.len() as u64;
                if binary_tx.send(data).await.is_err() {
                    // The receiver is gone (dropped by the application).
                    stream_error = true;
                    break;
                }
            }
            Err(err) => {
                tracing::warn!("Error reading upload body of file: {err:#}");
                stream_error = true;
                break;
            }
        }
    }

    // Signal end of file to the receiving side.
    drop(binary_tx);

    if stream_error {
        return SaveOutcome::failed(forwarded);
    }

    match result_rx.await {
        Ok(Ok(())) => {}
        Ok(Err(err)) => {
            tracing::warn!("Failed to process file: {err}");
            return SaveOutcome::failed(forwarded);
        }
        Err(_) => return SaveOutcome::failed(forwarded),
    }

    if forwarded != file_size {
        tracing::warn!("Expected {file_size} bytes, received {forwarded}");
        return SaveOutcome::failed(forwarded);
    }

    if let (Some(hasher), Some(expected)) = (hasher, expected_sha256) {
        let actual = crypto::hash::to_hex(&hasher.finalize());
        if !actual.eq_ignore_ascii_case(expected) {
            tracing::warn!("Checksum mismatch: expected {expected}, got {actual}");
            return SaveOutcome {
                result: SaveResult::HashMismatch,
                written: forwarded,
            };
        }
    }

    SaveOutcome {
        result: SaveResult::Success,
        written: forwarded,
    }
}

/// Streams the request body into a file written by a background task.
///
/// The application's result channel is answered once the complete outcome
/// (including the checksum verification) is known.
#[allow(clippy::too_many_arguments)]
async fn save_to_file<F>(
    req: Request<Incoming>,
    result_tx: oneshot::Sender<SaveOutcome>,
    progress_tx: Option<mpsc::Sender<u64>>,
    file_size: u64,
    offset: u64,
    expected_sha256: Option<&str>,
    timestamps: FileTimestamps,
    open: F,
    target_offset: u64,
) -> SaveOutcome
where
    F: Future<Output = Result<tokio::fs::File, String>> + Send + 'static,
{
    let (binary_tx, result_rx) = spawn_file_writer(
        open,
        file_size,
        target_offset,
        progress_tx,
        timestamps,
        expected_sha256.map(str::to_string),
    );

    // Forward the request body to the writer. Any error is reported by the
    // writer itself (a short body is a size mismatch there).
    let mut body = req.into_body();
    while let Some(frame) = body.frame().await {
        match frame {
            Ok(frame) => {
                let Ok(data) = frame.into_data() else {
                    continue; // ignore non-data frames (e.g. trailers)
                };
                if data.is_empty() {
                    continue;
                }
                if binary_tx.send(data).await.is_err() {
                    // The writer gave up (its own error is reported below).
                    break;
                }
            }
            Err(err) => {
                tracing::warn!("Error reading upload body of file: {err:#}");
                break;
            }
        }
    }
    drop(binary_tx);

    let outcome = match result_rx.await {
        Ok(outcome) => outcome,
        Err(_) => WriteOutcome {
            written: offset,
            error: Some("Upload aborted".to_string()),
            hash_mismatch: false,
        },
    };

    if let Some(error) = &outcome.error {
        tracing::warn!("Failed to process file: {error}");
    }

    let save_outcome = SaveOutcome {
        result: match (&outcome.error, outcome.hash_mismatch) {
            (None, _) => SaveResult::Success,
            (Some(_), true) => SaveResult::HashMismatch,
            (Some(_), false) => SaveResult::Failed,
        },
        written: outcome.written,
    };

    let _ = result_tx.send(save_outcome);
    save_outcome
}

/// Spawns a task that writes incoming chunks to a file provided by `open`.
///
/// Returns the sender for the binary chunks and a receiver for the outcome.
fn spawn_file_writer(
    open: impl Future<Output = Result<tokio::fs::File, String>> + Send + 'static,
    expected_size: u64,
    offset: u64,
    progress_tx: Option<mpsc::Sender<u64>>,
    timestamps: FileTimestamps,
    expected_sha256: Option<String>,
) -> (mpsc::Sender<Bytes>, oneshot::Receiver<WriteOutcome>) {
    let (binary_tx, mut binary_rx) = mpsc::channel::<Bytes>(UPLOAD_CHANNEL_CAPACITY);
    let (internal_tx, internal_rx) = oneshot::channel::<WriteOutcome>();

    tokio::spawn(async move {
        let outcome = write_file_from_receiver(
            open,
            expected_size,
            offset,
            &mut binary_rx,
            progress_tx,
            timestamps,
            expected_sha256,
        )
        .await;
        // Unblock the request handler if it is still sending chunks.
        binary_rx.close();
        let _ = internal_tx.send(outcome);
    });

    (binary_tx, internal_rx)
}

/// Writes all chunks received on `rx` to the file provided by `open`.
///
/// With `offset == 0` the file is written from the beginning. With `offset > 0`
/// the existing prefix is kept, the checksum is seeded from it (so the caller
/// still gets a full-file checksum) and the received bytes are appended.
///
/// Fails if the total number of bytes does not match `expected_size` (e.g. the
/// sender disconnected mid-transfer). The file is truncated to the final size so
/// that a target that pointed at a longer, pre-existing file cannot keep a tail
/// of the old content.
///
/// The sender-provided `timestamps` are applied to the completely written file.
/// This happens on the still-open handle: an Android file descriptor has no path
/// to address the file by afterwards.
#[allow(clippy::too_many_arguments)]
async fn write_file_from_receiver(
    open: impl Future<Output = Result<tokio::fs::File, String>>,
    expected_size: u64,
    offset: u64,
    rx: &mut mpsc::Receiver<Bytes>,
    progress_tx: Option<mpsc::Sender<u64>>,
    timestamps: FileTimestamps,
    expected_sha256: Option<String>,
) -> WriteOutcome {
    use sha2::{Digest, Sha256};

    let mut buffered = match open.await {
        Ok(file) => tokio::io::BufWriter::with_capacity(WRITE_BUFFER_SIZE, file),
        Err(error) => {
            return WriteOutcome {
                written: 0,
                error: Some(error),
                hash_mismatch: false,
            };
        }
    };
    let mut file = buffered.get_mut();

    let mut written: u64 = offset;

    if offset == 0 {
        // Best effort, mirroring the truncation of `File::create`: a document
        // provider may not support truncation, which must not fail the transfer.
        if let Err(e) = file.set_len(0).await {
            tracing::warn!("Could not truncate the target before writing: {e}");
        }
    } else {
        // A resumed transfer is only safe when the advertised prefix really is
        // on disk; a short file means the receiver lost data and must restart.
        match file.metadata().await {
            Ok(meta) if meta.len() >= offset => {}
            Ok(meta) => {
                return WriteOutcome {
                    written: 0,
                    error: Some(format!(
                        "Cannot resume at {offset} bytes: the target only holds {} bytes",
                        meta.len()
                    )),
                    hash_mismatch: false,
                };
            }
            Err(e) => {
                return WriteOutcome {
                    written: 0,
                    error: Some(format!("Failed to inspect the target: {e}")),
                    hash_mismatch: false,
                };
            }
        }
    }

    // Seed the checksum with the prefix that is already on disk, then continue
    // after it. Reading from the same handle keeps SAF descriptors working.
    let mut hasher = expected_sha256.as_ref().map(|_| Sha256::new());
    if let Some(hasher) = hasher.as_mut() {
        if offset > 0 {
            if let Err(error) = seed_hasher_from_prefix(file, hasher, offset).await {
                return WriteOutcome {
                    written: 0,
                    error: Some(error),
                    hash_mismatch: false,
                };
            }
        }
        if let Err(e) = file.seek(std::io::SeekFrom::Start(offset)).await {
            return WriteOutcome {
                written: offset,
                error: Some(format!("Failed to seek to the resume offset: {e}")),
                hash_mismatch: false,
            };
        }
    } else if offset > 0 {
        if let Err(e) = file.seek(std::io::SeekFrom::Start(offset)).await {
            return WriteOutcome {
                written: offset,
                error: Some(format!("Failed to seek to the resume offset: {e}")),
                hash_mismatch: false,
            };
        }
    }

    while let Some(chunk) = rx.recv().await {
        written += chunk.len() as u64;
        if written > expected_size {
            let error = format!("Expected {expected_size} bytes, received at least {written}");
            deliver_final_progress(&progress_tx, written).await;
            return WriteOutcome {
                written,
                error: Some(error),
                hash_mismatch: false,
            };
        }
        if let Some(hasher) = hasher.as_mut() {
            hasher.update(&chunk);
        }
        if let Err(e) = buffered.write_all(&chunk).await {
            let error = format!("Failed to write file: {e}");
            deliver_final_progress(&progress_tx, written).await;
            return WriteOutcome {
                written,
                error: Some(error),
                hash_mismatch: false,
            };
        }
        if let Some(progress_tx) = &progress_tx {
            // Progress is best-effort: drop the event when the consumer lags.
            let _ = progress_tx.try_send(written);
        }
    }

    if let Err(e) = buffered.flush().await {
        let error = format!("Failed to flush file: {e}");
        deliver_final_progress(&progress_tx, written).await;
        return WriteOutcome {
            written,
            error: Some(error),
            hash_mismatch: false,
        };
    }

    // Make sure the application learns the exact final byte count, which is what
    // it stores as the resume offset when the transfer failed.
    deliver_final_progress(&progress_tx, written).await;

    if written != expected_size {
        return WriteOutcome {
            written,
            error: Some(format!(
                "Expected {expected_size} bytes, received {written}"
            )),
            hash_mismatch: false,
        };
    }

    if let (Some(hasher), Some(expected)) = (hasher, expected_sha256) {
        let actual = crypto::hash::to_hex(&hasher.finalize());
        if !actual.eq_ignore_ascii_case(&expected) {
            return WriteOutcome {
                written,
                error: Some("Checksum mismatch".to_string()),
                hash_mismatch: true,
            };
        }
    }

    let file = buffered.into_inner();

    // Drops content beyond the file that was just written, in case the target
    // pointed at a longer, pre-existing file: opening truncates for paths and
    // for descriptors opened with the SAF "wt" mode, but a document provider is
    // free to ignore that mode.
    //
    // Best-effort: a provider may back the descriptor by something that cannot
    // be truncated (e.g. a pipe), which must not fail the completed transfer.
    if let Err(e) = file.set_len(written).await {
        tracing::warn!("Could not truncate file to {written} bytes: {e}");
    }

    // The timestamps are applied last because the writes and the truncation
    // above update the modification time themselves.
    //
    // Best-effort: the provider backing an Android file descriptor may not
    // support changing timestamps, which must not fail the completed transfer.
    if !timestamps.is_empty() {
        let mut times = std::fs::FileTimes::new();
        if let Some(modified) = timestamps.modified {
            times = times.set_modified(modified);
        }
        if let Some(accessed) = timestamps.accessed {
            times = times.set_accessed(accessed);
        }
        let file = file.into_std().await;
        // Also closes the file, off the async runtime like tokio::fs does.
        let result = tokio::task::spawn_blocking(move || file.set_times(times)).await;
        if let Ok(Err(e)) = result {
            tracing::warn!("Could not set file timestamps: {e}");
        }
    }

    WriteOutcome {
        written,
        error: None,
        hash_mismatch: false,
    }
}

/// Reads the first `offset` bytes of `file` into `hasher` and seeks back to
/// `offset`, so a resumed transfer can still verify a full-file checksum.
///
/// A short read means the advertised prefix is not on disk; callers turn that
/// into a failure so the application can restart the file from scratch.
async fn seed_hasher_from_prefix(
    file: &mut tokio::fs::File,
    hasher: &mut sha2::Sha256,
    offset: u64,
) -> Result<(), String> {
    file.seek(std::io::SeekFrom::Start(0))
        .await
        .map_err(|e| format!("Failed to read the existing prefix: {e}"))?;

    let mut buffer = vec![0_u8; PREFIX_READ_BUFFER_SIZE];
    let mut remaining = offset;
    while remaining > 0 {
        let want = buffer.len().min(remaining as usize);
        let read = file
            .read(&mut buffer[..want])
            .await
            .map_err(|e| format!("Failed to read the existing prefix: {e}"))?;
        if read == 0 {
            return Err(format!(
                "Cannot resume at {offset} bytes: the existing prefix is shorter"
            ));
        }
        hasher.update(&buffer[..read]);
        remaining -= read as u64;
    }

    file.seek(std::io::SeekFrom::Start(offset))
        .await
        .map_err(|e| format!("Failed to seek back to the resume offset: {e}"))?;
    Ok(())
}

/// Sends the final progress value, waiting for capacity instead of dropping it.
async fn deliver_final_progress(progress_tx: &Option<mpsc::Sender<u64>>, written: u64) {
    if let Some(progress_tx) = progress_tx {
        let _ = progress_tx.send(written).await;
    }
}
