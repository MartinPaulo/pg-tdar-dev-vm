#!/bin/sh -e

# The tdar db user
APP_DB_USER=tdar

# The tdar dev db password (don't use this in the wild!)
APP_DB_PASS=tdar

# The tdar data database
DATA_DB_NAME=tdardata

# The tdar metadata database
META_DB_NAME=tdarmetadata

# The tdar gis database
GIS_DB_NAME=tdargis

# Edit the following to change the version of PostgreSQL that is installed
PG_VERSION=9.3

###########################################################
# Changes below this line are probably not necessary
###########################################################
print_db_usage () {
  echo "Your PostgreSQL database has been setup and can be accessed on your local machine on the forwarded port (default: 15432)"
  echo "  Host: localhost"
  echo "  Port: 15432"
  echo "  Database: $DATA_DB_NAME"
  echo "  Username: $APP_DB_USER"
  echo "  Password: $APP_DB_PASS"
  echo ""
  echo "Admin access to postgres user via VM:"
  echo "  vagrant ssh"
  echo "  sudo su - postgres"
  echo ""
  echo "psql access to app database user via VM:"
  echo "  vagrant ssh"
  echo "  sudo su - postgres"
  echo "  PGUSER=$APP_DB_USER PGPASSWORD=$APP_DB_PASS psql -h localhost $DATA_DB_NAME"
  echo ""
  echo "Env variable for application development:"
  echo "  DATABASE_URL=postgresql://$APP_DB_USER:$APP_DB_PASS@localhost:15432/$DATA_DB_NAME"
  echo ""
  echo "Local command to access the database via psql:"
  echo "  PGUSER=$APP_DB_USER PGPASSWORD=$APP_DB_PASS psql -h localhost -p 15432 $DATA_DB_NAME"
}

export DEBIAN_FRONTEND=noninteractive

PROVISIONED_ON=/etc/vm_provision_on_timestamp
if [ -f "$PROVISIONED_ON" ]
then
  echo "VM was already provisioned at: $(cat $PROVISIONED_ON)"
  echo "To run system updates manually login via 'vagrant ssh' and run 'apt-get update && apt-get upgrade'"
  echo ""
  print_db_usage
  exit
fi

PG_REPO_APT_SOURCE=/etc/apt/sources.list.d/pgdg.list
if [ ! -f "$PG_REPO_APT_SOURCE" ]
then
  # Add PG apt repo:
  echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" > "$PG_REPO_APT_SOURCE"

  # Add PGDG repo key:
  wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | apt-key add -
fi

# Update package list and upgrade all packages
apt-get update
apt-get -y upgrade

apt-get -y install "postgresql-$PG_VERSION" "postgresql-contrib-$PG_VERSION" "postgresql-$PG_VERSION-postgis"

PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
PG_DIR="/var/lib/postgresql/$PG_VERSION/main"

# Edit postgresql.conf to change listen address to '*':
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

# Append to pg_hba.conf to add password auth:
echo "host    all             all             all                     md5" >> "$PG_HBA"

# Restart so that all new config is loaded:
service postgresql restart

echo "creating the databases..."
cat << EOF | su - postgres -c psql
-- Create the database user:
CREATE USER $APP_DB_USER WITH PASSWORD '$APP_DB_PASS';

-- Create the databases:
CREATE DATABASE $DATA_DB_NAME WITH OWNER $APP_DB_USER;
CREATE DATABASE $META_DB_NAME WITH OWNER $APP_DB_USER;
CREATE DATABASE $GIS_DB_NAME WITH OWNER $APP_DB_USER;
EOF

echo "loading schema based on the latest stable release"
su - postgres -c 'psql -f /vagrant/tdarmetadata_schema.sql tdarmetadata > log.txt'

echo "loading controlled data"
su - postgres -c 'psql -f /vagrant/tdarmetadata_init.sql tdarmetadata >> log.txt'

echo "loading sample data"
su - postgres -c 'psql -f /vagrant/tdarmetadata_sample_data.sql tdarmetadata >> log.txt'

echo "running latest upgrade-db script to bring up to current rev"
su - postgres -c 'psql -f /vagrant/upgrade-db.sql tdarmetadata >> log.txt'

# Tag the provision time:
date > "$PROVISIONED_ON"

echo "Successfully created PostgreSQL dev virtual machine."
echo ""
print_db_usage
