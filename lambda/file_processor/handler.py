import boto3
import os
import json
import time

region = os.environ.get("AWS_DEFAULT_REGION", "eu-central-1")

dynamodb = boto3.resource("dynamodb", region_name=region)
sqs = boto3.client("sqs", region_name=region)
s3 = boto3.client("s3", region_name=region)
table = dynamodb.Table(os.getenv("DYNAMODB_TABLE", "files"))
queue_url = os.getenv("SQS_QUEUE_URL", "")

def handler(event, context):
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        response = s3.get_object(Bucket=bucket, Key=key)
        body = json.loads(response["Body"].read())
        url = body["url"]
        code = body["code"]

        table.put_item(Item={
            "file_key": code,
            "url": url,
            "status": "pending",
            "uploaded_at": int(time.time()),
        })

        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps({"url": url, "code": code}),
        )
        print(f"Queued {code} for processing")

    return {"statusCode": 200}
