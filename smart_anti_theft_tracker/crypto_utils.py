from cryptography.fernet import Fernet
import os
from dotenv import load_dotenv

load_dotenv()
ENCRYPTION_KEY = os.getenv('ENCRYPTION_KEY').encode()  # Base64-encoded string to bytes

class Crypto:
    def __init__(self):
        self.cipher = Fernet(ENCRYPTION_KEY)

    def encrypt(self, data):
        return self.cipher.encrypt(data.encode()).decode()

    def decrypt(self, encrypted_data):
        print(self, encrypted_data);
        return self.cipher.decrypt(encrypted_data.encode()).decode()

crypto = Crypto()
