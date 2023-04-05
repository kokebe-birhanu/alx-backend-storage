#!/bin/bash
# Copyright (c) 2005 nixCraft project <http://cyberciti.biz/fb/>
# This script is licensed under GNU GPL version 2.0 or above
# Source: http://www.cyberciti.biz/tips/move-mysql-users-privileges-grants-from-one-host-to-new-host.html
# Author Vivek Gite <vivek@nixcraft.com>,
#        Peter Geil <code@petergeil.name>
# ------------------------------------------------------------
# SETME First - local mysql user/pass
_lusr="src-db-user"
_lpass="src-db-pw"
_lhost="src-db-host"

# SETME First - remote mysql user/pass
_rusr="target-db-user"
_rpass="target-db-pw"
_rhost="target-db-host"

# SETME First - remote mysql ssh info
# Make sure ssh keys are set
_rsshusr="target-ssh-user"
_rsshhost="target-ssh-host"

# sql file to hold grants and db info locally
_tmp="/tmp/output.mysql.$$.sql"

#### No editing below #####

# Input data
_db="$1"
_user="$2"

# Die if no input given
[ $# -eq 0 ] && { echo "Usage: $0 MySQLDatabaseName [MySQLUserName]"; exit 1; }

# Make sure you can connect to local db server
mysqladmin -u "$_lusr" -p"$_lpass" -h "$_lhost"  ping &>/dev/null || { echo "Error: Mysql server is not online or set correct values for _lusr, _lpass, and _lhost"; exit 2; }

# Make sure database exists
mysql -u "$_lusr" -p"$_lpass" -h "$_lhost" -N -B  -e'show databases;' | grep -q "^${_db}$" ||  { echo "Error: Database $_db not found."; exit 3; }

##### Step 1: Okay build .sql file with db and users, password info ####
echo "*** Getting info about $_db..."
echo "create database IF NOT EXISTS $_db; " > "$_tmp"

# Generate grant statements used to recreate user accounts on target database server

# Build pattern used to filter grant statements
if [ $# -eq 1 ]
then
    # Grab all users having privs on given db
    _users_qry="SELECT DISTINCT user.User FROM user RIGHT JOIN db ON user.User=db.User WHERE db.Db=REPLACE('$_db', '_', '\\\\_')"
    _users_re=`mysql -u "$_lusr" -p"$_lpass" -h "$_lhost" -B -N -e "$_users_qry" mysql | tr '\n' '|'`
    _users_re="(${_users_re%?})"
else
    # Grab all privs for given user name (old default)
    _users_re="$_user"
fi

# Filter out grant statements for databases other than given one
_negate_db_qry="SELECT DISTINCT Db FROM db WHERE REPLACE(Db,'\\\\','') NOT IN ('mysql', '$_db')"
_negate_db_re=`mysql -u "$_lusr" -p"$_lpass" -h "$_lhost" -B -N -e "$_negate_db_qry" mysql | tr '\n' '|' | tr '\' '\\\'`

# Generate grant statements and write to temporary file
# Preprocessing: 1. write comment line -> 2. remove semicolons already there -> 3. add semicolons to all statement lines
mysql -u "$_lusr" -p"$_lpass" -h "$_lhost" -D mysql -B -N \
-e "SELECT DISTINCT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') AS query FROM user" \
| grep -P "$_users_re\'" \
| mysql  -u "$_lusr" -p"$_lpass" -h "$_lhost" \
| grep -P -v "(${_negate_db_re%?})\`" \
| sed -e 's/Grants for .*/#### &/' -e '/;\s$/ s/;\s$//' -e '/;$/ s/;$//' -e '/^[^#]/ s/$/;/' >> "$_tmp"

##### Step 2: send .sql file to remote server ####
echo "*** Creating $_db on ${rsshhost}..."
scp "$_tmp" ${_rsshusr}@${_rsshhost}:/tmp/

#### Step 3: Create db and load users into remote db server ####
ssh ${_rsshusr}@${_rsshhost} mysql -u "$_rusr" -p"$_rpass" -h "$_rhost" < "$_tmp"

#### Step 4: Send mysql database and all data ####
echo "*** Exporting $_db from $HOSTNAME to ${_rsshhost}..."
mysqldump -u "$_lusr" -p"$_lpass" -h "$_lhost" "$_db" | ssh ${_rsshusr}@${_rsshhost} mysql -u "$_rusr" -p"$_rpass" -h "$_rhost" "$_db"

rm -f "$_tmp"
