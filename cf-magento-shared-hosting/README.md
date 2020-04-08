# Magento2 demo website management scripts

Magento share-hosting environment for hosting multiple Magento sites in a single server instance.

## Background

This project enabled us to maintain one individual site for testing and demo installations of Magento 2. With a focus
on lower costs - rather than performance and availability, consolidating all hosted sites onto the one box was an
obvious option. Scripted installation and the ability to specify installation version at the command line meant that
new sites can be deployed in minutes and developers, product managers weren't kept waiting.

This project was originally created by a colleague with my work being:

- Cost optimisations: removed load balancers, removed NAT gateways
- Security: added Security Group with SSH access to the host
- Security: removed SSH keys from project
- Workflow: moved a lot of the installation and environment setup to EC2 userdata
- Workflow: added random password generation and summary info to site setup script
- Functionality: added ability to specify Magento version to site setup script

## Creating new share-hosting stack from CloudFormation.

You can initialise new share-hosting stack with template file `m23-bionic.yml`. Which will create all necessary
resources necessary for the stack running, including MySQL RDS instance and WebApp EC2 instance.

When deciding which AMI to use, consider the following command. Take note of the region, Ubuntu version (e.g. bionic)
and CPU architecture (e.g. amd64) and update as needed:

```
aws --region us-west-2 --output text ec2 describe-images --filters Name=name,Values=ubuntu/images/hvm-ssd/* --query 'Images[*].[ImageId,CreationDate,Name]' | sort -k 3 | grep bionic | grep amd64 | sort -k 2 | tail -n3
```

## Connecting to the Magento host

Please add your private ssh key that has been granted repo access into ssh-agent as well as the EC2 instance assess key
before login into the WebApp instance as user `siteuser`.

```
$ ssh-agent bash
$ ssh-add ~/.ssh/id_rsa
$ ssh-add ~/.ssh/key-m2demo-apac.pem
$ ssh -A siteuser@m2ee.example.com
```

## To create new Magento site after stack creation.

 - Connect to the Magento host.
 - If you haven't already, you need to clone the setup files `git clone git@src.example.com:dev-ops/m2demo-scripts.git`.
 - Create a new site with `./m2-site-install.sh <site-name> <branch-name>`
 - Most obvious use of `<site-name>` will be used in the domain name. Recommmend alphanumeric up to 8 chars.
 - `<branch-name>` is the tag/branch to check out for Magento. e.g. 2.3.1 or 2.3-develop for pre-release 2.3.2.

## Other tasks

 - Remove existing Magento site with `./m2-site-remove.sh <site-name>`
 - List the hosted sites with `ls -l /var/www/html/m2/`
 - List the available tags/branches with `git ls-remote git@src.example.com:dev-ops/magento2-ee.git`

## To enable HTTPS support after CloudFormation stack creation:

 - Create a wildcard DNS entry like *.m2ee.example.com according to the WildcardDomain setting of CloudFormation
 - Issue a new cert for the wildcard domain-name.
 - Add a HTTPS listener associated with the wildcard domain cert into the LoadBalancer in EC2 panel
 - Edit `m2-site-install.sh` and uncomment certain actions to enable HTTPS on new sites.
 - Check `m2-site-install.sh` for commands to enable HTTPS on existing sites.
