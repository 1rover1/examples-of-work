#!/bin/bash

# Set the output logfile
LOGFILE="/var/log/bootstrap-metrics.csv"
TIMER_SCRIPT_START=$(date +%s.%N)

# Benchmarking function defs
function benchmark()
{
    if [ "${BENCHMARK_TITLE}" == "" ]; then
        # print the file header
        echo "date,description,time_taken,system_uptime" >> $LOGFILE
    else
        # Only log when a benchmark title has been set
        BENCHMARK_TIME_TAKEN=$(echo "$(date +%s.%N) - $BENCHMARK_TIMER_START" | bc)
        SYSTEM_UPTIME=$(awk '{print $1}' /proc/uptime)
        SYSTEM_DATE=$( date "+%Y-%m-%d %H:%M:%S" )
        echo "${SYSTEM_DATE},${BENCHMARK_TITLE},${BENCHMARK_TIME_TAKEN},${SYSTEM_UPTIME}" >> $LOGFILE
    fi
    BENCHMARK_TITLE=$1
    BENCHMARK_TIMER_START=$(date +%s.%N)
}

function benchmark_stop()
{
    benchmark "TOTAL"
    BENCHMARK_TIMER_START=$TIMER_SCRIPT_START
    benchmark "" # Doesn't matter what title we give this - it just forces a log write
}


benchmark "Apache stop"
service apache2 stop


benchmark "Define variables"

# Tell bash to do case insensitive compares
shopt -s nocasematch

# Load variables from config file created by CloudFormation
source /root/bootstrap-config.sh

# Set webroot variable for easy reference later
WEBROOT=/home/siteuser/$APPLICATION_TYPE.example.com

# Get region and elasticache information
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | cut -d'"' -f 4)
REDIS=$(aws elasticache describe-replication-groups \
    --region $REGION \
    --replication-group-id ${REDISID} \
    --query 'ReplicationGroups[*].NodeGroups[*].PrimaryEndpoint[*].Address[*]' --output text)

HOSTEDZONEID=$DOMAIN
DOMAIN=$(aws route53 get-hosted-zone --id $DOMAIN --output text --query 'HostedZone.Name' | sed 's/.$//')

