from fastapi import FastAPI, HTTPException
from schemas import ShortenRequest
import hashlib
import boto3
import json
import os
from fastapi.responses import RedirectResponse

app = FastAPI()
@app.get("/health")
def health():
    return {"status": "ok"}


dynamodb = boto3.resource("dynamodb", region_name="eu-central-1")
table = dynamodb.Table("urls")
db = {}


def generate_code(url: str) -> str:
    return hashlib.md5(url.encode()).hexdigest()[:7]

@app.post("/shorten")
def shorten(req: ShortenRequest):
    code = generate_code(req.url)
    table.put_item(Item={
        "code": code,
        "url": req.url,
        "hits": 0
    })

    s3 = boto3.client("s3")
    print(f"Uploading to S3 bucket: {os.getenv('S3_BUCKET')}")
    s3.put_object(
        Bucket=os.getenv("S3_BUCKET"),
        Key=f"{code}.json",
        Body=json.dumps({"url": req.url, "code": code})
    )

    print(f"Uploaded successfully")

    return {"code": code, "short_url": f"/r/{code}"}

@app.get("/r/{code}")
def redirect(code: str):
    resp = table.get_item(Key={"code": code})
    item = resp.get("Item")
    if item is None:
        raise HTTPException(status_code=404)
    else:
        table.update_item(
            Key={"code": code},
            UpdateExpression="ADD hits :inc",
            ExpressionAttributeValues={":inc": 1})
        return RedirectResponse(url=item["url"], status_code=302)


@app.get("/stats/{code}")
def get_stats(code: str):
    resp = table.get_item(Key={"code": code})
    item = resp.get("Item")
    if item is None:
        raise HTTPException(status_code=404)
    else:
        return {"code": code, "hits": item["hits"], "url" : item["url"]}