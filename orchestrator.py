
import os
import subprocess
from flask import Flask, jsonify, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

SETUP_LOCK_FILE = "/app/config/setup.complete"

@app.route("/api/status", methods=["GET"])
def get_status():
    if os.path.exists(SETUP_LOCK_FILE):
        return jsonify({"status": "complete"})
    else:
        return jsonify({"status": "incomplete"})

@app.route("/api/initialize", methods=["POST"])
def initialize():
    if os.path.exists(SETUP_LOCK_FILE):
        return jsonify({"message": "Setup is already complete."}), 400

    script_path = "/app/initialize_postgres.sh"
    if not os.path.exists(script_path):
        return jsonify({"error": "Initialization script not found."}), 500

    try:
        # Ensure the script is executable
        subprocess.run(["chmod", "+x", script_path], check=True)
        
        # Run the script
        result = subprocess.run([script_path], capture_output=True, text=True)

        if result.returncode == 0:
            # Create the lock file on success
            with open(SETUP_LOCK_FILE, "w") as f:
                f.write("complete")
            return jsonify({"message": "Initialization successful."})
        else:
            # Return the error output from the script
            return jsonify({
                "error": "Initialization script failed.",
                "stdout": result.stdout,
                "stderr": result.stderr
            }), 400
    except subprocess.CalledProcessError as e:
        return jsonify({
            "error": "Failed to execute initialization script.",
            "details": str(e)
        }), 500
    except Exception as e:
        return jsonify({"error": f"An unexpected error occurred: {str(e)}"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
