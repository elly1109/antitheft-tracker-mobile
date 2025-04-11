from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
import base64
import os
from dotenv import load_dotenv

load_dotenv()
ENCRYPTION_KEY = os.getenv('ENCRYPTION_KEY', '').ljust(32, '\0')[:32].encode('utf-8')  # Ensure 32 bytes

class Crypto:
    def __init__(self):
        self.key = ENCRYPTION_KEY

    def encrypt(self, data):
        iv = os.urandom(16)  # 16-byte IV
        cipher = AES.new(self.key, AES.MODE_CBC, iv=iv)
        padded_data = pad(data.encode('utf-8'), AES.block_size, style='pkcs7')
        encrypted = cipher.encrypt(padded_data)
        return base64.b64encode(iv + encrypted).decode('utf-8')

    def decrypt(self, encrypted_data):
        raw = base64.b64decode(encrypted_data)
        iv = raw[:16]  # First 16 bytes are IV
        encrypted = raw[16:]
        cipher = AES.new(self.key, AES.MODE_CBC, iv=iv)
        decrypted = unpad(cipher.decrypt(encrypted), AES.block_size, style='pkcs7')
        return decrypted.decode('utf-8')

crypto = Crypto()