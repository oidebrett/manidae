
import os
import subprocess
from flask import Flask, jsonify, request
from flask_cors import CORS
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv("/app/config/.env")

app = Flask(__name__)
CORS(app)

SETUP_LOCK_FILE = "/app/config/setup.complete"

def check_db_connection(host, user, password):
    """Checks if a connection to the database can be established."""
    try:
        # Use pg_isready to check the connection without needing the database name
        subprocess.run(
            ["pg_isready", "-h", host, "-U", user],
            check=True,
            capture_output=True,
            text=True,
            # Pass the password via environment variable for security
            env=dict(os.environ, PGPASSWORD=password),
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

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

    # Get database credentials from environment variables
    db_user = os.getenv("POSTGRES_USER")
    db_password = os.getenv("POSTGRES_PASSWORD")

    if not db_user or not db_password:
        return jsonify({"error": "Database credentials not found in environment variables."}), 500

    # Determine the correct database host
    db_host = None
    if check_db_connection("komodo-postgres-1", db_user, db_password):
        db_host = "komodo-postgres-1"
    elif check_db_connection("pangolin-postgres", db_user, db_password):
        db_host = "pangolin-postgres"

    if not db_host:
        return jsonify({"error": "Could not connect to any of the specified database hosts."}), 500

    try:
        # Ensure the script is executable
        subprocess.run(["chmod", "+x", script_path], check=True)
        
        # Run the script with the determined host
        result = subprocess.run(
            [script_path, db_host],
            capture_output=True,
            text=True,
            env=dict(os.environ, PGPASSWORD=db_password),
        )

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
