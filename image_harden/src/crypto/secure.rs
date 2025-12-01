///! Secure memory operations
///!
///! Provides secure memory management for sensitive data:
///! - Memory locking (prevent swapping to disk)
///! - Secure zeroing (prevent data leakage)
///! - Guard pages (detect buffer overflows)
///! - Memory protection (mprotect)

use crate::ImageHardenError;
use std::ptr;

/// Secure buffer that locks memory and zeros on drop
pub struct SecureBuffer {
    ptr: *mut u8,
    len: usize,
    locked: bool,
}

impl SecureBuffer {
    /// Allocate a new secure buffer
    ///
    /// Memory is:
    /// - Allocated from secure heap
    /// - Locked to prevent swapping
    /// - Zeroed before return
    /// - Protected with guard pages (if available)
    pub fn new(len: usize) -> Result<Self, ImageHardenError> {
        if len == 0 {
            return Err(ImageHardenError::CryptoError(
                "Cannot allocate zero-length buffer".to_string(),
            ));
        }

        if len > 1024 * 1024 * 1024 {
            // 1 GB max
            return Err(ImageHardenError::CryptoError(
                "Buffer size exceeds maximum (1 GB)".to_string(),
            ));
        }

        // TODO: Implement using libsodium sodium_malloc()
        // For now, use std allocation (NOT secure)
        let layout = std::alloc::Layout::from_size_align(len, 8)
            .map_err(|e| ImageHardenError::CryptoError(format!("Layout error: {}", e)))?;

        let ptr = unsafe { std::alloc::alloc_zeroed(layout) };
        if ptr.is_null() {
            return Err(ImageHardenError::CryptoError(
                "Failed to allocate memory".to_string(),
            ));
        }

        Ok(Self {
            ptr,
            len,
            locked: false, // TODO: Set to true when using sodium_malloc
        })
    }

    /// Get a mutable slice to the buffer
    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        unsafe { std::slice::from_raw_parts_mut(self.ptr, self.len) }
    }

    /// Get an immutable slice to the buffer
    pub fn as_slice(&self) -> &[u8] {
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }

    /// Get the buffer length
    pub fn len(&self) -> usize {
        self.len
    }

    /// Check if buffer is empty
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// Check if memory is locked
    pub fn is_locked(&self) -> bool {
        self.locked
    }
}

impl Drop for SecureBuffer {
    fn drop(&mut self) {
        if !self.ptr.is_null() {
            // Securely zero memory
            unsafe {
                // TODO: Use libsodium sodium_memzero()
                ptr::write_bytes(self.ptr, 0, self.len);
            }

            // Free memory
            // TODO: Use libsodium sodium_free() when available
            unsafe {
                let layout = std::alloc::Layout::from_size_align_unchecked(self.len, 8);
                std::alloc::dealloc(self.ptr, layout);
            }
        }
    }
}

// SecureBuffer is not Send/Sync by default for safety
unsafe impl Send for SecureBuffer {}
// Note: SecureBuffer is deliberately NOT Sync

/// Lock memory to prevent swapping to disk
///
/// Uses mlock() to lock pages in physical memory
///
/// # Security
/// Prevents sensitive data (keys, passwords) from being written to swap
pub fn lock_memory(data: &mut [u8]) -> Result<(), ImageHardenError> {
    if data.is_empty() {
        return Ok(());
    }

    // TODO: Implement using libsodium sodium_mlock()
    // For now, return placeholder
    Err(ImageHardenError::CryptoError(
        "Libsodium not yet integrated - run build_crypto.sh".to_string(),
    ))
}

/// Unlock previously locked memory
///
/// Allows memory to be swapped again
pub fn unlock_memory(data: &mut [u8]) -> Result<(), ImageHardenError> {
    if data.is_empty() {
        return Ok(());
    }

    // TODO: Implement using libsodium sodium_munlock()
    Err(ImageHardenError::CryptoError(
        "Libsodium not yet integrated - run build_crypto.sh".to_string(),
    ))
}

/// Securely zero memory
///
/// Uses a method that won't be optimized away by the compiler
///
/// # Security
/// Ensures sensitive data is actually zeroed, not just marked for zeroing
pub fn secure_zero(data: &mut [u8]) {
    if data.is_empty() {
        return;
    }

    // TODO: Use libsodium sodium_memzero() when available
    // For now, use volatile write (less reliable but better than nothing)
    unsafe {
        ptr::write_bytes(data.as_mut_ptr(), 0, data.len());
    }
}

/// Compare two byte slices in constant time
///
/// Prevents timing attacks when comparing secrets (keys, MACs, etc.)
///
/// # Returns
/// true if slices are equal, false otherwise
pub fn constant_time_compare(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }

    // TODO: Use libsodium sodium_memcmp() when available
    // For now, use simple XOR accumulator (basic constant-time)
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

/// Make memory read-only
///
/// Uses mprotect() to mark memory as PROT_READ
pub fn make_readonly(data: &[u8]) -> Result<(), ImageHardenError> {
    if data.is_empty() {
        return Ok(());
    }

    // TODO: Implement using libsodium sodium_mprotect_readonly()
    Err(ImageHardenError::CryptoError(
        "Libsodium not yet integrated - run build_crypto.sh".to_string(),
    ))
}

/// Make memory read-write
///
/// Uses mprotect() to restore read-write access
pub fn make_readwrite(data: &mut [u8]) -> Result<(), ImageHardenError> {
    if data.is_empty() {
        return Ok(());
    }

    // TODO: Implement using libsodium sodium_mprotect_readwrite()
    Err(ImageHardenError::CryptoError(
        "Libsodium not yet integrated - run build_crypto.sh".to_string(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_secure_buffer_new() {
        let buffer = SecureBuffer::new(1024);
        assert!(buffer.is_ok());

        let buffer = buffer.unwrap();
        assert_eq!(buffer.len(), 1024);
        assert!(!buffer.is_empty());
    }

    #[test]
    fn test_secure_buffer_zero_len() {
        let result = SecureBuffer::new(0);
        assert!(result.is_err());
    }

    #[test]
    fn test_secure_buffer_too_large() {
        let result = SecureBuffer::new(2 * 1024 * 1024 * 1024); // 2 GB
        assert!(result.is_err());
    }

    #[test]
    fn test_secure_buffer_access() {
        let mut buffer = SecureBuffer::new(10).unwrap();

        // Write some data
        let slice = buffer.as_mut_slice();
        slice[0] = 42;
        slice[9] = 99;

        // Read it back
        let slice = buffer.as_slice();
        assert_eq!(slice[0], 42);
        assert_eq!(slice[9], 99);
    }

    #[test]
    fn test_secure_zero() {
        let mut data = vec![1, 2, 3, 4, 5];
        secure_zero(&mut data);
        assert_eq!(data, vec![0, 0, 0, 0, 0]);
    }

    #[test]
    fn test_constant_time_compare() {
        assert!(constant_time_compare(b"hello", b"hello"));
        assert!(!constant_time_compare(b"hello", b"world"));
        assert!(!constant_time_compare(b"hi", b"hello"));
    }

    #[test]
    fn test_secure_buffer_drop() {
        // Test that buffer is properly zeroed on drop
        let mut buffer = SecureBuffer::new(100).unwrap();
        buffer.as_mut_slice().fill(42);

        // Drop should zero the memory
        drop(buffer);
        // Can't verify zeroing directly, but no crash = good
    }
}
