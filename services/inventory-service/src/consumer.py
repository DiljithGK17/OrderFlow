import boto3, json, time
import os

sqs = boto3.client("sqs")
dynamodb = boto3.resource("dynamodb")
inventory_table = dynamodb.Table(os.getenv("INVENTORY_TABLE_NAME", "orderflow-inventory-dev"))
QUEUE_URL = os.getenv("QUEUE_URL")

def poll():
    while True:
        resp = sqs.receive_message(QueueUrl=QUEUE_URL, MaxNumberOfMessages=5, WaitTimeSeconds=10)
        for msg in resp.get("Messages", []):
            body = json.loads(msg["Body"])
            item = inventory_table.get_item(Key={"sku": body["sku"]}).get("Item")
            if item and item["stock"] >= body["quantity"]:
                inventory_table.update_item(
                    Key={"sku": body["sku"]},
                    UpdateExpression="SET stock = stock - :q",
                    ExpressionAttributeValues={":q": body["quantity"]}
                )
            sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=msg["ReceiptHandle"])
        time.sleep(1)

if __name__ == "__main__":
    poll()
