from kafka import KafkaProducer
import redis
import json
import os
import logging
import time

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka-kraft:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "questions")

def main():
    logger.info("Starting Redis to Kafka bridge...")
    redis_client = redis.Redis(
        host=REDIS_HOST, port=REDIS_PORT,
        password=REDIS_PASSWORD if REDIS_PASSWORD else None,
        decode_responses=True
    )
    for i in range(30):
        try:
            redis_client.ping()
            logger.info("Connected to Redis")
            break
        except:
            logger.info(f"Waiting for Redis... ({i+1}/30)")
            time.sleep(5)
    else:
        logger.error("Failed to connect to Redis")
        return

    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP,
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        retries=5, acks='all'
    )
    logger.info(f"Connected to Kafka: {KAFKA_BOOTSTRAP}")

    count = 0
    try:
        while True:
            message = redis_client.rpop("questions:queue")
            if message:
                try:
                    data = json.loads(message)
                    future = producer.send(KAFKA_TOPIC, value=data)
                    meta = future.get(timeout=10)
                    count += 1
                    logger.info(f"Sent {data['id']} to Kafka (partition={meta.partition}, offset={meta.offset}) [total: {count}]")
                except Exception as e:
                    logger.error(f"Error: {e}")
                    redis_client.lpush("questions:queue", message)
                    time.sleep(1)
            else:
                time.sleep(0.5)
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        producer.close()

if __name__ == "__main__":
    main()
