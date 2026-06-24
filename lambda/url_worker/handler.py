import boto3
import os
import json
import urllib.request
from html.parser import HTMLParser

region = os.environ.get("AWS_DEFAULT_REGION", "eu-central-1")

dynamodb = boto3.resource("dynamodb", region_name=region)
table = dynamodb.Table(os.getenv("DYNAMODB_TABLE", "files"))


class MetaParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = None
        self.description = None
        self.in_title = False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "title":
            self.in_title = True
        if tag == "meta":
            if attrs.get("name") == "description":
                self.description = attrs.get("content")
            if attrs.get("property") == "og:description" and not self.description:
                self.description = attrs.get("content")

    def handle_data(self, data):
        if self.in_title and not self.title:
            self.title = data.strip()

    def handle_endtag(self, tag):
        if tag == "title":
            self.in_title = False


def fetch_meta(url: str):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            html = resp.read(50000).decode("utf-8", errors="ignore")
        parser = MetaParser()
        parser.feed(html)
        return parser.title, parser.description
    except Exception as e:
        print(f"Failed to fetch meta for {url}: {e}")
        return None, None


def handler(event, context):
    for record in event["Records"]:
        body = json.loads(record["body"])
        url = body.get("url")
        code = body.get("code")
        title, description = fetch_meta(url)
        table.update_item(
            Key={"file_key": code},
            UpdateExpression="SET #s = :s, title = :t, description = :d",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":s": "processed",
                ":t": title or "",
                ":d": description or "",
            },
        )
        print(f"Updated meta for {code}: {title}")
    return {"statusCode": 200}
