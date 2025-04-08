import asyncpg
import os
DB_USER = os.getenv("POSTGRES_USER", "myuser")
DB_PASSWORD = os.getenv("POSTGRES_PASSWORD", "mypassword")
DB_NAME = os.getenv("POSTGRES_DB", "chatbot")
DB_HOST = os.getenv("POSTGRES_HOST", "localhost")

async def get_db_connection():
    return await asyncpg.connect(
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        host=DB_HOST
    )
