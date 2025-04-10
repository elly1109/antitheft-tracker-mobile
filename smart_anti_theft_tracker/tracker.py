import time
import random

class Tracker:
    def __init__(self, device_id: str):
        self.device_id = device_id

    def generate_location(self) -> tuple:
        """Simulate GPS coordinates and timestamp."""
        latitude = random.uniform(-90, 90)
        longitude = random.uniform(-180, 180)
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        return (latitude, longitude, timestamp)

    def ping(self) -> str:
        """Generate an encrypted location ping."""
        lat, lon, ts = self.generate_location()
        data = f"{self.device_id},{lat},{lon},{ts}"
        from crypto_utils import crypto
        return crypto.encrypt(data)
