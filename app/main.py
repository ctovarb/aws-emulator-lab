import json
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Dict

import boto3
from botocore.config import Config
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="Order Processor Service", version="1.0.0")

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
S3_BUCKET = os.getenv("S3_BUCKET_NAME", "order-processor-local-documents")
DYNAMODB_TABLE = os.getenv("DYNAMODB_TABLE_NAME", "order-processor-local-orders")
SQS_QUEUE_NAME = os.getenv("SQS_QUEUE_NAME", "order-processor-local-orders-queue")
SECRET_NAME = os.getenv("SECRET_NAME", "order-processor/local/app-config")

# Forzamos path-style en S3 para evitar que boto3 anteponga el nombre del bucket al host
boto_config = Config(
    region_name=AWS_REGION,
    s3={"addressing_style": "path"},
    retries={"max_attempts": 3, "mode": "standard"},
)


def get_clients() -> Dict[str, Any]:
    return {
        "s3": boto3.client("s3", config=boto_config),
        "dynamodb": boto3.resource("dynamodb", config=boto_config),
        "sqs": boto3.client("sqs", config=boto_config),
        "secretsmanager": boto3.client("secretsmanager", config=boto_config),
        "sts": boto3.client("sts", config=boto_config),
    }


class OrderCreateRequest(BaseModel):
    customer_id: str = Field(..., min_length=3, examples=["cust-9001"])
    item_sku: str = Field(..., min_length=2, examples=["HUSQ-701-FILTER"])
    amount: float = Field(..., gt=0, examples=[149.99])
    notes: str = Field(default="Standard processing")


@app.get("/health")
def health_check():
    """Valida conectividad TLS y firma SigV4 contra STS y Secrets Manager en aws-emulator."""
    try:
        clients = get_clients()
        identity = clients["sts"].get_caller_identity()
        secret_resp = clients["secretsmanager"].get_secret_value(SecretId=SECRET_NAME)
        secret_data = json.loads(secret_resp["SecretString"])
        return {
            "status": "healthy",
            "aws_account": identity.get("Account"),
            "caller_arn": identity.get("Arn"),
            "max_order_retry_config": secret_data.get("max_order_retry"),
        }
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Upstream AWS Emulator error: {str(exc)}")


@app.post("/orders", status_code=201)
def create_order(payload: OrderCreateRequest):
    """Persiste recibo en S3, guarda metadatos en DynamoDB y encola evento en SQS."""
    try:
        clients = get_clients()
        order_id = f"ord-{uuid.uuid4().hex[:10]}"
        created_at = datetime.now(timezone.utc).isoformat()
        s3_key = f"receipts/{payload.customer_id}/{order_id}.json"

        order_record = {
            "order_id": order_id,
            "customer_id": payload.customer_id,
            "item_sku": payload.item_sku,
            "amount": str(payload.amount),
            "notes": payload.notes,
            "s3_receipt_key": s3_key,
            "status": "QUEUED",
            "created_at": created_at,
        }

        # 1. Guardar documento JSON en S3
        clients["s3"].put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(order_record, indent=2).encode("utf-8"),
            ContentType="application/json",
        )

        # 2. Guardar registro en DynamoDB
        table = clients["dynamodb"].Table(DYNAMODB_TABLE)
        table.put_item(Item=order_record)

        # 3. Resolver QueueUrl dinámicamente y publicar mensaje en SQS
        queue_url = clients["sqs"].get_queue_url(QueueName=SQS_QUEUE_NAME)["QueueUrl"]
        sqs_resp = clients["sqs"].send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps({"order_id": order_id, "customer_id": payload.customer_id}),
        )

        return {
            "order_id": order_id,
            "status": "QUEUED",
            "s3_key": s3_key,
            "sqs_message_id": sqs_resp.get("MessageId"),
            "created_at": created_at,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Order pipeline failure: {str(exc)}")


@app.get("/orders/{order_id}")
def get_order(order_id: str):
    """Recupera la orden desde DynamoDB y descarga el recibo almacenado en S3."""
    try:
        clients = get_clients()
        table = clients["dynamodb"].Table(DYNAMODB_TABLE)
        resp = table.get_item(Key={"order_id": order_id})

        if "Item" not in resp:
            raise HTTPException(status_code=404, detail="Order not found")

        item = resp["Item"]
        s3_obj = clients["s3"].get_object(Bucket=S3_BUCKET, Key=item["s3_receipt_key"])
        receipt_content = json.loads(s3_obj["Body"].read().decode("utf-8"))

        return {
            "metadata": item,
            "s3_receipt": receipt_content,
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed retrieving order: {str(exc)}")
