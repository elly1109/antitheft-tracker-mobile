import random
import asyncio

class CrowdNetwork:
    def __init__(self):
        self.nodes = ["node_1", "node_2", "node_3"]

    async def relay_signal(self, device_id: str, encrypted_data: str) -> str:
        """Simulate a node relaying the signal."""
        relay_node = random.choice(self.nodes)
        print(f"{relay_node} relayed {device_id}: {encrypted_data}")
        await asyncio.sleep(1)  # Simulate network delay
        return encrypted_data

network = CrowdNetwork()
