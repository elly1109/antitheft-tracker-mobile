from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_cors import CORS
from flask_bcrypt import Bcrypt
from crypto_utils import crypto
import jwt
import datetime
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

app = Flask(__name__)
CORS(app)  # Allow all origins for development
bcrypt = Bcrypt(app)

# PostgreSQL configuration
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

SECRET_KEY = os.getenv('SECRET_KEY')


# User model for authentication
class User(db.Model):
    __tablename__ = 'users'
    id = db.Column(db.Integer, primary_key=True)
    device_id = db.Column(db.String(50), unique=True, nullable=False)
    password = db.Column(db.String(100), nullable=False)  # In production, hash this


# Location model
class Location(db.Model):
    __tablename__ = 'locations'
    id = db.Column(db.Integer, primary_key=True)
    device_id = db.Column(db.String(50), nullable=False)
    latitude = db.Column(db.Float, nullable=False)
    longitude = db.Column(db.Float, nullable=False)
    timestamp = db.Column(db.String(50), nullable=False)


# Initialize the database
with app.app_context():
    db.create_all()


# Token required decorator
def token_required(f):
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token or not token.startswith('Bearer '):
            return jsonify({"status": "error", "message": "Token missing"}), 401
        token = token.split(" ")[1]
        try:
            data = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
            current_user = User.query.filter_by(device_id=data['device_id']).first()
            if not current_user:
                return jsonify({"status": "error", "message": "User not found"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"status": "error", "message": "Invalid token"}), 401
        return f(current_user, *args, **kwargs)

    decorated.__name__ = f.__name__
    return decorated


# Registration route
@app.route('/register', methods=['POST'])
def register():
    """Register a new user."""
    data = request.json
    device_id = data.get('device_id')
    password = data.get('password')
    if not device_id or not password:
        return jsonify({"status": "error", "message": "Device ID and password required"}), 400
    if User.query.filter_by(device_id=device_id).first():
        return jsonify({"status": "error", "message": "Device ID already registered"}), 400
    hashed_password = bcrypt.generate_password_hash(password).decode('utf-8')
    new_user = User(device_id=device_id, password=hashed_password)
    db.session.add(new_user)
    db.session.commit()
    return jsonify({"status": "success", "message": "User registered successfully"}), 201


# Login route
@app.route('/login', methods=['POST'])
def login():
    """Authenticate user and return JWT."""
    data = request.json
    device_id = data.get('device_id')
    password = data.get('password')
    user = User.query.filter_by(device_id=device_id).first()
    if not user or not bcrypt.check_password_hash(user.password, password):
        return jsonify({"status": "error", "message": "Invalid credentials"}), 401
    token = jwt.encode({
        'device_id': user.device_id,
        'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=24)
    }, SECRET_KEY, algorithm="HS256")
    return jsonify({"token": token}), 200


# Update location route
@app.route('/update', methods=['POST'])
@token_required
def receive_update(current_user):
    """Receive encrypted location data from authenticated user."""
    encrypted_data = request.json.get('data')

    try:
        decrypted = crypto.decrypt(encrypted_data)

        print(encrypted_data)

        device_id, lat, lon, ts = decrypted.split(',')
        if device_id != current_user.device_id:
            return jsonify({"status": "error", "message": "Device ID mismatch"}), 403
        location = Location(device_id=device_id, latitude=float(lat), longitude=float(lon), timestamp=ts)
        db.session.add(location)
        db.session.commit()
        return jsonify({"status": "success"}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({"status": "error", "message": str(e)}), 400

# Latest location route
@app.route('/latest', methods=['GET'])
def get_latest_location():
    """Return the latest location as JSON."""
    location = Location.query.order_by(Location.timestamp.desc()).first()
    if location:
        return jsonify({"device_id": location.device_id, "latitude": location.latitude, "longitude": location.longitude,
                        "timestamp": location.timestamp}), 200
    return jsonify({"status": "error", "message": "No location data"}), 404


@app.route('/predict', methods=['GET'])
@token_required
def predict_location(current_user):
    # Get last two locations to estimate speed and direction
    locations = Location.query.filter_by(device_id=current_user.device_id)\
        .order_by(Location.timestamp.desc()).limit(2).all()
    if len(locations) < 1:
        return jsonify({"status": "error", "message": "Insufficient data"}), 400

    latest = locations[0]
    if len(locations) == 1:
        # No movement data, return last known location
        return jsonify({
            "status": "success",
            "predicted_latitude": latest.latitude,
            "predicted_longitude": latest.longitude,
            "confidence": 0.5
        })

    # Calculate speed and direction from last two points
    prev = locations[1]
    time_diff = (latest.timestamp - prev.timestamp).total_seconds() / 3600  # hours
    if time_diff == 0:
        return jsonify({"status": "error", "message": "Invalid time difference"}), 400

    lat_diff = latest.latitude - prev.latitude
    lon_diff = latest.longitude - prev.longitude
    speed_lat = lat_diff / time_diff  # degrees/hour
    speed_lon = lon_diff / time_diff  # degrees/hour

    # Predict location 1 hour from latest (simplified linear extrapolation)
    elapsed_hours = 1.0  # Predict 1 hour ahead
    predicted_lat = latest.latitude + speed_lat * elapsed_hours
    predicted_lon = latest.longitude + speed_lon * elapsed_hours

    return jsonify({
        "status": "success",
        "predicted_latitude": predicted_lat,
        "predicted_longitude": predicted_lon,
        "confidence": 0.8,  # Arbitrary confidence for now
        "based_on": {
            "last_latitude": latest.latitude,
            "last_longitude": latest.longitude,
            "last_timestamp": latest.timestamp.isoformat()
        }
    })


if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=5000)