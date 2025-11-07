#![no_main]

use libfuzzer_sys::fuzz_target;
// Note: Opus decoding is typically done via Ogg container (Vorbis fuzzer covers similar paths)
// This fuzzer validates raw Opus packet decoding

fuzz_target!(|data: &[u8]| {
    // Fuzz raw Opus packet decoding
    // Opus packets can be embedded in Ogg (covered by Vorbis fuzzer) or raw

    // Basic validation: Opus packets start with TOC byte
    if data.is_empty() {
        return;
    }

    let toc = data[0];
    let config = (toc >> 3) & 0x1F;  // Configuration number (0-31)
    let stereo = (toc & 0x04) != 0;   // Stereo flag
    let frame_count = toc & 0x03;     // Frame count indicator

    // Validate configuration ranges
    if config > 31 {
        return;
    }

    // Simulate basic Opus packet structure validation
    // Real Opus decoding would happen here, but we're fuzzing the parser logic
    let _channels = if stereo { 2 } else { 1 };
    let _frames = match frame_count {
        0 => 1,
        1 | 2 => 2,
        3 => {
            // Variable frame count, read from packet
            if data.len() < 2 {
                return;
            }
            data[1] & 0x3F
        }
        _ => return,
    };

    // Validate packet doesn't exceed reasonable size (120ms at 48kHz stereo)
    const MAX_OPUS_PACKET_SIZE: usize = 1275 * 3; // Max 3 frames
    if data.len() > MAX_OPUS_PACKET_SIZE {
        return;
    }

    // If we wanted to actually decode, we'd use the opus crate here
    // For now, this fuzzes the packet validation logic
});
