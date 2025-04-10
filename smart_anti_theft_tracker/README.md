# Smart Anti-Theft Device Tracker

A Flask-based simulation of a phone anti-theft system that tracks a device even when powered off using a crowdsourced network.

## Setup
1. Clone the repo: `git clone <repo-url>`
2. Create a virtual environment: `python3 -m venv venv`
3. Activate it: `source venv/bin/activate`
4. Install dependencies: `pip install -r requirements.txt`
5. Run the app: `python app.py`

## Usage
- Visit `http://127.0.0.1:5000` to see the tracker UI.
- The simulation runs in the background, updating the location every 10 seconds.

## Future Steps
- Integrate real GPS/Bluetooth hardware.
- Deploy to a cloud server (e.g., AWS).
