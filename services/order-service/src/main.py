from fastapi import FastAPI, Request
import boto3, uuid, time, json
from prometheus_client import Counter, Histogram, make_asgi_app
import os

app = FastAPI()
app.mount("/metrics", make_asgi_app())

dynamodb = boto3.resource("dynamodb")
orders_table = dynamodb.Table(os.getenv("ORDERS_TABLE_NAME", "orderflow-orders-dev"))
idempotency_table = dynamodb.Table(os.getenv("IDEMPOTENCY_TABLE_NAME", "orderflow-idempotency-dev"))
sns = boto3.client("sns")

ORDERS_CREATED = Counter("orders_created_total", "Total orders created")
REQUEST_LATENCY = Histogram("order_request_latency_seconds", "Order request latency")

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.post("/orders")
def create_order(payload: dict, request: Request):
    request_id = request.headers.get("Idempotency-Key", str(uuid.uuid4()))

    existing = idempotency_table.get_item(Key={"requestId": request_id}).get("Item")
    if existing:
        return {"orderId": existing["orderId"], "status": "duplicate-ignored"}

    order_id = str(uuid.uuid4())
    with REQUEST_LATENCY.time():
        orders_table.put_item(Item={
            "orderId": order_id, "customerId": payload["customerId"],
            "sku": payload["sku"], "quantity": payload["quantity"],
            "status": "PENDING", "createdAt": int(time.time())
        })
        idempotency_table.put_item(Item={
            "requestId": request_id, "orderId": order_id,
            "expiresAt": int(time.time()) + 86400
        })
        sns.publish(
            TopicArn=os.getenv("SNS_TOPIC_ARN"),
            Message=json.dumps({"orderId": order_id, "sku": payload["sku"], "quantity": payload["quantity"]}),
            MessageAttributes={"eventType": {"DataType": "String", "StringValue": "OrderCreated"}}
        )
    ORDERS_CREATED.inc()
    return {"orderId": order_id, "status": "PENDING"}
