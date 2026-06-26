import json, os
import firebase_admin
from firebase_admin import credentials

# Singleton Firebase Admin app — initialize once at process start.
if not firebase_admin._apps:
    firebase_admin.initialize_app(
        credentials.Certificate(json.loads(os.environ["FIREBASE_SERVICE_ACCOUNT"]))
    )
