import boto3, json, time, os

sqs = boto3.client("sqs")
QUEUE_URL = os.getenv("QUEUE_URL")


def poll():
    while True:
        resp = sqs.receive_message(
            QueueUrl=QUEUE_URL, MaxNumberOfMessages=5, WaitTimeSeconds=10
        )
        for msg in resp.get("Messages", []):
            body = json.loads(msg["Body"])
            # In production this would send an email/push notification.
            # For now we log the event so the service stays healthy.
            print(f"[notification-service] OrderCreated event received: {body}")
            sqs.delete_message(
                QueueUrl=QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"]
            )
        time.sleep(1)


if __name__ == "__main__":
    poll()
