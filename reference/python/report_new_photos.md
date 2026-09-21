# Passport photo report

**Result: FAIL** - India passport (VFS USA, 2026), 26s, no human input

## Checks on the finished file

| check | result | value | rule |
|---|---|---|---|
| dimensions | pass | 630x810 | 630x810 |
| file_size_kb | pass | 151.9 | 10-250 KB |
| face_detected | pass | yes | one face |
| background_white | pass | 97.9% pure, min 250 | >=95% pure 255, min >=245 |
| head_height_mm | pass | 36.33 | 36.0 +/- 0.75 mm (crown to chin) |
| top_gap_mm | pass | 1.94 | 1.5-4.0 mm |
| eye_line_from_bottom | pass | 54.2% | 50-60% |
| head_roll_deg | pass | 0.0 | <= 2.0 deg |
| centred | pass | 0.11% off | <= 2% of width |
| head_yaw_deg | **FAIL** | 5.5 | <= 5 deg (ISO/IEC 19794-5); estimate +/- 2 deg |
| eyes_open | pass | 0.29 | >= 0.2 |
| mouth_closed | pass | 0.028 | <= 0.12 |
| even_lighting | pass | 7.6% | <= 10% cheek difference |
| sharpness | pass | 566.7 | >= 250.0 |
| face_not_whitened | pass | 0.00% of face | <= 0.5% |
| shoulders_visible | pass | 100% of width at bottom | >= 60% |

Head height against the published ranges:
- ICAO Doc 9303 (32-36 mm): outside
- India-strict reading (36-38 mm): inside

## Processing

- source: IMG_0012.HEIC
- rotation_deg: 2.68
- crown_px: 941
- chin_px: 2741
- head_px: 1800
- crop_px: 1750x2250
- resample: 2.78x downscale
- background: full background replacement
- bg_distance_from_white: 46.5

## Photo selection

| rank | file | score | sharp | cheek diff | yaw deg | roll | scale | verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | IMG_0012.HEIC | 0.607 | 351.896 | 8.9% | +4.6 | 2.677 | 2.82 | **chosen** |
| 2 | IMG_0008.HEIC | 0.39 | 153.537 | 8.2% | +4.8 | 5.986 | 1.28 | ok |
| 3 | IMG_0009.HEIC | 0.624 | 315.067 | 4.3% | +6.3 | 6.367 | 2.08 | REJECTED: mouth open |
| 4 | IMG_0010.HEIC | 0.587 | 596.062 | 12.6% | +3.8 | 4.526 | 3.79 | REJECTED: uneven lighting (12.6% cheek difference) - processing can't fix this |
| 5 | IMG_0011.HEIC | 0.172 | 43.961 | 13.0% | +6.1 | 5.58 | 0.8 | REJECTED: blurry (sharpness 44, need >= 100); uneven lighting (13.0% cheek difference) - processing can't fix this; too small/far: face would need 1.24x upscaling |
| 6 | IMG_0013.HEIC | 0.404 | 196.053 | 11.0% | +5.6 | 3.816 | 1.96 | REJECTED: uneven lighting (11.0% cheek difference) - processing can't fix this |
| 7 | IMG_0014.HEIC | 0.284 | 104.639 | 11.9% | +5.9 | 3.128 | 1.31 | REJECTED: uneven lighting (11.9% cheek difference) - processing can't fix this |
| 8 | IMG_0015.HEIC | 0.322 | 42.956 | 7.2% | +3.9 | 4.247 | 0.88 | REJECTED: blurry (sharpness 43, need >= 100); too small/far: face would need 1.14x upscaling |
| 9 | IMG_0016.HEIC | 0.142 | 19.541 | 13.8% | +5.8 | 6.24 | 0.64 | REJECTED: blurry (sharpness 20, need >= 100); uneven lighting (13.8% cheek difference) - processing can't fix this; too small/far: face would need 1.57x upscaling |
