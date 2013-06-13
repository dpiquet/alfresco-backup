#!/bin/bash

#################################################################
#
#	ALFRESCO Backup script
#
#################################################################
#
#  Script ecrit par Damien PIQUET: damien.piquet@iutbeziers.fr || piqudam@gmail.com
#
#  Save user files (alf_data)
#  Full backups
#  Incremental backups
#
#

# User variables
alf_data_dir="alf_data"
alf_dir="/opt/alfresco"

dbName="alfresco"
dbUser="alfresco"
dbPasswd="alfresco"

fullArchiveName="alf-full-`date +%F`.tar.bz2"
incArchiveName="alf-inc-`date +%F`.tar.bz2"
softArchiveName="alf-soft-`date +%F`.tar.bz2"
dbDumpFilename="alf-db.dump"

fileList="alf-fileList.txt"
tempDir="/root/alf_backup"

# required programs and scripts
mysqldump="/usr/bin/mysqldump"
tar="/bin/tar"
alfInitScript="/etc/init.d/alfresco"
logger="/usr/bin/logger"

# Commands priority, -20 (high prio) to 19 (low prio); 0 is default prio
niceVal='-20'

# Some standards return codes
ret_ok=0
ret_err=1
ret_invalid_args=2

function log_msg() {
	$logger "Alfresco backup: $1"
}

# Perform full backup of alfresco
function full_backup() {
    stop_alfresco
    if [ $? -ne $ret_ok ]; then
    	log_msg "CRIT: Alfresco n'a pas pu etre arrete! La sauvegarde ne sera pas effectuee"
	return $ret_err;
    fi

    dump_database
    if [ $? -ne $ret_ok ]; then
        log_msg "CRIT: La sauvegarde de la base de donnees a echoue ! Abandon..."
	return $ret_err;
    fi

    #Remove previously created incremental list
    if [ -f $tempDir/$fileList ]; then
        rm $tempDir/$fileList;
    fi

    # tar bzip2 all files, plus database dump
    nice -$niceVal $tar --create --preserve-permissions --bzip2 --file=$tempDir/$fullArchiveName --listed-incremental=$tempDir/$fileList $alf_dir/$alf_data_dir
    if [ $? -eq 3 ]; then
    	log_msg "Erreur lors de la creation de l'archive $fullArchiveName !"
	return $ret_err;
    fi

    # software backup
    soft_backup
    if [ $? -ne $ret_ok ]; then
    	log_msg "Erreur lors de la creation de l'archive $softArchiveName !"
	return $ret_err;
    fi

    start_alfresco
    if [ $? -ne $ret_ok ]; then
    	log_msg "CRIT: Alfresco n'a pas pu etre relance apres la sauvegarde"
	return $ret_err;
    fi

    return $ret_ok
}

# Perform incremental save (relative to last full backup)
function inc_backup() {
    stop_alfresco
    if [ $? -ne $ret_ok ]; then
    	log_msg "CRIT: Alfresco n'a pas pu etre arrete. La sauvegarde ne sera pas effectuee"
	return $ret_err;
    fi

    dump_database
    if [ $? -ne $ret_ok ]; then
    	log_msg "Erreur lors de la sauvegarde de la base de donnees !"
	return $ret_err;
    fi

    # tar bzip modified and new files (relative to filelist); return err on 3
    nice -$niceVal $tar --create --preserve-permissions --bzip2 --file=$tempDir/$incArchiveName --listed-incremental=$tempDir/$fileList $alf_dir/$alf_data_dir
    if [ $? -eq 3 ]; then
	return $ret_err;
    fi

    start_alfresco
    if [ $? -ne $ret_ok ]; then
        log_msg "CRIT: Alfresco n'a pas pu etre relance apres la sauvegarde !"
	return $ret_err;
    fi

    return $ret_ok
}

# Perform software backup
function soft_backup() {
    
    nice -$niceVal $tar --create --preserve-permissions --bzip2 --file=$tempDir/$softArchiveName  --exclude="$alf_data_dir" $alf_dir
    if [ $? -eq 3 ]; then
	return $ret_err;
    fi

    return $ret_ok
}

function dump_database() {
    $mysqldump -u $dbUser -p$dbPasswd $dbName > $alf_dir/$alf_data_dir/$dbDumpFilename
    if [ $? -ne 0 ]; then
	return $ret_err;
    else
	return $ret_ok;
    fi
}

function stop_alfresco() {
    if [ ! -x $alfInitScript ]; then
    	log_msg "Erreur ! le script $alfInitScript n'existe pas ou n'est pas executable"
	return $ret_err;
    fi

    $alfInitScript stop

    # Wait while alfresco stops
    sleep 10

    return $ret_ok
}

function start_alfresco() {
    if [ ! -x $alfInitScript ]; then
        log_msg "Erreur ! Le script $alfInitScript n'existe pas ou n'est pas executable"
	return $ret_err;
    fi

    $alfInitScript start

    return $ret_ok
}

case $1 in
    full)
        full_backup
	exit $?
    ;;
    inc)
	inc_backup
	exit $?
    ;;
    *)
        echo "Usage $0 full|inc"
	exit $ret_invalid_args
    ;;
esac

