#!/bin/bash

if [ $# -ne 1 ]
  then
    echo "You need to supply a CloudFormation stack name as one single argument"
    exit 1
fi

# config items

export AWS_PROFILE="climbthemountain"
export AWS_DEFAULT_REGION="ap-southeast-2"

STACK_NAME=$1

CLOUDFORMATION_BUCKET="this-is-my-deploy-bucket"
CLOUDFORMATION_LOCATION="https://$CLOUDFORMATION_BUCKET.s3-ap-southeast-2.amazonaws.com"

TEMPFILE=$( mktemp )
cat > $TEMPFILE <<- EOM
[
  {"ParameterKey": "StackKeyName",                      "ParameterValue": "climbthemountain"},
  {"ParameterKey": "CertificateARN",                    "ParameterValue": "arn:aws:acm:ap-northeast-1:401074448412:certificate/44479900-8a0e-4a02-ac99-ca0520104412"},
  {"ParameterKey": "EnvironmentName",                   "ParameterValue": "climbthemountain"},
  {"ParameterKey": "DeploymentArtifactLocation",        "ParameterValue": "https://this-is-my-application-bucket.s3-ap-southeast-2.amazonaws.com"},
  {"ParameterKey": "DeploymentCloudformationLocation",  "ParameterValue": "$CLOUDFORMATION_LOCATION"},
  {"ParameterKey": "WebApp1ImageId",                    "ParameterValue": "ami-03344c819e1ac354d"},
  {"ParameterKey": "DatabaseRootUser",                  "ParameterValue": "rootuser"},
  {"ParameterKey": "DatabaseRootPassword",              "ParameterValue": "Password123456"},
  {"ParameterKey": "DatabaseAppUser",                   "ParameterValue": "climbthemountain"},
  {"ParameterKey": "DatabaseAppPassword",               "ParameterValue": "TCsOrv6dMhwmSEf1"},
  {"ParameterKey": "YourIPAddress",                     "ParameterValue": "$( curl -s http://icanhazip.com )"}
]
EOM
   
# upload all cloudformation files
aws s3 sync --no-progress \
    cloudformation/ \
    s3://$CLOUDFORMATION_BUCKET

sleep 2 # Give AWS S3 a chance to sync internally

aws cloudformation create-stack \
   --stack-name $STACK_NAME \
   --template-url $CLOUDFORMATION_LOCATION/climbthemountain.yaml \
   --parameters file://$TEMPFILE \
   --output text
