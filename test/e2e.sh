#!/bin/bash -e
# End to end test script

# Settings
S3_ENDPOINT_URL="http://localhost:10080"

# handle exit and clean up containers
#   ref. https://fumiyas.github.io/2013/12/06/tempfile.sh-advent-calendar.html
handle_exit() {
  docker-compose down -v
}
trap handle_exit EXIT
trap 'rc=$?; trap - EXIT; handle_exit; exit $?' INT PIPE TERM

# assert file exist on s3
#   ARGS
#     $1 ... ENDPOINT_URL: Endpoint URL of S3
#     $2 ... S3_FILE_PATH: File path of S3 to be checked for existence
assert_file_exists_on_s3() {
  if [ $# -ne 2 ]; then return 100; fi

  ENDPOINT_URL=$1
  S3_FILE_PATH=$2
  HTTP_OK=$(curl -I -L --silent "${ENDPOINT_URL}/${S3_FILE_PATH}" 2>&1 | grep -e '^HTTP/.\+200 OK')
  if [ "x${HTTP_OK}" = "x" ]; then echo 'assert_file_exists_on_s3 FAILED'; exit 1; fi
}

# assert restore is successful
assert_dummy_record_exists_on_mongodb () {
  docker-compose exec mongo bash -c 'echo -e "use dummy;\n db.dummy.find({name: \"test\"})\n" | mongo | grep -q "ObjectId"'
  if [ $? -ne 0 ]; then echo 'assert_restore_dummy_record FAILED'; exit 1; fi
}

# Start test script
CWD=$(dirname $0)
cd $CWD

TODAY=`/bin/date +%Y%m%d` # It is used to generate file name to restore

# Clean up before start s3proxy and mongodb
docker-compose down -v

# Start s3proxy and mongodb
docker-compose up --build s3proxy mongo &
sleep 3 # wait for that network of docker-compose is ready
docker-compose up --build init

# Execute app_default
docker-compose up --build app_default
# Expect for app_default
assert_file_exists_on_s3 ${S3_ENDPOINT_URL} "app_default/backup-${TODAY}.tar.bz2"
# Exit test for app_default
echo 'Finished test for app_default: OK'

# Expect for app_restore
docker-compose up --build app_restore
# Expect for app_restore
assert_dummy_record_exists_on_mongodb
# Exit test for app_restore
echo 'Finished test for app_restore: OK'

# Expect for app_backup_cronmode
docker-compose up --build app_backup_cronmode &
sleep 3 # wait for that network of docker-compose is ready
## stop container
##   before stop, sleep 65s because test backup is executed every minute in cron mode
docker-compose stop -t 65 app_backup_cronmode
# Expect for app_backup_cronmode
assert_file_exists_on_s3 ${S3_ENDPOINT_URL} "app_backup_cronmode/backup-${TODAY}.tar.bz2"
# Exit test for app_restore
echo 'Finished test for app_backup_cronmode: OK'

# Clean up all containers
docker-compose down -v

echo "***** ALL TESTS ARE SUCCESSFUL *****"
