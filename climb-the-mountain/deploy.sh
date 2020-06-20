#!/bin/bash

if [ $# -ne 1 ]
  then
    echo "You need to supply a CloudFormation stack name as one single argument"
    exit 1
fi

# AWS CLI config
export AWS_PROFILE="climbthemountain"
export AWS_DEFAULT_REGION="ap-southeast-2"

# Deployment config
STACK_NAME=$1
STACK_DEPLOY_BUCKET="this-is-my-deploy-bucket"

# Stack variables

TMP_CF_PARAMS=$( mktemp )
cat > $TMP_CF_PARAMS <<- EOM
[
  {"ParameterKey": "StackKeyName",                 "ParameterValue": "climbthemountain"},
  {"ParameterKey": "CertificateARN",               "ParameterValue": "arn:aws:acm:ap-northeast-1:401074448412:certificate/44479900-8a0e-4a02-ac99-ca0520104412"},
  {"ParameterKey": "EnvironmentName",              "ParameterValue": "climbthemountain"},
  {"ParameterKey": "DeploymentArtifactLocation",   "ParameterValue": "https://this-is-my-application-bucket.s3-ap-southeast-2.amazonaws.com"},
  {"ParameterKey": "WebApp1ImageId",               "ParameterValue": "ami-04fcc97b5f6edcd89"},
  {"ParameterKey": "DatabaseRootUser",             "ParameterValue": "rootuser"},
  {"ParameterKey": "DatabaseRootPassword",         "ParameterValue": "Password123456"},
  {"ParameterKey": "DatabaseAppUser",              "ParameterValue": "climbthemountain"},
  {"ParameterKey": "DatabaseAppPassword",          "ParameterValue": "TCsOrv6dMhwmSEf1"},
  {"ParameterKey": "YourIPAddress",                "ParameterValue": "$( curl -s http://icanhazip.com )"}
]
EOM
   
# Package and deploy

TMP_CF_PARENT=$( mktemp )
aws cloudformation package \
  --template-file cloudformation/climbthemountain.yaml \
  --s3-bucket $STACK_DEPLOY_BUCKET \
  --output-template-file $TMP_CF_PARENT


aws cloudformation create-stack \
  --stack-name $STACK_NAME \
  --template-body file://$TMP_CF_PARENT \
  --parameters file://$TMP_CF_PARAMS \
  --output text
