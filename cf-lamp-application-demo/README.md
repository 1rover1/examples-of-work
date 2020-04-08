# Legacy application stack using EC2, RDS, Elasticache

## Background

This stack was originally created by a third party working with our internal devops team. It was used extensively in
Europe and this implementation would eventually serve as a base for an AWS implementation of our UAT system here in
Australia.

The stack includes a user dashboard, separate SOAP/REST API, and SSO applications.

## Technical Description

This CloudFormation stack sets up a LAMP application over multiple Availability Zones (AZ's) within an AWS region, thus
giving it a reasonably high availability. Multi-region was not required.

The application stack features:

- Elasticache (Memcache) for caching
- Elasticache (Redis) for fast data storage
- RDS (MySQL) as the backend database
- Classic Elastic Load Balancer (ELB) for balance the web traffic between AZ's
- Support for multiple LAMP applications
- Script-based application deployments
- Deployment by scaling up (doubling the application instances, loading a new application blob from S3) and then
  scaling down (halving instances and removing old versions)

## My work

I inherited ownership of the project after the production system was running in Europe. First tasks were to:

- Check the code into source control - although it's against best practice to include configuration data I figured the
  security we had around this was better than leaving the source code unattended on the corporate network.
- Remove files and code that was unused or no longer relevant. I could see previous attempts to use Nginx instead of
  Apache, there were `.bak` `.1` and similar files.

Over time it became obvious that the European stack included applications that just weren't being used. These were
removed from the CloudFormation definition for significant cost savings.

When the need to migrate our Australian stack from a data centre to AWS I performed the following:

- Refactored much of the BASH bootstrap file (`bootstrap.sh`), adding benchmarking to better understand deployment
  timelines, adding a Splunk agent and performing a general tidy up
- Added linting for php, json and sh files
- Added helper scripts to: create stacks; compile scripts; and bump AMI versions. Made it easier for devops team
  members to set up and test their own stacks
- Added a basic GitLab pipeline to automatically push updated CloudFormation templates and application configuration
  files to S3.

## Disclaimer

This project is no longer in service. This repo has been sanitised and for demonstration purposes had custom application
data and configuration removed.