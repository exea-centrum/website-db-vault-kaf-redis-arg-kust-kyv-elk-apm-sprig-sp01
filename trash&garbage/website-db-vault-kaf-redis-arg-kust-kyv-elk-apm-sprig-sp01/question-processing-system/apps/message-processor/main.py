from kafka import KafkaConsumer
import psycopg2
import json
import os
import logging
import time

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "questions")
KAFKA_GROUP = os.getenv("KAFKA_GROUP_ID", "question-processor")
PG_HOST = os.getenv("POSTGRES_HOST", "postgres-db")
PG_PORT = int(os.getenv("POSTGRES_PORT", 5432))
PG_DB = os.getenv("POSTGRES_DB", "questions_db")
PG_USER = os.getenv("POSTGRES_USER", "postgres")
PG_PASS = os.getenv("POSTGRES_PASSWORD", "postgres")

def init_db():
    try:
        conn = psycopg2.connect(host=PG_HOST, port=PG_PORT, database=PG_DB, user=PG_USER, password=PG_PASS)
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS questions (
                id VARCHAR(50) PRIMARY KEY,
                content TEXT NOT NULL,
                author VARCHAR(255) NOT NULL,
                timestamp TIMESTAMP NOT NULL,
                status VARCHAR(50) DEFAULT 'processed',
                processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        cur.close()
        conn.close()
        logger.info("Database initialized")
        return True
    except Exception as e:
        logger.error(f"DB init failed: {e}")
        return False

def save_to_postgres(data):
    try:
        conn = psycopg2.connect(host=PG_HOST, port=PG_PORT, database=PG_DB, user=PG_USER, password=PG_PASS)
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO questions (id, content, author, timestamp, status)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, processed_at = CURRENT_TIMESTAMP
        """, (data['id'], data['content'], data['author'], data['timestamp'], 'processed'))
        conn.commit()
        cur.close()
        conn.close()
        logger.info(f"Saved {data['id']} to PostgreSQL")
        return True
    except Exception as e:
        logger.error(f"Save failed: {e}")
        return False

def main():
    logger.info("Starting message processor...")
    for i in range(30):
        if init_db():
            break
        logger.info(f"Waiting for DB... ({i+1}/30)")
        time.sleep(5)
    else:
        return

    consumer = KafkaConsumer(
        KAFKA_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP,
        group_id=KAFKA_GROUP,
        auto_offset_reset='earliest',
        enable_auto_commit=True,
        value_deserializer=lambda m: json.loads(m.decode('utf-8'))
    )
    logger.info(f"Connected to Kafka topic: {KAFKA_TOPIC}")

    count = 0
    try:
        for message in consumer:
            try:
                data = message.value
                if save_to_postgres(data):
                    count += 1
                    logger.info(f"Processed {count} questions")
            except Exception as e:
                logger.error(f"Error: {e}")
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        consumer.close()

if __name__ == "__main__":
    main()
