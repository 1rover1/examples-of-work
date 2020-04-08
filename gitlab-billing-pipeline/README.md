# Billing via GitLab Pipeline

## Background

Generating a monthly billing file was a manual process until this script was implemented via a GitLab pipeline. Setting
this up in GitLab meant that the billing process had clear accountability with our service partner. If visibility 
wasn't required by our service partner this, arguably, would have been better set up as a lambda function.

## Description

This is a Python script that uses Boto to create and send a report on a pre-defined list of AWS accounts.

## Installation

1. Add the project to GitLab
2. Schedule a pipeline to run at the start of the billing month
3. Set CI/CD variables for `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `EMAIL_RECIPIENTS`

AWS credentials referenced must have access to send SES raw emails and read Cost and Usage data. *TODO:* add better IAM
role definition.

As AWS billing data is based on USA time plus a few hours of potential lag I found the best time to run this was on the
2nd day of the month at 4pm UTC+10.
