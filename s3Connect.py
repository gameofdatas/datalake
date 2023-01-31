import boto3
from botocore.exceptions import ClientError
import logging


ddb1 = boto3.client('s3', endpoint_url="http://localhost:4566",
                    use_ssl=False,
                    aws_access_key_id='test',
                    aws_secret_access_key='test',
                    region_name='us-east-1')

try:
    ddb1.create_bucket(Bucket='newbucket')
except ClientError as e:
    logging.error(e)
