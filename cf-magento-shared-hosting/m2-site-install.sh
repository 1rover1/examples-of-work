#!/bin/sh

install_dir=`dirname $0`
install_dir=`realpath $install_dir`
cerepo="git@src.example.com:dev-ops/magento2-ce.git"
eerepo="git@src.example.com:dev-ops/magento2-ee.git"
smprepo="git@src.example.com:dev-ops/magento2-sample-data.git"

if [ "$2" = "" ]; then
	echo "Branch name is necessary:"
	git ls-remote $eerepo
	exit 1
fi

rs=`mysql -u $DBUSER -Ns -e "select 1" 2>/dev/null`
if [ "$rs" != "1" ]; then
    echo "Failed database connection attempt.";
    echo "Please check."
    exit 1
fi

echo "CREATE DATABASE m2_$1;"|mysql -u $DBUSER
echo "CREATE USER 'm2_$1'@'%' IDENTIFIED BY 'm2-dbpass';"|mysql -u $DBUSER
echo "GRANT ALL PRIVILEGES ON m2_$1.* TO 'm2_$1'@'%';"|mysql -u $DBUSER

mkdir /var/www/html/m2/$1 && cd /var/www/html/m2/$1
git clone -b $2 --single-branch --depth 1 $cerepo magento2ce
git clone -b $2 --single-branch --depth 1 $eerepo magento2ee
git clone -b $2 --single-branch --depth 1 $smprepo magento2smp

php magento2ee/dev/tools/build-ee.php --command link --ce-source magento2ce --ee-source magento2ee
cp magento2ee/composer.json magento2ce/
rm -rf magento2ce/composer.lock

php -f magento2smp/dev/tools/build-sample-data.php -- --ce-source magento2ce

cd /var/www/html/m2/$1/magento2ce
~/composer config repositories.shipping-module vcs git@src.example.com:magento/shipping-m2.git
~/composer config repositories.shipping-api vcs git@src.example.com:magento/shipping-api-rest.git
~/composer require temando/module-shipping-m2:"1.5.1"

~/composer install -o

mkdir -p var/composer_home/
cp $install_dir/auth.json var/composer_home/
mkdir -p /home/siteuser/.composer/
cp $install_dir/auth.json /home/siteuser/.composer/auth.json

ADMIN_USER=admin
ADMIN_PASSWORD=T3m$(cat /dev/urandom | tr -dc A-Za-z0-9 | head --bytes=10)

php bin/magento setup:install --db-host="$MYSQL_HOST" --db-name="m2_$1" --db-user="m2_$1" --db-password="m2-dbpass" \
  --admin-firstname=Magento --admin-lastname=User --admin-email=user@example.com --language=en_AU \
  --currency=AUD --timezone=Australia/Brisbane --use-rewrites=1 \
  --admin-user=$ADMIN_USER --admin-password=$ADMIN_PASSWORD

php bin/magento setup:store-config:set --base-url="http://$1.$DOMAIN/"
php bin/magento setup:store-config:set --base-url-secure="https://$1.$DOMAIN/"

# Uncomment the following lines for Magento installation with HTTPS support
#php bin/magento setup:store-config:set --use-secure=1
#php bin/magento setup:store-config:set --use-secure-admin=1

# NOTE: After the execution of the instruction above, you need
# to manually enable "HTTP Strict Transport Security (HSTS)"
# and "Upgrade Insecure Requests" from the admin panel of the
# new user to get HTTPS access out off endless redirection loop.

php bin/magento sampledata:deploy
php bin/magento setup:upgrade
php bin/magento setup:di:compile
php bin/magento indexer:reindex

rm -rf /var/www/html/m2/$1/var/cache/*

find . -type d -exec chmod 770 {} \;
find . -type f -exec chmod 660 {} \;

ADMIN_URI=$(php bin/magento info:adminuri | grep Admin | cut -f3 -d' ')

echo "\n\n"
echo "Site:  http://$1.$DOMAIN"
echo "Admin: http://$1.$DOMAIN$ADMIN_URI"
echo "Admin user: $ADMIN_USER"
echo "Admin pass: $ADMIN_PASSWORD"
