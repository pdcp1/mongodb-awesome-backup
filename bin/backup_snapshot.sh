#!/bin/bash -e

echo "Starting backup_snapshot.sh script execution..."

# settings
BACKUPFILE_PREFIX=${BACKUPFILE_PREFIX:-backup}
MONGODB_HOST=${MONGODB_HOST:-mongo}
CRONMODE=${CRONMODE:-false}
#MONGODB_URI=
#MONGODB_HOST=
#MONGODB_DBNAME=
#MONGODB_USERNAME=
#MONGODB_PASSWORD=
#MONGODB_AUTHDB=
#MONGODUMP_OPTS=
#TARGET_PUBLIC_BUCKET_URL=[s3://... | gs://...] (must be ended with /)

# start script
CWD=`/usr/bin/dirname $0`
cd $CWD

. ./functions.sh
NOW=`create_current_yyyymmddhhmmss`

echo "=== $0 started at `/bin/date "+%Y/%m/%d %H:%M:%S"` ==="

TMPDIR="/tmp"
TARGET_DIRNAME="mongodump"
TARGET="${TMPDIR}/${TARGET_DIRNAME}"
TAR_CMD="/bin/tar"
TAR_OPTS="jcvf"

DIRNAME=`/usr/bin/dirname ${TARGET}`
BASENAME=`/usr/bin/basename ${TARGET}`
TARBALL="${BACKUPFILE_PREFIX}-${NOW}.tar.bz2"
TARBALL_FULLPATH="${TMPDIR}/${TARBALL}"


# check parameters
# deprecate the old option
if [ "x${S3_TARGET_PUBLIC_BUCKET_URL}" != "x" ]; then
  echo "WARNING: The environment variable S3_TARGET_PUBLIC_BUCKET_URL is deprecated.  Please use TARGET_PUBLIC_BUCKET_URL instead."
  TARGET_PUBLIC_BUCKET_URL=$S3_TARGET_PUBLIC_BUCKET_URL
fi
if [ "x${TARGET_PUBLIC_BUCKET_URL}" == "x" ]; then
  echo "ERROR: The environment variable TARGET_PUBLIC_BUCKET_URL must be specified." 1>&2
  exit 1
fi

# dump databases
MONGODUMP_OPTS="--uri=${MONGODB_URI} ${MONGODUMP_OPTS}"
echo "dump MongoDB aiidprod to the local filesystem..."
mongodump -o ${TARGET} ${MONGODUMP_OPTS}

# Translations Export
MONGODUMP_OPTS_TRANSLATIONS="--uri=${MONGODB_URI_TRANSLATIONS}"
echo "dump MongoDB translations to the local filesystem..."
mongodump -o ${TARGET} ${MONGODUMP_OPTS_TRANSLATIONS}

echo "Report contents are subject to their own intellectual property rights. Unless otherwise noted, the database is shared under (CC BY-SA 4.0). See: https://creativecommons.org/licenses/by-sa/4.0/" > ${TARGET}/license.txt

ls -lah
echo "---"
ls -lah ${TARGET}

# run tar command
echo "backup ${TARGET}..."
time ${TAR_CMD} ${TAR_OPTS} ${TARBALL_FULLPATH} -C ${DIRNAME} ${BASENAME}

if [ `echo $TARGET_PUBLIC_BUCKET_URL | cut -f1 -d":"` == "s3" ]; then
  # transfer tarball to Amazon S3
  s3_copy_file ${TARBALL_FULLPATH} ${TARGET_PUBLIC_BUCKET_URL}
elif [ `echo $TARGET_PUBLIC_BUCKET_URL | cut -f1 -d":"` == "gs" ]; then
  gs_copy_file ${TARBALL_FULLPATH} ${TARGET_PUBLIC_BUCKET_URL}
fi

# call healthchecks url for successful backup
if [ "x${HEALTHCHECKS_URL}" != "x" ]; then
  curl -fsS --retry 3 ${HEALTHCHECKS_URL} > /dev/null
fi

# clean up working files if in cron mode
if ${CRONMODE} ; then
  rm -rf ${TARGET}
  rm -f ${TARBALL_FULLPATH}
fi
