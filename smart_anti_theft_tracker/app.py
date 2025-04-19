from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_bcrypt import Bcrypt
import jwt
import datetime
from functools import wraps
from dotenv import load_dotenv
import os
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
import base64
import json

app = Flask(__name__)
load_dotenv()
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY')
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL', 'sqlite:///antitheft.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
bcrypt = Bcrypt(app)

# AES key setup
ENCRYPTION_KEY = os.getenv('ENCRYPTION_KEY', '').ljust(32, '\0')[:32].encode('utf-8')  # Ensure 32 bytes
if len(ENCRYPTION_KEY) != 32:
    raise ValueError(f"ENCRYPTION_KEY must be 32 bytes, got {len(ENCRYPTION_KEY)} bytes")

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
        try:
            raw = base64.b64decode(encrypted_data)
            iv = raw[:16]  # First 16 bytes are IV
            encrypted = raw[16:]
            cipher = AES.new(self.key, AES.MODE_CBC, iv=iv)
            decrypted = unpad(cipher.decrypt(encrypted), AES.block_size, style='pkcs7')
            return decrypted.decode('utf-8')
        except Exception as e:
            print(f"Decryption error: {str(e)}")
            raise Exception(f"Failed to decrypt data: {str(e)}")

crypto = Crypto()

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), unique=True, nullable=False)
    device_id = db.Column(db.String(50), unique=True, nullable=False)
    password = db.Column(db.String(100), nullable=False)
    is_stolen = db.Column(db.Boolean, default=False)

class Location(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    device_id = db.Column(db.String(50), nullable=False)
    latitude = db.Column(db.Float, nullable=False)
    longitude = db.Column(db.Float, nullable=False)
    timestamp = db.Column(db.DateTime, nullable=False)
    is_theft = db.Column(db.Boolean, default=False)

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token or not token.startswith('Bearer '):
            return jsonify({"status": "error", "message": "Token is missing"}), 401
        try:
            token = token.split(" ")[1]
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=["HS256"])
            current_user = User.query.filter_by(email=data['email']).first()
            if not current_user:
                raise Exception("User not found")
        except Exception as e:
            return jsonify({"status": "error", "message": f"Token is invalid: {str(e)}"}), 401
        return f(current_user, *args, **kwargs)
    return decorated

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    user = User.query.filter_by(email=data.get('email')).first()
    if user and bcrypt.check_password_hash(user.password, data.get('password')):
        token = jwt.encode({
            'email': user.email,
            'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=24)
        }, app.config['SECRET_KEY'], algorithm="HS256")

        return jsonify({
            "status": "success",
            "token": token,
            "device_id": user.device_id,
            "is_stolen": user.is_stolen
        })
    return jsonify({"status": "error", "message": "Invalid credentials"}), 401

@app.route('/update', methods=['POST'])
@token_required
def receive_update(current_user):
    data = request.get_json()

    encrypted_data = data.get('data')

    print(encrypted_data)

    if not encrypted_data:
        return jsonify({"status": "error", "message": "Missing encrypted data"}), 400

    try:
        decrypted_json = crypto.decrypt(encrypted_data)
        decrypted_data = json.loads(decrypted_json)
        print(f"Decrypted data: {decrypted_data}")

        device_id = decrypted_data.get('device_id')
        latitude = decrypted_data.get('latitude')
        longitude = decrypted_data.get('longitude')
        timestamp = decrypted_data.get('timestamp')
        is_theft = decrypted_data.get('is_theft', False)

        if not all([device_id, latitude, longitude, timestamp]):
            return jsonify({"status": "error", "message": "Missing required fields"}), 400

        if device_id != current_user.device_id:
            print(f"Device ID mismatch: received {device_id}, expected {current_user.device_id}")
            return jsonify({"status": "error", "message": "Device ID mismatch"}), 403

        timestamp = datetime.datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        location = Location(
            device_id=device_id,
            latitude=float(latitude),
            longitude=float(longitude),
            timestamp=timestamp,
            is_theft=is_theft
        )
        db.session.add(location)
        db.session.commit()
        return jsonify({"status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        print(f"Error: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 400

@app.route('/latest', methods=['GET'])
@token_required
def get_latest_location(current_user):
    latest_location = Location.query.filter_by(device_id=current_user.device_id) \
        .order_by(Location.timestamp.desc()) \
        .first()
    if latest_location:
        return jsonify({
            "status": "success",
            "device_id": latest_location.device_id,
            "latitude": latest_location.latitude,
            "longitude": latest_location.longitude,
            "timestamp": latest_location.timestamp.isoformat() + "Z",
            "is_theft": latest_location.is_theft
        }), 200
    return jsonify({"status": "error", "message": "No location data available"}), 404

if __name__ == "__main__":
    with app.app_context():
        db.create_all()
    app.run(debug=True, host='0.0.0.0', port=5000)