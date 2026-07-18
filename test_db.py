import boto3
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table = dynamodb.Table('orderflow-inventory-dev')
item = table.get_item(Key={"sku": "MacBook-Pro-M3"}).get("Item")
print("ITEM:", item)
if item and item["stock"] >= 1:
    print("Greater than or equal")
else:
    print("Not greater")
