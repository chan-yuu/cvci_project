"""Sensor rig configuration: cameras, optional LiDARs/radars, and HD-map input."""

from typing import TypedDict

from lead.config.node import ConfigNode


class CameraSpec(TypedDict):
    """Calibration of one camera: mounting pose, resolution and field of view."""

    pos: list[float]
    rot: list[float]
    width: int
    height: int
    fov: int


class RadarSpec(TypedDict):
    """Calibration of one radar: mounting pose and field of view."""

    pos: list[float]
    rot: list[float]
    horz_fov: float
    vert_fov: float


class SensorRigConfig(ConfigNode):
    """Mounting positions and parameters of the LiDAR, camera and radar rig."""

    # If true spawn and store the two-LiDAR rig. CVCI collection keeps this off:
    # the BEV encoder reads a local HD-map raster instead.
    use_lidars: bool = False

    # --- LiDAR Configuration ---
    # Used only when ``use_lidars`` is true. The rig is two LiDARs.

    # x, y, z mounting position of the first LiDAR
    lidar_pos_1: list[float] = [1.0, 0.0, 2.5]
    # Roll, pitch, yaw rotation of first LiDAR (degrees)
    lidar_rot_1: list[float] = [0.0, 0.0, -90.0]
    # x, y, z mounting position of the second LiDAR
    lidar_pos_2: list[float] = [-1.0, 0.0, 2.5]
    # Roll, pitch, yaw rotation of second LiDAR (degrees)
    lidar_rot_2: list[float] = [0.0, 0.0, -270.0]

    # --- Camera Configuration ---
    # Camera ``i`` (1-based) is ``cameras[i - 1]``. Default is the CVCI 7-cam
    # windshield / mirror / rear-roof rig. Poses are metres / degrees in the
    # CARLA vehicle frame (x forward, y right, z up).
    cameras: list[CameraSpec] = [
        {  # 1 CAM0 front-narrow, windshield, left of the pair (<2 cm)
            "pos": [1.10, -0.01, 1.45],
            "rot": [0.0, 0.0, 0.0],
            "width": 384,
            "height": 384,
            "fov": 30,
        },
        {  # 2 CAM1 front-wide, windshield, right of the pair
            "pos": [1.10, 0.01, 1.45],
            "rot": [0.0, 0.0, 0.0],
            "width": 384,
            "height": 384,
            "fov": 100,
        },
        {  # 3 left-front, side-mirror height, 50° from forward
            "pos": [0.85, -1.05, 1.10],
            "rot": [0.0, 0.0, -50.0],
            "width": 384,
            "height": 384,
            "fov": 100,
        },
        {  # 4 right-front, side-mirror height, 50° from forward
            "pos": [0.85, 1.05, 1.10],
            "rot": [0.0, 0.0, 50.0],
            "width": 384,
            "height": 384,
            "fov": 100,
        },
        {  # 5 left-rear, side-mirror height, 50° from rearward
            "pos": [-0.50, -1.05, 1.10],
            "rot": [0.0, 0.0, -130.0],
            "width": 384,
            "height": 384,
            "fov": 100,
        },
        {  # 6 right-rear, side-mirror height, 50° from rearward
            "pos": [-0.50, 1.05, 1.10],
            "rot": [0.0, 0.0, 130.0],
            "width": 384,
            "height": 384,
            "fov": 100,
        },
        {  # 7 rear roof, pitched 4° down
            "pos": [-1.80, 0.0, 1.55],
            "rot": [0.0, -4.0, 180.0],
            "width": 384,
            "height": 384,
            "fov": 100,
        },
    ]

    @property
    def num_cameras(self) -> int:
        """Number of cameras in the rig."""
        return len(self.cameras)

    @property
    def camera_width(self) -> int:
        """Width of a single camera image; all cameras share one resolution."""
        return self.cameras[0]["width"]

    @property
    def camera_height(self) -> int:
        """Height of a single camera image; all cameras share one resolution."""
        return self.cameras[0]["height"]

    @property
    def image_width(self) -> int:
        """Width of all camera images stitched side by side."""
        return self.num_cameras * self.camera_width

    @property
    def image_height(self) -> int:
        """Height of the stitched camera image."""
        return self.camera_height

    # --- Radar Configuration ---
    # Calibration of the radar sensors. Radar ``i`` (1-based) in sensor specs
    # corresponds to ``radars[i - 1]``.
    radars: list[RadarSpec] = [
        {  # front-left
            "pos": [2.6, 0.0, 0.60],
            "rot": [0.0, 0.0, -45.0],
            "horz_fov": 90,
            "vert_fov": 0.1,
        },
        {  # front
            "pos": [2.6, 0.0, 0.60],
            "rot": [0.0, 0.0, 45.0],
            "horz_fov": 90,
            "vert_fov": 0.1,
        },
        {  # front-right
            "pos": [-2.6, 0.0, 0.60],
            "rot": [0.0, 0.0, 135.0],
            "horz_fov": 90,
            "vert_fov": 0.1,
        },
        {  # rear
            "pos": [-2.6, 0.0, 0.60],
            "rot": [0.0, 0.0, 225.0],
            "horz_fov": 90,
            "vert_fov": 0.1,
        },
    ]

    @property
    def num_radar_sensors(self) -> int:
        """Number of radar sensors in the rig."""
        return len(self.radars)

    # If true spawn and store the radar rig. CVCI collection keeps this off.
    use_radars: bool = False

    # If true the policy BEV branch reads a local HD-map raster (lanes, road,
    # route) instead of LiDAR. Same local tile a vehicle can query from a map
    # SDK given GNSS + a navigation route — not privileged CARLA actors.
    use_hd_map: bool = True
