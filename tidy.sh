#!/bin/bash

SOURCE_DIR=.
TARGET_DIR=.
DIR_PREFIX="aha-"
CP_CMD="cp -p"
#CP_CMD="echo [DEBUG]: "
CP_COUNT=0
FILE_COUNT=0
SKIP_COUNT=0
CONFLICT_COUNT=0
DIR_COUNT=0
CHECK_SUM="Y"
USE_EXIFTOOL="Y"

if [ $# -eq 2 ]
then
	SOURCE_DIR=$1
	TARGET_DIR=$2
else
	if [ $# -ne 0 ]
	then
		echo "usage: `basename $0` (source dir) (target dir)"
		exit
	fi
fi

LOG_FILE="${TARGET_DIR}/`date "+%Y%m%d-%H%M%S"`.log"

SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

for FILE_NAME in `find "${SOURCE_DIR}" -print`
do
	if [ -d ${FILE_NAME} ]; then
		DIR_COUNT=`expr ${DIR_COUNT} + 1`
		echo "Processing files in directory [${FILE_NAME}]" | tee -a "${LOG_FILE}"
		continue
	fi
	
	BASE_FILE_NAME=`basename ${FILE_NAME}`

	if [[ "${BASE_FILE_NAME}" == .* ]]; then
		echo "${FILE_NAME} skipped (hidden file)." | tee -a "${LOG_FILE}"
		continue
	fi

	FILE_COUNT=`expr $FILE_COUNT + 1`
	
	if which exiftool>/dev/null; then
		USE_EXIFTOOL="Y"
	else
		USE_EXIFTOOL="N"
	fi

	if [ "${USE_EXIFTOOL}" == "Y" ]; then
		CREATION_DATE=`exiftool -d '%Y-%m' -DateTimeOriginal -s3 "${FILE_NAME}"`	
		if [ -z "${CREATION_DATE}" ]; then
			CREATION_DATE=`exiftool -d '%Y-%m' -CreateDate -s3 "${FILE_NAME}"`
		fi
		if [ -z "${CREATION_DATE}" ]; then
			CREATION_DATE=`exiftool -d '%Y-%m' -FileModif* -s3 "${FILE_NAME}"`
		fi
		if [ -z "${CREATION_DATE}" ]; then
			echo "Can't get ${FILE_NAME} file date, exiting..."
			exit 1
		fi
	else
		CREATION_TIME=`mdls "${FILE_NAME}" | awk -F= '/kMDItemContentCreationDate /{print $2}'`
		if [ -z "${CREATION_TIME}" ]; then
			CREATION_TIME=`mdls "${FILE_NAME}" | awk -F= '/kMDItemFSContentChangeDate /{print $2}'`
		fi
		if [ ! -z "${CREATION_TIME}" ]; then
			CREATION_DATE=`TZ=UTC-8 date -j -f " %Y-%m-%d %T %z" "${CREATION_TIME}"  "+%Y-%m"`
		else 
			echo "Can't get ${FILE_NAME} file date, exiting..."
			exit 1
		fi
	fi

	if [ -d "${TARGET_DIR}/${CREATION_DATE}" ]
	then
		CP_DIR="${TARGET_DIR}/${CREATION_DATE}"
		echo "Using the existing directory ${CREATION_DATE}" >>  "${LOG_FILE}"
	else
		if [ ! -e "${TARGET_DIR}/${CREATION_DATE}" ]
		then
			CP_DIR="${TARGET_DIR}/${CREATION_DATE}"
			mkdir "${CP_DIR}"
			echo "making dir ${CP_DIR}" | tee -a "${LOG_FILE}"
		else
			echo "The filename conflict, using the prefix ($DIR_PREFIX)"
			CP_DIR="${TARGET_DIR}/${DIR_PREFIX}${CREATION_DATE}"
			mkdir "${CP_DIR}"
			echo "making dir ${CP_DIR}" | tee -a "${LOG_FILE}"
		fi
	fi

	if [ -d "${CP_DIR}" ]; then
		if [ -f "${CP_DIR}/${BASE_FILE_NAME}" ]; then
			if [ "${CHECK_SUM}" != "N" ]; then
				SOURCE_SUM=`sum "${FILE_NAME}"| cut -d" " -f 1`
				TARGET_SUM=`sum "${CP_DIR}/${BASE_FILE_NAME}"|cut -d" " -f 1`
			else
				SOURCE_SUM=0
				TARGET_SUM=1
			fi
			if [ $SOURCE_SUM -eq $TARGET_SUM ]; then
				echo "${FILE_NAME} already exist, skipping" | tee -a "${LOG_FILE}"
				SKIP_COUNT=`expr $SKIP_COUNT + 1`
			else
				NEW_FILE_NAME="${BASE_FILE_NAME%.*}_`cat /dev/urandom | head -n 10 | md5 | cut -c 1-6`.${FILE_NAME##*.}"
				eval "${CP_CMD}" \""${FILE_NAME}"\" \""${CP_DIR}/${NEW_FILE_NAME}"\"
				CONFLICT_COUNT=`expr $CONFLICT_COUNT + 1`
				echo ${CP_CMD} "${FILE_NAME}" "${CP_DIR}/${NEW_FILE_NAME}" >> "${LOG_FILE}"
				echo "${FILE_NAME} copied using new file name ${NEW_FILE_NAME}."  | tee -a "${LOG_FILE}"
			fi
		else
			eval "${CP_CMD}" \""${FILE_NAME}"\" \""${CP_DIR}/${BASE_FILE_NAME}"\"
			CP_COUNT=`expr $CP_COUNT + 1`
			echo ${CP_CMD} "${FILE_NAME}" "${CP_DIR}/${BASE_FILE_NAME}" >> "${LOG_FILE}"
			echo "${FILE_NAME} copied to ${CP_DIR}."  | tee -a "${LOG_FILE}"
			
		fi
	else
		echo "Tidying failed at file ${FILE_NAME}"	
		exit 99
	fi
done
IFS=$SAVEIFS

echo "Total $DIR_COUNT directories,$FILE_COUNT files. $CP_COUNT copied, $CONFLICT_COUNT conflict and copied with new filename, $SKIP_COUNT files skipped." | tee -a "${LOG_FILE}"
