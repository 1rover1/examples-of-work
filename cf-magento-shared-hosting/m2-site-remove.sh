#!/bin/sh

echo "DROP USER 'm2_$1'@'%';"
echo "DROP USER 'm2_$1'@'%';"|mysql -u $DBUSER
echo "DROP DATABASE m2_$1;"
echo "DROP DATABASE m2_$1;"|mysql -u $DBUSER

rm -rf /var/www/html/m2/$1
