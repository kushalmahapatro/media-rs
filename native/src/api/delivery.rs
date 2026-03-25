//! WhatsApp-style delivery profiles: analytic size/time estimates from duration + fixed bitrates.

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum DeliveryProfileId {
    Hd720,
    Sd480,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DeliveryProfile {
    pub id: DeliveryProfileId,
    pub max_long_edge_px: u32,
    pub video_bitrate_kbps: u32,
    pub audio_bitrate_kbps: u32,
    pub mux_overhead_bytes: u64,
    pub encode_realtime_speed_factor: f64,
}

impl DeliveryProfile {
    pub fn hd720() -> Self {
        Self {
            id: DeliveryProfileId::Hd720,
            max_long_edge_px: 1280,
            video_bitrate_kbps: 2500,
            audio_bitrate_kbps: 128,
            mux_overhead_bytes: 65_536,
            encode_realtime_speed_factor: 2.5,
        }
    }

    pub fn sd480() -> Self {
        Self {
            id: DeliveryProfileId::Sd480,
            max_long_edge_px: 854,
            video_bitrate_kbps: 1000,
            audio_bitrate_kbps: 96,
            mux_overhead_bytes: 65_536,
            encode_realtime_speed_factor: 2.5,
        }
    }
}

/// Typical H.264+AAC output is often a few percent below peak CBR math (VBR / easy scenes).
pub fn apply_vbr_size_calibration(raw_size_bytes: u64) -> u64 {
    (raw_size_bytes.saturating_mul(92)) / 100
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DeliveryEstimate {
    pub profile_id: DeliveryProfileId,
    pub width: u32,
    pub height: u32,
    pub estimated_size_bytes: u64,
    pub video_bitrate_kbps: u32,
    pub audio_bitrate_kbps: u32,
    pub estimated_encode_time_ms: u64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct VideoDeliveryEstimates {
    pub hd_720: DeliveryEstimate,
    pub sd_480: DeliveryEstimate,
}

pub fn fit_long_edge(sw: u32, sh: u32, max_long: u32) -> (u32, u32) {
    if sw == 0 || sh == 0 {
        return (0, 0);
    }
    let long_e = sw.max(sh);
    if long_e <= max_long {
        return (sw & !1, sh & !1);
    }
    let scale = max_long as f64 / long_e as f64;
    let w = ((sw as f64 * scale).round() as u32).max(2) & !1;
    let h = ((sh as f64 * scale).round() as u32).max(2) & !1;
    (w, h)
}

pub fn estimate_delivery_size_bytes(
    duration_ms: u64,
    video_kbps: u32,
    audio_kbps: u32,
    mux_pad: u64,
) -> u64 {
    let total_kbps = video_kbps as u64 + audio_kbps as u64;
    (total_kbps * 1000 * duration_ms) / 8000 + mux_pad
}

pub fn estimate_encode_time_ms(duration_ms: u64, speed_factor: f64) -> u64 {
    if speed_factor <= 0.0 {
        return duration_ms;
    }
    let t = (duration_ms as f64 / speed_factor).round() as u64;
    t.max(1)
}

pub fn delivery_estimate_for_profile_with_source_bitrate(
    duration_ms: u64,
    display_width: u32,
    display_height: u32,
    profile: &DeliveryProfile,
    source_bitrate_bps: Option<u64>,
) -> DeliveryEstimate {
    let (w, h) = fit_long_edge(
        display_width,
        display_height,
        profile.max_long_edge_px,
    );
    let mut v_kbps = profile.video_bitrate_kbps;
    if let Some(bps) = source_bitrate_bps {
        let src_kbps = (bps / 1000).max(1) as u32;
        let audio = profile.audio_bitrate_kbps;
        if src_kbps > audio && v_kbps + audio > src_kbps {
            v_kbps = src_kbps.saturating_sub(audio).max(1);
        }
    }
    let raw_size = estimate_delivery_size_bytes(
        duration_ms,
        v_kbps,
        profile.audio_bitrate_kbps,
        profile.mux_overhead_bytes,
    );
    let size = apply_vbr_size_calibration(raw_size);
    let enc_ms = estimate_encode_time_ms(duration_ms, profile.encode_realtime_speed_factor);
    DeliveryEstimate {
        profile_id: profile.id,
        width: w,
        height: h,
        estimated_size_bytes: size,
        video_bitrate_kbps: v_kbps,
        audio_bitrate_kbps: profile.audio_bitrate_kbps,
        estimated_encode_time_ms: enc_ms,
    }
}

pub fn compute_video_delivery_estimates_with_source(
    duration_ms: u64,
    display_width: u32,
    display_height: u32,
    source_bitrate_bps: Option<u64>,
) -> VideoDeliveryEstimates {
    let hd = DeliveryProfile::hd720();
    let sd = DeliveryProfile::sd480();
    VideoDeliveryEstimates {
        hd_720: delivery_estimate_for_profile_with_source_bitrate(
            duration_ms,
            display_width,
            display_height,
            &hd,
            source_bitrate_bps,
        ),
        sd_480: delivery_estimate_for_profile_with_source_bitrate(
            duration_ms,
            display_width,
            display_height,
            &sd,
            source_bitrate_bps,
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn estimate_delivery_size_bytes_formula() {
        let duration_ms = 60_000u64;
        let mux = 65_536u64;
        let got = estimate_delivery_size_bytes(duration_ms, 1000, 128, mux);
        let total_kbps = 1128u64;
        let expected = (total_kbps * 1000 * duration_ms) / 8000 + mux;
        assert_eq!(got, expected);
    }

    #[test]
    fn fit_long_edge_even_dimensions() {
        let (w, h) = fit_long_edge(1920, 1080, 1280);
        assert_eq!(w % 2, 0);
        assert_eq!(h % 2, 0);
        assert!(w <= 1280);
        assert!(h <= 720);
    }

    #[test]
    fn apply_vbr_size_calibration_percent() {
        assert_eq!(apply_vbr_size_calibration(1000), 920);
        assert_eq!(apply_vbr_size_calibration(0), 0);
    }
}
