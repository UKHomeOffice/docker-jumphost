#!/bin/bash -x

function log()
{
    echo "$(date)  $1"
}

function apply_migration_scripts()
{
    log "Running migration scripts"
    if [[ $run_mode = "test" ]]
    then
        cd $DIR/test_migrations/
    else
        cd $DIR/migrations/
    fi
    
    for file in  $(ls | grep -E '[0-9]{14}_.+\.js')
    do
        migration_script_count=$($MONGO_COMMAND --eval "db.migrations.count({filename:'"$file"'})")	
        if [[ $migration_script_count = 0 ]]
        then
            log "Applying $file"
	    $MONGO_COMMAND $file
            if [[ $? != 0 ]]
            then
                log "Applying migration $file failed. Aborting. Please fix before continuing."
                exit 2
            fi
            $MONGO_COMMAND --eval "db.migrations.insert({filename:'"$file"'})"
            log "Successfully applied $file"
	else
	    log "Already migrated $file."
	fi
    done
}

function update_db_version()
{
    $MONGO_COMMAND --eval "db.versionInfo.update(
	{_id: 'versionNumber'}, 
	{\$set: {'versionNumber':'"$1"'}},
	{upsert: true});"
}

# Read the current version of the database, which is based on the caseworkerdomain version number.
# If this is the first time running this script, the current_db_version is set to 0
function read_db_version()
{
    version_info_count=$($MONGO_COMMAND --eval "db.versionInfo.count()")
    if [[ $version_info_count = 0 ]]
    then
	current_db_version=0
    else    
	current_db_version=$($MONGO_COMMAND --eval "var versionDoc = db.versionInfo.findOne({_id: 'versionNumber'},{versionNumber:true, _id:false}); print(versionDoc.versionNumber)") 
    fi
    log "The current db version is: "$current_db_version
}

function backup_database()
{
    log "Cleaning out previous backups"
    [ "$(ls -A $DB_DUMPS)" ] && rm -rf $DB_DUMPS
    log "Backing up database"
    $MONGODUMP_CMD --host $mongo_host --port 27017 $mongo_user $mongo_pass --db caseworker --out $DB_DUMPS$current_db_version"_backup" > mongodump.txt
    #check that size of outfile is alteast 1 mb - if not fail
    size=$(du -m $DB_DUMPS$current_db_version"_backup" | grep -o -e  "[0-9]*" | grep -v "^$")
    if [ $size -lt 5 ]; then
      log "database backup size too small or non-existant - abortingexecution"
      exit 2
    fi    
}

function belt_braces_backup_database()
{
    log "Cleaning out previous backups"
    [ "$(ls -A $DB_BACKUPS)" ] && rm -rf $DB_BACKUPS
    log "Backing up timestamp database"
    TIMESTAMP=`date +%Y-%m-%d-%H-%M-%S`
    $MONGODUMP_CMD --host $mongo_host --port 27017 $mongo_user $mongo_pass --db caseworker --out $DB_BACKUPS$TIMESTAMP"_backup" > mongodump.txt
    #check that size of outfile is alteast 1 mb - if not fail
    size=$(du -m $DB_BACKUPS$TIMESTAMP"_backup" | grep -o -e  "[0-9]*" | grep -v "^$")
    if [ $size -lt 5 ]; then
      log "database backup size too small or non-existant - aborting execution"
      exit 2 
    fi
}

function restore_database()
{
    log "Restoring database"
    $MONGO_COMMAND --eval "db.dropDatabase()"
    $MONGORESTORE_CMD --host $mongo_host --port 27017 $mongo_user $mongo_pass $1 > mongorestore.txt
}

ismaster()
{
  ismaster_bool=$(mongo --quiet --eval 'db.isMaster().ismaster' --host ${mongo_host})
  echo "$ismaster_bool"
}

getmaster()
{
  getmaster_host=$(mongo --quiet --eval 'db.isMaster().primary' --host ${mongo_host})
  echo "${getmaster_host/:27017/}"
}

function restore_or_migrate_database()
{
    # *********************************
    #belt_braces_backup_database
    # *********************************

    read_db_version
    previous_db_backup_path=$DB_DUMPS$db_version_to_be_installed"_backup"

    # No version is supplied
    if [[ $db_version_to_be_installed = "0" ]]
    then
      log "Db version to be installed is: 0"
      #backup_database
	  apply_migration_scripts

	# No change between version to be installed and current version
    elif [[ $db_version_to_be_installed = $current_db_version ]]
    then
      log "No change required"

    # Previous backup exists
    elif [ -d "$previous_db_backup_path" ]; then
      log "Restoring db"
	  restore_database $previous_db_backup_path

    # Newer version is supplied, migrate database
    else
      log "Migration db"
      #backup_database
	  apply_migration_scripts
    fi

    update_db_version $db_version_to_be_installed
    log "Finished database migration"
}

# Test for root
#if [[ $run_mode != "test" ]]
#    then
#        if [ "$EUID" -ne "0" ] ; then
#            echo "Script must be run as root." >&2
#            exit 1
#        fi
#fi

if [ $# -eq 0 ]
 then
    log "usage: migrate [Version] [Mode] [DB name] [DB host]"
    exit
fi

db_version_to_be_installed=$1
run_mode=$2
mongo_db=$3
mongo_host=${4:-localhost}
mongo_user=${5:+-u "$5"}
mongo_pass=${6:+-p "$6"}
master_bool=$(ismaster)
MONGO_PREFIX='/usr/bin/'
MONGO="$(which mongo)"
MONGO_CMD="$MONGO --quiet"
MONGODUMP_CMD="$(which mongodump)"
MONGORESTORE_CMD="$(which mongorestore)"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

for com in "$MONGO" "$MONGODUMP_CMD" "$MONGORESTORE_CMD"
do
  if [ ! -x "$com" ]
  then
    echo "Missing mongo or mongo-org-tools  on the server available"
    exit 1;
  fi
done

if [[ "$master_bool" = "true" ]]
then
  mongo_address="$mongo_host/$mongo_db"
else
  mongomaster=$(getmaster)
  mongo_address="$mongomaster/$mongo_db"
fi

MONGO_COMMAND="$MONGO_CMD $mongo_user $mongo_pass $mongo_address"

if [[ $run_mode = "test" ]]
    then
        DB_DUMPS=/tmp/registered-traveller/schema-migration/db_dumps/
        DB_BACKUPS=/tmp/registered-traveller/schema-migration/db_backups/
    else
        DB_DUMPS=/mnt/data/registered-traveller/schema-migration/db_dumps/
        DB_BACKUPS=/mnt/data/registered-traveller/schema-migration/db_backups/
fi

# Direct output to log
if [[ $run_mode = "test" ]]
    then
        exec 1>> /tmp/reg_traveller_db_migrate.log 2>&1
    else
        exec 1>> /mnt/data/reg_traveller_db_migrate.log 2>&1
fi

mkdir -p $DB_DUMPS
mkdir -p $DB_BACKUPS

if [[ "$master_bool" = "true" ]]
then
  mongo_address="$mongo_host/$mongo_db"
else
  mongomaster=$(getmaster)
  mongo_address="$mongomaster/$mongo_db"
fi


export TZ=Europe/London


restore_or_migrate_database
