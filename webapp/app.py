import requests
from flask import Flask, render_template, jsonify, request

app = Flask(__name__)
GO_SERVICE_URL = "http://localhost:8080"

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/status')
def get_status():
    try:
        response = requests.get(f"{GO_SERVICE_URL}/status")
        response.raise_for_status()
        return jsonify(response.json())
    except requests.exceptions.RequestException:
        return jsonify({"error": "P2P service is not reachable"}), 500

@app.route('/api/broadcast_tx', methods=['POST'])
def broadcast_tx():
    try:
        tx_data = request.get_json()
        headers = {'Content-Type': 'application/json'}
        response = requests.post(f"{GO_SERVICE_URL}/broadcast_tx", json=tx_data, headers=headers)
        if response.status_code != 200:
             return jsonify({"status": "error", "message": response.text}), response.status_code
        return jsonify({"status": "success", "message": "Transaction broadcasted"}), 200
    except Exception as e:
        return jsonify({"status": "error", "message": "Failed to broadcast tx"}), 500
