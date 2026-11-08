import os

from flask import Flask, jsonify
from pymongo import MongoClient
from redis import Redis

from .routes import api


def create_app() -> Flask:
    app = Flask(__name__)
    app.config.from_mapping(
        FLASK_SECRET_KEY=os.environ["FLASK_SECRET_KEY"],
        MONGO_URI=os.environ["MONGO_URI"],
        MONGO_DATABASE=os.environ["MONGO_DATABASE"],
        REDIS_URL=os.environ["REDIS_URL"],
    )

    app.extensions["mongo_client"] = MongoClient(
        app.config["MONGO_URI"], serverSelectionTimeoutMS=3000
    )
    app.extensions["redis_client"] = Redis.from_url(
        app.config["REDIS_URL"], decode_responses=True, socket_connect_timeout=3
    )

    app.register_blueprint(api, url_prefix="/api")

    @app.get("/")
    def index():
        return jsonify({"servico": "JurisDocs API", "status": "ok"})

    return app