# shellcheck disable=SC2153
MEMCACHE=$(aws elasticache describe-cache-clusters \
    --cache-cluster-id ${MEMCACHEID} \
    --show-cache-node-info \
    --query "CacheClusters[*].CacheNodes[*].Endpoint.Address" --output text \
    --region $REGION | awk -F " " '{print"tcp://"$1":11211,tcp://"$2":11211"}'
)
IP=$(wget -qO- http://instance-data/latest/meta-data/local-ipv4)
SHORTNAME=$(echo ${DOMAIN} | awk -F "." '{print$1}')

# Update hosts
echo $IP ${APPLICATION_TYPE}-${APPLICATION_ENV}.${SHORTNAME}.$IP >> /etc/hosts
echo ${APPLICATION_TYPE}-${APPLICATION_ENV}.${SHORTNAME}.$IP > /etc/hostname
hostname -F /etc/hostname

# Setup endpoint variables
if [ "$APPLICATION_ENV" == "production" ]; then
    SSO="sso.${DOMAIN}"
    SOAP="api.${DOMAIN}"
    FINANCE="finance.${DOMAIN}"
    DASHBOARD="dashboard.${DOMAIN}"
    MY="my.${DOMAIN}"
    SHIPPING="shipping.${DOMAIN}"
    PDF="pdf.${DOMAIN}"
    MGT="mgt.${DOMAIN}"
    # JOBS="jobs.${DOMAIN}"  -- removed, not refernced anywhere
    # KPI_DASHBOARD="kpi-dashboard.${DOMAIN}"  -- removed, not refernced anywhere
else
    SSO="sso-${APPLICATION_ENV}.${DOMAIN}"
    SOAP="api-${APPLICATION_ENV}.${DOMAIN}"
    FINANCE="finance-${APPLICATION_ENV}.${DOMAIN}"
    DASHBOARD="dashboard-${APPLICATION_ENV}.${DOMAIN}"
    MY="my-${APPLICATION_ENV}.${DOMAIN}"
    SHIPPING="shipping-${APPLICATION_ENV}.${DOMAIN}"
    PDF="pdf-${APPLICATION_ENV}.${DOMAIN}"
    MGT="mgt-${APPLICATION_ENV}.${DOMAIN}"
    # JOBS="jobs-${APPLICATION_ENV}.${DOMAIN}"  -- removed, not refernced anywhere
    # KPI_DASHBOARD="kpi-dashboard.${APPLICATION_ENV}.${DOMAIN}"  -- removed, not refernced anywhere
fi

# Save environment variables for the new instance
echo export REGION="apac" >> /etc/environment

echo export APPLICATION_ENV_REGION="apac" >> /etc/environment
echo export APPLICATION_ENV_REGION="apac" >> /etc/apache2/envvars

if [[ "$APPLICATION_ENV" =~ ^(uat|uat-ct|demo)$ ]]; then
    echo export APPLICATION_ENV_OWNER="$APPLICATION_ENV" >> /etc/environment
    echo export APPLICATION_ENV_OWNER="$APPLICATION_ENV" >> /etc/apache2/envvars
else
    echo export APPLICATION_ENV_OWNER="" >> /etc/environment
    echo export APPLICATION_ENV_OWNER="" >> /etc/apache2/envvars
fi

# Add environment variables for httpd, user and current session
if [[ "$APPLICATION_ENV" =~ ^(staging|uat|uat-ct|demo)$ ]]; then
    SOAP_SUPER_PASSWORD=""
    echo export APPLICATION_ENV="staging" >> /etc/environment
    echo export APPLICATION_ENV="staging" >> /etc/apache2/envvars
    echo export NODE_ENV="staging" >> /etc/environment
elif [[ "$APPLICATION_ENV" =~ ^(production)$ ]]; then
    SOAP_SUPER_PASSWORD=""
    echo export APPLICATION_ENV="production" >> /etc/environment
    echo export APPLICATION_ENV="production" >> /etc/apache2/envvars
    echo export NODE_ENV="production" >> /etc/environment
elif [[ "$APPLICATION_ENV" =~ ^(dev|test)$ ]]; then
    SOAP_SUPER_PASSWORD="xRb9GBXCtxHq"
    echo export APPLICATION_ENV="development" >> /etc/environment
    echo export APPLICATION_ENV="development" >> /etc/apache2/envvars
    echo export NODE_ENV="development" >> /etc/environment
fi

{
    echo export S3_BUCKET="${BUCKET_NAME}"
    echo export APPLICATION_TYPE="${APPLICATION_TYPE}"
    echo export AWS_REGION="${REGION}"
} >> /etc/environment

# Move the change log so that it doesn't show when the ubuntu user logs in
if [ -f /home/ubuntu/changelog.txt ]; then
    mv /home/ubuntu/changelog.txt /home/ubuntu/change.log
fi

# Disable the following hostnames when not in production
if [ "$APPLICATION_ENV" != "production" ]; then
    DISABLE_HOSTNAMES=" \
        webservices.hunterexpress.com.au \
        hunterexpress.com.au \
        test.hunterexpress.com.au \
        farmapi.fastway.org \
        api.fastway.org \
        au.api.fastway.org \
        xmlapi.emea.netdespatch.com \
        "

    for HOSTNAME in $DISABLE_HOSTNAMES; do
        echo "192.168.1.123    $HOSTNAME" >> /etc/hosts
    done
fi


if [[ "$APPLICATION_TYPE" =~ ^(mgt|api|dashboard)$ ]]; then
    benchmark "Mount network drive"
    LOCAL_EFS_MOUNT=/mnt/efs
    mkdir -p $LOCAL_EFS_MOUNT
    mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 $NET_FILE_SYSTEM:/ $LOCAL_EFS_MOUNT
fi


benchmark "Cloudwatch"

# Remove Cloudwatch custom metrics temporary folder
if [ -d "/var/tmp/aws-mon/" ]; then
    rm -rf /var/tmp/aws-mon/
fi
if [ -d "/tmp/aws-mon/" ]; then
    rm -rf /tmp/aws-mon/
fi

# Check that CloudWatch custom metrics are using auto-scaling metrics
if ! grep "auto\-scaling" /etc/cron.d/cwpump; then
    sed -i "s/\-\-mem\-util/\-\-auto\-scaling \-\-mem\-util/g" /etc/cron.d/cwpump
fi


benchmark "Apache configuration"

# Change php memory_limit
sed -i 's/memory_limit = 128M/memory_limit = 1024M/g' /etc/php5/apache2/php.ini
sed -i 's/memory_limit = 256M/memory_limit = 1024M/g' /etc/php5/apache2/php.ini
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 8M/g' /etc/php5/apache2/php.ini

aws s3 --region $REGION cp s3://$BUCKET_NAME/newrelic.ini /etc/php5/mods-available/newrelic.ini

# Fix php.ini if Ioncube is missing
if [ "$APPLICATION_TYPE" == "api" ]; then
    echo "zend_extension = /opt/ioncube/ioncube_loader_lin_5.5.so" >> /etc/php5/mods-available/ioncube.ini
    /usr/sbin/php5enmod ioncube
    # Ioncube has to be the first module on load or fails otherwise
    mv /etc/php5/apache2/conf.d/20-ioncube.ini /etc/php5/apache2/conf.d/00-ioncube.ini
    mv /etc/php5/cli/conf.d/20-ioncube.ini /etc/php5/cli/conf.d/00-ioncube.ini
fi

# Update Apache vhost with the correct ServerAlias
if [ "$APPLICATION_ENV" == "production" ]; then
    sed -i "s/ServerAlias.*\$/ServerAlias *.example.com/g" /etc/apache2/sites-enabled/000-default.conf
    sed -i "s/DocumentRoot .*\$/DocumentRoot \/home\/siteuser\/${APPLICATION_TYPE}.example.com\/htdocs/g" /etc/apache2/sites-enabled/000-default.conf
    sed -i "s/<Directory \"\/home.*\$/<Directory \/home\/siteuser\/${APPLICATION_TYPE}.example.com\/htdocs>/g" /etc/apache2/sites-enabled/000-default.conf
else
    sed -i "s/ServerAlias.*\$/ServerAlias *.example.com/g" /etc/apache2/sites-enabled/000-default.conf
    sed -i "s/DocumentRoot .*\$/DocumentRoot \/home\/siteuser\/${APPLICATION_TYPE}.example.com\/htdocs/g" /etc/apache2/sites-enabled/000-default.conf
    sed -i "s/<Directory \"\/home.*\$/<Directory \/home\/siteuser\/${APPLICATION_TYPE}.example.com\/htdocs>/g" /etc/apache2/sites-enabled/000-default.conf
fi

# Setup Apache logging
sed -i "s/<\/VirtualHost>//g" /etc/apache2/sites-enabled/000-default.conf
sed -i "s/ExtendedStatus On//g" /etc/apache2/sites-enabled/000-default.conf
{
    echo "LogLevel warn"
    echo "LogFormat \"%h %l %u %t \\\"%r\\\" %>s %b \\\"%{Referer}i\\\" \\\"%{User-Agent}i\\\" %D\" combined"
    echo "LogFormat \"%{X-Forwarded-For}i %l %u %t \\\"%r\\\" %>s %b \\\"%{Referer}i\\\" \\\"%{User-Agent}i\\\" %D\" proxy"
    echo "SetEnvIf X-Forwarded-For \"^.*\\..*\\..*\\..*\" forwarded"
    echo "CustomLog /var/log/apache2/$APPLICATION_TYPE.example.com.access.log combined env=!forwarded"
    echo "CustomLog /var/log/apache2/$APPLICATION_TYPE.example.com.access.log proxy env=forwarded"
    echo "ErrorLog /var/log/apache2/$APPLICATION_TYPE.example.com.error.log"
} >> /etc/apache2/sites-enabled/000-default.conf

# Setup Dashboard specific apache configuration
if [[ "$APPLICATION_TYPE" =~ ^(dashboard)$ ]]; then
    DASHBOARD_DATA_PATH=$LOCAL_EFS_MOUNT/dashboard/data
    {
        echo "XSendFile on"
        echo "XSendFilePath /tmp"
        echo "XSendFilePath $WEBROOT"
        echo "XSendFilePath $WEBROOT/htdocs"
        echo "XSendFilePath $WEBROOT/www"
        echo "XSendFilePath $WEBROOT/common"
        echo "XSendFilePath $WEBROOT/siteuser.cache/combine"
        echo "XSendFilePath $WEBROOT/siteuser.cache/image"
        echo "XSendFilePath $WEBROOT/siteuser.cache/sprite"
        echo "XSendFilePath $DASHBOARD_DATA_PATH/export"
    } >> /etc/apache2/sites-enabled/000-default.conf
fi

# Finish Apache vhost modification
echo "</VirtualHost>" >> /etc/apache2/sites-enabled/000-default.conf
echo "ExtendedStatus On" >> /etc/apache2/sites-enabled/000-default.conf


# Setup Splunk
if [[ "$APPLICATION_ENV" =~ ^(uat|production)$ ]]; then
    benchmark "Splunk setup"

    aws s3 --region $REGION cp s3://$BUCKET_NAME/splunk_inputs.conf /opt/splunkforwarder/etc/system/local/inputs.conf

    sed -i "s/TREGION/apac/g" /opt/splunkforwarder/etc/system/local/inputs.conf
    sed -i "s/REGION/$REGION/g" /opt/splunkforwarder/etc/system/local/inputs.conf

    if [ "$APPLICATION_ENV" == "uat" ]; then
      sed -i "s/ENV_TYPE/stage/g" /opt/splunkforwarder/etc/system/local/inputs.conf
    else
      sed -i "s/ENV_TYPE/${APPLICATION_ENV}/g" /opt/splunkforwarder/etc/system/local/inputs.conf
    fi
    
    /opt/splunkforwarder/bin/splunk start --accept-license
fi


benchmark "New Relic setup"

# Setup new relic configuration
cp /etc/newrelic/newrelic.cfg.template /etc/newrelic/newrelic.cfg

# Setup environment specific newrelic license
if [ "$APPLICATION_ENV" == "uat" ] && [ "$DOMAIN" == "apac1.example.com" ]; then
    sed -i "s/REPLACE_WITH_REAL_KEY//g" /etc/php5/apache2/conf.d/20-newrelic.ini
    sed -i "s/REPLACE_WITH_REAL_KEY//g" /etc/php5/cli/conf.d/20-newrelic.ini
    sed -i "s/REPLACE_WITH_REAL_KEY/8e20be47b54e06a93dafd2ecc32696243e77971/g" /etc/newrelic/nrsysmond.cfg
    echo "license_key=" >> /etc/newrelic/newrelic.cfg
    service newrelic-daemon restart
    service newrelic-sysmond restart
fi


benchmark "Primary application download"

# Create web root directory if it doesn't exist
if [ ! -d "$WEBROOT" ]; then
    mkdir $WEBROOT
fi

# Remove broken extended ACL permissions
#setfacl -b -R /home/siteuser

# Switch to context of web root directory
pushd $WEBROOT


# Pull application files from S3
aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/$APPLICATION_TYPE.example.com.tgz /tmp/
tar -xf /tmp/$APPLICATION_TYPE.example.com.tgz --strip 1
rm -f /tmp/$APPLICATION_TYPE.example.com.tgz


benchmark "Primary application config"

# Pull config files from S3
if [[ "$APPLICATION_TYPE" =~ ^(api)$ ]]; then
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/local.php ./config/autoload/local.php
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/parameters.yml ./app/config/parameters.yml
    if [ "$APPLICATION_ENV" != "production" ]; then
        aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/codeception.yml ./codeception.yml
        aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/api.suite.yml ./tests/api.suite.yml
    fi
    THIS_APPLICATIONS_DOMAIN=$SOAP
    
elif [[ "$APPLICATION_TYPE" =~ ^(jobs)$ ]]; then
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/local.php ./config/autoload/local.php
    
elif [[ "$APPLICATION_TYPE" =~ ^(sso|finance)$ ]]; then
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/parameters.yml ./app/config/parameters.yml
    THIS_APPLICATIONS_DOMAIN=$SSO
    
elif [[ "$APPLICATION_TYPE" =~ ^(shipping)$ ]]; then
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/parameters.yml ./app/config/parameters.yml
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/upstart.conf /etc/init/supervisor.conf
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/supervisord.conf /etc/supervisord.conf
    THIS_APPLICATIONS_DOMAIN=$SHIPPING
    
elif [[ "$APPLICATION_TYPE" =~ ^(dashboard)$ ]]; then
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/serverlist.inc ./serverlist.inc
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/dashboard-environment.inc ./dashboard-environment.inc
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/core.inc ./core.inc
    THIS_APPLICATIONS_DOMAIN=$DASHBOARD
    
elif [[ "$APPLICATION_TYPE" =~ ^(my)$ ]]; then
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/local.yml ./config/local.yml
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/production.yml ./config/production.yml
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/staging.yml ./config/staging.yml
    # mkdir -p /etc/nginx/sites-enabled/
    # aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/etc/nginx.nodejs.config /etc/nginx/sites-enabled/default
    THIS_APPLICATIONS_DOMAIN=$MY
    
#elif [[ "$APPLICATION_TYPE" =~ ^(tracking)$ ]]; then
#  aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/local.php ./config/autoload/local.php

elif [[ "$APPLICATION_TYPE" =~ ^(kpi-dashboard)$ ]]; then
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/config.php ./config.php
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/.htpasswd ../
    ln -s /home/siteuser/kpi-dashboard.example.com/ /home/siteuser/kpi-dashboard.example.com/www
    THIS_APPLICATIONS_DOMAIN=$KPI_DASHBOARD
    
elif [[ "$APPLICATION_TYPE" =~ ^(mgt)$ ]]; then
    mkdir /home/siteuser/bin
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/composer_auth.json /home/siteuser/.config/composer/auth.json
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/ansible/ /etc/ansible/ --recursive
    sed -i "s/S3_CONFIG_BUCKET/${BUCKET_NAME}/g" /etc/ansible/*
    aws s3 --region $REGION cp s3://$BUCKET_NAME/base-image/bin/ /home/siteuser/bin/ --recursive
    # Note: we're not wanting to set the THIS_APPLICATIONS_DOMAIN variable for mgt. We'll set the DNS A record directly below
    PUBLIC_IP=$( curl -s http://169.254.169.254/latest/meta-data/public-ipv4 )
    echo "{\"Changes\": [{ \"Action\": \"UPSERT\", \"ResourceRecordSet\": {\"Name\": \"${MGT}\",\"Type\": \"A\",\"TTL\": 300,\"ResourceRecords\": [{\"Value\": \"${PUBLIC_IP}\"}]}}]}" > create_cname.json
    aws route53 change-resource-record-sets --hosted-zone-id $HOSTEDZONEID --change-batch file://./create_cname.json
    
elif [[ "$APPLICATION_TYPE" =~ ^(pdf)$ ]]; then
    aws s3 --region $REGION cp s3://$BUCKET_NAME/$REGION/$APPLICATION_ENV/$APPLICATION_TYPE/local.php ./config/autoload/local.php
    THIS_APPLICATIONS_DOMAIN=$PDF
    rm -rf cache/*
fi


# Replacing configuration options in files
if [ -f "./config/autoload/local.php" ]; then
    sed -i "s/MYSQL-ADDR/${DATABASE}/g" ./config/autoload/local.php
    sed -i "s/TBRIDGE-ADDR/${TBRIDGEDB}/g" ./config/autoload/local.php
    sed -i "s/DB-USER/${DBUSER}/g" ./config/autoload/local.php
    sed -i "s/DB-PASS/${DBPASS}/g" ./config/autoload/local.php
    sed -i "s/REDIS-ADDR/${REDIS}/g" ./config/autoload/local.php
    sed -i "s/dashboard-demo.example.fr/${DASHBOARD}/g" ./config/autoload/local.php
    sed -i "s/api-demo.example.fr/${SOAP}/g" ./config/autoload/local.php
    sed -i "s/sso-demo.example.fr/${SSO}/g" ./config/autoload/local.php
    sed -i "s/KPI-DB/${LOGDB}/g" ./config/autoload/local.php
    sed -i "s/SOAP_SUPER_PASSWORD/${SOAP_SUPER_PASSWORD}/g" ./config/autoload/local.php
    sed -i "s/pdf-null.example.com/${PDF}/g" ./config/autoload/local.php
fi

if [ -f "./codeception.yml" ]; then
    sed -i "s/MYSQL-ADDR/${DATABASE}/g" ./codeception.yml
    sed -i "s/DB-USER/${DBUSER}/g" ./codeception.yml
    sed -i "s/DB-PASS/${DBPASS}/g" ./codeception.yml
fi

if [ -f "./tests/api.suite.yml" ]; then
    sed -i "s/api.some-developer.example.dev55/${SOAP}/g" ./tests/api.suite.yml
    sed -i "s/MYSQL-ADDR/${DATABASE}/g" ./tests/api.suite.yml
    sed -i "s/DB-USER/${DBUSER}/g" ./tests/api.suite.yml
    sed -i "s/DB-PASS/${DBPASS}/g" ./tests/api.suite.yml
fi

if [ -f "./app/config/parameters.yml" ]; then
    sed -i "s/sso-demo.example.fr/${SSO}/g" ./app/config/parameters.yml
    sed -i "s/finance-demo.example.fr/${FINANCE}/g" ./app/config/parameters.yml
    sed -i "s/api-demo.example.fr/${SOAP}/g" ./app/config/parameters.yml
    sed -i "s/shipping-demo.example.fr/${SHIPPING}/g" ./app/config/parameters.yml
    sed -i "s/my-demo.example.fr/${MY}/g" ./app/config/parameters.yml
    sed -i "s/MYSQL-ADDR/${DATABASE}/g" ./app/config/parameters.yml
    sed -i "s/TBRIDGE-ADDR/${TBRIDGEDB}/g" ./app/config/parameters.yml
    sed -i "s/DB-USER/${DBUSER}/g" ./app/config/parameters.yml
    sed -i "s/DB-PASS/${DBPASS}/g" ./app/config/parameters.yml
    sed -i "s/REDIS-ADDR/${REDIS}/g" ./app/config/parameters.yml
    sed -i "s/KPI-DB/${LOGDB}/g" ./app/config/parameters.yml
    sed -i "s/REGION/$REGION/g" ./app/config/parameters.yml
    sed -i "s/SOAP_SUPER_PASSWORD/${SOAP_SUPER_PASSWORD}/g" ./config/autoload/local.php
fi

if [ -f "./app/config/config_production.yml" ]; then
    sed -i "s/sso.example.com/${SSO}/g" ./app/config/config_production.yml
    sed -i "s/finance.example.com/${FINANCE}/g" ./app/config/config_production.yml
fi 

if [ -f "./app/config/config_staging.yml" ]; then
    sed -i "s/sso-staging.example.com/${SSO}/g" ./app/config/config_staging.yml
    sed -i "s/finance-staging.example.com/${FINANCE}/g" ./app/config/config_staging.yml
fi

if [ -f "./config.php" ]; then
    sed -i "s/MYSQL-ADDR/${DATABASE}/g" ./config.php
    sed -i "s/TBRIDGE-ADDR/${TBRIDGEDB}/g" ./config.php
    sed -i "s/DB-USER/${DBUSER}/g" ./config.php
    sed -i "s/DB-PASS/${DBPASS}/g" ./config.php
    sed -i "s/REDIS-ADDR/${REDIS}/g" ./config.php
    sed -i "s/KPI-DB/${LOGDB}/g" ./config.php
fi

if [ -f "/etc/nginx/sites-enabled/default" ]; then
    sed -i "s/SHIPPING-URL/${SHIPPING}/g" /etc/nginx/sites-enabled/default
    if [ "$APPLICATION_ENV" == "production" ]; then
        sed -i "s/MY-HOST/${APPLICATION_TYPE}.${DOMAIN}/g" /etc/nginx/sites-enabled/default
    else
        sed -i "s/MY-HOST/${APPLICATION_TYPE}-${APPLICATION_ENV}.${DOMAIN}/g" /etc/nginx/sites-enabled/default
    fi
fi 

if [ -f "./www/.htaccess" ]; then
    # Fix SSL offloading HTTPS redirect loop
    sed -i "s/%{HTTPS} \!=on/%{HTTP:X-Forwarded-Proto} \!https/g" ./www/.htaccess
fi

if [ -f "./dashboard-environment.inc" ]; then
    sed -i "s/MYSQL-ADDR/${DATABASE}/g" ./dashboard-environment.inc
    sed -i "s/TBRIDGE-ADDR/${TBRIDGEDB}/g" ./dashboard-environment.inc
    sed -i "s/api-demo.example.com/${SOAP}/g" ./dashboard-environment.inc
    sed -i "s/DB-USER/${DBUSER}/g" ./dashboard-environment.inc
    sed -i "s/DB-PASS/${DBPASS}/g" ./dashboard-environment.inc
    sed -i "s/pdf-demo.example.com/${PDF}/g" ./dashboard-environment.inc
    sed -i "s/SOAP_SUPER_PASSWORD/${SOAP_SUPER_PASSWORD}/g" ./dashboard-environment.inc
    sed -i "s/sso-demo.example.fr/${SSO}/g" ./dashboard-environment.inc
fi

if [ -f "./config/production.yml" ]; then
    sed -i "s/api-demo.example.fr/${SOAP}/g" ./config/production.yml
    sed -i "s/shipping-demo.example.fr/${SHIPPING}/g" ./config/production.yml
    sed -i "s/my-demo.example.fr/${MY}/g" ./config/production.yml
    sed -i "s/sso-demo.example.fr/${SSO}/g" ./config/production.yml
    sed -i "s/sso.example.com/${SSO}/g" ./config/production.yml
    sed -i "s/shipping.example.com/${MY}/g" ./config/production.yml
    sed -i "s/shipping-api.example.com/${SHIPPING}/g" ./config/production.yml
fi 

if [ -f "./config/local.yml" ]; then
    sed -i "s/api-demo.example.fr/${SOAP}/g" ./config/local.yml
    sed -i "s/shipping-demo.example.fr/${MY}/g" ./config/local.yml
    sed -i "s/my-demo.example.fr/${MY}/g" ./config/local.yml
    sed -i "s/sso-demo.example.fr/${SSO}/g" ./config/local.yml
    sed -i "s/my-staging.example.com/${MY}/g" ./config/local.yml
    sed -i "s/my.example.com/${MY}/g" ./config/local.yml
fi

if [ -f "./config/staging.yml" ]; then
    sed -i "s/shipping-staging.example.com/${SHIPPING}/g" ./config/staging.yml
    sed -i "s/my-staging.example.com/${MY}/g" ./config/staging.yml
    sed -i "s/sso-staging.example.com/${SSO}/g" ./config/staging.yml
    sed -i "s/shipping-demo.example.fr/${SHIPPING}/g" ./config/staging.yml
    sed -i "s/my-demo.example.fr/${MY}/g" ./config/staging.yml
    sed -i "s/sso-demo.example.fr/${SSO}/g" ./config/staging.yml
fi

if [ -f "./core.inc" ]; then
    sed -i "s/dashboard-demo.example.fr/${DASHBOARD}/g" ./core.inc
    sed -i "s#DASHBOARD_DATA_PATH#${DASHBOARD_DATA_PATH}#g" ./core.inc
    sed -i "s/sso-demo.example.fr/${SSO}/g" ./core.inc
fi

if [ -f "./tracking-service-backend.json" ]; then
    sed -i "s/MYSQL-ADDR/${DATABASE}/g" ./tracking-service-backend.json
    sed -i "s/TBIRDGE-ADDR/${DATABASE}/g" ./tracking-service-backend.json
    sed -i "s/DB-USER/${DBUSER}/g" ./tracking-service-backend.json
    sed -i "s/DB-PASS/${DBPASS}/g" ./tracking-service-backend.json
    sed -i "s/ENV/${APPLICATION_ENV}/g" ./tracking-service-backend.json
fi

if [ -f "./tracking-service-web.json" ]; then
    sed -i "s/MYSQL-ADDR/${DATABASE}/g" ./tracking-service-web.json
    sed -i "s/TBRIDGE-ADDR/${TBRIDGEDB}/g" ./tracking-service-web.json
    sed -i "s/DB-USER/${DBUSER}/g" ./tracking-service-web.json
    sed -i "s/DB-PASS/${DBPASS}/g" ./tracking-service-web.json
    sed -i "s/ENV/${APPLICATION_ENV}/g" ./tracking-service-web.json
fi

# Create htdocs folder if it is missing
if [ ! -d "$WEBROOT/htdocs" ]; then
    ln -s $WEBROOT/www $WEBROOT/htdocs
fi

# Create logs folder if it is missing
if [ ! -d "$WEBROOT/var/logs" ]; then
    mkdir -p $WEBROOT/var/logs
    chmod 775 $WEBROOT/var/logs
fi

# Create cache folder if it is missing
if [ ! -d "$WEBROOT/var/cache" ]; then
    mkdir -p $WEBROOT/var/cache
    chmod 775 $WEBROOT/var/cache
fi

# # Create /data folder if it is missing
# if [ ! -d "/data/www.siteuser.data" ]; then
#     mkdir -p /data/www.siteuser.data
#     chown -R siteuser:www-data /data
#     chmod -R 775 /data
# fi

# Update schema file if it exists
if [ -d "$WEBROOT/htdocs/schema/2009_06/" ]; then
    sed -i "s/api.example.com/${SOAP}/g" $WEBROOT/htdocs/schema/2009_06/server.*
    sed -i "s/api.example.com/${SOAP}/g" $WEBROOT/htdocs/schema/2009_06/common.*
    sed -i "s/api.example.com/${SOAP}/g" $WEBROOT/htdocs/schema/2009_06/carrier/*.xsd
    cd /home/siteuser/api.example.com; bin/setup.sh ${SOAP};
fi

# Configure memcache sessions for SSO, Shipping, Dashboard
#if [[ "$APPLICATION_TYPE" =~ ^(sso|shipping)$ ]]; then
  # Update php.ini to use memcache sessions
#  sed -i "s/session.save_handler = files/session.save_handler = memcache/g" /etc/php5/apache2/php.ini
#  echo "session.save_path = \"${ELASTICACHE}:11211\"" >> /etc/php5/apache2/php.ini
#fi

if [[ "$APPLICATION_TYPE" == "api" ]]; then
    mkdir -p /home/siteuser/api.example.com/logs/transactions
    chmod 777 /home/siteuser/api.example.com/logs/transactions /home/siteuser/api.example.com/logs
    chown siteuser:www-data /home/siteuser/api.example.com/logs/transactions /home/siteuser/api.example.com/logs
    echo "RewriteEngine On" >> /home/siteuser/api.example.com/www/.htaccess
    echo 'RewriteRule "^monitor/health"  "check.php" [NC,L]' >> /home/siteuser/api.example.com/www/.htaccess
fi 

if [[ "$APPLICATION_TYPE" == "kpi-dashboard" ]]; then
    sed -i "s/localhost/$REDIS/g" /home/siteuser/kpi-dashboard.example.com/index.php
fi 

if [[ "$APPLICATION_TYPE" =~ ^(sso|shipping)$ ]]; then
    sed -i "s/session.save_handler = files/session.save_handler = memcache/g" /etc/php5/apache2/php.ini
    echo "session.save_path = \"$MEMCACHE\"" >> /etc/php5/apache2/php.ini
fi
 
if [[ "$APPLICATION_TYPE" =~ ^(shipping)$ ]]; then
    # Fix config file for shipping app - config_demo.yml is missing
    cp $WEBROOT/app/config/config_production.yml $WEBROOT/app/config/config_demo.yml
    ln -s $WEBROOT/htdocs /home/siteuser/shipping.example.com

    # Fix trusted_proxies in $WEBROOT/app/config/parameters.yml - Because the only allowed traffic is via ELB, it can be 0.0.0.0
    sed -i "s/trusted_proxies\: .*$/trusted_proxies\: 0.0.0.0/g" $WEBROOT/app/config/parameters.yml
    sed -i "s/my-demo.example.fr/${MY}/g" $WEBROOT/app/config/config_demo.yml
    sed -i "s/shipping-demo.example.fr/${SHIPPING}/g" $WEBROOT/app/config/config_demo.yml
    sed -i "s/sso-demo.example.fr/${SSO}/g" $WEBROOT/app/config/config_demo.yml
fi

# Perform Dashboard specific configuration
if [[ "$APPLICATION_TYPE" =~ ^(dashboard)$ ]]; then
    benchmark "Dashboard config"
    
    # Disable HTTPS redirection
    sed -i 's/^RewriteCond %{HTTP:X-Forwarded-Proto/# RewriteCond %{HTTP:X-Forwarded-Proto/g' $WEBROOT/www/.htaccess
    sed -i 's/^RewriteRule (.*) https/# RewriteRule (.*) https/g' $WEBROOT/www/.htaccess
    
    # Fix missing directories

    chmod -R 775 /home/siteuser/dashboard.example.com/siteuser.cache
    chown -R siteuser:www-data /home/siteuser/dashboard.example.com/siteuser.cache
    mkdir -p $DASHBOARD_DATA_PATH
    chmod -R 777 $DASHBOARD_DATA_PATH
    
    mkdir -p $DASHBOARD_DATA_PATH/export/csv
    mkdir -p $DASHBOARD_DATA_PATH/export/pdf
    mkdir -p $DASHBOARD_DATA_PATH/thread
    mkdir -p $DASHBOARD_DATA_PATH/cache
    mkdir -p $DASHBOARD_DATA_PATH/import/csv
    mkdir -p $DASHBOARD_DATA_PATH/logs/server
    mkdir -p $DASHBOARD_DATA_PATH/logs/db
    mkdir -p $DASHBOARD_DATA_PATH/smarty/res
    mkdir -p $DASHBOARD_DATA_PATH/smarty/com
    mkdir -p $DASHBOARD_DATA_PATH/import/xml
    chmod -R 777 $DASHBOARD_DATA_PATH/*
    
    # Install mod_xsendfile.so if it is missing
    apt-get install -y libapache2-mod-xsendfile
    a2enmod xsendfile

    # Fix incorrect http call in template
    sed -i "s/http\:\/\/ajax.googleapis.com/https\:\/\/ajax.googleapis.com/g" $WEBROOT/siteuser.skin/templates/view/exception_cookie.tpl
fi

# Perform my.example.com specific configuration
if [[ "$APPLICATION_TYPE" =~ ^(my)$ ]]; then
    benchmark "My config"
    #   curl -sL https://deb.nodesource.com/setup_4.x | sudo -E bash -
    curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -
    apt-get -y remove apache2
    apt-get -y autoremove
    # apt-get install -y --force-yes nginx nodejs
    npm install -g newrelic pm2 bower grunt
    chown -R siteuser:www-data $WEBROOT
    #   chmod +x $WEBROOT/node_modules/pm2/bin/pm2
    #   chmod 775 $WEBROOT/node_modules/.bin/webpack
    #   sed -i "s/sso-staging.example.com/${SSO}/g" /home/siteuser/my.example.com/dist/server.bundle.js
    #   sed -i "s/shipping-staging.example.com/${SHIPPING}/g" /home/siteuser/my.example.com/dist/server.bundle.js
    su -c "cd $WEBROOT; npm install --no-dev && npm run build" siteuser
    su -c "cd $WEBROOT; npm start" siteuser
    # service nginx restart
fi

# Perform shipping.example.com specific configuration
if [[ "$APPLICATION_TYPE" =~ ^(shipping)$ ]]; then
    benchmark "Shipping config"
    # Fix rewrite rules to work with Cloudfront
    sed -i "s/^\s*RewriteEngine On\$/RewriteEngine on\nRewriteRule ^api\/api\/(.*?)\$ \/api\/\$1 [P,L]\nRewriteRule ^carrier_integration\/(.*?)\$ \/api\/\$1 [P,L]/g" $WEBROOT/htdocs/.htaccess
    #  wget http://download.gna.org/wkhtmltopdf/0.12/0.12.2.1/wkhtmltox-0.12.2.1_linux-trusty-amd64.deb
    #  dpkg -i wkhtmltox-0.12.2.1_linux-trusty-amd64.deb
    #  apt-get install -y -f
    # Make missing directories
    mkdir -p $WEBROOT/var/logs/
    chmod -R 775 $WEBROOT/var
    chown -R www-data:siteuser $WEBROOT/var
    mkdir /opt/supervisor
    chown siteuser:siteuser /opt/supervisor
    mkdir -p /etc/supervisor/conf.d
    ln -sf /home/siteuser/shipping.example.com/supervisor.conf /etc/supervisor/conf.d/shipping.conf
    pip install supervisor
    service supervisor restart
fi

if [[ "$APPLICATION_TYPE" =~ ^(sso|shipping|finance|jobs)$ ]]; then
    benchmark "symfony cache clear"
    su -c "cd $WEBROOT; app/console cache:clear" siteuser
fi 

if [[ "$APPLICATION_TYPE" =~ ^(mgt)$ ]]; then
    benchmark "Management config"
    aws s3 --region $REGION cp s3://$BUCKET_NAME/base-image/bin/log-import.php /home/siteuser/bin/
    mkdir /home/siteuser/backups
    mkdir /home/siteuser/deploy
    #  curl -sL https://deb.nodesource.com/setup_4.x | sudo -E bash -
    curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
    echo "alias ec2list='aws ec2 --region $REGION describe-instances --query '\''Reservations[*].Instances[*].[IamInstanceProfile.Arn, PrivateIpAddress]'\'' --output text | grep $APPLICATION_ENV | sort'" >> /etc/profile

    benchmark "Management software installation"
    apt-get -y install ansible mysql-client nodejs
    
    benchmark "Management pip install"
    pip install boto

    benchmark "Management npm install"
    npm install bower@1.3.12 -g
    npm install pm2 -g
    npm install grunt-cli@0.1.13 -g
    npm install grunt@v0.4.5 -g
fi

if [[ "$APPLICATION_TYPE" =~ ^(mgt|jobs)$ ]]; then
    benchmark "Set aliases"
    {
        echo "alias mainDB='mysql -u$DBUSER -p$DBPASS -h$DATABASE'"
        echo "alias tbridgeDB='mysql -u$DBUSER -p$DBPASS -h$TBRIDGEDB'"
        echo "alias logDB='mysql -u$DBUSER -p$DBPASS -h$LOGDB'"
    } >> /etc/profile
fi

if [[ "$APPLICATION_TYPE" =~ ^(jobs)$ ]]; then
    benchmark "Jobs config"
    apt-get -y install ansible mysql-client
    ln -s /home/siteuser/jobs.example.com/init.d/siteuser-jobs-dirk /etc/init.d/siteuser-jobs
    chkconfig --add siteuser-jobs
    sudo -u siteuser service siteuser-jobs start

    # Install database archiving script
    aws s3 --region $REGION cp s3://$BUCKET_NAME/base-image/bin/archive-logdb.sh /home/siteuser/bin/
    sed -i "s/INSERT_DEPLOY_HERE/${APPLICATION_ENV}/g" /home/siteuser/bin/archive-logdb.sh
    sed -i "s/INSERT_REGION_HERE/${REGION}/g" /home/siteuser/bin/archive-logdb.sh
    su siteuser -c 'crontab -l | { cat; echo "0 * * * * bash /home/siteuser/bin/archive-logdb.sh"; } | crontab -'

    # Add collection point loaders
    if [[ "$REGION" == "eu-west-1" ]]; then
        aws s3 --region $REGION cp s3://$BUCKET_NAME/base-image/bin/collectionpoint-loader.sh /home/siteuser/bin/
        su siteuser -c 'crontab -l | { cat; echo "10 2 * * * bash /home/siteuser/bin/collectionpoint-loader.sh > /home/siteuser/logs/collectionpoint-loader.log"; } | crontab -'
    fi
fi

#Install php http and ssh2
#apt-get install -y php-http php5-dev libcurl3 libpcre3-dev libcurl4-openssl-dev libssh2-php
#echo "" | pecl install pecl_http-1.7.6
#echo "extension=http.so" > /etc/php5/mods-available/http.ini
#php5enmod http
#php5enmod ssh2

if [[ "$APPLICATION_TYPE" =~ ^(xps)$ ]]; then
    benchmark "XPS config"
    apt-get -y install supervisor
    cat > /etc/supervisor/conf.d/xps-service.conf << EOL
[program:xps-service]
command=/home/siteuser/xps.example.com/xps-service -config /home/siteuser/xps.example.com/xps-service.conf
user=siteuser
EOL
    service supervisor restart
fi

if [[ "$APPLICATION_TYPE" =~ ^(tracking-service)$ ]]; then
    benchmark "Tracking config"
    apt-get -y install supervisor
    echo "compose.crt" >> /etc/ca-certificates.conf
    update-ca-certificates
    ln -s /home/siteuser/tracking-service.example.com/tracking-service-backend.conf /etc/supervisor/conf.d/tracking-service-backend.conf
    ln -s /home/siteuser/tracking-service.example.com/tracking-service-web.conf /etc/supervisor/conf.d/tracking-service-web.conf
    service supervisor restart
fi
 
# Return to original directory
popd

if [ -n "$THIS_APPLICATIONS_DOMAIN" ]; then
    benchmark "Update Route53"
    echo "{\"Changes\": [{ \"Action\": \"UPSERT\", \"ResourceRecordSet\": {\"Name\": \"${THIS_APPLICATIONS_DOMAIN}\",\"Type\": \"CNAME\",\"TTL\": 300,\"ResourceRecords\": [{\"Value\": \"${LBNAME}\"}]}}]}" > create_cname.json
    aws route53 change-resource-record-sets --hosted-zone-id $HOSTEDZONEID --change-batch file://./create_cname.json
fi


benchmark "Final config"

#Add 3'rd memcache instance
cp /etc/memcached_1.conf /etc/memcached_3.conf
sed -i 's/11211/33133/g' /etc/memcached_3.conf
service memcached restart

# Fix some final permissions
# find $WEBROOT -type f -exec chmod 644 {} \;
find $WEBROOT -type d -exec chmod 775 {} \;
chmod 775 /home/siteuser
chmod 775 $WEBROOT
mkdir /home/siteuser/logs
chown -R siteuser:www-data /home/siteuser/logs
chmod -R 775 /home/siteuser/logs
chown -R siteuser:www-data /home/siteuser 
usermod -g www-data siteuser


# Restart apache
#a2enmod rewrite
#php5enmod mcrypt

benchmark "Apache restart"
service apache2 restart

benchmark_stop
