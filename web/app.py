import os
import logging
from flask import Flask, jsonify
import mysql.connector
from mysql.connector import Error

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)


def get_db_connection():
    return mysql.connector.connect(
        host=os.environ.get("DB_HOST", "db"),
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
        connection_timeout=5,
    )


@app.route("/")
def index():
    return jsonify({
        "status": "ok",
        "message": "Multi-container Flask + MySQL app running on Docker Compose",
        "endpoints": ["/health", "/users", "/users/<id>"],
    })


@app.route("/health")
def health():
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({"status": "healthy", "database": "connected"}), 200
    except Error as exc:
        logger.error("DB health check failed: %s", exc)
        return jsonify({"status": "unhealthy", "database": "unreachable"}), 503


@app.route("/users")
def list_users():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT id, name, email, created_at FROM users")
        rows = cursor.fetchall()
        cursor.close()
        conn.close()
        for row in rows:
            if row.get("created_at"):
                row["created_at"] = row["created_at"].isoformat()
        return jsonify({"count": len(rows), "users": rows})
    except Error as exc:
        logger.error("Failed to fetch users: %s", exc)
        return jsonify({"error": "Database error"}), 500


@app.route("/users/<int:user_id>")
def get_user(user_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT id, name, email, created_at FROM users WHERE id = %s",
            (user_id,),
        )
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if row is None:
            return jsonify({"error": "User not found"}), 404
        if row.get("created_at"):
            row["created_at"] = row["created_at"].isoformat()
        return jsonify(row)
    except Error as exc:
        logger.error("Failed to fetch user %d: %s", user_id, exc)
        return jsonify({"error": "Database error"}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
