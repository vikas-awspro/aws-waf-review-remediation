#!/usr/bin/env python3
"""
REL-05 helper — drains the ARAS integration DLQ by re-invoking the
originating Lambda function with the failed event payload.

The Lambda destination is read from the SQS message attribute
`OriginalFunctionArn` set by the producer's destination config. If absent,
the message is left in the queue and logged for human review.

Usage:
    python3 reprocess-dlq.py \
        --queue-url https://sqs.eu-west-1.amazonaws.com/000/aras-integration-dlq-prod \
        --max-messages 100
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Optional

import boto3


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--queue-url", required=True)
    p.add_argument("--max-messages", type=int, default=100,
                   help="Maximum messages to process in this run")
    p.add_argument("--region", default="eu-west-1")
    p.add_argument("--dry-run", action="store_true",
                   help="Print what would be reprocessed without invoking Lambda")
    return p.parse_args()


def get_original_function_arn(msg: dict) -> Optional[str]:
    attrs = msg.get("MessageAttributes", {}) or {}
    for key in ("OriginalFunctionArn", "RequestPayload.functionArn", "X-Amz-Function-Arn"):
        if key in attrs:
            return attrs[key].get("StringValue")
    # Fall back to embedded payload (asyncInvokeConfig.destinationConfig)
    try:
        body = json.loads(msg["Body"])
        return body.get("functionArn") or body.get("requestContext", {}).get("functionArn")
    except (json.JSONDecodeError, KeyError):
        return None


def get_original_payload(msg: dict) -> dict:
    try:
        body = json.loads(msg["Body"])
        # Lambda async invocation DLQ envelope: requestPayload is the original event.
        if "requestPayload" in body:
            return body["requestPayload"]
        return body
    except json.JSONDecodeError:
        return {"raw": msg["Body"]}


def main() -> int:
    args = parse_args()
    sqs = boto3.client("sqs", region_name=args.region)
    lam = boto3.client("lambda", region_name=args.region)

    processed = 0
    skipped = 0
    failed: list[str] = []

    while processed + skipped < args.max_messages:
        batch_size = min(10, args.max_messages - (processed + skipped))
        resp = sqs.receive_message(
            QueueUrl=args.queue_url,
            MaxNumberOfMessages=batch_size,
            MessageAttributeNames=["All"],
            WaitTimeSeconds=2,
            VisibilityTimeout=120,
        )
        msgs = resp.get("Messages", [])
        if not msgs:
            break

        for msg in msgs:
            fn = get_original_function_arn(msg)
            if not fn:
                print(f"  [SKIP] {msg['MessageId']}: no OriginalFunctionArn — leaving in DLQ for review")
                skipped += 1
                continue

            payload = get_original_payload(msg)
            print(f"  [RUN]  {msg['MessageId']} → {fn}")

            if args.dry_run:
                processed += 1
                continue

            try:
                lam.invoke(
                    FunctionName=fn,
                    InvocationType="Event",   # async re-invoke; result goes to the same destinations
                    Payload=json.dumps(payload).encode(),
                )
                sqs.delete_message(QueueUrl=args.queue_url, ReceiptHandle=msg["ReceiptHandle"])
                processed += 1
            except Exception as exc:  # noqa: BLE001
                print(f"    FAILED: {exc}")
                failed.append(msg["MessageId"])

    print(f"\nProcessed: {processed}")
    print(f"Skipped (manual review): {skipped}")
    print(f"Failed: {len(failed)}")
    if failed:
        print("    " + "\n    ".join(failed))
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
