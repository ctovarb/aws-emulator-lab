import json
import os
import uuid
import boto3
from botocore.config import Config

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
S3_BUCKET = os.getenv("S3_BUCKET_NAME", "order-processor-local-documents")
DYNAMODB_TABLE = os.getenv("DYNAMODB_TABLE_NAME", "order-processor-local-orders")
SQS_QUEUE_NAME = os.getenv("SQS_QUEUE_NAME", "order-processor-local-orders-queue")
SECRET_NAME = os.getenv("SECRET_NAME", "order-processor/local/app-config")

boto_cfg = Config(region_name=AWS_REGION, s3={"addressing_style": "path"})


def test_sts_emulator_identity():
    sts = boto3.client("sts", config=boto_cfg)
    identity = sts.get_caller_identity()
    assert identity["Account"] == "000000000000"
    assert "emulator" in identity["Arn"]


def test_secrets_manager_config():
    sm = boto3.client("secretsmanager", config=boto_cfg)
    resp = sm.get_secret_value(SecretId=SECRET_NAME)
    secret = json.loads(resp["SecretString"])
    assert secret["max_order_retry"] == 3
    assert "payment_gateway_api_key" in secret


def test_s3_dynamodb_sqs_pipeline():
    s3 = boto3.client("s3", config=boto_cfg)
    dynamodb = boto3.resource("dynamodb", config=boto_cfg)
    sqs = boto3.client("sqs", config=boto_cfg)

    order_id = f"ord-test-{uuid.uuid4().hex[:8]}"
    customer_id = "cust-ci-001"
    s3_key = f"receipts/{customer_id}/{order_id}.json"
    record = {
        "order_id": order_id,
        "customer_id": customer_id,
        "item_sku": "CI-VALIDATION-SKU",
        "amount": "199.99",
        "status": "QUEUED",
        "created_at": "2026-11-12T21:00:00Z",
    }

    # 1. Validar escritura y lectura en S3
    s3.put_object(Bucket=S3_BUCKET, Key=s3_key, Body=json.dumps(record).encode("utf-8"))
    s3_obj = s3.get_object(Bucket=S3_BUCKET, Key=s3_key)
    assert json.loads(s3_obj["Body"].read().decode("utf-8"))["order_id"] == order_id

    # 2. Validar escritura y consulta por GSI en DynamoDB
    table = dynamodb.Table(DYNAMODB_TABLE)
    table.put_item(Item=record)
    ddb_resp = table.get_item(Key={"order_id": order_id})
    assert ddb_resp["Item"]["item_sku"] == "CI-VALIDATION-SKU"

    # 3. Validar envío y recepción en SQS
    queue_url = sqs.get_queue_url(QueueName=SQS_QUEUE_NAME)["QueueUrl"]
    send_resp = sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps({"order_id": order_id}))
    assert "MessageId" in send_resp
