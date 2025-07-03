
import os
import subprocess
import logging
from flask import Flask, jsonify, request
from flask_cors import CORS
from dotenv import load_dotenv

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Load environment variables from .env file
load_dotenv("/app/config/.env")

app = Flask(__name__)
CORS(app)

SETUP_LOCK_FILE = "/app/config/setup.complete"

def check_db_connection(host, user, password):
    """Checks if a connection to the database can be established."""
    try:
        # Use pg_isready to check the connection without needing the database name
        logging.info(f"Attempting to connect to database host: {host}")
        result = subprocess.run(
            ["pg_isready", "-h", host, "-U", user],
            check=True,
            capture_output=True,
            text=True,
            # Pass the password via environment variable for security
            env=dict(os.environ, PGPASSWORD=password),
        )
        logging.info(f"Successfully connected to {host}.")
        logging.info(f"pg_isready output: {result.stdout}")
        return True
    except subprocess.CalledProcessError as e:
        logging.warning(f"Failed to connect to {host}: {e.stderr}")
        return False
    except FileNotFoundError:
        logging.error("pg_isready command not found. Please ensure postgresql-client is installed.")
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
        logging.info("Initialization endpoint called, but setup is already complete.")
        return jsonify({"message": "Setup is already complete."}), 400

    logging.info("Initialization process started.")
    script_path = "/app/initialize_postgres.sh"
    if not os.path.exists(script_path):
        logging.error("Initialization script not found at %s.", script_path)
        return jsonify({"error": "Initialization script not found."}), 500

    # Get database credentials from environment variables
    db_user = os.getenv("POSTGRES_USER")
    db_password = os.getenv("POSTGRES_PASSWORD")

    if not db_user or not db_password:
        logging.error("Database credentials (POSTGRES_USER, POSTGRES_PASSWORD) not found.")
        return jsonify({"error": "Database credentials not found in environment variables."}), 500

    # Determine the correct database host
    db_host = None
    if check_db_connection("komodo-postgres-1", db_user, db_password):
        db_host = "komodo-postgres-1"
    elif check_db_connection("pangolin-postgres", db_user, db_password):
        db_host = "pangolin-postgres"

    if not db_host:
        logging.error("Could not connect to any of the specified database hosts.")
        return jsonify({"error": "Could not connect to any of the specified database hosts."}), 500

    logging.info(f"Selected database host: {db_host}")

    try:
        # Ensure the script is executable
        subprocess.run(["chmod", "+x", script_path], check=True)
        
        # Run the script with the determined host
        logging.info(f"Executing script: {script_path} with host {db_host}")
        result = subprocess.run(
            [script_path, db_host],
            capture_output=True,
            text=True,
            env=dict(os.environ, PGPASSWORD=db_password),
        )

        # Log the output from the script
        if result.stdout:
            logging.info("Script stdout:\n%s", result.stdout)
        if result.stderr:
            logging.error("Script stderr:\n%s", result.stderr)

        if result.returncode == 0:
            # Create the lock file on success
            with open(SETUP_LOCK_FILE, "w") as f:
                f.write("complete")
            logging.info("Initialization successful. Lock file created.")
            return jsonify({"message": "Initialization successful.", "output": result.stdout})
        else:
            # Return the error output from the script
            logging.error("Initialization script failed.")
            return jsonify({
                "error": "Initialization script failed.",
                "stdout": result.stdout,
                "stderr": result.stderr
            }), 400
    except subprocess.CalledProcessError as e:
        logging.error("Failed to execute initialization script: %s", e)
        return jsonify({
            "error": "Failed to execute initialization script.",
            "details": str(e)
        }), 500
    except Exception as e:
        logging.error("An unexpected error occurred: %s", e)
        return jsonify({"error": f"An unexpected error occurred: {str(e)}"}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
