from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from flask_bcrypt import Bcrypt
import jwt
import datetime
from functools import wraps
from dotenv import load_dotenv
import os
from crypto_utils import crypto
import json

load_dotenv()
app = Flask(__name__)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY')
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
CORS(app)
bcrypt = Bcrypt(app)


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


@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    email = data.get('email')
    password = data.get('password')
    device_id = data.get('device_id')
    if User.query.filter_by(email=email).first():
        return jsonify({"status": "error", "message": "Email already registered"}), 400
    if User.query.filter_by(device_id=device_id).first():
        return jsonify({"status": "error", "message": "Device ID already registered"}), 400
    hashed_password = bcrypt.generate_password_hash(password).decode('utf-8')
    new_user = User(email=email, device_id=device_id, password=hashed_password)
    db.session.add(new_user)
    db.session.commit()
    return jsonify({"status": "success", "message": "User registered"}), 201


@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    user = User.query.filter_by(email=data.get('email')).first()
    if user and bcrypt.check_password_hash(user.password, data.get('password')):
        token = jwt.encode({
            'email': user.email,
            'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=24)
        }, app.config['SECRET_KEY'], algorithm="HS256")
        return jsonify({"status": "success", "token": token, "device_id": user.device_id, "is_stolen": user.is_stolen})
    return jsonify({"status": "error", "message": "Invalid credentials"}), 401


@app.route('/update', methods=['POST'])
@token_required
def receive_update(current_user):
    encrypted_data = request.json.get('data')
    try:
        print(f"Encrypted data: {encrypted_data}")
        decrypted = crypto.decrypt(encrypted_data)
        print(f"Decrypted data: {decrypted}")

        parts = decrypted.split(',')
        device_id, lat, lon, ts = parts[0:4]
        is_theft = len(parts) > 4 and parts[4] == "theft"

        if device_id != current_user.device_id:
            return jsonify({"status": "error", "message": "Device ID mismatch"}), 403

        timestamp = datetime.datetime.fromisoformat(ts.replace('Z', '+00:00'))

        location = Location(
            device_id=device_id,
            latitude=float(lat),
            longitude=float(lon),
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


@app.route('/report-stolen', methods=['POST'])
@token_required
def report_stolen(current_user):
    current_user.is_stolen = True
    db.session.commit()
    return jsonify({"status": "success", "message": "Device marked as stolen"}), 200


@app.route('/check-stolen/<device_id>', methods=['GET'])
def check_stolen(device_id):
    user = User.query.filter_by(device_id=device_id).first()
    if user and user.is_stolen:
        return jsonify({"status": "stolen", "device_id": device_id}), 200
    return jsonify({"status": "not_stolen", "device_id": device_id}), 200


if __name__ == "__main__":
    with app.app_context():
        db.create_all()  # Use drop_all() only if resetting
    app.run(debug=True, host='0.0.0.0', port=5000)