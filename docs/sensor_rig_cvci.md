# CVCI sensor rig

Default model inputs on `feat/cvci-7cam-hdmap`: **7 cameras + a local HD-map
raster**. LiDAR and radar are not spawned, not stored, and not fed to the
policy.

Do not mix logs from this rig with the older 6-camera + LiDAR + radar 123D
trial data.

## Why not store a privileged map dump per tick

A real vehicle does not receive CARLA actor lists. It receives:

1. A **town / city HD map** (OpenDRIVE, Lanelet2, or a vendor SDK tile)
2. **GNSS + IMU localization** (here: leaderboard GNSS + compass, Kalman-filtered)
3. A **navigation route** (here: the same target points the planner already uses)

Those three already exist in a LEAD log:

- Town map: converted once per town from bundled OpenDRIVE to
  `<PY123D_DATA_ROOT>/maps/<dataset>/<dataset>_<town>.arrow`
- Localized pose: `driving_meta["localized_ego_state_se3"]`
- Route: `previous_target_point` / `target_point` / `next_target_point`

Collection therefore does **not** write a per-tick raster. Training and
closed-loop eval rebuild the same ego-centric tile from the map SDK + pose +
route. That is also what an onboard stack can do.

Privileged boxes, occupancy, and traffic-light *actor* state stay labels only.

## HD-map feature

`build_hd_map_raster` draws into the existing BEV tensor
`rasterized_lidar` (`1 × H × W`, same size as the old LiDAR splat) so the
TransFuser BEV encoder (`in_chans=1`) is unchanged:

| Value | Layer |
| --- | --- |
| 0.35 | road / intersection / drivable |
| 0.70 | stop-sign stop lines (always on; a map has them whether you are in the zone) |
| 1.00 | lane markings |
| 0.85 | navigation polyline |

Online, the agent loads the town arrow and puts the GNSS+IMU pose (ISO 8855)
into `ego_state` so the query frame matches training. If the town arrow is
missing, the raster is route-only until collection converts that town.

Do **not** turn on `policy.transfuser.backbone.LTF` for this rig: LTF replaces
the BEV raster with positional encodings.

## 7-camera mount

Poses are metres / degrees in the CARLA vehicle frame (x forward, y right, z
up). 384×384 each; stitch order is LEAD index 1→7 (width 2688).

| Index | Name | FOV | Position | Rotation (roll, pitch, yaw) | 123D ID |
| --- | --- | --- | --- | --- | --- |
| 1 | CAM0 front-narrow | 30° | windshield, 1 cm left of center | 0, 0, 0 | `PCAM_STEREO_L` |
| 2 | CAM1 front-wide | 100° | windshield, 1 cm right of center | 0, 0, 0 | `PCAM_F0` |
| 3 | Left-front | 100° | mirror height | 0, 0, −50° | `PCAM_L0` |
| 4 | Right-front | 100° | mirror height | 0, 0, +50° | `PCAM_R0` |
| 5 | Left-rear | 100° | mirror height | 0, 0, −130° | `PCAM_L1` |
| 6 | Right-rear | 100° | mirror height | 0, 0, +130° | `PCAM_R1` |
| 7 | Rear roof | 100° | roof camera | 0, −4° (down), 180° | `PCAM_B0` |

py123d has no second front pinhole id, so CAM0 uses `PCAM_STEREO_L`.

Lincoln-ish heights: windshield 1.45 m, mirrors 1.10 m, rear roof 1.55 m.
Re-tune on the actual spawn vehicle if the body differs.

## Flags

```text
expert.sensor_rig.use_lidars=false
expert.sensor_rig.use_radars=false
expert.sensor_rig.use_hd_map=true
policy.transfuser.radar.use_radar_detection=false
policy.transfuser.lidar.merge_radar_into_lidar=false
```

`use_lidars=true` restores the old BEV LiDAR path and skips the HD-map raster.
